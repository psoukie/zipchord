package zipchord_library

import "core:fmt"
import "base:runtime"
import "core:log"
import "core:os"
import "core:strings"

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
			add_to_dictionary(dict, shortcut, expansion)
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

test_file :: proc() {
	log.debugf("Chord dic in dic-handler: {}", chord_dictionary)
	expansion2, ok := lookup_in_dictionary(&chord_dictionary, string("nw"))
	log.debugf("Looked up in dic-handler: {}", expansion2)
}


dump_bytes :: proc(s: string) {
   for b, i in s {
       fmt.printf("%d: 0x%02X\n", i, b)
   }
}
