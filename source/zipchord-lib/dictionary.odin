package zipchord_library

/*
This file is part of ZipChord.
Copyright (c) 2021-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license.
*/

import "base:runtime"
import "core:os"
import "core:strings"
import "core:slice"
import "core:mem/virtual"
import "core:unicode/utf8"

Dict_Error :: enum i32 {
    None             =  0,
    Not_Found        = -1,
    Shortcut_Exists  = -2,
    Repeated_Key     = -3,
	Empty_Chord      = -4,
	Fewer_Than_Two   = -5,
    Bad_Argument     = -6,
    Buffer_Too_Small = -7,
    Allocation_Error = -8,
	File_IO_Error    = -9,
    Internal_Error   = -10,
	Version_Mismatch = -11,
	Chain_Ends_In_Single_Key = -12,
}

MAX_CHORD_RUNES :: 40
MAX_CHORD_BYTES :: MAX_CHORD_RUNES * utf8.UTF_MAX
MAX_CHAIN_BYTES :: 5 * MAX_CHORD_BYTES
STRING_BUFFER_BYTES :: 1024

Fixed_Buffer :: struct($CAP: int) {
	bytes: [CAP]u8,
	len:   int,
}

Chord_Buffer       :: Fixed_Buffer(MAX_CHORD_BYTES)
Chord_Chain_Buffer :: Fixed_Buffer(MAX_CHAIN_BYTES)

copy_string_to_buffer :: proc(str: string, buf_ptr: rawptr, buf_capacity: i32) -> Dict_Error {
	out := slice.bytes_from_ptr(buf_ptr, int(buf_capacity))
	str_len := len(str)
	if str_len + 1 > len(out) {
		out[0] = 0
		return .Buffer_Too_Small
	}
    copy(out[:str_len], str)
	out[str_len] = 0
	return .None
}

_normalize_chord :: proc(raw_chord: string, chord_buf: ^Chord_Buffer) -> (normalized: string, err: Dict_Error) {
	chord_buf.len = 0

	rune_buf: [MAX_CHORD_RUNES]rune
	rune_count := 0

	if len(raw_chord)  <= MAX_CHORD_RUNES {
		// fast path without checking
		for r in raw_chord {
			rune_buf[rune_count] = r
			rune_count += 1
		}
	} else {
		for r in raw_chord {
			if rune_count >= MAX_CHORD_RUNES {
				return "", .Buffer_Too_Small
			}
			rune_buf[rune_count] = r
			rune_count += 1
		}
	}

	runes := rune_buf[:rune_count]
	slice.sort(runes)

	for r, i in runes {
		if i > 0 && r == runes[i-1] {
			return "", .Repeated_Key
		}
		encoded, n := utf8.encode_rune(r)
		copy(chord_buf.bytes[chord_buf.len:chord_buf.len+n], encoded[:n])
		chord_buf.len += n
	}

	return string(chord_buf.bytes[:chord_buf.len]), .None
}

normalize_chained_chords :: proc(raw_shortcut: string, chain_buf: ^Chord_Chain_Buffer) -> (shortcut: string, err: Dict_Error) {
	chain_buf.len = 0
	raw_shortcut := raw_shortcut

	if len(raw_shortcut) >= MAX_CHAIN_BYTES {
		return "", .Buffer_Too_Small
	}

	chord_buf: Chord_Buffer

	rune_count: int
	segments := 0
	for raw_chord in strings.split_iterator(&raw_shortcut, "|") {
		segments += 1
		n := len(raw_chord)
		if n == 0 do return "", .Empty_Chord

		if chain_buf.len > 0 {
			chain_buf.bytes[chain_buf.len] = u8('|')
			chain_buf.len += 1
		}
		normalized := _normalize_chord(raw_chord, &chord_buf) or_return
		copy(chain_buf.bytes[chain_buf.len:chain_buf.len+n], normalized[:])
		chain_buf.len += n
		rune_count = utf8.rune_count(raw_chord)
	}

	if segments > 1 && rune_count < 2 do return "", .Chain_Ends_In_Single_Key

	return string(chain_buf.bytes[:chain_buf.len]), .None
}

Dict_Data :: struct {
    arena_memory:          virtual.Arena,      // owns cloned key/value string bytes
	// map internals allocated with context.allocator
	shortcut_to_expansion: map[string]string,
    expansion_to_shortcut: map[string]string,
}

// TK: The following two structs will be removed
Chord_Dict :: struct {
	using dict_data: Dict_Data
}
Shorthand_Dict :: struct {
	using dict_data: Dict_Data
}

// global variable for dictionaries
dicts: struct {
	// chord:      Dict_Data,    // unused for now, but will replace chord_dict
	// shorthand:  Dict_Data,    // same for shorthand_dict
	prefix:     Dict_Data,    // Chord chain prefixes without standalone chord entries
}

// TK: Alternatively, the above could be handled as an enumerated array.

chord_dict:     Chord_Dict
shorthand_dict: Shorthand_Dict
string_buf:     Fixed_Buffer(STRING_BUFFER_BYTES)

dict_data_init :: proc(dict: ^Dict_Data) -> (err: Dict_Error ) {
	alloc_err := virtual.arena_init_growing(&dict.arena_memory)
    if alloc_err != .None {
    	return .Allocation_Error
    }

	//Uses normal allocator, so resizing can free old buckets
	dict.shortcut_to_expansion = make(map[string]string, context.allocator)
    dict.expansion_to_shortcut = make(map[string]string, context.allocator)
    return .None
}

dict_data_destroy :: proc(dict: ^Dict_Data) {
    delete(dict.shortcut_to_expansion)          // free map internals
    delete(dict.expansion_to_shortcut)
    virtual.arena_destroy(&dict.arena_memory)   // free cloned strings
    dict^ = {}
}

dict_data_add :: proc (
	dict: ^Dict_Data,
	shortcut: string,
	expansion: string,
	raw_chord := "",
) -> (err: Dict_Error ) {

	alloc_err: runtime.Allocator_Error
	own_shortcut,
	own_lcase_expansion,
	own_expansion,
	own_raw_chord: string

	alloc := virtual.arena_allocator(&dict.arena_memory)

	// uses an arena allocator for 'owned' strings
	own_shortcut, alloc_err = strings.clone(shortcut, alloc)
	if alloc_err != .None {
		return .Allocation_Error
	}

	own_lcase_expansion, alloc_err = strings.to_lower(expansion, alloc)
	if alloc_err != .None {
		return .Allocation_Error
	}

	// if the lowercase is different, store also the original version
	if expansion != own_lcase_expansion {
		own_expansion, alloc_err = strings.clone(expansion, alloc)
		if alloc_err != .None {
			return .Allocation_Error
		}
		dict.shortcut_to_expansion[own_shortcut] = own_expansion
	} else {
		dict.shortcut_to_expansion[own_shortcut] = own_lcase_expansion
	}

	if raw_chord != "" && raw_chord != shortcut {
		own_raw_chord, alloc_err = strings.clone(raw_chord, alloc)
		if alloc_err != .None {
			return .Allocation_Error
		}
		dict.expansion_to_shortcut[own_lcase_expansion] = own_raw_chord
	} else {
		dict.expansion_to_shortcut[own_lcase_expansion] = own_shortcut
	}
	return .None
}

chord_dict_add :: proc(dict: ^Chord_Dict, chord, expansion: string) -> (err: Dict_Error ) {
	return dict_data_add(&dict.dict_data, chord, expansion)
}

shorthand_dict_add :: proc(dict: ^Shorthand_Dict, shortcut, expansion: string) -> (err: Dict_Error ) {
	return dict_data_add(&dict.dict_data, shortcut, expansion)
}

dict_add :: proc{
	chord_dict_add,
	shorthand_dict_add,
	dict_data_add,
}

dict_data_lookup :: proc(dict: ^Dict_Data, shortcut: string) -> (expansion: string, err: Dict_Error ) {
	ok: bool
	if expansion, ok = dict.shortcut_to_expansion[shortcut]; !ok {
		return "", .Not_Found
	}
	return expansion, .None
}

chord_dict_lookup :: proc(dict: ^Chord_Dict, chord: string) -> (expansion: string, err: Dict_Error ) {
	return dict_data_lookup(&dict.dict_data, chord)
}
shorthand_dict_lookup :: proc(dict: ^Shorthand_Dict, shortcut: string) -> (expansion: string, err: Dict_Error ) {
	return dict_data_lookup(&dict.dict_data, shortcut)
}

dict_lookup :: proc{
	chord_dict_lookup,
	shorthand_dict_lookup,
	dict_data_lookup
}

dict_data_reverse_lookup :: proc(dict: ^Dict_Data, expansion: string) -> (shortcut: string, err: Dict_Error ) {
	ok: bool
	if shortcut, ok = dict.expansion_to_shortcut[expansion]; !ok {
		return "", .Not_Found
	}
	return shortcut, .None
}

chord_dict_reverse_lookup :: proc(dict: ^Chord_Dict, expansion: string) -> (shortcut: string, err: Dict_Error ) {
	return dict_data_reverse_lookup(&dict.dict_data, expansion)
}

shorthand_dict_reverse_lookup :: proc(dict: ^Shorthand_Dict, expansion: string) -> (shortcut: string, err: Dict_Error ) {
	return dict_data_reverse_lookup(&dict.dict_data, expansion)
}

dict_reverse_lookup :: proc{
	chord_dict_reverse_lookup,
	shorthand_dict_reverse_lookup,
}

dict_data_load_file :: proc(
	filepath: string,
	dict: ^Dict_Data,
	as_chords: bool,
	shortcuts_loaded_ptr: ^i32,
) -> (err: Dict_Error) {
	// re-initialize the dictionary
	shortcuts_loaded_ptr^ = 0

	dict_data_destroy(dict)
	dict_data_init(dict) or_return

	// Treat an empty path as clearing the dictionary
	if filepath == "" {
		return .None
	}

	file_data, file_err := os.read_entire_file(filepath, context.allocator)
	defer delete(file_data, context.allocator)
	if file_err != nil {
		return .File_IO_Error
	}

	file_text := string(file_data)
	file_text = remove_bom(file_text)

	chain_buf: Chord_Chain_Buffer
	for raw_line in strings.split_iterator(&file_text, "\n") {
		// Extract a tabbed pair if available
		line := strings.trim_right(raw_line, "\r")
		shortcut := strings.split_iterator(&line, "\t") or_continue
		if shortcut == "" do continue
		expansion := strings.split_iterator(&line, "\t") or_continue

		result := register_shortcut(dict, shortcut, expansion, as_chords, &chain_buf)
		if result != .None {
			string_buf.len = 0
			copy_string_to_buffer(shortcut, &string_buf.bytes, len(string_buf.bytes)) or_return
			string_buf.len = len(shortcut)
			shortcuts_loaded_ptr^ = i32(len(dict.shortcut_to_expansion))
			return result
		}
	}
	shortcuts_loaded_ptr^ = i32(len(dict.shortcut_to_expansion))
	return  .None
}

dict_chord_load_file :: proc(
	filepath: string,
	dict: ^Chord_Dict,
	shortcuts_loaded_ptr: ^i32,
) -> (err: Dict_Error) {
	return dict_data_load_file(filepath, &dict.dict_data, true, shortcuts_loaded_ptr)
}

dict_shorthand_load_file :: proc(
	filepath: string,
	dict: ^Shorthand_Dict,
	shortcuts_loaded_ptr: ^i32,
) -> (err: Dict_Error) {
	return dict_data_load_file(filepath, &dict.dict_data, false, shortcuts_loaded_ptr)
}

dict_load_file :: proc {
	dict_chord_load_file,
	dict_shorthand_load_file,
}

// inconsistent name on purpose -- should converge on convention with context_subject_operation proc naming
dict_prefix_build :: proc(chords, prefixes: ^Dict_Data) -> Dict_Error {
	dict_data_destroy(prefixes)
	dict_data_init(prefixes) or_return
	for chained_chord, _ in chords.shortcut_to_expansion {
		current_pos := 0
		for {
			delimiter_pos := strings.index(chained_chord[current_pos:], "|")
			if delimiter_pos == -1 do break

			current_pos += delimiter_pos
			_, result := dict_lookup(chords, chained_chord[:current_pos])
			if result == .Not_Found {
				dict_add(prefixes, chained_chord[:current_pos], "-") or_return
			}
			current_pos += 1
		}
	}
	return .None
}

validate_shortcut :: proc (
	dict_data: ^Dict_Data,
	orig_shortcut: string,
	as_chords: bool,
	chain_buffer: ^Chord_Chain_Buffer,
) -> (shortcut: string, err: Dict_Error) {
	shortcut = orig_shortcut

	if utf8.rune_count(shortcut) < 2 do return "", .Fewer_Than_Two

	if as_chords {
		shortcut = normalize_chained_chords(shortcut, chain_buffer) or_return
	}

	_, lookup_err := dict_data_lookup(dict_data, shortcut)
	if lookup_err == .None do return "", .Shortcut_Exists
	if lookup_err == .Not_Found do return shortcut, .None  // Available
	return "", lookup_err  // Unexpected error
}

register_shortcut :: proc (
	dict_data: ^Dict_Data,
	orig_shortcut, expansion: string,
	as_chords: bool,
	chain_buffer: ^Chord_Chain_Buffer,
) -> Dict_Error {
	shortcut := validate_shortcut(dict_data, orig_shortcut, as_chords, chain_buffer) or_return
	raw_chord := orig_shortcut if as_chords else ""
	return dict_data_add(dict_data, shortcut, expansion, raw_chord)
}

dict_file_edit :: proc(
	filepath: string,
	old_shortcut:= "",
	new_shortcut := "",
	expansion := "",
) -> (err: Dict_Error) {
	/* Calling convention based on which parameters are defined:
	   - new_shortcut && expansion -- add a shortcut
       - new_shortcut && old_shortuct -- change the assigned shortcut
       - old_shortcut only -- delete the shortcut
    */
	defer free_all(context.temp_allocator)
	operation: enum {
		Delete,
		Change,
		Add,
	}
	start_pos: int
	end_pos: int
	replacement := ""
	write_err: os.Error

	// Determine the operation; we do not flag invalid combinations
	switch {
		case filepath == "":
			return .Bad_Argument
		case new_shortcut != "" && expansion != "":
			operation = .Add
		case new_shortcut != "" && old_shortcut != "":
			operation = .Change
		case old_shortcut != "":
			operation = .Delete
		case:
			return .Bad_Argument
	}

	// Load the file as text
	file_data, file_err := os.read_entire_file(filepath, context.temp_allocator)
	if file_err != nil do return .File_IO_Error
	file_text := string(file_data)

	// Create a new file
	temp_filepath := strings.concatenate({filepath, ".tmp"},
			context.temp_allocator)
	temp_file, create_err := os.create(temp_filepath)
	if create_err != nil do return .File_IO_Error
	defer {
		if temp_file != nil do os.close(temp_file)
		if os.exists(temp_filepath) {
			os.remove(temp_filepath)
		}
	}

	// Handle .Add and other operations separately
	if operation == .Add {
		opening_new_line := "\r\n"
		ending_new_line := "\r\n"

		// Detect ending line break
		if strings.has_suffix(file_text, "\r\n") {
			opening_new_line = ""
		} else if strings.has_suffix(file_text, "\n") {
			opening_new_line = ""
			ending_new_line = "\n"
		} else {
			// check what new lines are used; or keep defaults
			if strings.index(file_text, "\r\n") == -1 &&
			   strings.index(file_text, "\n") != -1 {
				opening_new_line = "\n"
				ending_new_line = "\n"
			}
		}

		replacement = strings.concatenate({
					opening_new_line,
					new_shortcut,
					"\t",
					expansion,
					ending_new_line,
				}, context.temp_allocator)

		// Write into the file
		_, write_err = os.write_strings(temp_file,
					file_text,
					replacement)
	} else {
		// For non-adding edits, find the strating position
		needle := strings.concatenate({"\n", old_shortcut, "\t"}, context.temp_allocator)
		pos := strings.index(file_text, needle)
		if pos != -1 {
			start_pos = pos + 1 // after \n
		} else {
			// try looking at the start of file with BOM
			needle = strings.concatenate({"\ufeff", old_shortcut, "\t"}, context.temp_allocator)
			if strings.has_prefix(file_text, needle) {
				start_pos = 3 //right after BOM
			} else {
				needle = strings.concatenate({old_shortcut, "\t"}, context.temp_allocator)
				if strings.has_prefix(file_text, needle) {
					start_pos = 0
				} else {
					return .Not_Found
				}
			}
		}

		// Find the ending position and define replacement
		if operation == .Delete {
			replacement = ""
			pos = strings.index(file_text[start_pos:], "\n")
			 if pos == -1 {
				end_pos = len(file_text)
			} else {
				end_pos = start_pos + pos + 1
			}
		} else {
			replacement = new_shortcut
			end_pos = start_pos + len(old_shortcut)
		}

		// Write into the file
		_, write_err = os.write_strings(temp_file,
					file_text[:start_pos],
					replacement,
					file_text[end_pos:])
	}
	if write_err != nil do return .File_IO_Error

	// Sync & close temp file and rename it to the original dictionary
	if os.sync(temp_file) != nil do return .File_IO_Error
	close_err := os.close(temp_file)
	temp_file = nil
	if close_err != nil do return .File_IO_Error
	if os.rename(temp_filepath, filepath) != nil do return .File_IO_Error

	return .None
}

remove_bom :: proc(text: string) -> string {
    // The UTF-8 BOM is represented by the rune '\ufeff' (3 bytes)
    return strings.trim_prefix(text, "\ufeff")
}
