package main

import win32 "core:sys/windows"
import "core:os"
import "core:time"
import "core:fmt"
import "core:container/queue"
import "core:thread"
import "core:sync"
import "base:runtime"

Key_State :: enum {
	Is_Key_Up,
	Is_E0,
	Is_E1,
}

Physical_Key :: struct {
	key_code: u16,
	state: bit_set[Key_State; u16],
}

Key_Event :: struct {
	using physical_key: Physical_Key,
	timestamp: i32,
}

KEY_BUFFER_LENGTH :: 128

app_start_time: time.Tick
key_buffer: [KEY_BUFFER_LENGTH]Key_Event
key_events: queue.Queue(Key_Event)
log_file: ^os.File
key_buffer_mutex: sync.Mutex
worker_running := true
worker_sema: sync.Sema

key_q := Physical_Key{key_code = 0x2D}

window_proc :: proc "system" (
	hwnd: win32.HWND,
	message: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	context = runtime.default_context()
	switch message {
	case win32.WM_INPUT:
		timestamp := time.tick_diff(app_start_time, time.tick_now())

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
			raw_key := raw.data.keyboard
			timestamp_ms :=i32(u64(time.duration_milliseconds(timestamp)))

			key_ev: Key_Event
			key_ev.timestamp = timestamp_ms
			key_ev.key_code = raw_key.MakeCode
			if raw_key.Flags & win32.RI_KEY_BREAK != 0 {
				key_ev.state |= {.Is_Key_Up}
			}
			if raw_key.Flags & win32.RI_KEY_E0 != 0 {
				key_ev.state |= {.Is_E0}
			}
			if raw_key.Flags & win32.RI_KEY_E1 != 0 {
				key_ev.state |= {.Is_E1}
			}

			sync.mutex_lock(&key_buffer_mutex)
			ok, err := queue.push(&key_events, key_ev)
			sync.mutex_unlock(&key_buffer_mutex)

			if !ok || err == .None {
				sync.sema_post(&worker_sema)
			} else {
				// Buffer full
				// we exit
				win32.PostMessageW(hwnd, win32.WM_CLOSE, 0, 0)
			}

			// We test until 'Q' is pressed
			if key_ev == key_q {
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

	e: os.Error
	log_file, e = os.create("output.txt")
	if e != os.General_Error.None do return

	app_start_time = time.tick_now()

	queue.init_from_slice(&key_events, key_buffer[:])

	worker := thread.create_and_start(worker_write_event_to_file)
	if worker == nil do return


	defer {
		sync.mutex_lock(&key_buffer_mutex)
		worker_running = false
		sync.mutex_unlock(&key_buffer_mutex)
		sync.sema_post(&worker_sema)
		thread.destroy(worker)
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

	_, e = os.write_string(log_file, "time (ms)\tMakeCode\tKey up?\tExtended?\n")
	if e != os.General_Error.None do return

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

worker_write_event_to_file :: proc() {
	for {
		sync.sema_wait(&worker_sema)
		sync.mutex_lock(&key_buffer_mutex)
		continue_running := worker_running
		key_ev, ok := queue.pop_front_safe(&key_events)
		sync.mutex_unlock(&key_buffer_mutex)

		if !ok {
			if continue_running {
				continue
			} else {
				return
			}
		}

		is_extended := .Is_E0 in key_ev.state || .Is_E1 in key_ev.state
		fmt.fprintfln(
			log_file,
			"%v\t0x%X\t%v\t%v",
			key_ev.timestamp,
			key_ev.key_code,
			.Is_Key_Up in key_ev.state,
			is_extended
		)
	}
}
