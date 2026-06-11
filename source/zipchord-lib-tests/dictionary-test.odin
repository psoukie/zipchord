package tests

import "core:testing"
import zc "../zipchord-lib"

@(test)
utf8bom :: proc(t: ^testing.T) {
    TEST_TEXT :: "test"
    BOM :: "\uFEFF"

    act := zc.remove_bom(TEST_TEXT)
    testing.expect(t, act == TEST_TEXT, "BOM removal removes regular characters.")

    act = zc.remove_bom(BOM + TEST_TEXT)
    testing.expect(t, act == TEST_TEXT, "BOM is not being removed.")
}

@(test)
dictionary_clones_keys_and_survives_reload :: proc(t: ^testing.T) {
    dict: zc.Dictionary
    err := zc.dictionary_init(&dict, true)
    testing.expect(t, err == .None, "dictionary_init failed")
    defer zc.dictionary_destroy(&dict)

    key_bytes := make([]u8, 2, context.allocator)
    defer delete(key_bytes, context.allocator)

    key_bytes[0] = 't'
    key_bytes[1] = 'h'

    err = zc.dictionary_add(&dict, string(key_bytes), "the")
    testing.expect(t, err == .None, "dictionary_add failed")

    key_bytes[0] = 'x'
    key_bytes[1] = 'y'

    expansion, lookup_err := zc.dictionary_lookup(&dict, "th")
    testing.expect(t, lookup_err == .None, "lookup for cloned key failed")
    testing.expect(t, expansion == "the", "dictionary did not retain cloned key/value bytes")

    zc.dictionary_destroy(&dict)
    testing.expect(t, len(dict.data) == 0, "dictionary_destroy should clear the map")

    err = zc.dictionary_init(&dict, true)
    testing.expect(t, err == .None, "dictionary re-init failed")

    err = zc.dictionary_add(&dict, "nw", "new")
    testing.expect(t, err == .None, "dictionary_add after re-init failed")

    expansion, lookup_err = zc.dictionary_lookup(&dict, "nw")
    testing.expect(t, lookup_err == .None, "lookup after re-init failed")
    testing.expect(t, expansion == "new", "dictionary returned the wrong value after re-init")
}
