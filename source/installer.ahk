/*

This file is part of ZipChord

Copyright (c) 2023 Pavel Soukenik

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the conditions set out
in the BSD-3-Clause license are met.

See the LICENSE file in the root folder for details.

*/

#NoEnv
#SingleInstance Force
#MaxThreadsBuffer On
#KeyHistory 0
ListLines Off

#Include version.ahk
#Include shared.ahk

installer := new clsInstaller

Class clsInstaller {
    Class _clsUIHandles {
        destination_Program_Files := ""
        destination_current := ""
        dictionary_folder := ""
        zipchord_shortcut := ""
        developer_shortcut := ""
        autostart := ""
        start_after := ""
    }
    Class _clsOptions {
        destination_Program_Files := true
        dictionary_folder := A_MyDocuments . "\ZipChord"
        zipchord_shortcut := true
        developer_shortcut := false
        autostart := false
        start_after := true
    }

    UI := New this._clsUIHandles
    options := New this._clsOptions

    __New() {
        full_command_line := DllCall("GetCommandLine", "str")
        ; First, if the installer was already restarted to try get elevated rights 
        if (RegExMatch(full_command_line, " /restart(?!\S)")) {
            MsgBox, % "Restarted"
            this._LoadOptions()
            if (A_IsAdmin) {
                MsgBox, % "Running as admin"
                this._Install()
            } else {
                this.ShowUI()
                this._CloseProgramFileOption()
            }
        } else this.ShowUI()
    }
    ShowUI() {
        call := Func("OpenHelp").Bind("Installation")
        Hotkey, F1, % call, On
        Gui, New, , % "ZipChord Setup"
        Gui, Margin, 15, 15
        Gui, Font, s10, Segoe UI
        Gui, Add, GroupBox, w370 h90 Section, % "Application installation folder"
        state := this.options.destination_Program_Files
        notice := A_IsAdmin ? "" : "  (will need Admin access)"
        Gui, Add, Radio, xs+20 ys+30 Hwndtemp Checked%state%, % "Program Files" . notice
        this.UI.destination_Program_Files := temp
        state := 1 - state
        Gui, Add, Radio, y+10 Hwndtemp Checked%state%, % "Current folder"
        this.UI.destination_current := temp
        Gui, Add, GroupBox, xs w370 h100 Section, % "Default dictionary folder"
        Gui, Add, Text, xs+20 ys+30 Hwndtemp w330, % str.Ellipsisize(this.options.dictionary_folder, 330)
        this.UI.dictionary_folder := temp
        Gui, Add, Button, y+10 w150 Hwndtemp, % "Change Folder"
        fn := ObjBindMethod(this, "_btnSelectFolder")
        GuiControl +g, % temp, % fn
        this.UI.zipchord_shortcut := UI.AddCheckbox("Create a ZipChord shortcut in Start menu", this.options.zipchord_shortcut, "xs")
        this.UI.zipchord_autostart := UI.AddCheckbox("Start ZipChord automatically with Windows", this.options.autostart)
        this.UI.developer_shortcut := UI.AddCheckbox("Create a Developer version shortcut in Start menu", this.options.developer_shortcut)
        this.UI.start_after := UI.AddCheckbox("Open ZipChord after installation", this.options.start_after)
        Gui, Add, Button, w80 xm+170 yp+50 Hwndtemp, % "Cancel"
        fn := ObjBindMethod(this, "_CloseUI")
        GuiControl +g, % temp, % fn
        Gui, Add, Button, Default w80 xm+270 yp Hwndtemp, % "Install"
        fn := ObjBindMethod(this, "_btnInstall")
        GuiControl +g, % temp, % fn
        Gui, Show
    }
    _btnInstall() {
        this._UpdateOptions()
        this._SaveOptions()
        if (this.options.destination_Program_Files && this._CheckAdmin())
            return
        this._Install()
        this._CloseUI()
    }
    _CheckAdmin() {
        if (!A_IsAdmin) {
            try
            {
                if A_IsCompiled
                    Run *RunAs "%A_ScriptFullPath%" /restart
                else
                    Run *RunAs "%A_AhkPath%" /restart "%A_ScriptFullPath%"
            }
            MsgBox, % "I wil survive"
            this._CloseProgramFileOption()
            return true
        }
    }
    _CloseProgramFileOption() {
        GuiControl, Disable, % this.UI.destination_Program_Files
        GuiControl, , % this.UI.destination_Program_Files, % False
        GuiControl, , % this.UI.destination_current, % True
    }
    _CloseUI() {
        Hotkey, F1, Off
        Gui, Destroy
        ExitApp
    }
    _UpdateOptions() {
        For key, _ in this.options
        {
            GuiControlGet, val, , % this.UI[key]
            this.options[key] := val 
        }
    }
    _SaveOptions() {
        ini.SaveProperties(this.options, "Options", A_Temp . "\zipchord_installation_options.ini")
    }
    _LoadOptions() {
        ini.LoadProperties(this.options, "Options", A_Temp . "\zipchord_installation_options.ini")
    }
    _btnSelectFolder() {
        FileSelectFolder dict_path, % "*" . A_MyDocuments, , % "Select a folder for ZipChord dictionaries:"
        if (dict_path != "")
            GuiControl, , % this.UI.dictionary_folder, % dict_path
    }
    _Install() {
        global zc_app_name
        Process, Close, % "zipchord.exe"
        path := this.options.destination_Program_Files ? A_ProgramFiles . "\ZipChord" : A_ScriptDir
        exe_path := this.options.destination_Program_Files ? A_ProgramFiles . "\ZipChord\zipchord.exe" : "zipchord.exe"
        MsgBox, % "Paths: " . path . ", " . exe_path
        ; install zipchord.exe
        if ( ! InStr(FileExist(path), "D"))
            FileCreateDir,  % path
        FileInstall, zipchord.exe, % exe_path, true
        ; install dictionaries
        RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, % "dictionary_folder", this.options.dictionary_folder
        if ( ! InStr(FileExist(this.options.dictionary_folder), "D"))
            FileCreateDir,  % A_MyDocuments . "\ZipChord"
        FileInstall, ..\dictionaries\chords-en-qwerty.txt, % this.options.dictionary_folder . "\chords-en-starting.txt"
        FileInstall, ..\dictionaries\shorthands-english.txt, % this.options.dictionary_folder . "\shorthands-english-starting.txt"
        ; Create a ZipChord folder and application shortcut in the user's Programs folder in Start menu
        if ( ! InStr(FileExist(A_Programs . "\ZipChord"), "D"))
            FileCreateDir,  % A_Programs . "\ZipChord"
        FileCreateShortcut, % exe_path, % A_Programs . "\ZipChord\" . zc_app_name . ".lnk", % this.options.dictionary_folder, , % zc_app_name
        ; Create shortcuts
        if (this.options.zipchord_shortcut)
            FileCreateShortcut, % exe_path, % A_Startup . "\" . zc_app_name . ".lnk", % this.options.dictionary_folder, , % zc_app_name
        if (this.options.developer_shortcut)
            FileCreateShortcut, % exe_path, % A_Startup . "\" . zc_app_name . ".lnk", % this.options.dictionary_folder, "developer", % zc_app_name
        ; run ZipChord if selected
        MsgBox, , % "ZipChord", % "Installation completed."
        Run, % exe_path
        ExitApp
    }
}

GuiClose() {
    global installer
    installer._CloseUI()
}
GuiEscape() {
    global installer
    installer._CloseUI()
}