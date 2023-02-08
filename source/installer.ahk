﻿/*

This file is part of ZipChord

Copyright (c) 2023 Pavel Soukenik

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the conditions set out
in the BSD-3-Clause license are met.

See the LICENSE file in the root folder for details.

*/

#NoEnv
#SingleInstance Off
#MaxThreadsBuffer On
#KeyHistory 0
ListLines Off

#Include version.ahk
#Include shared.ahk

installer := new clsInstaller

Class clsInstaller {
    notice := A_IsAdmin ? "" : "  (will need Admin access)"
    dictionary_dir_full := A_MyDocuments . "\ZipChord"
    controls := { destination_Programs: { type: "Radio"
                                        , text: "Program Files" . this.notice
                                        , state: True}
                , destination_current:  { type: "Radio"
                                        , text: "Current folder"}
                , dictionary_dir:       { type: "Text"
                                        , text: str.Ellipsisize(this.dictionary_dir_full, 330)}
                , zipchord_shortcut:    { type: "Checkbox"
                                        , text: "Create a ZipChord shortcut in Start menu"
                                        , state: true}
                , autostart:            { type: "Checkbox"
                                        , text: "Start ZipChord automatically with Windows"}
                , developer_shortcut:   { type: "Checkbox"
                                        , text: "Create a Developer version shortcut in Start menu"}
                , open_after:           { type: "Checkbox"
                                        , text: "Open ZipChord after installation"
                                        , state: true}}

    options := {}

    __New() {
        if (A_Args[1] == "/elevate") {
            this._LoadOptions()
            if (A_IsAdmin)
                this._Install()  ; this call end in ExitApp
            this._LocalOption()
        }
        else
            this.ShowUI()
    }
    ShowUI() {
        global zc_version
        call := Func("OpenHelp").Bind("Installation")
        Hotkey, F1, % call, On
        Gui, New, , % "ZipChord Setup"
        Gui, Margin, 15, 15
        Gui, Font, s10, Segoe UI
        Gui, Add, GroupBox, w370 h90 Section, % "Application installation folder"
        UI.Add(this.controls.destination_Programs, "xs+20 ys+30")
        UI.Add(this.controls.destination_current, "y+10")
        Gui, Add, GroupBox, xs w370 h100 Section, % "Default dictionary folder"
        UI.Add(this.controls.dictionary_dir, "xs+20 ys+30 w330")
        UI.Add("Button", "Change Folder", "y+10 w150", , ObjBindMethod(this, "_btnSelectFolder"))
        UI.Add(this.controls.zipchord_shortcut, "xs")
        UI.Add(this.controls.autostart)
        UI.Add(this.controls.developer_shortcut)
        UI.Add(this.controls.open_after)
        UI.Add("Text", "v" . zc_version, "yp+50")
        UI.Add("Button", "Cancel", "w80 xm+170 yp", , ObjBindMethod(this, "_CloseUI"))
        UI.Add("Button", "Install", "Default w80 xm+270 yp", , ObjBindMethod(this, "_btnInstall"))
        Gui, Show
    }
    _btnInstall() {
        this._UpdateOptions()
        this._SaveOptions()
        this._SaveRegistryInfo()
        if (this.options.destination_Programs) {
            if (this._CheckAdmin())
                this._LocalOption()
            else {
                this._CloseUI()
                this._Install()
            }
        } else this._Install()
    }
    _CheckAdmin() {
        if (A_IsAdmin) {
            return
        } else {
            Gui, Destroy
            try
                RunWait *RunAs "%A_ScriptFullPath%" /elevate, % A_Temp
            catch _
                return True
        }
        this._OpenAfter() ; exits the app
    }
    _LocalOption() {
        this.ShowUI()
        GuiControl, Disable, % this.controls.destination_Programs.handle
        GuiControl, , % this.controls.destination_Programs.handle, % False
        GuiControl, , % this.controls.destination_current.handle, % True
    }
    _CloseUI() {
        Hotkey, F1, Off
        Gui, Destroy
        ExitApp
    }
    _UpdateOptions() {
        For key, control in this.controls
        {
            GuiControlGet, val, , % control.handle
            this.options[key] := val
        }
    }
    _SaveOptions() {
        this.options.dictionary_dir := this.dictionary_dir_full  ; override the potentially abbreviated path from the UI with the actual value
        this.options.installation_dir := this.options.destination_Programs ? A_ProgramFiles . "\ZipChord" : A_ScriptDir
        this.options.programs_dir := A_Programs
        this.options.startup_dir := A_Startup
        this.options.my_documents_dir := A_MyDocuments
        ini.SaveProperties(this.options, "Options", A_Temp . "\zipchord_installation_options.ini")
    }
    _LoadOptions() {
        ini.LoadProperties(this.options, "Options", A_WorkingDir . "\zipchord_installation_options.ini") ; the WorkingDir is needed to override the default folder in LoadProperties
    }
    _btnSelectFolder() {
        FileSelectFolder dict_path, % "*" . A_MyDocuments, , % "Select a folder for ZipChord dictionaries:"
        if (dict_path != "") {
            this.dictionary_dir_full := dict_path
            GuiControl, , % this.controls.dictionary_dir.handle, %  str.Ellipsisize(dict_path, 330)
        }
    }
    _SaveRegistryInfo() {
        global zc_app_name
        ; This needs to happen before we elevate user rights to Admin
        SaveVarToRegistry("dictionary_dir", this.dictionary_dir_full)
        ; create uninstallation registry entries
        reg_uninstall := "Software\Microsoft\Windows\CurrentVersion\Uninstall\ZipChord"
        RegWrite, REG_SZ, HKEY_CURRENT_USER, %reg_uninstall%, DisplayName, %zc_app_name%
        RegWrite, REG_SZ, HKEY_CURRENT_USER, %reg_uninstall%, UninstallString, % this.options.installation_dir . "\uninstall.exe"
        RegWrite, REG_SZ, HKEY_CURRENT_USER, %reg_uninstall%, DisplayIcon, % path . "\zipchord.ico"
        RegWrite, REG_SZ, HKEY_CURRENT_USER, %reg_uninstall%, DisplayVersion, %zc_version%
        RegWrite, REG_SZ, HKEY_CURRENT_USER, %reg_uninstall%, URLInfoAbout, % "https://github.com/psoukie/zipchord/wiki/"
        RegWrite, REG_SZ, HKEY_CURRENT_USER, %reg_uninstall%, Publisher, % "Pavel Soukenik"
        RegWrite, REG_SZ, HKEY_CURRENT_USER, %reg_uninstall%, NoModify, 1
    }
    _Install() {
        global zc_app_name
        global zc_version
        Process, Close, % "zipchord.exe"
        path := this.options.installation_dir
        exe_path := path . "\zipchord.exe"
        dict_dir := this.options.dictionary_dir
        ; install zipchord.exe
        if ( ! InStr(FileExist(path), "D"))
            FileCreateDir,  % path
        FileInstall, zipchord.exe, % exe_path, true
        FileInstall, uninstall.exe, % path . "\uninstall.exe", true
        FileInstall, zipchord.ico, % path . "\zipchord.ico", true
        ; install dictionaries
        if ( ! InStr(FileExist(dict_dir), "D"))
            FileCreateDir,  % this.options.my_documents_dir . "\ZipChord"
        FileInstall, ..\dictionaries\chords-en-qwerty.txt, % dict_dir . "\chords-en-starting.txt"
        FileInstall, ..\dictionaries\shorthands-english.txt, % dict_dir . "\shorthands-en-starting.txt"
        ; Create a ZipChord folder and application shortcut in the user's Programs folder in Start menu
        if (this.options.zipchord_shortcut || this.options.developer_shortcut) {
            if ( ! InStr(FileExist(this.options.programs_dir . "\ZipChord"), "D"))
                FileCreateDir,  % this.options.programs_dir . "\ZipChord"
            FileCreateShortcut, % path . "\uninstall.exe", % this.options.programs_dir . "\ZipChord\Uninstall ZipChord.lnk", % path, , % zc_app_name, % path . "\uninstall.exe"
        }
        if (this.options.zipchord_shortcut)
            FileCreateShortcut, % exe_path, % this.options.programs_dir . "\ZipChord\ZipChord.lnk", % dict_dir, , % zc_app_name, % path . "\zipchord.ico"
        if (this.options.developer_shortcut)
            FileCreateShortcut, % exe_path, % this.options.programs_dir . "\ZipChord\ZipChord Developer.lnk", % dict_dir, "dev", %zc_app_name% . " Developer", % path . "\zipchord.ico"
        if (this.options.autostart) {
            FileCreateShortcut, % exe_path, % this.options.startup_dir . "ZipChord.lnk", % dict_dir, , %zc_app_name%, % path . "\zipchord.ico"
        }
        MsgBox, , % "ZipChord", % "Setup has completed."
         if (A_Args[1] != "/elevate")
            this._OpenAfter()
        ExitApp
    }
    _OpenAfter() {
        if (this.options.open_after) {
            Run % this.options.installation_dir . "\zipchord.exe", % this.options.dictionary_dir_full
        }
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