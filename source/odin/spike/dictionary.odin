package zipchord

/*
This file is part of ZipChord.
Copyright (c) 2021-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license.
*/

import "base:runtime"
import "core:os"
import "core:strings"
import "core:mem/virtual"

Dict_Error :: enum i32 {
    None,
    Not_Found,
    Shortcut_Exists,
    Repeated_Key,
	Empty_Chord,
	Fewer_Than_Two,
    Bad_Argument,
    Buffer_Too_Small,
    Allocation_Error,
	File_IO_Error,
    Internal_Error,
	Version_Mismatch,
	Chain_Ends_In_Single_Key,
	Undefined_Key_Symbol,
	Unsupported_Chain,
}

Chord :: distinct bit_set[Key_Printable]
Chord_Notation :: distinct string    // chord as defined in the dictionary
Shorthand :: distinct string
Expansion :: distinct string

STRING_BUFFER_BYTES :: 1024

Fixed_Buffer :: struct($CAP: int) {
	bytes: [CAP]u8,
	len:   int,
}

clone_text :: proc (
	text: $T,
	alloc:= context.allocator,
) -> (own_text: T, err: Dict_Error) where
	T == Shorthand || T == Expansion || T == Chord_Notation {
	cloned_string, alloc_err := strings.clone(string(text), alloc)
	if alloc_err != .None {
		return own_text, .Allocation_Error
	}

	return T(cloned_string), .None
}

clone_expansion_to_lower :: proc (exp: Expansion, alloc:= context.allocator) ->
(Expansion, Dict_Error) {
	cloned_string, alloc_err := strings.to_lower(string(exp), alloc)
	if alloc_err != .None {
		return {}, .Allocation_Error
	}

	return Expansion(cloned_string), .None
}


// normalize_chained_chords :: proc(raw_shortcut: string, chain_buf: ^Chord_Chain_Buffer) -> (shortcut: string, err: Dict_Error) {
// 	chain_buf.len = 0
// 	raw_shortcut := raw_shortcut

// 	if len(raw_shortcut) >= MAX_CHAIN_BYTES {
// 		return "", .Buffer_Too_Small
// 	}

// 	chord_buf: Chord_Buffer

// 	rune_count: int
// 	segments := 0
// 	for raw_chord in strings.split_iterator(&raw_shortcut, "|") {
// 		segments += 1
// 		n := len(raw_chord)
// 		if n == 0 do return "", .Empty_Chord

// 		if chain_buf.len > 0 {
// 			chain_buf.bytes[chain_buf.len] = u8('|')
// 			chain_buf.len += 1
// 		}
// 		normalized := _normalize_chord(raw_chord, &chord_buf) or_return
// 		copy(chain_buf.bytes[chain_buf.len:chain_buf.len+n], normalized[:])
// 		chain_buf.len += n
// 		rune_count = utf8.rune_count(raw_chord)
// 	}

// 	if segments > 1 && rune_count < 2 do return "", .Chain_Ends_In_Single_Key

// 	return string(chain_buf.bytes[:chain_buf.len]), .None
// }

Dict_Shorthand :: struct {
    arena_memory:           virtual.Arena,      // owns cloned key/value string bytes
	// map internals allocated with context.allocator
	shorthand_to_expansion: map[Shorthand]Expansion,
    expansion_to_shorthand: map[Expansion]Shorthand,
}


Dict_Chord :: struct {
    arena_memory:       virtual.Arena,      // owns cloned key/value string bytes
	// map internals allocated with context.allocator
	chord_to_expansion: map[Chord]Expansion,
    expansion_to_chord_notation: map[Expansion]Chord_Notation,
}

// global variable for dictionaries
dicts: struct {
	chord:      Dict_Chord,
	prefix:     Dict_Chord,  // Chord chain prefixes without standalone chord entries
	shorthand:  Dict_Shorthand,
}

string_buf:     Fixed_Buffer(STRING_BUFFER_BYTES)

dict_chord_init :: proc(dict: ^Dict_Chord) -> (err: Dict_Error ) {
	alloc_err := virtual.arena_init_growing(&dict.arena_memory)
    if alloc_err != .None do return .Allocation_Error

	dict.chord_to_expansion = make(map[Chord]Expansion, context.allocator)
	dict.expansion_to_chord_notation = make(map[Expansion]Chord_Notation, context.allocator)
    return .None
}

dict_shorthand_init :: proc(dict: ^Dict_Shorthand) -> (err: Dict_Error ) {
	alloc_err := virtual.arena_init_growing(&dict.arena_memory)
    if alloc_err != .None do return .Allocation_Error

	dict.shorthand_to_expansion = make(map[Shorthand]Expansion, context.allocator)
	dict.expansion_to_shorthand = make(map[Expansion]Shorthand, context.allocator)
    return .None
}

dict_init :: proc {
	dict_chord_init,
	dict_shorthand_init,
}

dict_chord_destroy :: proc(dict: ^Dict_Chord) {
    delete(dict.chord_to_expansion)          // free map internals
    delete(dict.expansion_to_chord_notation)
    virtual.arena_destroy(&dict.arena_memory)   // free cloned strings
    dict^ = {}
}

dict_shorthand_destroy :: proc(dict: ^Dict_Shorthand) {
    delete(dict.shorthand_to_expansion)          // free map internals
    delete(dict.expansion_to_shorthand)
    virtual.arena_destroy(&dict.arena_memory)   // free cloned strings
    dict^ = {}
}

dict_destroy :: proc {
	dict_chord_destroy,
	dict_shorthand_destroy,
}

dict_chord_add :: proc (
	dict: ^Dict_Chord,
	chord: Chord,
	expansion: Expansion,
	chord_notation: Chord_Notation,
) -> (err: Dict_Error) {
	_, lookup_err := dict_lookup(dict^, chord)
	if lookup_err == .None do return .Shortcut_Exists

	// uses the arena for 'owned' strings
	alloc := virtual.arena_allocator(&dict.arena_memory)
	own_chord_notation := clone_text(chord_notation, alloc) or_return
	own_expansion_lower := clone_expansion_to_lower(expansion, alloc) or_return

	// if the lowercase is different, store also the original version
	own_expansion := own_expansion_lower
	if expansion != own_expansion_lower {
		own_expansion = clone_text(expansion, alloc) or_return
	}

	dict.chord_to_expansion[chord] = own_expansion
	dict.expansion_to_chord_notation[own_expansion_lower] = own_chord_notation
	return .None
}

dict_shorthand_add :: proc (
	dict: ^Dict_Shorthand,
	shorthand: Shorthand,
	expansion: Expansion,
) -> (err: Dict_Error) {
	_, lookup_err := dict_lookup(dict^, shorthand)
	if lookup_err == .None do return .Shortcut_Exists

	// uses the arena for 'owned' strings
	alloc := virtual.arena_allocator(&dict.arena_memory)
	own_shorthand := clone_text(shorthand, alloc) or_return

	own_expansion_lower := clone_expansion_to_lower(expansion, alloc) or_return

	// if the lowercase is different, store also the original version
	own_expansion := own_expansion_lower
	if expansion != own_expansion_lower {
		own_expansion = clone_text(expansion, alloc) or_return
	}

	dict.shorthand_to_expansion[own_shorthand] = own_expansion
	dict.expansion_to_shorthand[own_expansion_lower] = own_shorthand
	return .None
}

dict_chord_lookup :: proc(dict: Dict_Chord, chord: Chord) ->
	(expansion: Expansion, err: Dict_Error ) {
	ok: bool
	if expansion, ok = dict.chord_to_expansion[chord]; !ok {
		return {}, .Not_Found
	}
	return expansion, .None
}

dict_shorthand_lookup :: proc(dict: Dict_Shorthand, shorthand: Shorthand) ->
	(expansion: Expansion, err: Dict_Error ) {
	ok: bool
	if expansion, ok := dict.shorthand_to_expansion[shorthand]; !ok {
		return {}, .Not_Found
	}
	return expansion, .None
}

dict_lookup :: proc {
	dict_chord_lookup,
	dict_shorthand_lookup,
}

dict_chord_reverse_lookup :: proc(dict: ^Dict_Chord, expansion: Expansion) ->
	(chord_notation: Chord_Notation, err: Dict_Error ) {
	ok: bool
	if chord_notation, ok = dict.expansion_to_chord_notation[expansion]; !ok {
		return {}, .Not_Found
	}
	return chord_notation, .None
}

dict_shorthand_reverse_lookup :: proc(dict: ^Dict_Shorthand, expansion: Expansion) ->
	(shorthand: Shorthand, err: Dict_Error ) {
	ok: bool
	if shorthand, ok := dict.expansion_to_shorthand[expansion]; !ok {
		return {}, .Not_Found
	}
	return shorthand, .None
}

dict_reverse_lookup :: proc {
	dict_chord_reverse_lookup,
	dict_shorthand_reverse_lookup,
}

dict_line_parse :: proc(raw_line: string, $T: typeid) ->
(shortcut: T, expansion: Expansion, ok: bool) where
T == Chord_Notation || T == Shorthand {
	line := strings.trim_right(raw_line, "\r")
	shortcut_string := strings.split_iterator(&line, "\t") or_return

	if shortcut_string == "" do return

	exp_string := strings.split_iterator(&line, "\t") or_return

	return T(shortcut_string), Expansion(exp_string), true
}

Dict_Load_Diagnostic :: struct {
	invalid_shortcut: union {
		Chord_Notation,
		Shorthand,
	},
	line_number: uint,
}

dict_chord_load_file :: proc(
	dict: ^Dict_Chord,
	key_map: Key_Map,
	filepath: string,
	diagnostic_alloc := context.temp_allocator,
) -> (
	diagnostic: Dict_Load_Diagnostic,
	err: Dict_Error,
) {
	// re-initialize the dictionary
	dict_destroy(dict)
	dict_init(dict) or_return

	// Treat an empty path as clearing the dictionary
	if filepath == "" do return {}, .None

	file_data, err_file := os.read_entire_file(filepath, context.allocator)
	defer delete(file_data, context.allocator)
	if err_file != nil do return {}, .File_IO_Error

	file_text := remove_bom(string(file_data))

	for line in strings.split_iterator(&file_text, "\n") {
		diagnostic.line_number += 1
		chord_notation, expansion, ok := dict_line_parse(line, Chord_Notation)
		if !ok do continue

		chord, error := chord_compile(chord_notation, key_map)
		if error == .None {
			error = dict_chord_add(dict, chord, expansion, chord_notation)
		}
		if error != .None {
			shortcut, alloc_err := clone_text(chord_notation, diagnostic_alloc)
			if alloc_err != .None do return diagnostic, alloc_err

			diagnostic.invalid_shortcut = shortcut
			return diagnostic, error
		}
	}
	return diagnostic, .None
}

// dict_prefix_build :: proc(chords, prefixes: ^Dictionary) -> Dict_Error {
// 	dict_destroy(prefixes)
// 	dict_init(prefixes) or_return
// 	for chained_chord, _ in chords.shortcut_to_expansion {
// 		current_pos := 0
// 		for {
// 			delimiter_pos := strings.index(chained_chord[current_pos:], "|")
// 			if delimiter_pos == -1 do break

// 			current_pos += delimiter_pos
// 			_, result := dict_lookup(chords, chained_chord[:current_pos])
// 			if result == .Not_Found {
// 				dict_add(prefixes, chained_chord[:current_pos], "-") or_return
// 			}
// 			current_pos += 1
// 		}
// 	}
// 	return .None
// }


chord_compile :: proc (
	chord_notation: Chord_Notation,
	key_map: Key_Map,
) -> (chord: Chord, err: Dict_Error) {
	for key_symbol in string(chord_notation) {
		if key_symbol == '|' do return {}, .Unsupported_Chain

		key, ok := key_printable_from_symbol(key_map, key_symbol)
		if !ok do return {}, .Undefined_Key_Symbol

		if key in chord do return {}, .Repeated_Key
		chord += {key}
	}
	if card(chord) < 2 do return {}, .Fewer_Than_Two

	return chord, .None
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
