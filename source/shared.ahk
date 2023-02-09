/*

This file is part of ZipChord.

Copyright (c) 2021-2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

;;  Shared Functions and Classes 
; --------------------------------

global ini := new clsIniFile
global str := new clsStringFunctions
global UI := new clsUIBuilder

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

class clsUIBuilder {
    name := "" ; UI name
    controls := {}
    class clsControl {
        type := ""
        text := ""
        state := 0
        disabled := false  ; Enabled - true / Disabled - false
    }
    Add(control_or_type, text:="", param:="", state:="", fn:="") {
        new_control := new this.clsControl
        if (IsObject(control_or_type)) {
            param := text
            type := control_or_type.type
            text := control_or_type.text
            state := control_or_type.state ? true : false
        } else {
            type := control_or_type
            new_control.type := type
            new_control.text := text
            new_control.state := state
        }
        Switch type {
            Case "Text", "Button":
                Gui, Add, %type%, %param% Hwndhandle, %text%
            Default:
                Gui, Add, %type%, %param% Hwndhandle Checked%state%, %text%
        }
        this.controls[handle] := new_control
        if (fn)
            GuiControl +g, % handle, % fn
        if (IsObject(control_or_type))
            control_or_type.handle := handle
        return handle
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
    _TextInPixels(string, font_name, size)
    {
        Gui, strFunc:Font, s%size%, %font_name%
        Gui, strFunc:Add, Text, Hwndtemp, %string%
        GuiControlGet, values, Pos, % temp
        Gui, strFunc:Destroy
        return valuesW
        values := values ; to get rid of a compiler warning courtesy of weird return from GuiControlGet into differently named variables
    }
}


class clsIniFile {
    default_folder := A_AppData . "\ZipChord"
    default_ini := A_AppData . "\ZipChord\locales.ini"
    __New() {
        if ( ! InStr(FileExist(this.default_folder), "D"))
            FileCreateDir,  % this.default_folder
    }
    SaveLicense() {
        FileInstall, ..\LICENSE, % this.default_folder . "\LICENSE.txt", true
    }
    ShowLicense() {
        if (FileExist(this.default_folder . "\LICENSE.txt"))
            Run % this.default_folder . "\LICENSE.txt"
        else
            Run https://raw.githubusercontent.com/psoukie/zipchord/main/LICENSE
    }
    SaveProperty(value, key, filename, section:="Default") {
        IniWrite %value%, %filename%, %section%, %key%
    }
    ; LoadProperty returns "ERROR" if key not found
    LoadProperty(key, filename, section:="Default") {
        IniRead value, %filename%, %section%, %key%
        Return value  
    }
    SaveProperties(object_to_save, ini_section, ini_filename := "") {
        if (!ini_filename) {
            ini_filename := this.default_ini
        }
        For key, value in object_to_save
            this.SaveProperty(value, key, ini_filename, ini_section)
    }
    ; return true if section not found
    LoadProperties(ByRef object_destination, ini_section, ini_filename := "") {
        if (!ini_filename)
            ini_filename := this.default_ini
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
    LoadSections(ini_filename := "") {
        if (!ini_filename)
            ini_filename := this.default_ini
        if (! FileExist(ini_filename))
            return -1
        IniRead, sections, %ini_filename%
        return sections
    }
    DeleteSection(section, ini_filename := "") {
        if (!ini_filename)
            ini_filename := this.default_ini
        IniDelete, % ini_filename, % section
    }
}

UpdateVarFromConfig(ByRef var, key) {
    new_value := ini.LoadProperty(key, A_AppData . "\ZipChord\config.ini")
    if (new_value != "ERROR")
        var := new_value
}

SaveVarToConfig(key, value) {
    ini.SaveProperty(value, key, A_AppData . "\ZipChord\config.ini")
}