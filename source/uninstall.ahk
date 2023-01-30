/*

This file is part of ZipChord

Copyright (c) 2023 Pavel Soukenik

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the conditions set out
in the BSD-3-Clause license are met.

See the LICENSE file in the root folder for details.

*/

uninstall := New clsUninstall

Return

class clsUninstall {
    __New() {
        MsgBox , 1, % "Uninstall ZipChord", % "This will uninstall ZipChord. Dictionaries and other files you have created will stay untouched."
        IfMsgBox Cancel
            return
        Process, Close, % "zipchord.exe"
        FileDelete, % A_ScriptDir . "\locales.ini"
        FileDelete, % A_ScriptDir . "\LICENSE.txt"
        FileDelete, % A_ScriptDir . "\zipchord.exe"
        FileDelete, % A_ScriptDir . "\uninstall.exe"
        FileDelete, % A_Startup . "\ZipChord.lnk"
        SetWorkingDir, % A_Temp
        RegDelete, % "HKEY_CURRENT_USER\Software\ZipChord"
        RegDelete, % "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\ZipChord"
        this.Destruct(3000)
    }
    Destruct(delay) {
        programs_folder := % A_Programs . "\ZipChord"
        FileDelete, % A_Temp . "\deleteself.vbs"
        ; Adapts code by cooljeans and SKAN from https://www.autohotkey.com/board/topic/1488-make-exe-file-delete-itself/
        FileAppend,
(
Wscript.Sleep %delay%
Dim fso, MyFile, ZCfolder
Set fso = CreateObject("Scripting.FileSystemObject")
Set MyFile = fso.GetFile("%A_ScriptFullPath%") 
MyFile.Delete
If fso.FolderExists("%A_ScriptDir%") Then
    Set ZCfolder = fso.GetFolder("%A_ScriptDir%")
    If ZCfolder.Files.Count = 0 And ZCfolder.SubFolders.Count = 0 Then ZCfolder.Delete(true)
End If
If fso.FolderExists("%programs_folder%") Then
    Set ZCfolder = fso.GetFolder("%programs_folder%")
    If ZCfolder Then ZCfolder.Delete(true)
End If
fso.DeleteFile WScript.ScriptFullName
MsgBox("Uninstallation of ZipChord was completed.")
Set fso = Nothing 
)
        , % A_Temp . "\deleteself.vbs"
        Run, % A_Temp . "\deleteself.vbs"
        ExitApp
        programs_folder := programs_folder ; to bypass syntax warning
    }
}