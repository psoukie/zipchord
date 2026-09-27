package zipchord

import "core:log"
import "core:time"
import "core:container/queue"
import "core:thread"
import "core:sync"

INPUT_BUFFER_LENGTH :: 256
CHORD_DETECTION_OVERLAP_PERCENTAGE :: .65
EDIT_EVENT_BUFFER_LENGTH :: 256

Input_Timing :: struct {
	start: Timestamp_MS,
	end: Timestamp_MS,
}

Input_Event :: struct {
	key: Key_Printable,
	timing: Input_Timing,
}


Input_Events :: struct {
	events: [INPUT_BUFFER_LENGTH]Input_Event,
	offset: int,
	length: int,
	classify_from: int,
}

input_event_at :: proc(input_ev: ^Input_Events, rel_index: int) -> ^Input_Event
{
	abs_index := (rel_index + input_ev.offset) % INPUT_BUFFER_LENGTH
	return &input_ev.events[abs_index]
}

Input_Classifier :: struct {
	keys_active: bit_set[Key_Printable],
	key_index: [Key_Printable]int,
}

Edit_Delete :: distinct int
Edit_Output_Key :: struct {
	key: Key_Printable,
	with_shift: bool,
}

Smart_Space :: Edit_Output_Key {
	key = .Spacebar,
	with_shift = false,
}

Edit_Event :: union {
	Edit_Delete,
	Edit_Output_Key,
	Expansion,
}

Edit_Buffer :: [dynamic; EDIT_EVENT_BUFFER_LENGTH]Edit_Event

IO_Engine :: struct {
	classifier: Input_Classifier,
	input: Input_Events,
	key_map: ^Key_Map,
	dictionaries: Dictionaries,
	edits: Edit_Buffer,
	output: Keyboard_Output,
}

io_worker_init :: proc(
		reader: ^Key_Reader,
		input_engine: ^IO_Engine,
		logger: log.Logger,
		os_state: ^OS_State,
		key_map: ^Key_Map,
) -> bool
{
	reader.logger = logger
	reader.os_state = os_state
	reader.start_time = time.tick_now()
	queue.init_from_slice(&reader.events, reader._buffer[:])
	input_engine.key_map = key_map
	reader.running = true
	reader._worker = thread.create_and_start_with_poly_data2(
			reader,
			input_engine,
			io_worker,
	)
	return reader._worker != nil
}

io_worker :: proc(reader: ^Key_Reader, io: ^IO_Engine)
{
	record_input_event :: proc(
			io: ^IO_Engine,
			key_ev: Key_Event,
			key: Key_Printable,
			record_as_up: bool,
	) -> (event_index: int, err: App_Error) {
		if key_ev.is_up != record_as_up do return -1, .Key_Up_Down_Mismatch

		input := &io.input

		if record_as_up {
			ev_index := io.classifier.key_index[key]
			input_event_at(input, ev_index).timing.end = key_ev.timestamp
			io.classifier.keys_active -= {key}
			return ev_index, .None
		}

		// record a key down
		if input.length == INPUT_BUFFER_LENGTH do return -1, .Input_Event_Buffer_Full

		input_ev: Input_Event
		input_ev.key = key
		input_ev.timing.start = key_ev.timestamp
		io.classifier.keys_active += {key}

		input_event_at(input, input.length)^ = input_ev
		io.classifier.key_index[key] = input.length
		input.length += 1
		return input.length - 1, .None
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
			record_as_up := key in io.classifier.keys_active
			ev_id, err := record_input_event(io, key_ev, key, record_as_up)
			if err == .Input_Event_Buffer_Full {
				log.error("Input buffer of IO engine is full.")
				if !os_post_message(reader.os_state, .Quit) {
					log.error("Could not post application quit message.")
				}
				break
			}
			if err == .Key_Up_Down_Mismatch do break

			if !record_as_up do break

			// Shift the input window offset when no keys are held and its safe
			drop_count := INPUT_BUFFER_LENGTH / 4
			if io.input.length > (INPUT_BUFFER_LENGTH / 2) &&
					card(io.classifier.keys_active) == 0 &&
					io.input.classify_from >= drop_count &&
					ev_id >= drop_count {
				io.input.offset = (io.input.offset + drop_count) % INPUT_BUFFER_LENGTH
				io.input.length -= drop_count
				io.input.classify_from -= drop_count
				ev_id -= drop_count
			}

			// Ignore keys from already discarded potential chords
			if ev_id < io.input.classify_from do break

			found, chord := io_classify(&io.input, ev_id)


			if !found do break

			exp, dict_err := dict_lookup(io.dictionaries.chord, chord)
			if dict_err == .Not_Found do break

			if dict_err == .Dictionary_Not_Initialized {
				log.warnf("Dictionary not initialized.")
				break
			}

			// TK: This will eventually create an array of edits
			clear(&io.edits)
			chars_to_del := card(chord)
			io_edits_append(&io.edits, Edit_Delete(chars_to_del)) or_break

			io_edits_append(&io.edits, exp) or_break

			io_edits_append(&io.edits, Smart_Space) or_break

			edit_err := edits_process(&io.output, io.key_map, io.edits[:])
			if edit_err != .None {
				log.error("Error in processing edits")
				clear(&io.edits)
				break
			}

		case Key_Special:
			if key_ev.is_up do break

			switch key {
			case .Enter, .Pad_Enter:
				io_input_reset(io)
				// TK: should set the engine so that shorthand and capitalization are enabled
			case .Backspace:
				// TK: Backspace
			case .Left, .Right, .Up, .Down, .Home, .End, .Page_Up, .Page_Down:
				io_input_reset(io)
			case .Tab, .Insert, .Delete:
				// do nothing
			case .Escape:
				// TK: Provisional way to quit ZipChord
				if !os_post_message(reader.os_state, .Quit) {
					log.error("Could not post application quit message.")
				}
			}
		}
	}
}

io_input_reset :: proc(io: ^IO_Engine)
{
	io.input.offset = 0
	io.input.length = 0
	io.input.classify_from = 0
	io.classifier = {}
}

io_classify :: proc(
		input: ^Input_Events,
		lifted_key_index: int,
) -> (detected_chord: bool, chord: Chord)
{
	last_event_index := input.length - 1
	if input.classify_from == last_event_index {
		// we're classifying a single key
		input.classify_from = last_event_index + 1
		return false, chord
	}

	start_of_last_ev := input_event_at(input, last_event_index).timing.start
	end_of_lift_ev := input_event_at(input, lifted_key_index).timing.end
	shortest_duration := end_of_lift_ev - start_of_last_ev

	iter_until := min(lifted_key_index, last_event_index - 1)
	for opening_index in input.classify_from..=iter_until {
		start_of_opening_ev := input_event_at(input, opening_index).timing.start
		duration := end_of_lift_ev - start_of_opening_ev
		overlap_pct := f32(shortest_duration) / f32(duration) if duration > 0 else 0
		if overlap_pct >= CHORD_DETECTION_OVERLAP_PERCENTAGE {
			input.classify_from = input.length
			for chord_index in opening_index..<input.length {
				chord += {input_event_at(input, chord_index).key}
			}
			return true, chord
		}
	}

	input.classify_from = lifted_key_index + 1
	return false, chord
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

io_edits_append :: proc(
		edit_buf: ^Edit_Buffer,
		edit: Edit_Event,
	) -> App_Error
{
	if append(edit_buf, edit) == 0 {
		log.error("Edit event buffer is full.")
		clear(edit_buf)
		return .Edit_Buffer_Full
	}

	return .None
}

edits_process :: proc(
		output: ^Keyboard_Output,
		key_map: ^Key_Map,
		edit_events: []Edit_Event,
) -> (err: App_Error)
{
	defer clear(output)

	for edit in edit_events {
		switch ed in edit {
		case Edit_Delete:
			err = output_add_backspaces(output, int(ed))
		case Expansion:
			err = output_add_expansion(output, ed)
		case Edit_Output_Key:
			err = output_add_key(output, key_map, ed)
		}

		if err != .None {
			log.errorf("ZipChord error while preparing output events: %v", err)
			return err
		}
	}

	qpc_start := time.tick_now()

	err = output_send_keys(output)
	if err != .None {
		log.errorf("ZipChord error while outputting events: %v", err)
		return err
	}

	elapsed_us := time.duration_microseconds(time.tick_diff(qpc_start, time.tick_now()))
	log.infof("QPC: %.2f us", elapsed_us)

	return .None
}
