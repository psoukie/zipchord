package zipchord

import "core:log"
import "core:time"
import "core:container/queue"
import "core:thread"
import "core:sync"

Input_Timing :: struct {
	start: Timestamp_MS,
	end: Timestamp_MS,
}

Input_Event :: struct {
	key: Key_Printable,
	timing: Input_Timing,
}

INPUT_BUFFER_LENGTH :: 256

Input_Engine :: struct {
	events: [INPUT_BUFFER_LENGTH]Input_Event,
	start: int,
	length: int,
	keys_active: bit_set[Key_Printable],
	key_index: [Key_Printable]int,
	dictionaries: Dictionaries,
}

input_engine_reset :: proc ()
{

}

io_worker_init :: proc(
		reader: ^Key_Reader,
		input_engine: ^Input_Engine,
		logger: log.Logger,
		os_state: ^OS_State,
) -> bool
{
	reader.logger = logger
	reader.os_state = os_state
	reader.start_time = time.tick_now()
	queue.init_from_slice(&reader.events, reader._buffer[:])
	reader.running = true
	reader._worker = thread.create_and_start_with_poly_data2(
			reader,
			input_engine,
			io_worker,
	)
	return reader._worker != nil
}

io_worker :: proc(reader: ^Key_Reader, io: ^Input_Engine)
{
	record_input_event :: proc(
			io: ^Input_Engine,
			key_ev: Key_Event,
			key: Key_Printable,
			record_as_up: bool,
	) -> (event_id: int, err: App_Error) {
		if key_ev.is_up != record_as_up do return -1, .Key_Up_Down_Mismatch

		if record_as_up {
			ev_index := io.key_index[key]
			io.events[ev_index].timing.end = key_ev.timestamp
			io.keys_active -= {key}
			return ev_index, .None
		}

		// record a key down
		if io.length == INPUT_BUFFER_LENGTH do return -1, .Input_Event_Buffer_Full

		input_ev: Input_Event
		input_ev.key = key
		input_ev.timing.start = key_ev.timestamp
		io.keys_active += {key}

		write_index := (io.start + io.length) % INPUT_BUFFER_LENGTH
		io.events[write_index] = input_ev
		io.key_index[key] = write_index
		io.length += 1
		return write_index, .None
	}

	context.logger = reader.logger
	for {
		sync.sema_wait(&reader.sema)

		sync.mutex_lock(&reader.mutex)
		running := reader.running
		key_ev, ok := queue.pop_front_safe(&reader.events)
		sync.mutex_unlock(&reader.mutex)

		if !ok {
			if running do continue

			return
		}

		switch key in key_ev.key {
		case Key_Modifier:
			// Do nothing yet
		case Key_Printable:
			record_as_up := key in io.keys_active
			ev_id, err := record_input_event(io, key_ev, key, record_as_up)
			if err == .Input_Event_Buffer_Full {
				log.error("Input buffer of IO engine is full.")
				if !os_post_message(reader.os_state, .Quit) {
					log.error("Could not post application quit message.")
				}
				break
			}
			if err == .Key_Up_Down_Mismatch do break

			if record_as_up {
				input_ev := &io.events[ev_id]
				log.infof(
						"%v\t%v\t%v",
						input_ev.key,
						input_ev.timing.start,
						input_ev.timing.end,
				)
			}

		case Key_Special:
			// Do nothing yet
		}


		// We test until 'X' is pressed
		if key_ev.key == Key_Printable.X && !key_ev.is_up {
			if !os_post_message(reader.os_state, .Quit) {
				log.error("Could not post application quit message.")
			}
		}
	}
}

Token_Type :: enum {
    Character,
    Interrupt,
    Enter,
    Manual_Space,
    Smart_Space,
    Numeral,
    Punctuation,
    Expansion,
}

Token_Attribute :: enum {
    With_Shift,
    Was_Capitalized,
    Is_Prefix,
    Capitalizes_Next,
    First_In_Chord,
    Removes_Smart_Space,
    Smart_Space_After,
    Capitalizing_Key,
    Tombstoned,
}

Token_Output :: union {
	rune,
	Expansion,
}

Token :: struct {
	timestamp: Timestamp_MS,
	key: Key_ZC,
    type: Token_Type,
    attribs: bit_set[Token_Attribute],
    output: Token_Output,
}

