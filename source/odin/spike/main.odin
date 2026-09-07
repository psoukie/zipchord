package zipchord

import "core:thread"
import "core:log"

App_State :: struct {
	logger: log.Logger,
	key_map: Key_Map,
	keys_down: Keys_Down,
	key_reader: Key_Reader,
	os_state: OS_State,
}

main :: proc()
{
	app: App_State
	app.logger = log.create_console_logger()
	context.logger = app.logger
	defer log.destroy_console_logger(app.logger)

	key_map_scan_codes_init(&app.key_map)
	if !key_map_populate_from_active_layout(&app.key_map) {
		log.error("Could not allocate memory for key map.")
		return
	}

	defer key_symbol_map_delete(&app.key_map)

	// TK: Debug only
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

	if !key_reader_init(&app.key_reader, app.logger) do return

	defer {
		key_reader_stop(&app.key_reader)
		thread.destroy(app.key_reader._worker)
	}

	if !os_init(&app) {
		log.error("Could not initialize the OS platform.")
		return
	}

	log.info("Ready...")
	os_main_loop()
}
