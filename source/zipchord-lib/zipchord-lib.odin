package zipchord_library

import "base:runtime"
import "core:slice"

@export
zc_init :: proc "c" () -> bool {
	context = runtime.default_context()
	dictionary_init(&chord_dictionary, true)
	dictionary_init(&shorthand_dictionary, false)
	return true
}

@export
zc_add_chord :: proc "c" (
	chord: cstring,
	expansion: cstring,
) -> i32 {
	context = runtime.default_context()

	if chord == nil || expansion == nil {
		return i32(Dictionary_Error.Bad_Argument)
	}

	result := dictionary_add(&chord_dictionary, string(chord), string(expansion))
	return i32(result)
}

@export
zc_lookup_chord :: proc "c" (
	chord: cstring,
	out_buf: rawptr,
	out_buf_len: i32,
) -> i32 {
	context = runtime.default_context()

	if chord == nil || out_buf == nil || out_buf_len <= 0 {
		return i32(Dictionary_Error.Bad_Argument)
	}

	out := slice.bytes_from_ptr(out_buf, int(out_buf_len))
	
	expansion, err := dictionary_lookup(&chord_dictionary, string(chord))
	if err != .None {
		out[0] = 0
		return i32(err)
	}

	expansion_len := len(expansion)

	if expansion_len + 1 > len(out) {
		out[0] = 0
		return i32(Dictionary_Error.Buffer_Too_Small)
	}

    copy(out[:expansion_len], expansion)
	out[expansion_len] = 0

	return i32(expansion_len)
}

