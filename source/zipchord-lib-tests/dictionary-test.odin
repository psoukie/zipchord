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
dictionary_clones_keys_and_survives_reload :: proc(t: ^tst.T) {
    dict: zc.Dictionary
    err := zc.dictionary_init(&dict, true)
    tst.expect(t, err == .None, "dictionary_init failed")
    defer zc.dictionary_destroy(&dict)

    key_bytes := make([]u8, 2, context.allocator)
    defer delete(key_bytes, context.allocator)

    key_bytes[0] = 't'
    key_bytes[1] = 'h'

    err = zc.dictionary_add(&dict, string(key_bytes), "the")
    tst.expect(t, err == .None, "dictionary_add failed")

    key_bytes[0] = 'x'
    key_bytes[1] = 'y'

    expansion, lookup_err := zc.dictionary_lookup(&dict, "th")
    tst.expect(t, lookup_err == .None, "lookup for cloned key failed")
    tst.expect(t, expansion == "the", "dictionary did not retain cloned key/value bytes")

    zc.dictionary_destroy(&dict)
    tst.expect(t, len(dict.data) == 0, "dictionary_destroy should clear the map")

    err = zc.dictionary_init(&dict, true)
    tst.expect(t, err == .None, "dictionary re-init failed")

    err = zc.dictionary_add(&dict, "nw", "new")
    tst.expect(t, err == .None, "dictionary_add after re-init failed")

    expansion, lookup_err = zc.dictionary_lookup(&dict, "nw")
    tst.expect(t, lookup_err == .None, "lookup after re-init failed")
    tst.expect(t, expansion == "new", "dictionary returned the wrong value after re-init")
}

@(test)
load_dictionary :: proc(t: ^tst.T) {
    dict: zc.Dictionary
    zc.dictionary_init(&dict, true)
    defer zc.dictionary_destroy(&dict)
	zc.dictionary_load_file("../zipchord-lib-tests/chords-en-dvorak.txt", &dict)
    expansion, lookup_err := zc.dictionary_lookup(&dict, "th")
	tst.expect(t, expansion == "the", "dictionary after load did not find a chord")
}

@(test)
normalize_chords :: proc(t: ^tst.T) {
    normalize :: proc(t: ^tst.T, raw, sorted: string) {
    	normalized, err := zc.normalize_chord(raw)
    	tst.expect_value(t, err, zc.Dictionary_Error.None)
    	ch_str := zc.chord_to_string(&normalized)
    	tst.expect_value(t, ch_str, sorted)
    	// log.debugf("Normalized to: {}", chord_to_string(&normalized)) // 
    	normalized, err = zc.normalize_chord("ts")
	}
	
    normalize(t, "cabťžř", "abcřťž")
    normalize(t, "ts", "st")
    normalize(t, "a !", " !a")

    noramalized, err := zc.normalize_chord("mem")
    tst.expect_value(t, err, zc.Dictionary_Error.Repeated_Key)
    
    noramalized, err = zc.normalize_chord("ťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťťť")
    tst.expect_value(t, err, zc.Dictionary_Error.Buffer_Too_Small)
}
	
