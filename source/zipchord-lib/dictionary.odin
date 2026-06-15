package zipchord_library

import "core:fmt"
import "base:runtime"
import "core:log"
import "core:os"
import "core:strings"
import "core:slice"
import "core:mem/virtual"
import "core:unicode/utf8"

Dict_Error :: enum i32 {
    None             =  0,
    Not_Found        = -1,
    Repeated_Key     = -2,
    Bad_Argument     = -3,
    Buffer_Too_Small = -4,
    Allocation_Error = -5,
    Internal_Error   = -7,
}

Dict_Load_Error :: enum i32 {
	None             =  0,
    Repeated_Key     = -2,
    Buffer_Too_Small = -4,
	File_Read_Fail   = -6,
}

MAX_CHORD_RUNES :: 40
MAX_CHORD_BYTES :: MAX_CHORD_RUNES * utf8.UTF_MAX
MAX_CHAIN_BYTES :: 5 * MAX_CHORD_BYTES

Chord_Buffer :: struct {
	bytes: [MAX_CHORD_BYTES]u8,
	len:   int,
}

Chord_Chain_Buffer :: struct {
	bytes: [MAX_CHAIN_BYTES]u8,
	len:   int,
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

_normalize_chained_chords :: proc(raw_shortcut: string, chain_buf: ^Chord_Chain_Buffer) -> (shortcut: string, err: Dict_Load_Error) {
	chain_buf.len = 0
	raw_shortcut := raw_shortcut
	
	if len(raw_shortcut) >= MAX_CHAIN_BYTES {
		return "", .Buffer_Too_Small
	}
	
	for chord in strings.split_iterator(&raw_shortcut, "|") {
		log.debugf("Chain part: {}", chord)
	}

	// copy(chain_buf.bytes[:chain_buf.len], raw_shortcut)	
	
	// return string(chain_buf.bytes[:chain_buf.len]), .None
	return "x", .None
}

// chord_to_string :: proc (chord: ^Normalized_Chord) -> string {
// 	return string(chord.bytes[:chord.len])
// }

Dict_Data :: struct {
    arena_memory:          virtual.Arena,      // owns cloned key/value string bytes
    shortcut_to_expansion: map[string]string,  // map internals allocated with context.allocator
}

Chord_Dict :: struct {
	using dict_data: Dict_Data
}
Shorthand_Dict :: struct {
	using dict_data: Dict_Data
}

chord_dict:     Chord_Dict
shorthand_dict: Shorthand_Dict

dict_data_init :: proc(dict: ^Dict_Data) -> (err: Dict_Error ) {
	alloc_err := virtual.arena_init_growing(&dict.arena_memory)
    if alloc_err != .None {
    	return .Allocation_Error
    }

    dict.shortcut_to_expansion = make(map[string]string, context.allocator)  // Uses normal allocator, so resizing can free old buckets.
    return .None
}

dict_data_destroy :: proc(dict: ^Dict_Data) {
    delete(dict.shortcut_to_expansion)          // free map internals
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
	return .None
}

chord_dict_add :: proc(dict: ^Chord_Dict, shortcut, expansion: string) -> (err: Dict_Error ) {
	return dict_data_add(&dict.dict_data, shortcut, expansion)
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

chord_dict_lookup :: proc(dict: ^Chord_Dict, shortcut: string) -> (expansion: string, err: Dict_Error ) {
	return dict_data_lookup(&dict.dict_data, shortcut)
}

shorthand_dict_lookup :: proc(dict: ^Shorthand_Dict, shortcut: string) -> (expansion: string, err: Dict_Error ) {
	return dict_data_lookup(&dict.dict_data, shortcut)
}

dict_lookup :: proc{
	chord_dict_lookup,
	shorthand_dict_lookup,
}

dict_data_load_file :: proc(filepath: string, dict: ^Dict_Data, as_chords: bool) -> Dict_Load_Error {
	file_data, err := os.read_entire_file(filepath, context.allocator)
	if err != nil {
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
		log.debugf("Line {}: {}", i, line)
		shortcut, expansion, ok := _extract_a_tabbed_pair(line)
		if !ok {
			log.debugf("NOT OK: {}", expansion)
			continue
		}
		
		normalized_shortcut, err := _normalize_chained_chords(shortcut, &chain_buf) 
		dict_data_add(dict, shortcut, expansion)
	}
	return .None
}

_extract_a_tabbed_pair :: proc(line: string) -> (shortcut: string, expansion: string, ok: bool) {
	line := line
	shortcut = strings.split_iterator(&line, "\t") or_return
	expansion = strings.split_iterator(&line, "\t") or_return
	log.debugf("Shortcut: {} - {}", shortcut, expansion)
	if shortcut == "" || expansion == "" {
		return "", "", false
	}
	return shortcut, expansion, true
} 

// main :: proc() {
// 	context.logger = log.create_console_logger()
// 	// dict_load_file("../zipchord-lib-tests/chords-en-dvorak.txt", &chord_dict)	
// }

main :: proc() {
	context.logger = log.create_console_logger()
    dict: Chord_Dict
    dict_data_init(&dict.dict_data)
    defer dict_data_destroy(&dict.dict_data)
	dict_data_load_file("../zipchord-lib-tests/en-dvorak.chords.txt", &dict, true)

// 	empty_chord := Normalized_Chord{}
// 	normalized := normalize_chord("řžťcab") or_else empty_chord
// 	log.debugf("Normalized to: {}", chord_to_string(&normalized)) // abcřťž
// 	normalized = normalize_chord("ts") or_else empty_chord
// 	log.debugf("Normalized to: {}", chord_to_string(&normalized)) // st
}


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


