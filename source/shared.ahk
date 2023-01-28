/*

This file is part of ZipChord.

Copyright (c) 2021-2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

;;  Shared Functions and Classes 
; --------------------------------

; Ini Files Functions

class clsIniFile {
    _processing := false
    _dir_backup := ""
    ; for all methods, we first back-up, change, and then restore the working directory
    __Call(name, params*) {
        if (! this._processing) {
            this._processing:=true
            this._dir_backup := A_WorkingDir
            SetWorkingDir, % A_ScriptDir
            fn := ObjBindMethod(this, name, params*)
            val := %fn%()
            this._processing:=false
            SetWorkingDir, % this._dir_backup
            return val
        }
    }
    SaveProperties(object_to_save, ini_section, ini_filename := "locales.ini") {
        For key, value in object_to_save
            IniWrite %value%, %ini_filename%, %ini_section%, %key%
    }
    ; return true if section not found
    LoadProperties(ByRef object_destination, ini_section, ini_filename := "locales.ini") {
        IniRead, properties, %ini_filename%, %ini_section%
        if (! properties)
            return true
        Loop, Parse, properties, `n
        {
            key := SubStr(A_LoopField, 1, InStr(A_LoopField, "=")-1)
            value := SubStr(A_LoopField, InStr(A_LoopField, "=")+1)
            object_destination[key] := value
        }
    }
    ; return -1 if file not found
    LoadSections(ini_filename := "locales.ini") {
        if (! FileExist(ini_filename))
            return -1
        IniRead, sections, %ini_filename%
        return sections
    }
    DeleteSection(section, ini_filename := "locales.ini") {
        IniDelete, % ini_filename, % section
    }
}

global ini := new clsIniFile