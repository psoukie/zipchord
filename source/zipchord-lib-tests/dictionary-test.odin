package tests

import tst "core:testing"
import zc "../zipchord-lib"
import "core:os"

@(test)
utf8bom :: proc(t: ^tst.T) {
    TEST_TEXT :: "test"
    BOM :: "\uFEFF"

    act := zc.remove_bom(TEST_TEXT)
    tst.expect(t, act == TEST_TEXT, "BOM removal removes regular characters.")

    act = zc.remove_bom(BOM + TEST_TEXT)
    tst.expect(t, act == TEST_TEXT, "BOM is not being removed.")
}

@(test)
validate_shortcuts :: proc(t: ^tst.T) {
    dict_data: zc.Dictionary
    buf: zc.Chord_Chain_Buffer
    shortcut: string
    err: zc.Dict_Error

    shortcut, err = zc.validate_shortcut(&dict_data, "ba|cd", true, &buf)
    tst.expect_value(t, err, zc.Dict_Error.None)
    tst.expect_value(t, shortcut, "ab|cd")
    shortcut, err = zc.validate_shortcut(&dict_data, "bac", false, &buf)
    tst.expect_value(t, err, zc.Dict_Error.None)
    tst.expect_value(t, shortcut, "bac")
    shortcut, err = zc.validate_shortcut(&dict_data, "b", false, &buf)
    tst.expect_value(t, err, zc.Dict_Error.Fewer_Than_Two)
    shortcut, err = zc.validate_shortcut(&dict_data, "ž", false, &buf)
    tst.expect_value(t, err, zc.Dict_Error.Fewer_Than_Two)
    shortcut, err = zc.validate_shortcut(&dict_data, "ab|ž", true, &buf)
    tst.expect_value(t, err, zc.Dict_Error.Chain_Ends_In_Single_Key)
    shortcut, err = zc.validate_shortcut(&dict_data, "xa|b|cd", true, &buf)
    tst.expect_value(t, err, zc.Dict_Error.None)
    tst.expect_value(t, shortcut, "ax|b|cd")
    shortcut, err = zc.validate_shortcut(&dict_data, "xa|cd|b", true, &buf)
    tst.expect_value(t, err, zc.Dict_Error.Chain_Ends_In_Single_Key)
    shortcut, err = zc.validate_shortcut(&dict_data, "a|xax", true, &buf)
    tst.expect_value(t, err, zc.Dict_Error.Repeated_Key)
    shortcut, err = zc.validate_shortcut(&dict_data, "a||b", true, &buf)
    tst.expect_value(t, err, zc.Dict_Error.Empty_Chord)
}

@(test)
dict_clones_keys_and_survives_reload :: proc(t: ^tst.T) {
    dict: zc.Dictionary
    err := zc.dict_init(&dict)
    defer zc.dict_destroy(&dict)
    tst.expect(t, err == .None, "dict_init failed")

    key_bytes := make([]u8, 2, context.allocator)
    defer delete(key_bytes, context.allocator)

    key_bytes[0] = 't'
    key_bytes[1] = 'h'

    err = zc.dict_add(&dict, string(key_bytes), "the")
    tst.expect(t, err == .None, "dict_add failed")

    key_bytes[0] = 'x'
    key_bytes[1] = 'y'

    expansion, lookup_err := zc.dict_lookup(&dict, "th")
    tst.expect(t, lookup_err == .None, "lookup for cloned key failed")
    tst.expect(t, expansion == "the", "dict did not retain cloned key/value bytes")

    zc.dict_destroy(&dict)
    tst.expect(t, len(dict.shortcut_to_expansion) == 0, "dict_destroy should clear the map")

    err = zc.dict_init(&dict)
    tst.expect(t, err == .None, "dict re-init failed")

    err = zc.dict_add(&dict, "nw", "new")
    tst.expect(t, err == .None, "dict_add after re-init failed")

    expansion, lookup_err = zc.dict_lookup(&dict, "nw")
    tst.expect(t, lookup_err == .None, "lookup after re-init failed")
    tst.expect(t, expansion == "new", "dict returned the wrong value after re-init")
    zc.dict_destroy(&dict)
}

@(test)
load_dict :: proc(t: ^tst.T) {
    dict: zc.Dictionary
    loaded: i32
    zc.dict_init(&dict)
    defer zc.dict_destroy(&dict)
	zc.dict_load_file("../../_tests/en-dvorak.chords.txt", &dict, true, &loaded)
	tst.expect(t, loaded >  0, "dict load did not load any chords")
	expansion, lookup_err := zc.dict_lookup(&dict, "ms")
	tst.expect(t, expansion == "some", "dict after load did not find a chord")
    load_return := zc.dict_load_file("", &dict, true, &loaded)
    tst.expect_value(t, load_return, zc.Dict_Error.None)
	tst.expect(t, loaded == 0, "Did not unload chord dictionary.")
}

@(test)
load_dict_with_wrapper :: proc(t: ^tst.T) {
    init_return := zc.zc_init(zc.ZC_VERSION)
    tst.expect_value(t, init_return, zc.Dict_Error.None)
    buf := new([2048]u8)
    defer free(buf)
    loaded: i32
    load_return := zc.zc_load_dictionary("../../_tests/en-dvorak.chords.txt", true, &loaded)
    tst.expect_value(t, load_return, zc.Dict_Error.None)
	tst.expect(t, loaded > 0, "Did not load chord dictionary.")
    load_return = zc.zc_load_dictionary("../../_tests/english.shorthands.txt", false, &loaded)
    tst.expect_value(t, load_return, zc.Dict_Error.None)
	tst.expect(t, loaded > 0, "Did not load shorthand dictionary.")
    expansion, lookup_err := zc.dict_lookup(&zc.dicts.shorthand, "tst")
	tst.expect(t, expansion == "test", "dict after load did not find a shorthand")
    load_return = zc.zc_load_dictionary("", true, &loaded)
    tst.expect_value(t, load_return, zc.Dict_Error.None)
	tst.expect(t, loaded == 0, "Did not unload chord dictionary.")
    load_return = zc.zc_load_dictionary("", false, &loaded)
    tst.expect_value(t, load_return, zc.Dict_Error.None)
	tst.expect(t, loaded == 0, "Did not unload shorthand dictionary.")
}

@(test)
normalize_chords :: proc(t: ^tst.T) {
    normalize :: proc(t: ^tst.T, raw, sorted: string) {
        ch_buf: zc.Chord_Buffer
    	normalized, err := zc._normalize_chord(raw, &ch_buf)
    	tst.expect_value(t, err, zc.Dict_Error.None)
    	tst.expect_value(t, normalized, sorted)
	}

    normalize(t, "cabťžř", "abcřťž")
    normalize(t, "ts", "st")
    normalize(t, "a !", " !a")

    ch_buf: zc.Chord_Buffer
    noramalized, err := zc._normalize_chord("mem", &ch_buf)
    tst.expect_value(t, err, zc.Dict_Error.Repeated_Key)

    noramalized, err = zc._normalize_chord("ťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťť", &ch_buf)
    tst.expect_value(t, err, zc.Dict_Error.Buffer_Too_Small)
}

@(test)
edit_dict_file :: proc(t: ^tst.T) {
   SOURCE :: "\uFEFFNEEDLE\twas correct first.\r\n" +
             "This is my false NEEDLE file.\r\n" +
             "dl\tdelete this\tnote\r\n" +
             "NEEDLE is better but still false.\r\n" +
             "NEEDLE2\tis different despite the tab.\twith a note\r\n" +
             "tbad\tdelete this"
   EXPECTED :: "\uFEFF<first>\twas correct first.\r\n" +
               "This is my false NEEDLE file.\r\n" +
               "NEEDLE is better but still false.\r\n" +
               "<second>\tis different despite the tab.\twith a note\r\n" +
               "shct\tshortcut\r\n"
    dict_file :: "_test_dictionary.txt"
    err := os.write_entire_file_from_string(dict_file, SOURCE)
    tst.expect(t, err == nil, "Error writing dictionary file")
	zc.dict_file_edit(dict_file, "tbad") // delete the last line
	zc.dict_file_edit(dict_file, "", "shct", "shortcut") // add a shortcut
	zc.dict_file_edit(dict_file, "NEEDLE", "<first>") // replace the first line shortcut
	result := zc.dict_file_edit(dict_file, "na", "<first>") // not found
	tst.expect_value(t, result, zc.Dict_Error.Not_Found)
	zc.dict_file_edit(dict_file, "NEEDLE2", "<second>") // replace the second needle
	zc.dict_file_edit(dict_file, "dl") // delete dl shortcut
	file_data, file_err := os.read_entire_file(dict_file, context.temp_allocator)
	tst.expect(t, file_err == nil, "Could not read edited dictionary")
    os.remove(dict_file)
    tst.expect(t, string(file_data) == EXPECTED, "The dictionary edits do not match the correct result.")
}

@(test)
prefix_chained_chords :: proc(t: ^tst.T) {
    dict: zc.Dictionary
    prefixes: zc.Dictionary
    err := zc.dict_init(&dict)
    tst.expect(t, err == .None, "dict init failed")
    err = zc.dict_init(&prefixes)
    tst.expect(t, err == .None, "prefix dict init failed")
    defer zc.dict_destroy(&dict)
    defer zc.dict_destroy(&prefixes)

    err = zc.dict_add(&dict, "ab|cd|ef", "alphabet")
    tst.expect(t, err == .None, "dict_add failed")
    err = zc.dict_add(&dict, "pq|rs|tu", "next")
    err = zc.dict_add(&dict, "pq", "prefix for next")

    err = zc.dict_prefix_build(&dict, &prefixes)
    tst.expect(t, err == .None, "Adding artificial chained prefixes failed")

    exp, err2 := zc.dict_lookup(&dict, "ab|cd|ef")
    tst.expect(t, err2 == .None, "Could not find the chained chord")
    tst.expect(t, exp == "alphabet", "The chord was not added or could not be looked up.")
    exp, err2 = zc.dict_lookup(&dict, "ab|cd")
    tst.expect(t, err2 == zc.Dict_Error.Not_Found, "Found a chord that should not exist")
    exp, err2 = zc.dict_lookup(&prefixes, "ab")
    tst.expect(t, err2 == zc.Dict_Error.None, "Lookup of chained prefix failed")
    tst.expectf(t, exp == "-", "Artificial prefix of chained is incorrectly: '%v'", exp)
    exp, err2 = zc.dict_lookup(&prefixes, "ab|cd")
    tst.expect(t, err2 == zc.Dict_Error.None, "Lookup of chained prefix failed")
    tst.expectf(t, exp == "-", "Artificial prefix of chained is incorrectly: '%v'", exp)
    exp, err2 = zc.dict_lookup(&prefixes, "ab|cd|ef")
    tst.expect(t, err2 == zc.Dict_Error.Not_Found, "Saved incorrectly a full chained chord as prefix")
    exp, err2 = zc.dict_lookup(&prefixes, "pq")
    tst.expect(t, err2 == zc.Dict_Error.Not_Found, "Saved standalone chord incorrectly as a prefix")
    exp, err2 = zc.dict_lookup(&prefixes, "pq|rs")
    tst.expect_value(t, exp, "-")
}
