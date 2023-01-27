/*

This file is part of ZipChord.

Copyright (c) 2021-2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

;;  Shared Functions and Classes 
; --------------------------------

; Ini Files Functions

class clsIniFile {
    SaveProperties(object_to_save, ini_section, ini_filename := "locales.ini") {
        SetWorkingDir, % A_ScriptDir
        For key, value in object_to_save
            IniWrite %value%, %ini_filename%, %ini_section%, %key%
        SetWorkingDir, % settings.dictionary_folder
    }
    ; return true if section not found
    LoadProperties(ByRef object_destination, ini_section, ini_filename := "locales.ini") {
        SetWorkingDir, % A_ScriptDir
        IniRead, properties, %ini_filename%, %ini_section%
        if (! properties) {
            OutputDebug, % "INI section empty/doesn't exist"
            return true
        }
        SetWorkingDir, % settings.dictionary_folder
        Loop, Parse, properties, `n
        {
            key := SubStr(A_LoopField, 1, InStr(A_LoopField, "=")-1)
            value := SubStr(A_LoopField, InStr(A_LoopField, "=")+1)
            object_destination[key] := value
        }
    }
    ; return true if file not found
    LoadSections(ByRef sections, ini_filename := "locales.ini") {
        SetWorkingDir, % A_ScriptDir
        if (! FileExist(ini_filename)) {
            OutputDebug, % "INI file not found"
            return true
        }
        IniRead, sections, %ini_filename%
        SetWorkingDir, % settings.dictionary_folder
    }
    DeleteSection(section, ini_filename := "locales.ini") {
        SetWorkingDir, % A_ScriptDir
        IniDelete, % ini_filename, % section
        SetWorkingDir, % settings.dictionary_folder
    }
}

global ini := new clsIniFile