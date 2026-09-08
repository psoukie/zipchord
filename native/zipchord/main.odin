package zipchord

// SPDX-FileCopyrightText: 2026 Pavel Soukenik
// SPDX-License-Identifier: BSD-3-Clause

import "core:thread"
import "core:log"
import "core:os"

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

App_Error :: enum {
	None,
	Key_Event_Buffer_Full,
	Windows_GetMessageW_Failed,
	Windows_GetRawInput_Failed,
	Windows_Platform_Init_Failed,
	Key_Map_Alloc_Error,
	Key_Reader_Init_Failed,
}

run :: proc(logger: log.Logger) -> App_Error
{
	app: App_State
	app.logger = logger

	key_map_scan_codes_init(&app.key_map)
	if !key_map_populate_from_active_layout(&app.key_map) do return .Key_Map_Alloc_Error

	defer key_symbol_map_delete(&app.key_map)

	if !os_init(&app) do return .Windows_Platform_Init_Failed

	defer os_destroy(&app.os_state)

	if !key_reader_init(&app.key_reader, app.logger, &app.os_state) do return .Key_Reader_Init_Failed

	defer {
		key_reader_stop(&app.key_reader)
		thread.destroy(app.key_reader._worker)
	}

	log.info("Ready...")
	return os_main_loop()
}

main :: proc()
{
	logger := log.create_console_logger()
	context.logger = logger

	exit_err := run(logger)

	if exit_err != .None {
		log.errorf("ZipChord Error: %v", exit_err)
		log.destroy_console_logger(logger)
		os.exit(int(exit_err))
	}

	log.destroy_console_logger(logger)
}
