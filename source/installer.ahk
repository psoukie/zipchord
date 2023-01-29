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

full_command_line := DllCall("GetCommandLine", "str")

; First, if the installer was already restarted to try get elevated rights 
; if (RegExMatch(full_command_line, " /restart(?!\S)"))
;     if (!A_IsAdmin)
;         Program_Files_available := false
; if not (A_IsAdmin or RegExMatch(full_command_line, " /restart(?!\S)"))
; {
;     try
;     {
;         if A_IsCompiled
;             Run *RunAs "%A_ScriptFullPath%" /restart
;         else
;             Run *RunAs "%A_AhkPath%" /restart "%A_ScriptFullPath%"
;     }
;     ; ExitApp
; }

; MsgBox A_IsAdmin: %A_IsAdmin%`nCommand line: %full_command_line%

installer := new clsInstaller
installer.Show()

Class clsInstaller {
    Class _clsUIHandles {
        destination_Program_Files := ""
        destination_current := ""
        dictionary_folder := ""
        zipchord_shortcut := ""
        developer_shortcut := ""
        autostart := ""
    }
    Class _clsOptions {
        install_to_Program_Files := true
        dictionary_folder := A_MyDocuments . "\ZipChord"
        zipchord_shortcut := true
        developer_shortcut := false
        autostart := false
    }
    UI := New this._clsUIHandles
    options := New this._clsOptions
    Show() {
        call := Func("OpenHelp").Bind("Installation")
        Hotkey, F1, % call, On
        Gui, New, , % "ZipChord Setup"
        Gui, Margin, 15, 15
        Gui, Font, s10, Segoe UI
        Gui, Add, GroupBox, w370 h90 Section, % "Application installation folder"
        state := this.options.install_to_Program_Files
        Gui, Add, Radio, xs+20 ys+30 Hwndtemp Checked%state%, % "Program Files  (will need Admin access)"
        this.UI.destination_Program_Files := temp
        state := 1 - state
        Gui, Add, Radio, y+10 Hwndtemp Checked%state%, % "Current folder"
        this.UI.destination_current := temp
        Gui, Add, GroupBox, xs w370 h100 Section, % "Default dictionary folder"
        Gui, Add, Text, xs+20 ys+30 Hwndtemp w330, % str.Ellipsisize(this.options.dictionary_folder, 330)
        this.UI.dictionary_folder := temp
        Gui, Add, Button, y+10 w150, % "Change Folder"
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
        fn := ObjBindMethod(this, "_btnOK")
        GuiControl +g, % temp, % fn
        Gui, Show
    }
    _CloseUI() {
        Hotkey, F1, Off
        Gui, Destroy
        ExitApp
    }
    SelectFolder() {
        FileSelectFolder dict_path, % "*" . A_MyDocuments, , % "Select a folder for ZipChord dictionaries:"
        ; if (dict_path == "") {
        ;     dict_path := A_ScriptDir
    }
    Bulk() {
        global zc_app_name
        if ( ! InStr(FileExist(A_ProgramFiles . "\ZipChord"), "D"))
                FileCreateDir,  % A_ProgramFiles . "\ZipChord"
        FileInstall, zipchord.exe, % A_ProgramFiles . "\ZipChord\zipchord.exe", true
        MsgBox, 1, % "ZipChord Setup", % "Welcome to ZipChord!`n`nThis initial setup has three simple steps:`n`n1. Choose your default folder for Zipchord dictionaries.`n2. Select if you would like a shortcut to ZipChord in Start menu.`n3. Choose if ZipChord should automatically start with Windows."
        IfMsgBox Cancel
            ExitApp
        FileSelectFolder dict_path, % "*" . A_MyDocuments, , % "ZipChord Setup (1/3)`n`nSelect a folder for ZipChord dictionaries:`n (Click Cancel if you'd like to keep them in the same folder as zipchord.exe.)"
        if (dict_path == "") {
            dict_path := A_ScriptDir
            MsgBox, 1, % "ZipChord Setup (1/3)", % Format("The default folder for dictionaries will be:`n{}`n`nClick OK to accept, or click Cancel to cancel the installation.", dict_path)
            IfMsgBox Cancel
                ExitApp
        }
        RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, dictionary_folder, dict_path
        ; settings.dictionary_folder := dict_path
        SetWorkingDir, % dict_path
        ; settings.preferences &= ~PREF_FIRST_RUN
        ; Unpack the included default dictionaries 
        FileInstall, ..\dictionaries\chords-en-qwerty.txt, % "chords-en-starting.txt"
        FileInstall, ..\dictionaries\shorthands-english.txt, % "shorthands-english-starting.txt"
        ; Create a ZipChord folder and application shortcut in the user's Programs folder in Start menu (not in Startup folder)
        MsgBox, 4, % "ZipChord Setup (2/3)", % Format("Would you like to create a Start menu shortcut for {}?", zc_app_name)
        IfMsgBox Yes
        {
            if ( ! InStr(FileExist(A_Programs . "\ZipChord"), "D"))
                FileCreateDir,  % A_Programs . "\ZipChord"
            FileCreateShortcut, % A_ProgramFiles . "\ZipChord\zipchord.exe", % A_Programs . "\ZipChord\" . zc_app_name . ".lnk", % dict_path, , % zc_app_name
        }
        MsgBox, 4, % "ZipChord Setup (3/3)", % Format("Would you like to start {} automatically with Windows?", zc_app_name)
        IfMsgBox Yes
            FileCreateShortcut, % A_ProgramFiles . "\ZipChord\zipchord.exe", % A_Startup . "\" . zc_app_name . ".lnk", % dict_path, , % zc_app_name
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