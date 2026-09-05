package zipchord

import "core:thread"
import "core:log"

main :: proc() {
	app_logger = log.create_console_logger()
	context.logger = app_logger
	defer log.destroy_console_logger(app_logger)

	// Might eventually need to use `when ODIN_OS == .Windows {...}`
	hwnd := os_window_init()
	if hwnd == nil do return


	key_map_init(&key_map)
	if !key_symbol_map_populate(&key_map) {
		return
	}

	defer key_symbol_map_delete(&key_map)

	for printable in Key_Printable {
		symbol, _ := key_symbol_from_printable(key_map, printable)
		typed_char, _ := key_typed_char_from_printable(key_map, printable)
		typed_char_with_shift, _ := key_typed_char_from_printable(key_map, printable, true)
		log.infof(
			"%v %v: %v / %v",
			printable,
			symbol,
			typed_char,
			typed_char_with_shift,
		)
	}

	if ! key_reader_init(&key_reader) do return

	defer {
		key_reader_stop(&key_reader)
		thread.destroy(key_reader._worker)
	}

	if !register_keyboard_hook(hwnd) {
		log.errorf("Registering keyboard hook failed.")
		return
	}

	log.info("Ready...")  //TK: spike only

	main_loop()
}
