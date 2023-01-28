/*

This file is part of ZipChord.

Copyright (c) 2021-2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

;;  Shared Functions and Classes 
; --------------------------------

global ini := new clsIniFile
global str := new clsStringFunctions

OpenHelp(topic) {
    Switch topic {
        Case "Installation":
            Run https://github.com/psoukie/zipchord/wiki/Installation#setup-options
        Case "AppShortcuts":
            Run https://github.com/psoukie/zipchord/wiki/Application-Keyboard-Shortcuts-window
        Case "AddShortcut":
            Run https://github.com/psoukie/zipchord/wiki/Add-Shortcut-window
        Case "Main-Dictionaries":
            Run https://github.com/psoukie/zipchord/wiki/Main-Window#dictionaries
        Case "Main-Detection":
            Run https://github.com/psoukie/zipchord/wiki/Main-Window#detection
        Case "Main-Hints":
            Run https://github.com/psoukie/zipchord/wiki/Main-Window#hints
        Case "Main-Output":
            Run https://github.com/psoukie/zipchord/wiki/Main-Window#output
        Case "Main-About":
            Run https://github.com/psoukie/zipchord/wiki/Main-Window#about
        Default:
            Run https://github.com/psoukie/zipchord/wiki
    }
}

/**
* String Functions
* Methods:
*    Ellipsisize      Returns a shortened string (if it exceeds the limit) with ellipsis added.
*        text         String to shorten.
*        limit        Limit in pixel length.
*        to_end       [true|false] add ellipsis to the end (or start), default is false (left).
*        font         Font to use for adjustment calculation. Default is Segoe UI.    
*        size         Font size used for adjustment calculation. Default is 10.
*/
Class clsStringFunctions {
    Ellipsisize(text, limit, to_end:=false, font:="Segoe UI", size:=10) {
        if (this._TextInPixels(text, font, size) < limit)
            return text
        While ( (length := this._TextInPixels(text . "...", font, size)) > limit) {
            str_length := StrLen(text)
            new_length := Round(StrLen(text)*(limit/length))
            ; but we always decrease by at least a character
            if (new_length >= StrLen(text))
                new_length := StrLen(text)-1
            if (to_end)
                text := SubStr(text, 1, new_length)
            else
                text := SubStr(text, 1+StrLen(text)-new_length)
        }
        if (to_end)
            return text . "..."
        else
            return "..." . text
    }
    _TextInPixels(text, font, size)
    {
        Gui, strFunc:Font, s%size%, %font%
        Gui, strFunc:Add, Text, Hwndtemp, %text%
        GuiControlGet, values, Pos, % temp
        Gui, strFunc:Destroy
        return valuesW
    }
}


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