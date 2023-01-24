/*

This file is part of ZipChord.

Copyright (c) 2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

Class clsAppShortcuts {
    MD_SHORT := 1
    MD_LONG := 2
    
    _shortcuts := Array()
    _UI_controls := Array()

    Class clsShortcut {
        displayname := ""
        shortcut := ""
        mode := 0
    }
    Class clsHandles {
        HK_hwnd := ""
        optLong_hwnd := ""
        optShorthwnd := ""
    }
    Init() {
        this._Define("UI_Main_Show", "Open main ZipChord window", "^+z", this.MD_LONG)
        this._Define( "AddShortcut", "Open Add Shortcut window", "^c", this.MD_LONG)
        this._Define("TogglePause", "Pause / Unpause ZipChord", "", this.MD_LONG)
        this._Define("QuitApp", "Quit ZipChord", "", this.MD_SHORT)
    }
    _Define(function, name, shortcut, mode) {
        app_shortcut := New this.clsShortcut
        app_shortcut.displayname := name
        app_shortcut.shortcut := shortcut
        app_shortcut.mode := mode
        this._shortcuts[function] := app_shortcut
    }
    _ApplyHotkeys() {
        For fn, HK in this._shortcuts
            if (HK.shortcut) {
                call := ObjBindMethod(this, "_ProcessHotkey", fn)
                if (HK.mode == this.MD_SHORT)
                    Hotkey, % HK.shortcut, % call, % "On"
                else
                    Hotkey, % "~" . HK.shortcut, % call, % "On"
            }
    }
    _ProcessHotkey(fn) {
        HK := this[fn]
        shortcut := StrReplace(HK.shortcut, "+")
        shortcut := StrReplace(shortcut, "^")
        shortcut := StrReplace(shortcut, "!")
        if (HK.mode == this.MD_LONG) {
            Sleep 300
            if GetKeyState(shortcut,"P")
                %fn%()
        } else %fn%()
    }
    ShowUI() {
        Gui, UI_AppShortcuts:New, , % "ZipChord Keyboard Shortcuts"
        Gui, Margin, 20, 20
        Gui, Font, s10, Segoe UI
        Gui, Add, Text, x+20 y-35, % ""

        For function, _ in this._shortcuts
        {
            handles := New this.clsHandles
            Gui, Add, GroupBox, xs-20 y+35 w400 h90, % this[function].displayname
            Gui, Add, Hotkey, xp+20 yp+37 Section Hwndtemp Limit3, % this[function].shortcut
            handles.HK_hwnd := temp
            fn := ObjBindMethod(this, "_UpdateUI", function)
            GuiControl +g, % temp, % fn
            Gui, Add, Radio, xs+180 ys-9 Hwndtemp Checked, % "Long press (non-exclusive)"
            handles.optLong_hwnd := temp
            Gui, Add, Radio, Hwndtemp, % "Short press (exclusive)"
            handles.optShort_hwnd := temp
            this._UI_controls[function] := handles
            this._UpdateUI(function)
        }

        Gui, Add, Button, w80 xm+220 yp+60 Hwndtemp, % "Cancel"
        fn := ObjBindMethod(this, "_CloseUI")
        GuiControl +g, % temp, % fn

        Gui, Add, Button, Default w80 xm+320 yp Default Hwndtemp, % "OK"
        fn := ObjBindMethod(this, "_ApplyHK")
        GuiControl +g, % temp, % fn
        
        Gui, Show, w440
    }
    _UpdateUI(fn) {
        GuiControlGet, val, , % this._UI_controls[fn].HK_hwnd
        OutputDebug, % "`n state: >" . val . "<"
        state := val ? 1 : 0
        GuiControl, Enable%state%, % this._UI_controls[fn].optLong_hwnd
        GuiControl, Enable%state%, % this._UI_controls[fn].optShort_hwnd
    }
    _ApplyHK() {
        ; ...
        this._CloseUI()
    }
    _CloseUI() {
        UI_AppShortcuts_Close()
    }
    shortcut[which] {
        get {
            return this._shortcuts[which]
        }
    }
    __Get(what) {
        if ( ! clsAppShortcuts.HasKey(what)) {
            return this.shortcut[what]
        }
    }
}

t := New clsAppShortcuts
t.Init()
t.ShowUI()
t._ApplyHotkeys()
Return

UI_Main_Show() {
    MsgBox, % "Opening Menu..." . m
}

AddShortcut() {
    MsgBox, % "Add..." 
}
OpenMenu:
    MsgBox, % "3..."
Return
QuitApp:
    ExitApp
Return


UI_AppShortcutsGuiClose() {
    UI_AppShortcuts_Close()
}
UI_AppShortcutsGuiEscape() {
    UI_AppShortcuts_Close()
}
UI_AppShortcuts_Close() {
    Gui, UI_AppShortcuts:Destroy
}