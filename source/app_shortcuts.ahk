/*

This file is part of ZipChord.

Copyright (c) 2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

app_shortcuts := New clsAppShortcuts

/**
* App Shortcuts Class
*
*   Public methods:
*      Init
*      Show
*      GetHotkeyText   Get human-readable keyboard shortcut for activating a given function.
*      WireHotkeys(<"On"|"Off">)   Enable or disable the defined app hotkeys
*/
Class clsAppShortcuts {
    MD_SHORT := 1
    MD_LONG := 2

    shortcuts := { 1: { target:  "UI_Main_Show"
                      , display: "Open main ZipChord window"
                      , HK:      "^+z"
                      , mode:    this.MD_LONG}
                 , 2: { target:  "AddShortcut"
                      , display: "Open Add Shortcut window"
                      , HK:      "^c"
                      , mode:    this.MD_LONG}
                 , 3: { target:  "PauseApp"
                      , display: "Pause / Resume ZipChord"
                      , HK:      "^+F1"
                      , mode:    this.MD_SHORT}
                 , 4: { target:  "QuitApp"
                      , display: "Quit ZipChord"
                      , HK:      ""
                      , mode:    this.MD_SHORT}}

    controls := {}

    Init() {
        this._LoadSettings()
        this.WireHotkeys("On")
    }
    Show() {
        call := Func("OpenHelp").Bind("AppShortcuts")
        Hotkey, F1, % call, On
        this.WireHotkeys("Off")  ; so the current hotkeys don't interfere with defining
        UI := new clsUI("ZipChord Application Keyboard Shortcuts")
        UI.on_close := ObjBindMethod(this, "_CloseUI")
        UI.Add("Text", "x+20 y-35")
        For i, shortcut in this.shortcuts
        {
            this.controls[i] := {}
            UI.Add("GroupBox", "xs-20 y+35 w400 h90", shortcut.display)
            this.controls[i].HK := UI.Add("Hotkey", "xp+20 yp+37 Section Limit3", shortcut.HK, ObjBindMethod(this, "_UpdateUI", i))
            this.controls[i].long := UI.Add("Radio", "xs+180 ys-9", "Long press (non-exclusive)", , shortcut.mode==this.MD_LONG)
            this.controls[i].short := UI.Add("Radio", "y+10", "Short press (exclusive)", , shortcut.mode==this.MD_SHORT)
        }
        UI.Add("Button", "w80 xm+220 yp+60", "Cancel", ObjBindMethod(this, "_CloseUI"))
        temp := UI.Add("Button", "w80 xm+320 yp Default", "OK", ObjBindMethod(this, "_btnOK"))
        temp.Focus()
        UI.Show("w440")
        this.UI := UI
    }
    _SaveSettings() {
        For _, shortcut in this.shortcuts
            SaveVarToRegistry("hk_" . shortcut.target, shortcut.HK . "|" shortcut.mode)
    }
    _LoadSettings() {
        For _, shortcut in this.shortcuts
        {
            setting := ""
            UpdateVarFromRegistry(setting, "hk_" . shortcut.target)
            if (setting) {
                setting := StrSplit(setting, "|")
                shortcut.HK := setting[1]
                shortcut.mode := setting[2]
            }
        }
    }
    GetHotkeyText(target, press_prefix := "", hold_prefix := "hold ") {
        For _, shortcut in this.shortcuts
            if (shortcut.target == target && shortcut.HK) {
                prefix := shortcut.mode==this.MD_LONG ? hold_prefix : press_prefix
                return prefix . str.HotkeyToText(shortcut.HK)
            }
    }
    WireHotkeys(status) {
        For i, shortcut in this.shortcuts
            if (shortcut.HK) {
                call := ObjBindMethod(this, "_ProcessHotkey", i)
                if (shortcut.mode == this.MD_SHORT)
                    Hotkey, % shortcut.HK, % call, %status%
                else
                    Hotkey, % "~" . shortcut.HK, % call, %status%
            }
    }
    _ProcessHotkey(shortcut_ID) {
        shortcut := this.shortcuts[shortcut_ID]
        target := shortcut.target
        HK := RegExReplace(shortcut.HK, "[\+\^\!]")
        if (shortcut.mode == this.MD_LONG) {
            Sleep 300
            if GetKeyState(HK,"P")
                %target%()
        } else %target%()
    }
    _UpdateUI(shortcut_ID) {
        state := this.controls[shortcut_ID].HK.value ? 1 : 0
        this.controls[shortcut_ID].long.Enable(state)
        this.controls[shortcut_ID].short.Enable(state)
    }
    _btnOK() {
        if (this._CheckDuplicates()) {
            this._UpdateHotkeys()
            this._SaveSettings()
            UI_Tray_Update()
            this._CloseUI()
        }
    }
    _CheckDuplicates() {
        For i, shortcut in this.shortcuts
        {
            val := this.controls[i].HK.value
            if (val && InStr(list, "^" . val . "^")) {
                MsgBox ,, % "ZipChord", % Format("The keyboard shortcut for '{}' cannot be the same as another shortcut. (Even if the long or short press settings are different.)", shortcut.display)
                return false
            }
            list .= "^" . val . "^"
        }
        return true
    }
    _UpdateHotkeys() {
        For i, shortcut in this.shortcuts
        {
            shortcut.HK := this.controls[i].HK.value
            shortcut.mode := this.controls[i].long.value ? this.MD_LONG : this.MD_SHORT
        }
    }
    _CloseUI() {
        this.WireHotkeys("On") ; restore either previous (or define new) hotkeys
        Hotkey, F1, Off
        this.UI.Destroy()
    }
}

; Shared functions

HotkeyToText(HK) {
    if (StrLen(RegExReplace(HK, "[\+\^\!]")) == 1) {
        StringUpper, last_char, % SubStr(HK, 0)
        text := SubStr(HK, 1, StrLen(HK)-1) . last_char
    } else text := HK
    text := StrReplace(text, "+", "Shift+")
    text := StrReplace(text, "^", "Ctrl+")
    text := StrReplace(text, "!", "Alt+")
    return text
}