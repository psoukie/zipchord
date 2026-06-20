package tests

import tst "core:testing"
import zc "../zipchord-lib"

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
dict_clones_keys_and_survives_reload :: proc(t: ^tst.T) {
    dict: zc.Chord_Dict
    err := zc.dict_data_init(&dict.dict_data)
    tst.expect(t, err == .None, "dict_init failed")
    defer zc.dict_data_destroy(&dict.dict_data)

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

    zc.dict_data_destroy(&dict.dict_data)
    tst.expect(t, len(dict.shortcut_to_expansion) == 0, "dict_destroy should clear the map")

    err = zc.dict_data_init(&dict.dict_data)
    tst.expect(t, err == .None, "dict re-init failed")

    err = zc.dict_add(&dict, "nw", "new")
    tst.expect(t, err == .None, "dict_add after re-init failed")

    expansion, lookup_err = zc.dict_lookup(&dict, "nw")
    tst.expect(t, lookup_err == .None, "lookup after re-init failed")
    tst.expect(t, expansion == "new", "dict returned the wrong value after re-init")
}

@(test)
load_dict :: proc(t: ^tst.T) {
    dict: zc.Chord_Dict
    zc.dict_data_init(&dict.dict_data)
    defer zc.dict_data_destroy(&dict.dict_data)
	zc.dict_data_load_file("../zipchord-lib-tests/chords-en-dvorak.txt", &dict, true)
    expansion, lookup_err := zc.dict_lookup(&dict, "ms")
	tst.expect(t, expansion == "some", "dict after load did not find a chord")
}

@(test)
load_dict_with_wrapper :: proc(t: ^tst.T) {
    init_return := zc.zc_init()
    tst.expect_value(t, init_return, 0)
    load_return := zc.zc_load_dictionary("../zipchord-lib-tests/en-dvorak.chords.txt", true)
	tst.expect(t, load_return > 0, "Did not load chord dictionary.")
    load_return = zc.zc_load_dictionary("../zipchord-lib-tests/english.shorthands.txt", false)
	tst.expect(t, load_return > 0, "Did not load chord dictionary.")
    expansion, lookup_err := zc.dict_lookup(&zc.shorthand_dict, "tst")
	tst.expect(t, expansion == "test", "dict after load did not find a shorthand")
}

@(test)
normalize_chords :: proc(t: ^tst.T) {
    normalize :: proc(t: ^tst.T, raw, sorted: string) {
        ch_buf: zc.Chord_Buffer
    	normalized, err := zc.normalize_chord(raw, &ch_buf)
    	tst.expect_value(t, err, zc.Dict_Error.None)
    	tst.expect_value(t, normalized, sorted)
	}
	
    normalize(t, "cabťžř", "abcřťž")
    normalize(t, "ts", "st")
    normalize(t, "a !", " !a")

    ch_buf: zc.Chord_Buffer
    noramalized, err := zc.normalize_chord("mem", &ch_buf)
    tst.expect_value(t, err, zc.Dict_Error.Repeated_Key)
    
    noramalized, err = zc.normalize_chord("ťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťť", &ch_buf)
    tst.expect_value(t, err, zc.Dict_Error.Buffer_Too_Small)
}
	
