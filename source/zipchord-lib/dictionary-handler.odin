package zipchord_library

import "core:fmt"
import "base:runtime"
import "core:log"
import "core:os"
import "core:strings"
import "core:mem/virtual"

Error :: runtime.Allocator_Error

Dictionary :: struct {
    arena: virtual.Arena,      // owns cloned key/value string bytes
    data:  map[string]string,  // allocated with normal context allocator
    normalized_keys: bool,     // e.g. chord have chars in keys sorted
}

dictionary_init :: proc(dict: ^Dictionary, normalized_keys: bool) -> (err: Error) {
    err = virtual.arena_init_growing(&dict.arena)
    if err != .None {
    	return err
    }

    // Map internals use normal allocator, so resizing can free old buckets.
    dict.data = make(map[string]string)
    dict.normalized_keys = normalized_keys
    return .None
}

dictionary_destroy :: proc(dict: ^Dictionary) {
    delete(dict.data)                    // free map internals
    virtual.arena_destroy(&dict.arena)   // free cloned strings
    dict^ = {}
}

dictionary_add :: proc (dict: ^Dictionary, key: string, value: string) -> (err: Error) {
	own_key, own_value: string
	
	alloc := virtual.arena_allocator(&dict.arena)

	own_key, err = strings.clone(key, alloc)
	if err != .None {
		return err
	}
	
	own_value, err = strings.clone(value, alloc)
	if err != .None {
		return err
	}
	
	dict.data[own_key] = own_value
	return .None
}

load_dictionary_file :: proc(filepath: string, dict: ^Dictionary) {
	data, err := os.read_entire_file(filepath, context.allocator)
	if err != nil {
		log.debugf("Could not read the file {}", filepath)
		return
	}
	defer delete(data, context.allocator)

	it := string(data)
	it = remove_bom(it)

	// Normalize line endings
	sep := "\n"
	if strings.contains(it, "\r\n") {
		sep = "\r\n"
	}

	i := 1
	for line in strings.split_iterator(&it, sep) {
		log.debugf("Line {}: {}", i, line)
		shortcut, expansion := extract_a_tabbed_pair(line)
		if shortcut != "" {
			dictionary_add(dict, shortcut, expansion)
		}
		i += 1
	}
}

extract_a_tabbed_pair :: proc(line: string) -> (shortcut: string, expansion: string) {
	ok: bool
	line := line
	shortcut, ok = strings.split_iterator(&line, "\t")
	expansion, ok = strings.split_iterator(&line, "\t")
	log.debugf("Shortcut: {} - {} ({})", shortcut, expansion, ok)
	if !ok || shortcut == "" || expansion == "" {
		return "", ""
	}
	return shortcut, expansion
} 

// extract_shortcut_and_expansion :: proc(line: string) {
	
// }

remove_bom :: proc(text: string) -> string {
    // The UTF-8 BOM is represented by the rune '\ufeff' (2 bytes)
    if strings.has_prefix(text, "\ufeff") {
        return text[3:]
    }
    return text
}

// main :: proc() {
// 	context.logger = log.create_console_logger()

// 	log.debug("Starting...")
//  	read_file_by_lines_in_whole("chords-en-dvorak.txt")
// }

dump_bytes :: proc(s: string) {
   for b, i in s {
       fmt.printf("%d: 0x%02X\n", i, b)
   }
}
