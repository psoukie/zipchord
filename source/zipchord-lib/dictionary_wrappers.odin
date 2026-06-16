package zipchord_library

import "base:runtime"
import "core:slice"

@export
zc_init :: proc "c" () -> i32 {
	context = runtime.default_context()
	err := dict_data_init(&chord_dict.dict_data)
	if err != .None {
		return i32(err)
	}
	err = dict_data_init(&shorthand_dict.dict_data)
	return i32(err)
}

@export
zc_load_dictionary :: proc "c" (
	filepath: cstring,
	is_chord: bool,
) -> i32 {
	context = runtime.default_context()

	if filepath == nil {
		return i32(Dict_Error.Bad_Argument)
	}

	if is_chord {
		return i32(dict_data_load_file(string(filepath), &chord_dict.dict_data, true))
	}

	return i32(dict_data_load_file(string(filepath), &shorthand_dict.dict_data, false))
}

@export
zc_add_chord :: proc "c" (
	chord: cstring,
	expansion: cstring,
) -> i32 {
	context = runtime.default_context()

	if chord == nil || expansion == nil {
		return i32(Dict_Error.Bad_Argument)
	}

	result := dict_add(&chord_dict, string(chord), string(expansion))
	return i32(result)
}

@export
zc_lookup :: proc "c" (
	shortcut: cstring,
	is_chord: bool,
	out_buf: rawptr,
	out_buf_len: i32,
) -> i32 {
	context = runtime.default_context()

	if shortcut == nil || out_buf == nil || out_buf_len <= 0 {
		return i32(Dict_Error.Bad_Argument)
	}

	out := slice.bytes_from_ptr(out_buf, int(out_buf_len))

	exp: string
	err: Dict_Error
	if is_chord {
		exp, err = dict_lookup(&chord_dict, string(shortcut))
	} else {
		exp, err = dict_lookup(&shorthand_dict, string(shortcut))
	}
		
	if err != .None {
		out[0] = 0
		return i32(err)
	}

	expansion_len := len(exp)

	if expansion_len + 1 > len(out) {
		out[0] = 0
		return i32(Dict_Error.Buffer_Too_Small)
	}

    copy(out[:expansion_len], exp)
	out[expansion_len] = 0

	return i32(expansion_len)
}
