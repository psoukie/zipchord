/*
This file is part of ZipChord
Copyright (c) 2023 Pavel Soukenik
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the conditions set out
in the BSD-3-Clause license are met.
See the LICENSE file in the root folder for details.
*/

full_command_line := DllCall("GetCommandLine", "str")

uninstall := New clsUninstall

Return

class clsUninstall {
    ZC_UNIQUE_STRING := "ZC ZipChord RUNNING"

    __New() {
        global full_command_line
        if (RegExMatch(full_command_line, " /restart(?!\S)")) {
            this._Uninstall()
        }
        MsgBox , 1, % "Uninstall ZipChord", % "This will uninstall ZipChord.`n`nDictionaries and other files you have created will stay untouched."
        IfMsgBox Cancel
            ExitApp
        this._CheckAdmin()
        this._Uninstall()
    }
    _Uninstall() {
        if (!this._EnsureZipChordClosed())
            ExitApp
        this._DeleteInstalledFiles()
        this._DeleteRegistry()
        this._ShowCompletionMessage()
        ExitApp
    }
    _DeleteRegistry() {
        RegDelete, % "HKEY_CURRENT_USER\Software\ZipChord"
        RegDelete, % "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\ZipChord"
    }
    _EnsureZipChordClosed() {
        loop {
            if (!this._DetectRunningZipChord())
                return true
            MsgBox, 5, % "Uninstall ZipChord", % "ZipChord is currently running.`n`nPlease close ZipChord before continuing uninstallation, then click Retry."
            IfMsgBox Cancel
                return false
        }
    }
    _DetectRunningZipChord() {
        DetectHiddenWindows, On
        WinGet, target_hwnd, ID, % this.ZC_UNIQUE_STRING
        DetectHiddenWindows, Off
        return target_hwnd
    }
    _CheckAdmin() {
        if (A_ScriptDir == A_ProgramFiles . "\ZipChord" && !A_IsAdmin) {
            MsgBox , 1, % "Uninstall ZipChord", % "To remove ZipChord from Program Files, you will need to provide Admin access on the next screen."
            IfMsgBox Cancel
                ExitApp
            try
            {
                if A_IsCompiled
                    Run *RunAs "%A_ScriptFullPath%" /restart, % A_Temp
                else
                    Run *RunAs "%A_AhkPath%" /restart "%A_ScriptFullPath%", % A_Temp
            }
            ExitApp
        }
    }
    _DeleteInstalledFiles() {
        app_data_folder := A_AppData . "\ZipChord"
        programs_folder := A_Programs . "\ZipChord"
        startup_shortcut := A_Startup . "\ZipChord.lnk"
        install_files := [A_ScriptDir . "\zipchord.exe"
                        , A_ScriptDir . "\zipchord-lib.dll"
                        , A_ScriptDir . "\zipchord.ico"
                        , app_data_folder . "\locales.ini"
                        , app_data_folder . "\LICENSE.txt"
                        , startup_shortcut
                        , programs_folder . "\ZipChord.lnk"
                        , programs_folder . "\ZipChord Developer.lnk"
                        , programs_folder . "\Uninstall ZipChord.lnk"]
        for _, path in install_files {
            if FileExist(path)
                FileDelete, % path
        }
        this._DeleteFolderIfEmpty(programs_folder)
        this._DeleteFolderIfEmpty(app_data_folder)
    }
    _DeleteFolderIfEmpty(path) {
        if !InStr(FileExist(path), "D")
            return
        has_entries := false
        Loop, Files, % path . "\*", FD
        {
            has_entries := true
            break
        }
        if (!has_entries)
            FileRemoveDir, % path
    }
    _ShowCompletionMessage() {
        remaining_path := A_ScriptFullPath
        MsgBox, , % "Uninstall ZipChord", % "ZipChord has been uninstalled.`n`nThe uninstaller file was left in place:`n" . remaining_path . "`n`nYou can delete it manually."
    }
}