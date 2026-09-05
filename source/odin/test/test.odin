package tests

import tst "core:testing"
import "core:os"
import z "../spike"

None :: z.Dict_Error.None

@(test)
utf8bom :: proc(t: ^tst.T) {
    TEST_TEXT :: "test"
    BOM :: "\uFEFF"

    act := z.remove_bom(TEST_TEXT)
    tst.expect(t, act == TEST_TEXT, "BOM removal removes regular characters.")

    act = z.remove_bom(BOM + TEST_TEXT)
    tst.expect(t, act == TEST_TEXT, "BOM is not being removed.")
}

@(test)
key_map_ititialization :: proc(t: ^tst.T) {
    key_map: z.Key_Map
    z.key_map_init(&key_map)
    ok_pop := z.key_symbol_map_populate(&key_map)
	defer z.key_symbol_map_delete(&key_map)
    tst.expect_value(t, ok_pop, true)
    a_key, ok := z.key_printable_from_symbol(key_map, 'a')
    tst.expect_value(t, ok, true)
    tst.expect(t, a_key == z.Key_Printable.A, "Symbol 'a' should map to key `A` on US and Dvorak layouts.")
    m_symbol, ok2 := z.key_symbol_from_printable(key_map, z.Key_Printable.M)
    tst.expect_value(t, ok2, true)
    tst.expect(t, m_symbol == 'm', "Key `M` should map to symbol 'm' on US and Dvorak layouts.")
}

@(test)
chord_compiling :: proc(t: ^tst.T) {
    key_map: z.Key_Map
    test_chord := z.Chord{.K, .J}  // Corresponds to 't' and 'h' on Dvorak keyboard

    z.key_map_init(&key_map)
    ok_pop := z.key_symbol_map_populate(&key_map)
	defer z.key_symbol_map_delete(&key_map)
    tst.expect_value(t, ok_pop, true)

    chord, err := z.chord_compile("th", key_map)
    tst.expect_value(t, err, None)
    tst.expect_value(t, chord, test_chord)
}

@(test)
load_dict :: proc(t: ^tst.T) {
    DIC1 :: "\uFEFFFirst line\r\n" +
            "\r\n" +
            "tat\tnote\r\n"
    DIC2 :: "\uFEFFch|co\tchained chord"
    DIC3 :: "\r\n" +
            "a\ttoo short\r\n"
    DIC4 :: "Dictionary\n" +
            "\n" +
            "th\tthe\r\n" +
            "ou\tyou\n"
    dict: z.Dict_Chord
    key_map: z.Key_Map

    z.key_map_init(&key_map)
    ok_pop := z.key_symbol_map_populate(&key_map)
	defer z.key_symbol_map_delete(&key_map)
    tst.expect_value(t, ok_pop, true)

    dict_file :: "_test_dictionary.txt"
    err_f := os.write_entire_file_from_string(dict_file, DIC1)
    defer os.remove(dict_file)
    tst.expect(t, err_f == nil, "Error writing dictionary file")
    result, err := z.dict_chord_load_file(&dict, key_map, dict_file)
    defer z.dict_destroy(&dict)
    defer free_all(context.temp_allocator)
	tst.expect_value(t, result.line_number, 3)
    tst.expect_value(t, err, z.Dict_Error.Repeated_Key)

    err_f = os.write_entire_file_from_string(dict_file, DIC2)
    result, err = z.dict_chord_load_file(&dict, key_map, dict_file)
	tst.expect_value(t, result.line_number, 1)
    tst.expect_value(t, err, z.Dict_Error.Unsupported_Chain)

    err_f = os.write_entire_file_from_string(dict_file, DIC3)
    result, err = z.dict_chord_load_file(&dict, key_map, dict_file)
	tst.expect_value(t, result.line_number, 2)
    tst.expect_value(t, err, z.Dict_Error.Fewer_Than_Two)

    err_f = os.write_entire_file_from_string(dict_file, DIC4)
    result, err = z.dict_chord_load_file(&dict, key_map, dict_file)
	tst.expect_value(t, result.line_number, 4)
    tst.expect_value(t, err, None)

    test_chord := z.Chord{.K, .J}  // Corresponds to 't' and 'h' on Dvorak keyboard
    exp, e_lookup := z.dict_lookup(dict, test_chord)
    tst.expect_value(t, e_lookup, None)
    tst.expect_value(t, exp, "the")
}
