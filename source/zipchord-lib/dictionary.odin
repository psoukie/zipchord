package zipchord_library

import "core:fmt"
import "base:runtime"
import "core:log"
import "core:os"
import "core:strings"
import "core:slice"
import "core:mem/virtual"
import "core:unicode/utf8"

Dictionary_Error :: enum i32 {
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

normalize_chord :: proc(raw_chord: string) -> (chord: Normalized_Chord, err: Dictionary_Error) {
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

Dictionary :: struct {
    arena: virtual.Arena,      // owns cloned key/value string bytes
    data:  map[string]string,  // map internals allocated with context.allocator
    normalized_keys: bool,     // e.g. chord have chars in keys sorted
}

chord_dictionary:     Dictionary
shorthand_dictionary: Dictionary

dictionary_init :: proc(dict: ^Dictionary, normalized_keys: bool) -> (err: Dictionary_Error ) {
	alloc_err := virtual.arena_init_growing(&dict.arena)
    if alloc_err != .None {
    	return .Allocation_Error
    }

    dict.data = make(map[string]string, context.allocator)  // Uses normal allocator, so resizing can free old buckets.
    dict.normalized_keys = normalized_keys
    return .None
}

dictionary_destroy :: proc(dict: ^Dictionary) {
    delete(dict.data)                    // free map internals
    virtual.arena_destroy(&dict.arena)   // free cloned strings
    dict^ = {}
}

dictionary_add :: proc (dict: ^Dictionary, key: string, value: string) -> (err: Dictionary_Error ) {
	alloc_err: runtime.Allocator_Error
	own_key, own_value: string
	
	alloc := virtual.arena_allocator(&dict.arena)

	own_key, alloc_err = strings.clone(key, alloc)
	if alloc_err != .None {
		return .Allocation_Error
	}
	
	own_value, alloc_err = strings.clone(value, alloc)
	if alloc_err != .None {
		return .Allocation_Error
	}
	
	dict.data[own_key] = own_value
	return .None
}

dictionary_lookup :: proc(dict: ^Dictionary, key: string) -> (value: string, err: Dictionary_Error ) {
	ok: bool
	if value, ok = dict.data[key]; !ok {
		return "", .Not_Found 
	}
	return value, .None
}


dictionary_load_file :: proc(filepath: string, dict: ^Dictionary) {
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
			dictionary_add(dict, shortcut, expansion)
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

// main :: proc() {
// 	context.logger = log.create_console_logger()
// 	dictionary_init(&chord_dictionary, true)
// 	dictionary_load_file("../zipchord-lib-tests/chords-en-dvorak.txt", &chord_dictionary)	
// }

main :: proc() {
	context.logger = log.create_console_logger()
	empty_chord := Normalized_Chord{}
	normalized := normalize_chord("řžťcab") or_else empty_chord
	log.debugf("Normalized to: {}", chord_to_string(&normalized)) // abcřťž
	normalized = normalize_chord("ts") or_else empty_chord
	log.debugf("Normalized to: {}", chord_to_string(&normalized)) // st
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


