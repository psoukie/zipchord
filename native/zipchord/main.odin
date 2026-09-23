package zipchord

// SPDX-FileCopyrightText: 2026 Pavel Soukenik
// SPDX-License-Identifier: BSD-3-Clause

import "core:thread"
import "core:log"
import "core:os"

App_State :: struct {
	logger: log.Logger,
	key_map: Key_Map,
	key_reader: Key_Reader,
	input_engine: IO_Engine,
	os_state: OS_State,
}

App_Message :: enum {
	Quit = 1,
	Open_Command_Menu,
}

App_Error :: enum {
	None,
	Key_Event_Buffer_Full,
	Input_Event_Buffer_Full,
	Key_Up_Down_Mismatch,
	Windows_GetMessageW_Failed,
	Windows_GetRawInput_Failed,
	Windows_SendInput_Failed,
	Windows_Platform_Init_Failed,
	Key_Map_Alloc_Error,
	Key_Reader_Init_Failed,
	Unhandled_Dictionary_Error,
	File_Read_Write_Error,
	Memory_Allocation_Failed,
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

	dict_err := dict_init(&app.input_engine.dictionaries.chord)
	if dict_err != .None do return .Unhandled_Dictionary_Error

	defer dict_destroy(&app.input_engine.dictionaries.chord)

	spike_dictionary := "en-dvorak.chords.txt"
	result, dict_load_err := dict_chord_load_file(&app.input_engine.dictionaries.chord, app.key_map, spike_dictionary)
	if dict_load_err != .None {
		log.errorf("ZipChord Error: %v - %v", dict_load_err, result)
		return .Unhandled_Dictionary_Error
	}

	log.infof("Loaded %v entries into the chord dictionary.", app.input_engine.dictionaries.chord.entries_count)

	if !io_worker_init(
			&app.key_reader,
			&app.input_engine,
			app.logger,
			&app.os_state,
	) {
		return .Key_Reader_Init_Failed
	}

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
