package zipchord_library

import "base:runtime"
import "core:slice"

@export
zc_init :: proc "c" (version: cstring) -> i32 {
	context = runtime.default_context()
	if version == nil {
		return i32(Dict_Error.Bad_Argument)
	}
	if (string(version) != ZC_VERSION) {
		return i32(Dict_Error.Version_Mismatch)
	}
	err := dict_data_init(&chord_dict.dict_data)
	if err != .None {
		return i32(err)
	}
	err = dict_data_init(&shorthand_dict.dict_data)
	return i32(err)
}

@export
zc_destroy :: proc "c" () -> i32 {
	context = runtime.default_context()
	dict_data_destroy(&chord_dict.dict_data)
	dict_data_destroy(&shorthand_dict.dict_data)
	return 0
}

@export
zc_load_dictionary :: proc "c" (
	filepath: cstring,
	is_chord: bool,
	out_buf: rawptr,
	buf_len: i32,
) -> i32 {
	context = runtime.default_context()

	if filepath == nil || out_buf == nil || buf_len <= 0 {
		return i32(Dict_Error.Bad_Argument)
	}

	target := &chord_dict.dict_data if is_chord else &shorthand_dict.dict_data

	dict_data_destroy(target)
	
	err_init := dict_data_init(target)
	if err_init != .None {
		return i32(err_init)
	}

	number_loaded, shortcut, err := dict_data_load_file(string(filepath), target, is_chord)
	if err != .None {
		if copy_err := copy_string_to_buffer(shortcut, out_buf, buf_len); copy_err != .None {
			return i32(copy_err)
		}
		return i32(err)
	}
	return i32(number_loaded)
}

@export
zc_register_shortcut :: proc "c" (
	shortcut: cstring,
	expansion: cstring,
	is_chord: bool,
) -> i32 {
	context = runtime.default_context()

	if shortcut == nil || expansion == nil {
		return i32(Dict_Error.Bad_Argument)
	}

	buf: Chord_Chain_Buffer
	target := &chord_dict.dict_data if is_chord else &shorthand_dict.dict_data
	err := register_shortcut(target, string(shortcut), string(expansion), is_chord, &buf)
	return i32(err)
}

@export
zc_lookup :: proc "c" (
	shortcut: cstring,
	is_chord: bool,
	out_buf: rawptr,
	buf_len: i32,
) -> i32 {
	context = runtime.default_context()

	if shortcut == nil || out_buf == nil || buf_len <= 0 {
		return i32(Dict_Error.Bad_Argument)
	}

	exp: string
	err: Dict_Error
	if is_chord {
		exp, err = dict_lookup(&chord_dict, string(shortcut))
	} else {
		exp, err = dict_lookup(&shorthand_dict, string(shortcut))
	}

	if copy_err := copy_string_to_buffer(exp, out_buf, buf_len); copy_err != .None {
		return i32(copy_err)
	}
	
	if err != .None {
		return i32(err)
	}

	return i32(Dict_Error.None)
}

copy_string_to_buffer :: proc(str: string, buf_ptr: rawptr, buf_len: i32) -> Dict_Error {
	out := slice.bytes_from_ptr(buf_ptr, int(buf_len))
	str_len := len(str)
	if str_len + 1 > len(out) {
		out[0] = 0
		return .Buffer_Too_Small
	}
    copy(out[:str_len], str)
	out[str_len] = 0
	return .None
}

@export
zc_reverse_lookup :: proc "c" (
	expansion: cstring,
	is_chord: bool,
	out_buf: rawptr,
	out_buf_len: i32,
) -> i32 {
	context = runtime.default_context()

	if expansion == nil || out_buf == nil || out_buf_len <= 0 {
		return i32(Dict_Error.Bad_Argument)
	}

	out := slice.bytes_from_ptr(out_buf, int(out_buf_len))

	shortcut: string
	err: Dict_Error
	if is_chord {
		shortcut, err = dict_data_reverse_lookup(&chord_dict.dict_data, string(expansion))
	} else {
		shortcut, err = dict_data_reverse_lookup(&shorthand_dict.dict_data, string(expansion))
	}
		
	if err != .None {
		out[0] = 0
		return i32(err)
	}

	shortcut_len := len(shortcut)
	if shortcut_len + 1 > len(out) {
		out[0] = 0
		return i32(Dict_Error.Buffer_Too_Small)
	}

    copy(out[:shortcut_len], shortcut)
	out[shortcut_len] = 0

	return i32(shortcut_len)
}
