
/*
This file is part of ZipChord.
Copyright (c) 2021-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license.
*/

; OS-specific keyboard layout, input, and output handling

; WireHotKeys(["On"|"Off"]): Creates or releases hotkeys for tracking typing and chords
WireHotkeys(state) {
    global SC_to_symbol_map
    interrupts := "Del|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|LButton|RButton|Tab|NumpadEnd|NumpadDown|NumpadPgDn|NumpadLeft|NumpadRight|NumpadHome|NumpadUp|NumpadPgUp|NumpadDel" ; keys that interrupt the typing flow

    locale.RefreshScanCodeMapping()

    For sc_hex, symbol in SC_to_symbol_map {
        SC := str.SCHexToString(sc_hex)
        Hotkey, % "~" . SC, KeyDown, %state%
        Hotkey, % "~+" . SC, KeyDown, %state%
        Hotkey, % "~" . SC . " Up", KeyUp, %state%
        Hotkey, % "~+" . SC . " Up", KeyUp, %state%
    }

    Hotkey, % "~Space", KeyDown, %state%
    Hotkey, % "~+Space", KeyDown, %state%
    Hotkey, % "~Space Up", KeyUp, %state%
    Hotkey, % "~+Space Up", KeyUp, %state%
    Hotkey, % "~Shift", Shift_key, %state%
    Hotkey, % "~Shift Up", Shift_key, %state%
    Hotkey, % "~Enter", Enter_key, %state%
    Hotkey, % "~Backspace", Backspace_key, %state%
    Hotkey, % "~^Backspace", Ctrl_Backspace_key, %state%
    Loop Parse, % interrupts , |
    {
        Hotkey, % "~" A_LoopField, Interrupt, %state%
        Hotkey, % "~^" A_LoopField, Interrupt, %state%
    }
    runtime_status.is_keyboard_wired := state
}

Class clsOsKeyboard {
    DEBOUNCE_MS := 500

    current_layout_name := ""
    _current_hkl := 0
    _pending_hkl := 0
    _pending_since := 0
    _hkl_to_name_cache := {}

    GetActiveLayoutName() {
        hkl := this._GetForegroundHkl()
        if (! hkl) {
            return this.current_layout_name
        }
        layout_name := this._HklToName(hkl)
        if (layout_name) {
            this.current_layout_name := layout_name
            this._current_hkl := hkl
            this._pending_hkl := 0
            this._pending_since := 0
            return layout_name
        }

        if (this.current_layout_name) {
            return this.current_layout_name
        }
        return "Unknown"
    }

    CheckForLayoutChange() {
        changed_layout_name := ""
        hkl := this._GetForegroundHkl()
        if (! hkl) {
            return false
        }

        if (hkl == this._current_hkl) {
            this._pending_hkl := 0
            this._pending_since := 0
            return false
        }

        if (hkl != this._pending_hkl) {
            this._pending_hkl := hkl
            this._pending_since := A_TickCount
            return false
        }
        if (A_TickCount - this._pending_since < this.DEBOUNCE_MS) {
            return false
        }

        changed_layout_name := this._HklToName(hkl)
        if (!changed_layout_name) {
            return false
        }
        this.current_layout_name := changed_layout_name
        this._current_hkl := hkl
        this._pending_hkl := 0
        this._pending_since := 0
        return changed_layout_name
    }

    SetZipChordToHkl(hkl := -1) {
        if (hkl == -1) {
            hkl := this._current_hkl
        }
        own_hkl := DllCall("user32.dll\GetKeyboardLayout", "UInt", 0, "Ptr")
        if (own_hkl == hkl) {
            return true
        }
        return DllCall("user32.dll\ActivateKeyboardLayout"
                , "Ptr", hkl, "UInt", 0, "Ptr") != 0
    }

    _GetForegroundHkl() {
        hwnd := DllCall("user32.dll\GetForegroundWindow", "Ptr")
        if (!hwnd) {
            return false
        }

        process_id := 0
        thread_id := DllCall("user32.dll\GetWindowThreadProcessId"
                , "Ptr", hwnd, "UInt*", process_id, "UInt")
        if (!thread_id) {
            return false
        }

        hkl := DllCall("user32.dll\GetKeyboardLayout", "UInt", thread_id, "Ptr")
        if (!hkl) {
            return false
        }

        return hkl
    }

    _HklToName(hkl) {
        if (this._hkl_to_name_cache.HasKey(hkl)) {
            return this._hkl_to_name_cache[hkl]
        }

        ; We swich ZipChord to the active HKL to read and cache its name
        if (!this.SetZipChordToHkl(hkl)) {
            return false
        }

        VarSetCapacity(layout_id, 9 * 2, 0)
        if (!DllCall("user32.dll\GetKeyboardLayoutNameW", "Ptr", &layout_id)) {
            return false
        }
        klid := StrGet(&layout_id, 8, "UTF-16")

        RegRead, name
                , % "HKLM"
                , % "SYSTEM\CurrentControlSet\Control\Keyboard Layouts\" . klid
                , % "Layout Text"
            
        if (!name) {
            name := klid
        }
        this._hkl_to_name_cache[hkl] := name
        return name
    }
}

global kb := new clsOsKeyboard
