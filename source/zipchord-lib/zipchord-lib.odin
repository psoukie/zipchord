package zipchord_library

import "base:runtime"
import "core:slice"
import "core:mem"
import "core:fmt"
import "core:log"

Dictionary_Type :: enum {
	Chord,
	Shorthand,
}

Dictionary :: struct {
	shortcuts: map[string]string,
	type:      Dictionary_Type,
}

chord_dictionary:     Dictionary
shorthand_dictionary: Dictionary
lookup_count: i32

init_dictionary :: proc(dict: ^Dictionary, dict_type: Dictionary_Type) {
	dict^.type = dict_type
	dict^.shortcuts = make(map[string]string)
}

delete_dictionary :: proc(dict: ^Dictionary) {
	delete(dict^.shortcuts)
}

empty_dictionary :: proc(dict: ^Dictionary) {
	dict_type := dict^.type
	delete_dictionary(dict)
	init_dictionary(dict, dict_type)
}

add_to_dictionary :: proc(dict: ^Dictionary, shortcut: string, expansion: string) -> bool {
	if shortcut in dict^.shortcuts {
		return false
	}
	dict^.shortcuts[shortcut] = expansion
	return true
}

lookup_in_dictionary :: proc(dict: ^Dictionary, shortcut: string) -> (exp: string, ok: bool) {
	if expansion, ok := dict^.shortcuts[shortcut]; ok {
		return expansion, true 
	}
	return "", false
}


@export
zc_init :: proc "c" () -> bool {
	context = runtime.default_context()
	init_dictionary(&chord_dictionary, .Chord)
	init_dictionary(&shorthand_dictionary, .Shorthand)

	add_to_dictionary(&chord_dictionary, "th", "the")
	add_to_dictionary(&chord_dictionary, "wy", "way")
	return true
}


@export
zc_lookup_chord :: proc "c" (
	chord: cstring,
	out_buf: rawptr,
	out_buf_len: i32,
) -> i32 {
	context = runtime.default_context()

	if chord == nil || out_buf == nil || out_buf_len <= 0 {
		return -1
	}

	lookup_count += 1
	chord_string := string(chord)
	buf_len := int(out_buf_len)
	out := slice.bytes_from_ptr(out_buf, buf_len)
	
	expansion, ok := lookup_in_dictionary(&chord_dictionary, chord_string)
	if !ok {
		out[0] = 0
		return 0
	}

	expansion_len := len(expansion)

	// Need room for bytes plus null terminator.
	if expansion_len + 1 > buf_len {
		return -2
	}

	for i in 0..<expansion_len {
		out[i] = expansion[i]
	}
	out[expansion_len] = 0

	return i32(expansion_len)
}

@export
zc_lookup_count :: proc "c" () -> i32 {
	context = runtime.default_context()
	return lookup_count
}

// main :: proc() {
// 	context.logger = log.create_console_logger()

// 	when ODIN_DEBUG {
// 		track: mem.Tracking_Allocator
// 		mem.tracking_allocator_init(&track, context.allocator)
// 		context.allocator = mem.tracking_allocator(&track)

// 		defer {
// 			if len(track.allocation_map) > 0 {
// 				for _, entry in track.allocation_map {
// 					fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
// 				}
// 			}
// 			mem.tracking_allocator_destroy(&track)
// 		}
// 	}
	
// 	init_dictionary(&chord_dictionary, .Chord)
// 	init_dictionary(&shorthand_dictionary, .Shorthand)

// 	add_to_dictionary(&chord_dictionary, "th", "the")
// 	add_to_dictionary(&chord_dictionary, "wy", "way")
// 	if !add_to_dictionary(&chord_dictionary, "th", "the") {
// 		fmt.println("Already exists.")
// 	}
// 	log.debugf("Post-population: {}\n", chord_dictionary)
// 	chord : string
// 	expansion : string
// 	chord = "th"
// 	ok: bool
// 	expansion, ok = lookup_in_dictionary(&chord_dictionary, chord)
// 	log.debugf("Looked up: {}", expansion)
// 	empty_dictionary(&chord_dictionary)
// 	log.debugf("After-reset: {}", chord_dictionary)
//     chord_dictionary.shortcuts["nw"] = "new"
// 	log.debugf("After new: {}", chord_dictionary)
// 	delete_dictionary(&chord_dictionary)
// }
