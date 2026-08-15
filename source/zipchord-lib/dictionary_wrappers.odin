package zipchord_library

/*
This file is part of ZipChord.
Copyright (c) 2021-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license.
*/

import "base:runtime"

@export
zc_init :: proc "c" (version: cstring) -> Dict_Error {
	context = runtime.default_context()
	if version == nil {
		return .Bad_Argument
	}
	if (string(version) != ZC_VERSION) {
		return .Version_Mismatch
	}
	dict_data_init(&chord_dict.dict_data) or_return
	return dict_data_init(&shorthand_dict.dict_data)
}

@export
zc_destroy :: proc "c" () -> Dict_Error {
	context = runtime.default_context()
	dict_data_destroy(&chord_dict.dict_data)
	dict_data_destroy(&shorthand_dict.dict_data)
	return .None
}

@export
zc_load_dictionary :: proc "c" (
	filepath: cstring,
	is_chord: b32,
	shortcuts_loaded_ptr: ^i32,
) -> Dict_Error {
	context = runtime.default_context()

	if filepath == nil || shortcuts_loaded_ptr == nil {
		return .Bad_Argument
	}

	if is_chord {
		return dict_load_file(string(filepath), &chord_dict, shortcuts_loaded_ptr)
	} else {
		return dict_load_file(string(filepath), &shorthand_dict, shortcuts_loaded_ptr)
	}
}

@export
zc_register_shortcut :: proc "c" (
	shortcut: cstring,
	expansion: cstring,
	is_chord: b32,
	validate_only: b32,
) -> Dict_Error {
	context = runtime.default_context()

	if shortcut == nil || expansion == nil {
		return .Bad_Argument
	}

	buf: Chord_Chain_Buffer
	target := &chord_dict.dict_data if is_chord else &shorthand_dict.dict_data
	return register_shortcut(target, string(shortcut), string(expansion), bool(is_chord), &buf, bool(validate_only))
}

@export
zc_get_saved_string :: proc "c" (
	out_buf: rawptr,
	buf_len: i32,
) -> Dict_Error {
	context = runtime.default_context()

	if out_buf == nil || buf_len <= 0 {
		return .Bad_Argument
	}

	str := string(string_buf.bytes[:string_buf.len])
	return copy_string_to_buffer(str, out_buf, buf_len)
}

@export
zc_lookup :: proc "c" (
	shortcut: cstring,
	is_chord: b32,
	out_buf: rawptr,
	buf_len: i32,
) -> Dict_Error {
	context = runtime.default_context()

	if shortcut == nil || out_buf == nil || buf_len <= 0 {
		return .Bad_Argument
	}

	exp: string
	err: Dict_Error

	if is_chord {
		exp, err = dict_lookup(&chord_dict, string(shortcut))
	} else {
		exp, err = dict_lookup(&shorthand_dict, string(shortcut))
	}

	copy_string_to_buffer(exp, out_buf, buf_len) or_return

	return err
}

@export
zc_reverse_lookup :: proc "c" (
	expansion: cstring,
	is_chord: b32,
	out_buf: rawptr,
	buf_len: i32,
) -> Dict_Error {
	context = runtime.default_context()

	if expansion == nil || out_buf == nil || buf_len <= 0 {
		return .Bad_Argument
	}

	shortcut: string
	err: Dict_Error

	if is_chord {
		shortcut, err = dict_reverse_lookup(&chord_dict, string(expansion))
	} else {
		shortcut, err = dict_reverse_lookup(&shorthand_dict, string(expansion))
	}

	copy_string_to_buffer(shortcut, out_buf, buf_len) or_return

	return err
}

@export
zc_normalize_chord :: proc "c" (
	raw_chord: cstring,
	out_buf: rawptr,
	buf_len: i32,
) -> Dict_Error {
	context = runtime.default_context()

	if raw_chord == nil || out_buf == nil || buf_len <= 0 {
		return .Bad_Argument
	}

	chain_buf: Chord_Chain_Buffer
	norm_chord, err := normalize_chained_chords(string(raw_chord), &chain_buf)

	copy_string_to_buffer(norm_chord, out_buf, buf_len) or_return

	return err
}

@export
zc_dict_edit :: proc "c" (
	filepath: cstring,
	old_shortcut: cstring,
	new_shortcut: cstring,
	expansion: cstring,
) -> Dict_Error {
	context = runtime.default_context()

	return dict_file_edit(
		string(filepath),
		string(old_shortcut),
		string(new_shortcut),
		string(expansion)
	)
}
