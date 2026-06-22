package zipchord_library

import "core:fmt"
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
	File_Read_Fail   = -9,
    Internal_Error   = -10,
	Version_Mismatch = -11,
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

normalize_chord :: proc(raw_chord: string, chord_buf: ^Chord_Buffer) -> (normalized: string, err: Dict_Error) {
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

_normalize_chained_chords :: proc(raw_shortcut: string, chain_buf: ^Chord_Chain_Buffer) -> (shortcut: string, err: Dict_Error) {
	chain_buf.len = 0
	raw_shortcut := raw_shortcut
	
	if len(raw_shortcut) >= MAX_CHAIN_BYTES {
		return "", .Buffer_Too_Small
	}

	chord_buf: Chord_Buffer
	
	for raw_chord in strings.split_iterator(&raw_shortcut, "|") {
		n := len(raw_chord)
		if n == 0 {
			return "", .Empty_Chord	
		}
		if chain_buf.len > 0 {
			chain_buf.bytes[chain_buf.len] = u8('|')
			chain_buf.len += 1
		}
		normalized := normalize_chord(raw_chord, &chord_buf) or_return
		copy(chain_buf.bytes[chain_buf.len:chain_buf.len+n], normalized[:])
		chain_buf.len += n
	}

	return string(chain_buf.bytes[:chain_buf.len]), .None
}

Dict_Data :: struct {
    arena_memory:          virtual.Arena,      // owns cloned key/value string bytes
	// map internals allocated with context.allocator
	shortcut_to_expansion: map[string]string,
    expansion_to_shortcut: map[string]string,
}

Chord_Dict :: struct {
	using dict_data: Dict_Data
}
Shorthand_Dict :: struct {
	using dict_data: Dict_Data
}

// TK - encapsulate in an 'engine' struct
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

dict_data_add :: proc (dict: ^Dict_Data, key: string, value: string, ) -> (err: Dict_Error ) {
	alloc_err: runtime.Allocator_Error
	own_key, own_value: string
	
	alloc := virtual.arena_allocator(&dict.arena_memory)

	own_key, alloc_err = strings.clone(key, alloc)
	if alloc_err != .None {
		return .Allocation_Error
	}
	
	own_value, alloc_err = strings.clone(value, alloc)
	if alloc_err != .None {
		return .Allocation_Error
	}
	
	dict.shortcut_to_expansion[own_key] = own_value
	dict.expansion_to_shortcut[own_value] = own_key
	return .None
}

chord_dict_add :: proc(dict: ^Chord_Dict, raw_chord, expansion: string) -> (err: Dict_Error ) {
	buf: Chord_Buffer
	chord := normalize_chord(raw_chord, &buf) or_return
	return dict_data_add(&dict.dict_data, chord, expansion)
}

shorthand_dict_add :: proc(dict: ^Shorthand_Dict, shortcut, expansion: string) -> (err: Dict_Error ) {
	return dict_data_add(&dict.dict_data, shortcut, expansion)
}

dict_add :: proc{
	chord_dict_add,
	shorthand_dict_add,
}

dict_data_lookup :: proc(dict: ^Dict_Data, shortcut: string) -> (expansion: string, err: Dict_Error ) {
	ok: bool
	if expansion, ok = dict.shortcut_to_expansion[shortcut]; !ok {
		return "", .Not_Found 
	}
	return expansion, .None
}

chord_dict_lookup :: proc(dict: ^Chord_Dict, raw_chord: string) -> (expansion: string, err: Dict_Error ) {
	buf: Chord_Buffer
	chord := normalize_chord(raw_chord, &buf) or_return
	return dict_data_lookup(&dict.dict_data, chord)
}

shorthand_dict_lookup :: proc(dict: ^Shorthand_Dict, shortcut: string) -> (expansion: string, err: Dict_Error ) {
	return dict_data_lookup(&dict.dict_data, shortcut)
}

dict_lookup :: proc{
	chord_dict_lookup,
	shorthand_dict_lookup,
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
	shortcuts_loaded: ^i32,
) -> (err: Dict_Error) {
	file_data, file_err := os.read_entire_file(filepath, context.allocator)
	if file_err != nil {
		return .File_Read_Fail
	}
	defer delete(file_data, context.allocator)

	it := string(file_data)
	it = remove_bom(it)

	i := 0
	chain_buf: Chord_Chain_Buffer
	for raw_line in strings.split_iterator(&it, "\n") {
		i += 1
		line := strings.trim_right(raw_line, "\r") 
		shortcut, expansion := _extract_a_tabbed_pair(line) or_continue
		if shortcut == "" {
			continue
		}
		result := register_shortcut(dict, shortcut, expansion, as_chords, &chain_buf)
		if result != .None {
			string_buf.len = 0
			copy_string_to_buffer(shortcut, &string_buf.bytes, len(string_buf.bytes)) or_return
			string_buf.len = len(shortcut)
			shortcuts_loaded^ = i32(len(dict.shortcut_to_expansion))
			return result		
		}
	}
	shortcuts_loaded^ = i32(len(dict.shortcut_to_expansion))
	return  .None
}


register_shortcut :: proc (
	dict_data: ^Dict_Data,
	shortcut: string,
	expansion: string,
	as_chords: bool,
	chain_buffer: ^Chord_Chain_Buffer
) -> (err: Dict_Error) {
	shortcut := shortcut

	if len(shortcut) < 2 {  // TK: not foolproof for non-ASCII shortcuts
		return .Fewer_Than_Two
	}
	
	if as_chords {
		shortcut = _normalize_chained_chords(shortcut, chain_buffer) or_return 
	}

	existing, lookup_err := dict_data_lookup(dict_data, shortcut)
	if lookup_err != .Not_Found {
		return .Shortcut_Exists
	}
	return dict_data_add(dict_data, shortcut, expansion)
}

_extract_a_tabbed_pair :: proc(line: string) -> (shortcut: string, expansion: string, ok: bool) {
	line := line
	shortcut = strings.split_iterator(&line, "\t") or_return
	expansion = strings.split_iterator(&line, "\t") or_return
	return shortcut, expansion, true
} 

// main :: proc() {
// 	context.logger = log.create_console_logger()
// 	chord_dict: Chord_Dict
// 	dict_data_load_file("../zipchord-lib-tests/english.shorthands.txt", &chord_dict, false)	
// }

// main :: proc() {
// 	context.logger = log.create_console_logger()
//     dict: Chord_Dict
//     dict_data_init(&dict.dict_data)
//     defer dict_data_destroy(&dict.dict_data)
// 	dict_data_load_file("../zipchord-lib-tests/en-dvorak.chords.txt", &dict, true)
// 	expansion, err := dict_lookup(&dict, "ht")
// 	log.debugf("Expands to: {}", expansion)
// 	empty_chord := Normalized_Chord{}
// 	normalized := normalize_chord("řžťcab") or_else empty_chord
	// log.debugf("Normalized to: {}", chord_to_string(&normalized)) // abcřťž
// 	normalized = normalize_chord("ts") or_else empty_chord
// 	log.debugf("Normalized to: {}", chord_to_string(&normalized)) // st
// }


remove_bom :: proc(text: string) -> string {
    // The UTF-8 BOM is represented by the rune '\ufeff' (3 bytes)
    if strings.has_prefix(text, "\ufeff") {
        return text[3:]
    }
    return text
}

dump_bytes :: proc(s: string) {
   for b, i in s {
       fmt.printf("%d: 0x%02X\n", i, b)
   }
}


