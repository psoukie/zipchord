package main

import win32 "core:sys/windows"
import "core:os"
import "core:time"
import "core:fmt"
import "core:strings"
import "base:runtime"

app_start_time: time.Tick

window_proc :: proc "system" (
	hwnd: win32.HWND,
	message: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	context = runtime.default_context()
	switch message {
	case win32.WM_INPUT:
		timestamp := time.tick_now()
		to_first_key := time.tick_diff(app_start_time, timestamp)

		raw: win32.RAWINPUT
		raw_size := win32.UINT(size_of(raw))

		bytes_read := win32.GetRawInputData(
			win32.HRAWINPUT(lparam),
			win32.RID_INPUT,
			&raw,
			&raw_size,
			win32.UINT(size_of(win32.RAWINPUTHEADER)),
		)

		if bytes_read != ~win32.UINT(0) && raw.header.dwType == win32.RIM_TYPEKEYBOARD {
			key := raw.data.keyboard

			is_key_up := (key.Flags & win32.RI_KEY_BREAK) != 0
			is_e0 := (key.Flags & win32.RI_KEY_E0) != 0
			is_e1 := (key.Flags & win32.RI_KEY_E1) != 0

			buf := strings.builder_make()
			defer strings.builder_destroy(&buf)

			microseconds := time.duration_microseconds(to_first_key)
			time_string := fmt.sbprintf(
				&buf, "time (ms): %v, MakeCode: %v, Flags: %v, VKey: %v",
				microseconds,
				key.MakeCode, key.Flags, key.VKey,
			)
			_ = os.write_entire_file("output.txt", time_string)

			// and exit immediatelly
			win32.PostMessageW(hwnd, win32.WM_CLOSE, 0, 0)
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
	class_name := cstring16(win32.L("OdinHiddenWindowSpike"))

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
	   _ = os.write_entire_file("output.txt", "not ok")
		return
	}

	_ = os.write_entire_file("output.txt", "ok")

	app_start_time = time.tick_now()

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
