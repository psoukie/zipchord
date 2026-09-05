package zipchord

import "core:time"
import "core:log"
import "core:container/queue"
import "core:thread"
import "core:sync"
import "base:runtime"

Key_Printable :: enum u8 {
	Grave,
	Num_1, Num_2, Num_3, Num_4, Num_5, Num_6, Num_7, Num_8, Num_9, Num_0,
	Dash, Equals,
	Q, W, E, R, T, Y, U, I, O, P,
	Left_Brace, Right_Brace, Backslash,
	A, S, D, F, G, H, J, K, L,
	Semicolon, Apostrophe,
	Z, X, C, V, B, N, M,
	Comma, Period, Slash,
	Spacebar,
	Pad_Slash, Pad_Star,
	Pad_7, Pad_8, Pad_9, Pad_Dash,
	Pad_4, Pad_5, Pad_6, Pad_Plus,
	Pad_1, Pad_2, Pad_3, Pad_0, Pad_Period,
}

#assert(len(Key_Printable) <= 64)  // to fit into a u64 bitset

Key_Modifier :: enum u8 {
	Left_Shift,
	Right_Shift,
	Left_Control,
	Right_Control,
	Left_Alt,
	Right_Alt,
	Left_GUI,
	Right_GUI,
}

Key_Special :: enum u8 {
	Enter,
	Pad_Enter,
	Backspace, // called "Delete" in HID
	Tab,
	Escape,
	Left,
	Right,
	Up,
	Down,
	Home,
	End,
	Page_Up,
	Page_Down,
	Insert,
	Delete, // called "Delete Forward" in HID
}

Key_ZC :: union {
	Key_Printable,
	Key_Modifier,
	Key_Special,
}

Key_Event :: struct {
	timestamp: i32,
	key: Key_ZC,
	is_up: bool,
}

Keys_Down :: struct {
	printable: bit_set[Key_Printable],
	modifiers: bit_set[Key_Modifier],
	special: bit_set[Key_Special],
}

// TK: need to add listening for mouse button events

Scan_ID :: distinct u16

Key_Typed_Char :: struct {
	plain: rune,
	with_shift: rune,
}

Key_Map :: struct {
	zc_printable_to_scan: [Key_Printable]Scan_ID,
	zc_modifier_to_scan: [Key_Modifier]Scan_ID,
	zc_special_to_scan: [Key_Special]Scan_ID,
	scan_to_key_zc: [SCAN_TABLE_SIZE]Key_ZC,
	printable_to_symbol: [Key_Printable]rune,
	symbol_to_printable: map[rune]Key_Printable,
	printable_to_typed_char: [Key_Printable]Key_Typed_Char,
}

key_map: Key_Map
keys_down: Keys_Down

app_logger: log.Logger

key_symbol_map_delete :: proc(key_map: ^Key_Map) {
	delete(key_map.symbol_to_printable)
}

key_printable_from_symbol :: proc(key_map: Key_Map, symbol: rune) ->
	(printable: Key_Printable, ok: bool)
{
	return key_map.symbol_to_printable[symbol]
}

key_symbol_from_printable :: proc(
	key_map: Key_Map,
	printable: Key_Printable,
) -> (symbol: rune, ok: bool) {
	symbol = key_map.printable_to_symbol[printable]
	return symbol, symbol != 0
}

key_typed_char_from_printable :: proc(
	key_map: Key_Map,
	printable: Key_Printable,
	with_shift := false,
) -> (typed_char: rune, ok: bool) {
	typed_chars := key_map.printable_to_typed_char[printable]
	typed_char = typed_chars.with_shift if with_shift else typed_chars.plain
	return typed_char, typed_char != 0
}

keys_down_update :: proc(
	keys_list: ^Keys_Down,
	key: Key_ZC,
	is_up: bool,
) -> (has_changed: bool) {
	key_down_update :: proc(set: ^$S, key: $K, is_up: bool) -> bool {
		was_down := key in set^
		if was_down == !is_up do return false

		if is_up {
			set^ -= {key}
		} else {
			set^ += {key}
		}
		return true
	}

	switch k in key {
	case Key_Printable:
		has_changed = key_down_update(&keys_list.printable, k, is_up)
	case Key_Modifier:
		has_changed = key_down_update(&keys_list.modifiers, k, is_up)
	case Key_Special:
		has_changed = key_down_update(&keys_list.special, k, is_up)
	}
	return has_changed
}

KEY_BUFFER_LENGTH :: 128

Key_Reader :: struct {
	_buffer: [KEY_BUFFER_LENGTH]Key_Event,
	_worker: ^thread.Thread,
	start_time: time.Tick,
	events: queue.Queue(Key_Event),
	sema: sync.Sema,
	running: bool,
	mutex: sync.Mutex
}

key_reader: Key_Reader

key_reader_init :: proc(reader: ^Key_Reader) -> bool {
	reader.start_time = time.tick_now()
	queue.init_from_slice(&reader.events, reader._buffer[:])
	reader.running = true
	reader._worker = thread.create_and_start_with_poly_data(
		reader,
		io_worker,
	)
	return reader._worker != nil
}

key_reader_event_add :: proc(reader: ^Key_Reader, event: Key_Event) -> bool {
	log.info("Adding an event...")
	sync.mutex_lock(&reader.mutex)
	ok, err := queue.push(&reader.events, event)
	sync.mutex_unlock(&reader.mutex)
	if !ok || err != .None {
		return false
	}

	sync.sema_post(&reader.sema)
	return true
}

key_reader_stop :: proc(reader: ^Key_Reader) {
	sync.mutex_lock(&reader.mutex)
	reader.running = false
	sync.mutex_unlock(&reader.mutex)
	sync.sema_post(&reader.sema)
}

io_worker :: proc(reader: ^Key_Reader) {
	context.logger = app_logger
	for {
		sync.sema_wait(&reader.sema)

		sync.mutex_lock(&reader.mutex)
		running := reader.running
		key_ev, ok := queue.pop_front_safe(&reader.events)
		sync.mutex_unlock(&reader.mutex)

		if !ok {
			if running {
				continue
			} else {
				return
			}
		}

		log.infof(
			"%v\t%v\t%v",
			key_ev.timestamp,
			"Up" if key_ev.is_up else "Down",
			key_ev.key,
		)
	}
}

