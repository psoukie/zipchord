package main

import win32 "core:sys/windows"
import "core:os"
import "core:time"
import "core:fmt"
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
	Comma, Period, Forward_Slash,
	Spacebar,
	Pad_Forward_Slash, Pad_Star,
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

Key_Physical :: union {
	Key_Printable,
	Key_Modifier,
	Key_Special,
}

// TK: need to add listening for mouse button events

Windows_Scan_ID :: distinct u16

WINDOWS_KEY_PRINTABLE_TO_SCAN := [Key_Printable]Windows_Scan_ID {
	.Grave = 0x029,
	.Num_1 = 0x002,
	.Num_2 = 0x003,
	.Num_3 = 0x004,
	.Num_4 = 0x005,
	.Num_5 = 0x006,
	.Num_6 = 0x007,
	.Num_7 = 0x008,
	.Num_8 = 0x009,
	.Num_9 = 0x00A,
	.Num_0 = 0x00B,
	.Dash = 0x00C,
	.Equals = 0x00D,
	.Q = 0x010,
	.W = 0x011,
	.E = 0x012,
	.R = 0x013,
	.T = 0x014,
	.Y = 0x015,
	.U = 0x016,
	.I = 0x017,
	.O = 0x018,
	.P = 0x019,
	.Left_Brace = 0x01A,
	.Right_Brace = 0x01B,
	.Backslash = 0x02B,
	.A = 0x01E,
	.S = 0x01F,
	.D = 0x020,
	.F = 0x021,
	.G = 0x022,
	.H = 0x023,
	.J = 0x024,
	.K = 0x025,
	.L = 0x026,
	.Semicolon = 0x027,
	.Apostrophe = 0x028,
	.Z = 0x02C,
	.X = 0x02D,
	.C = 0x02E,
	.V = 0x02F,
	.B = 0x030,
	.N = 0x031,
	.M = 0x032,
	.Comma = 0x033,
	.Period = 0x034,
	.Forward_Slash = 0x035,
	.Spacebar = 0x039,

	.Pad_Forward_Slash = 0x135,
	.Pad_Star = 0x037,
	.Pad_7 = 0x047,
	.Pad_8 = 0x048,
	.Pad_9 = 0x049,
	.Pad_Dash = 0x04A,
	.Pad_4 = 0x04B,
	.Pad_5 = 0x04C,
	.Pad_6 = 0x04D,
	.Pad_Plus = 0x04E,
	.Pad_1 = 0x04F,
	.Pad_2 = 0x050,
	.Pad_3 = 0x051,
	.Pad_0 = 0x052,
	.Pad_Period = 0x053,
}

WINDOWS_KEY_MODIFIER_TO_SCAN := [Key_Modifier]Windows_Scan_ID {
	.Left_Shift = 0x02A,
	.Right_Shift = 0x036,
	.Left_Control = 0x01D,
	.Right_Control = 0x11D,
	.Left_Alt = 0x038,
	.Right_Alt = 0x138,
	.Left_GUI = 0x15B,
	.Right_GUI = 0x15C,
}

WINDOWS_KEY_SPECIAL_TO_SCAN := [Key_Special]Windows_Scan_ID {
	.Enter = 0x01C,
	.Pad_Enter = 0x11C,
	.Backspace = 0x00E,
	.Tab = 0x00F,
	.Escape = 0x001,
	.Left = 0x14B,
	.Right = 0x14D,
	.Up = 0x148,
	.Down = 0x150,
	.Home = 0x147,
	.End = 0x14F,
	.Page_Up = 0x149,
	.Page_Down = 0x151,
	.Insert = 0x152,
	.Delete = 0x153,
}

Key_Event :: struct {
	timestamp: i32,
	key: Key_Physical,
	is_up: bool,
}

WINDOWS_SCAN_TO_KEY_PHYSICAL: [0x200]Key_Physical

windows_key__init_scan_to_key :: proc() {
	populate_scan_to_key :: proc(array: [$T]Windows_Scan_ID) {
		for code, key in array {
			assert(
				code > 0 && code < len(WINDOWS_SCAN_TO_KEY_PHYSICAL),
				"Invalid scan code",
			)
			assert(
				WINDOWS_SCAN_TO_KEY_PHYSICAL[code] == nil,
				"Scan code double assigned",
			)
			WINDOWS_SCAN_TO_KEY_PHYSICAL[code] = key
		}
	}
	populate_scan_to_key(WINDOWS_KEY_PRINTABLE_TO_SCAN)
	populate_scan_to_key(WINDOWS_KEY_MODIFIER_TO_SCAN)
	populate_scan_to_key(WINDOWS_KEY_SPECIAL_TO_SCAN)
}

windows_key__get_scan_code :: proc(key: Key_Physical) ->
	(scan: Windows_Scan_ID, is_extended: bool) {
	switch k in key {
	case Key_Printable:
		scan = WINDOWS_KEY_PRINTABLE_TO_SCAN[k]
	case Key_Modifier:
		scan = WINDOWS_KEY_MODIFIER_TO_SCAN[k]
	case Key_Special:
		scan = WINDOWS_KEY_SPECIAL_TO_SCAN[k]
	}
	is_extended = (scan & 0x100 != 0)
	return scan & 0xff, is_extended
}

WINDOWS_CLASS_NAME :: "ZipChordSpike"
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
log_file: ^os.File

key_reader_init :: proc(reader: ^Key_Reader) -> bool {
	reader.start_time = time.tick_now()
	queue.init_from_slice(&reader.events, reader._buffer[:])
	reader.running = true
	reader._worker = thread.create_and_start_with_poly_data(
		reader,
		worker_write_event_to_file,
	)
	return reader._worker != nil
}

key_reader_event_add :: proc(reader: ^Key_Reader, event: Key_Event) -> bool {
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

key_get_physical_key :: proc(raw_key: win32.RAWKEYBOARD) ->
	(key: Key_Physical, is_up: bool) {
	if raw_key.Flags & win32.RI_KEY_E1 != 0 {
		return key, is_up   // We don't support key(s) with E1
	}
	key_code := raw_key.MakeCode
	is_up = (raw_key.Flags & win32.RI_KEY_BREAK != 0)
	if raw_key.Flags & win32.RI_KEY_E0 != 0 {
		key_code += 0x100
	}
	assert(key_code < len(WINDOWS_SCAN_TO_KEY_PHYSICAL), "Legal scan code must fit in the table")
	return WINDOWS_SCAN_TO_KEY_PHYSICAL[key_code], is_up
}

window_proc :: proc "system" (
	hwnd: win32.HWND,
	message: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	context = runtime.default_context()
	switch message {
	case win32.WM_INPUT:
		timestamp := time.tick_diff(key_reader.start_time, time.tick_now())

		raw: win32.RAWINPUT
		raw_size := win32.UINT(size_of(raw))

		bytes_read := win32.GetRawInputData(
			win32.HRAWINPUT(lparam),
			win32.RID_INPUT,
			&raw,
			&raw_size,
			win32.UINT(size_of(win32.RAWINPUTHEADER)),
		)

		if bytes_read != ~win32.UINT(0) &&
				raw.header.dwType == win32.RIM_TYPEKEYBOARD {
			raw_key := raw.data.keyboard
			key, is_up := key_get_physical_key(raw_key)
			if key == nil {
				// ignore untracked keys
				return win32.DefWindowProcW(hwnd, message, wparam, lparam)
			}

			key_ev := Key_Event {
				timestamp = i32(u64(time.duration_milliseconds(timestamp))),
				key = key,
				is_up = is_up,
			}

			ok := key_reader_event_add(&key_reader, key_ev)
			if !ok {
				// Buffer full, we exit
				win32.PostMessageW(hwnd, win32.WM_CLOSE, 0, 0)
			}

			// We test until 'X' is pressed
			if key_ev.key == Key_Printable.X {
				win32.PostMessageW(hwnd, win32.WM_CLOSE, 0, 0)
			}
		}

		// Required for appropriate Raw Input cleanup.
		// Unless we call
		// input_code := win32.GET_RAWINPUT_CODE_WPARAM(wparam)
		// and call DefWindowProcW only for RIM_INPUT
		return win32.DefWindowProcW(hwnd, message, wparam, lparam)

	case win32.WM_CLOSE:
		win32.DestroyWindow(hwnd)
		return 0

	case win32.WM_DESTROY:
		win32.PostQuitMessage(0)
		return 0
	}

	return win32.DefWindowProcW(hwnd, message, wparam, lparam)
}

main :: proc() {
	instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))
	class_name := cstring16(win32.L(WINDOWS_CLASS_NAME))

	window_class := win32.WNDCLASSEXW {
		cbSize        = win32.UINT(size_of(win32.WNDCLASSEXW)),
		lpfnWndProc   = window_proc,
		hInstance     = instance,
		lpszClassName = class_name,
	}

	if win32.RegisterClassExW(&window_class) == 0 {
		return
	}

	hwnd := win32.CreateWindowExW(
		0,
		class_name,
		cstring16(win32.L("Odin hidden window")),
		0,
		0, 0, 0, 0,
		nil, nil,
		instance,
		nil,
	)
	if hwnd == nil {
		return
	}

	e: os.Error
	log_file, e = os.create("output.txt")
	if e != os.General_Error.None do return

	windows_key__init_scan_to_key()

	if ! key_reader_init(&key_reader) {
		return
	}

	defer {
		key_reader_stop(&key_reader)
		thread.destroy(key_reader._worker)
		os.write_string(log_file, "\nlog closed ok\n")
		os.flush(log_file)
		os.close(log_file)
	}

	raw_keyboard := win32.RAWINPUTDEVICE {
		usUsagePage = 0x01, // Generic Desktop Controls
		usUsage     = 0x06, // Keyboard
		dwFlags     = win32.RIDEV_INPUTSINK,
		hwndTarget  = hwnd,
	}

	if ! win32.RegisterRawInputDevices(
		&raw_keyboard,
		1,
		win32.UINT(size_of(win32.RAWINPUTDEVICE)),
	) {
		os.write_string(log_file, "registering keyboard hook failed")
		return
	}

	_, e = os.write_string(log_file, "Time\tCode\tKey Up?\tScan\tExtended?\n")
	if e != os.General_Error.None do return

	fmt.printfln("Ready...")

	message: win32.MSG
	for {
		result := win32.GetMessageW(&message, nil, 0, 0)

		if result == 0 {
			// WM_QUIT
			break
		}

		if result == -1 {
			// GetMessageW failed.
			break
		}

		win32.TranslateMessage(&message)
		win32.DispatchMessageW(&message)
	}
}

worker_write_event_to_file :: proc(reader: ^Key_Reader) {
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

		scan_code, is_extended := windows_key__get_scan_code(key_ev.key)
		fmt.fprintfln(
			log_file,
			"%v\t%v\t%v\t0x%X\t%v",
			key_ev.timestamp,
			key_ev.key,
			key_ev.is_up,
			scan_code,
			is_extended,
		)
	}
}
