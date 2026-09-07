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

App_Message :: enum {
	Quit = 1,
	Open_Command_Menu,
}

main :: proc()
{
	app: App_State
	app.logger = log.create_console_logger()
	context.logger = app.logger
	defer log.destroy_console_logger(app.logger)

	key_map_scan_codes_init(&app.key_map)
	if !key_map_populate_from_active_layout(&app.key_map) do return  // Allocation for key map failed

	defer key_symbol_map_delete(&app.key_map)

	if !os_init(&app) do return  // Could not initialize the OS platform.

	defer os_destroy(&app.os_state)

	if !key_reader_init(&app.key_reader, app.logger, &app.os_state) do return

	defer {
		key_reader_stop(&app.key_reader)
		thread.destroy(app.key_reader._worker)
	}

	log.info("Ready...")
	_ = os_main_loop()
}
