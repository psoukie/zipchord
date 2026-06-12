package zipchord_library

import "core:fmt"
import "base:runtime"
import "core:log"
import "core:os"
import "core:strings"
import "core:mem/virtual"

Dictionary_Error :: enum i32 {
    None             =  0,
    Not_Found        = -1,
    Bad_Argument     = -2,
    Buffer_Too_Small = -3,
    Allocation_Error = -4,
    Internal_Error   = -5,
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
