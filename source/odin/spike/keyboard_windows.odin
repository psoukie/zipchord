package zipchord

import win32 "core:sys/windows"
foreign import user32 "system:User32.lib"
import "core:time"
import "core:unicode/utf16"
import "base:runtime"

HKL :: distinct win32.HANDLE

GUI_Thread_Info :: struct {
	cb_size: win32.DWORD,
	flags: win32.DWORD,
	hwnd_active: win32.HWND,
	hwnd_focus: win32.HWND,
	hwnd_capture: win32.HWND,
	hwnd_menu_owner: win32.HWND,
	hwnd_move_size: win32.HWND,
	hwnd_caret: win32.HWND,
	rc_caret: win32.RECT,
}

#assert(size_of(GUI_Thread_Info) == 8 + 6 * size_of(win32.HWND) + size_of(win32.RECT))

foreign user32 {
	GetGUIThreadInfo :: proc "system" (
		thread_id: win32.DWORD,
		gui_thread_info: ^GUI_Thread_Info,
	) -> win32.BOOL ---
	GetKeyboardLayout :: proc "system" (
		thread_id: win32.DWORD
	) -> HKL ---
	MapVirtualKeyExW :: proc "system" (
		code: win32.UINT,
		map_type: win32.UINT,
		keyboard_layout: HKL,
	) -> win32.UINT ---
	ToUnicodeEx :: proc "system" (
		virtual_key: win32.UINT,
		scan_code: win32.UINT,
		key_state: ^win32.BYTE,
		buffer: win32.LPWSTR,
		buffer_length: win32.INT,
		flags: win32.UINT,
		keyboard_layout: HKL,
	) -> win32.INT ---
}

SCAN_TABLE_SIZE :: 0x200

key_map_init :: proc(key_map: ^Key_Map) {
	key_map^ = {}

	key_map.zc_printable_to_scan = {
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
		.Slash = 0x035,
		.Spacebar = 0x039,

		.Pad_Slash = 0x135,
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

	key_map.zc_modifier_to_scan = {
		.Left_Shift = 0x02A,
		.Right_Shift = 0x036,
		.Left_Control = 0x01D,
		.Right_Control = 0x11D,
		.Left_Alt = 0x038,
		.Right_Alt = 0x138,
		.Left_GUI = 0x15B,
		.Right_GUI = 0x15C,
	}

	key_map.zc_special_to_scan = {
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

	populate_reverse :: proc(
		key_zc_to_scan: [$T]Scan_ID,
		scan_to_key_zc: ^[SCAN_TABLE_SIZE]Key_ZC)
	{
		for scan, key in key_zc_to_scan {
			assert(
				scan > 0 && scan < SCAN_TABLE_SIZE,
				"Scan code out of range",
			)
			assert(
				scan_to_key_zc[scan] == nil,
				"Scan code is double assigned",
			)
			scan_to_key_zc[scan] = key
		}
	}

	populate_reverse(key_map.zc_printable_to_scan, &key_map.scan_to_key_zc)
	populate_reverse(key_map.zc_modifier_to_scan, &key_map.scan_to_key_zc)
	populate_reverse(key_map.zc_special_to_scan, &key_map.scan_to_key_zc)
}

key_hkl_from_foreground :: proc() -> HKL {
	foreground_hwnd := win32.GetForegroundWindow()
	if foreground_hwnd == nil do return nil

	foreground_thread_id := win32.GetWindowThreadProcessId(foreground_hwnd, nil)
	if foreground_thread_id == 0 do return nil

	// Some applications give keyboard focus to a window owned by another thread.
	gui_info := GUI_Thread_Info {
		cb_size = size_of(GUI_Thread_Info),
	}
	if GetGUIThreadInfo(foreground_thread_id, &gui_info) != win32.FALSE &&
			gui_info.hwnd_focus != nil {
		focus_thread_id := win32.GetWindowThreadProcessId(gui_info.hwnd_focus, nil)
		if focus_thread_id != 0 {
			focus_hkl := GetKeyboardLayout(focus_thread_id)
			if focus_hkl != nil {
				return focus_hkl
			}
		}
	}

	return GetKeyboardLayout(foreground_thread_id)
}

key_symbol_map_populate :: proc(key_map: ^Key_Map) -> bool {
	// Supported since Windows 10 1607; avoids leaving ToUnicodeEx's internal
	// dead-key state changed while we probe a layout.
	TO_UNICODE_NO_STATE_CHANGE :: win32.UINT(1 << 2)

	translate_scan_to_symbol :: proc(
		hkl: HKL,
		scan: Scan_ID,
		with_shift: bool,
	) -> rune {
		windows_scan := win32.UINT(scan)
		virtual_key := MapVirtualKeyExW(
			windows_scan,
			win32.MAPVK_VSC_TO_VK_EX,
			hkl,
		)
		if virtual_key == 0 do return 0

		key_state: [256]win32.BYTE
		if with_shift {
			key_state[win32.VK_SHIFT] = 0x80
		}
		buffer: [8]u16
		count := ToUnicodeEx(
			virtual_key,
			win32.UINT(scan),
			&key_state[0],
			&buffer[0],
			len(buffer),
			TO_UNICODE_NO_STATE_CHANGE,
			hkl,
		)
		if count <= 0 do return 0

		// A Key_Typed_Char entry represents exactly one Unicode code point.
		// Reject a layout translation that produces a multi-rune string.
		symbol, width := utf16.decode_rune_in_string(string16(buffer[:count]))
		if width != int(count) do return 0
		return symbol
	}

	hkl := key_hkl_from_foreground()
	if hkl == nil {
		hkl = GetKeyboardLayout(0)
	}
	if hkl == nil do return false

	key_map.printable_to_symbol = {}
	key_map.printable_to_typed_char = {}
	clear(&key_map.symbol_to_printable)
	err := reserve(&key_map.symbol_to_printable, len(Key_Printable))
	if err != .None {
		panic("Could not allocate key symbol map")
	}

	for printable in Key_Printable {
		// Numeric-pad keys use layout-independent dictionary symbols so they
		// remain distinct from their main-keyboard counterparts.
		symbol: rune
		typed_char: Key_Typed_Char
		num: rune
		#partial switch printable {
		case .Pad_Slash:  symbol, num = '⊘', '/'
		case .Pad_Star:   symbol, num = '⊗', '*'
		case .Pad_7:      symbol, num = '⑦', '7'
		case .Pad_8:      symbol, num = '⑧', '8'
		case .Pad_9:      symbol, num = '⑨', '9'
		case .Pad_Dash:   symbol, num = '⊖', '-'
		case .Pad_4:      symbol, num = '④', '4'
		case .Pad_5:      symbol, num = '⑤', '5'
		case .Pad_6:      symbol, num = '⑥', '6'
		case .Pad_Plus:   symbol, num = '⊕', '+'
		case .Pad_1:      symbol, num = '①', '1'
		case .Pad_2:      symbol, num = '②', '2'
		case .Pad_3:      symbol, num = '③', '3'
		case .Pad_0:      symbol, num = '⓪', '0'
		case .Pad_Period: symbol, num = '⊙', '.'
		case:
			scan, _ := key_scan_code_from_key_zc(key_map^, printable)
			symbol = translate_scan_to_symbol(hkl, scan, false)
			typed_char.plain = symbol
			typed_char.with_shift = translate_scan_to_symbol(hkl, scan, true)
		}

		if num != 0 {
			typed_char.plain = num
			typed_char.with_shift = num
		}
		key_map.printable_to_typed_char[printable] = typed_char
		if symbol != 0 {
			key_map.printable_to_symbol[printable] = symbol
			key_map.symbol_to_printable[symbol] = printable
		}
	}
	return true
}

key_scan_code_from_key_zc :: proc(key_map: Key_Map, key: Key_ZC) ->
	(scan: Scan_ID, is_extended: bool) {
	switch k in key {
	case Key_Printable:
		scan = key_map.zc_printable_to_scan[k]
	case Key_Modifier:
		scan = key_map.zc_modifier_to_scan[k]
	case Key_Special:
		scan = key_map.zc_special_to_scan[k]
	}
	is_extended = (scan & 0x100 != 0)
	return scan & 0xff, is_extended
}

key_zc_from_key_raw :: proc(key_map: Key_Map, raw_key: win32.RAWKEYBOARD) ->
	(key: Key_ZC, is_up: bool) {
	if raw_key.Flags & win32.RI_KEY_E1 != 0 {
		return key, is_up   // We don't support key(s) with E1
	}
	scan := raw_key.MakeCode
	is_up = (raw_key.Flags & win32.RI_KEY_BREAK != 0)
	if raw_key.Flags & win32.RI_KEY_E0 != 0 {
		scan += 0x100
	}
	assert(scan < SCAN_TABLE_SIZE, "Legal scan code must fit in the table")
	return key_map.scan_to_key_zc[scan], is_up
}

WINDOWS_CLASS_NAME :: "ZipChordSpike"

window_proc :: proc "system" (
	hwnd: win32.HWND,
	message: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	context = runtime.default_context()
	context.logger = app_logger

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
			key, is_up := key_zc_from_key_raw(key_map, raw_key)
			if key == nil {
				// ignore untracked keys
				return win32.DefWindowProcW(hwnd, message, wparam, lparam)
			}

			if !keys_down_update(&keys_down, key, is_up) {
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

os_window_init :: proc() -> rawptr {
	instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))
	class_name := cstring16(win32.L(WINDOWS_CLASS_NAME))
	window_class := win32.WNDCLASSEXW {
		cbSize        = win32.UINT(size_of(win32.WNDCLASSEXW)),
		lpfnWndProc   = window_proc,
		hInstance     = instance,
		lpszClassName = class_name,
	}
	if win32.RegisterClassExW(&window_class) == 0 {
		return nil
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
	return rawptr(hwnd)
}


register_keyboard_hook :: proc(hwnd: rawptr) -> bool {
	raw_keyboard := win32.RAWINPUTDEVICE {
		usUsagePage = 0x01, // Generic Desktop Controls
		usUsage     = 0x06, // Keyboard
		dwFlags     = win32.RIDEV_INPUTSINK,
		hwndTarget  = win32.HWND(hwnd),
	}

	ok := win32.RegisterRawInputDevices(
		&raw_keyboard,
		1,
		win32.UINT(size_of(win32.RAWINPUTDEVICE)),
	)
	return bool(ok)
}

main_loop :: proc() {
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
