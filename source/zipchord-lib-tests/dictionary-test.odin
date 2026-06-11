package tests

import "core:testing"
import zc "../zipchord-lib"

@(test)
utf8bom :: proc(t: ^testing.T) {
    TEST_TEXT :: "test"
    BOM :: "\uFEFF a"
    act := zc.remove_bom(TEST_TEXT)
    testing.expect(t, act == TEST_TEXT, "BOM removal removes regular characters.")
    act = zc.remove_bom(BOM + TEST_TEXT)
    testing.expect(t, act == TEST_TEXT, "BOM is not being removed.")
}
