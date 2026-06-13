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
    Repeated_Key   = -2,
    Bad_Argument     = -3,
    Buffer_Too_Small = -4,
    Allocation_Error = -5,
    Internal_Error   = -6,
}

MAX_CHORD_RUNES :: 40
MAX_CHORD_BYTES :: MAX_CHORD_RUNES * utf8.UTF_MAX

Normalized_Chord :: struct {
	bytes: [MAX_CHORD_BYTES]u8,
	len:   int,
}

normalize_chord :: proc(raw_chord: string) -> (chord: Normalized_Chord, err: Dict_Error) {
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
				return chord, .Buffer_Too_Small
			}
			rune_buf[rune_count] = r
			rune_count += 1
		}
	}

	runes := rune_buf[:rune_count]
	slice.sort(runes)

	for r, i in runes {
		if i > 0 && r == runes[i-1] {
			return Normalized_Chord{}, .Repeated_Key  
		}
		encoded, n := utf8.encode_rune(r)
		copy(chord.bytes[chord.len:chord.len+n], encoded[:n])
		chord.len += n
	}

	return chord, .None
}

chord_to_string :: proc (chord: ^Normalized_Chord) -> string {
	return string(chord.bytes[:chord.len])
}

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

dict_load_file :: proc(filepath: string, dict: ^Dict_Data) {
	data, err := os.read_entire_file(filepath, context.allocator)
	if err != nil {
		log.debugf("Could not read the file {}", filepath)
		return
	}
	defer delete(data, context.allocator)

	it := string(data)
	it = remove_bom(it)

	// Detect line endings
	sep := "\n"
	if strings.contains(it, "\r\n") {
		sep = "\r\n"
	}

	i := 1
	for line in strings.split_iterator(&it, sep) {
		log.debugf("Line {}: {}", i, line)
		shortcut, expansion, ok := extract_a_tabbed_pair(line)
		if ok {
			dict_data_add(dict, shortcut, expansion)
		} else {
			log.debugf("NOT OK: {}", expansion)
		}
		i += 1
	}
}

@(private="file")
extract_a_tabbed_pair :: proc(line: string) -> (shortcut: string, expansion: string, ok: bool) {
	line := line
	shortcut = strings.split_iterator(&line, "\t") or_return
	expansion = strings.split_iterator(&line, "\t") or_return
	log.debugf("Shortcut: {} - {}", shortcut, expansion)
	if shortcut == "" || expansion == "" {
		return "", "", false
	}
	return shortcut, expansion, true
} 

main :: proc() {
	context.logger = log.create_console_logger()
	dict_data_init(&chord_dict.dict_data)
	// dict_load_file("../zipchord-lib-tests/chords-en-dvorak.txt", &chord_dict)	
}

// main :: proc() {
// 	context.logger = log.create_console_logger()
// 	empty_chord := Normalized_Chord{}
// 	normalized := normalize_chord("řžťcab") or_else empty_chord
// 	log.debugf("Normalized to: {}", chord_to_string(&normalized)) // abcřťž
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


