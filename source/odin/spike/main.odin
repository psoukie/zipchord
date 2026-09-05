package zipchord

import "core:thread"
import "core:log"

App_State :: struct {
	logger: log.Logger,
	key_map: Key_Map,
	keys_down: Keys_Down,
	key_reader: Key_Reader,
}

main :: proc() {
	app: App_State
	app.logger = log.create_console_logger()
	context.logger = app.logger
	defer log.destroy_console_logger(app.logger)

	// Might eventually need to use `when ODIN_OS == .Windows {...}`
	hwnd := os_window_init(&app)
	if hwnd == nil do return

	key_map_init(&app.key_map)
	if !key_symbol_map_populate(&app.key_map) {
		return
	}

	defer key_symbol_map_delete(&app.key_map)

	for printable in Key_Printable {
		symbol, _ := key_symbol_from_printable(app.key_map, printable)
		typed_char, _ := key_typed_char_from_printable(app.key_map, printable)
		typed_char_with_shift, _ := key_typed_char_from_printable(app.key_map, printable, true)
		log.infof(
			"%v %v: %v / %v",
			printable,
			symbol,
			typed_char,
			typed_char_with_shift,
		)
	}

	if ! key_reader_init(&app.key_reader, app.logger) do return

	defer {
		key_reader_stop(&app.key_reader)
		thread.destroy(app.key_reader._worker)
	}

	if !register_keyboard_hook(hwnd) {
		log.errorf("Registering keyboard hook failed.")
		return
	}

	log.info("Ready...")  //TK: spike only

	main_loop()
}
