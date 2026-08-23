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

	dict_init(&dicts.chord) or_return
	dict_init(&dicts.prefix) or_return
	return dict_init(&dicts.shorthand)
}

@export
zc_destroy :: proc "c" () -> Dict_Error {
	context = runtime.default_context()
	dict_destroy(&dicts.chord)
	dict_destroy(&dicts.shorthand)
	dict_destroy(&dicts.prefix)
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
		load_err := dict_load_file(
			string(filepath),
			&dicts.chord,
			true,
			shortcuts_loaded_ptr,
		)
		prefix_err := dict_prefix_build(&dicts.chord, &dicts.prefix)
		return_err := prefix_err if load_err == .None else load_err
		return return_err
	}

	return dict_load_file(
		string(filepath),
		&dicts.shorthand,
		false,
		shortcuts_loaded_ptr,
	)
}

@export
zc_validate_shortcut :: proc "c" (
	shortcut: cstring,
	is_chord: b32,
) -> Dict_Error {
	context = runtime.default_context()

	if shortcut == nil do return .Bad_Argument

	buf: Chord_Chain_Buffer
	target := &dicts.chord if is_chord else &dicts.shorthand
	_, e := validate_shortcut(
		target,
		string(shortcut),
		bool(is_chord),
		&buf
	)
	return e
}

@export
zc_register_shortcut :: proc "c" (
	shortcut: cstring,
	expansion: cstring,
	is_chord: b32,
) -> Dict_Error {
	context = runtime.default_context()

	if shortcut == nil || expansion == nil {
		return .Bad_Argument
	}

	buf: Chord_Chain_Buffer
	target := &dicts.chord if is_chord else &dicts.shorthand
	return register_shortcut(
		target,
		string(shortcut),
		string(expansion),
		bool(is_chord),
		&buf
	)
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

	target := &dicts.chord if is_chord else &dicts.shorthand
	exp, err = dict_lookup(target, string(shortcut))
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

	target := &dicts.chord if is_chord else &dicts.shorthand
	shortcut, err = dict_reverse_lookup(target, string(expansion))
	copy_string_to_buffer(shortcut, out_buf, buf_len) or_return

	return err
}

@export
zc_dict_prefix_has :: proc "c" (
	chord_candidate: cstring,
) -> Dict_Error {
	context = runtime.default_context()

	if chord_candidate == nil do return .Bad_Argument

	_, e := dict_lookup(&dicts.prefix, string(chord_candidate))
	return e
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
