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
    __New() {
        global full_command_line
        if (RegExMatch(full_command_line, " /restart(?!\S)")) {
            this._Unintstall()
        }
        MsgBox , 1, % "Uninstall ZipChord", % "This will uninstall ZipChord.`n`nDictionaries and other files you have created will stay untouched."
        IfMsgBox Cancel
            ExitApp
        SetWorkingDir, % A_Temp
        Process, Close, % "zipchord.exe"
        this.CreateUninstallScript(2000)
        this._DeleteRegistry()
        this._CheckAdmin()
        this._RunUninstallScript()
    }
    _Unintstall() {
        Process, Close, % "zipchord.exe"
        SetWorkingDir, % A_Temp
        this._RunUninstallScript()
    }
    _DeleteRegistry() {
        RegDelete, % "HKEY_CURRENT_USER\Software\ZipChord"
        RegDelete, % "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\ZipChord"
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
            return true
        }
    }
    CreateUninstallScript(delay) {
        app_data_folder := % A_AppData . "\ZipChord"
        programs_folder := % A_Programs . "\ZipChord"
        FileDelete, % A_Temp . "\ZC_uninstall.vbs"
        ; Adapts code by cooljeans and SKAN from https://www.autohotkey.com/board/topic/1488-make-exe-file-delete-itself/
        FileAppend,
            (LTrim
            Wscript.Sleep %delay%
            Dim fso, myfile, files, myfolder, folders
            Set fso = CreateObject("Scripting.FileSystemObject")
            files = Array("%A_ScriptFullPath%", "%app_data_folder%\locales.ini", "%app_data_folder%\LICENSE.txt", "%A_ScriptDir%\zipchord.exe", "%A_ScriptDir%\zipchord.ico",  "%A_Startup%\ZipChord.lnk") 
            For each file in files
                If fso.FileExists(file) Then
                    Set myfile = fso.GetFile(file) 
                    myfile.Delete(true)
                End If
            Next
            folders = Array("%A_ScriptDir%", "%app_data_folder%", "%programs_folder%")
            For each folder in folders
                If fso.FolderExists(folder) Then
                    Set myfolder = fso.GetFolder(folder)
                End If
                If (myfolder = "%programs_folder%")  Or (myfolder.Files.Count = 0 And myfolder.SubFolders.Count = 0) Then
                    myfolder.Delete(true)
                End If
            Next
            fso.DeleteFile WScript.ScriptFullName
            Set fso = Nothing
            )
        , % A_Temp . "\ZC_uninstall.vbs"
    }
    _RunUninstallScript() {
        Run, % "cscript.exe " . A_InitialWorkingDir . "\ZC_uninstall.vbs"
        ExitApp
        programs_folder := programs_folder ; to bypass syntax warning
    }
}