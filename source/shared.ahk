﻿/*
This file is part of ZipChord.
Copyright (c) 2021-2025 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

;;  Shared constants, functions and classes 
; ------------------------------------------

global CONFIG_FILE := A_AppData . "\ZipChord\config.ini"
global CONFIG_SECTION := "Default"

global ini := new clsIniFile
global str := new clsStringFunctions

updater := new clsUpdater

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
* UI class -- custom, object-oriented methods for working with windows and controls
* 
* Public properties:
*   on_close      callback function to use when user closes the window or escapes from it
*   controls      collection of controls in this window, see clsControl below 
*
* Public methods:
*   new clsUI     Creates a new window object.
*   Show          Shows the window.
*   Destroy       Destroys the window.
*   Hide          Hides the window.
*   Add           Adds a control.
*/
class clsUI {
    static _windows := {}   ; key-value array with handles pointing to UI objects
    _handle := ""           ; handle of the UI instance
    controls := {}          ; key-value array with handles pointing to controls within the UI instance
    on_close := ""          ; callback function when user closes or escapes the window

    /**
    * UI Control class for defining and working with controls
    *
    * Properties:
    *    type, text,          Can be used with Add as shorthand definition using object  
    *      function, state
    *    value                Retrieves or sets the value of the control 
    *
    * Methods:
    *    Enable([true|false]) Enables the control, unless called with Enable(false).             
    *    Disable              Disables the control.
    *    Choose
    *    Focus
    *    Hide
    */    
    class clsControl {
        type := ""
        text := ""
        function := ""
        state := 0
        _handle := ""
        value[] {
            get {
                GuiControlGet, val, , % this._handle
                return val
            }
            set {
                GuiControl, , % this._handle, % value
            }
        }
        is_enabled[] {
            get {
                GuiControlGet, val, Enabled, % this._handle
                return val
            }
        }
        Enable(state := true) {
            GuiControl, Enable%state%, % this._handle
            this.state := state
        }
        Disable(normal := true) {
            this.Enable(! normal)
        }
        Show(normal := true) {
            GuiControl, Show%normal%, % this._handle
        }
        Hide() {
            GuiControl, Hide, % this._handle
        }
        Focus() {
            GuiControl, Focus, % this._handle
        }
        Choose(option) {
            handle := this._handle
            if option is not integer
                Controlget, option, FindString, % option, , ahk_id %handle%  ; to get exact match 
            GuiControl, Choose, % handle, % option
        }
        MakeDefault() {
            GuiControl, +Default, % this._handle
        }
    }

    /**
    * __New is used to create new window objects:
    *
    *    <obj> := new clsUI(<name>, [options])
    *
    *         <obj>          The returned new object
    *         <name>         Title of the new window       
    *         [options]      String with Gui options
    */
    __New(name:="", options:="") {
        Gui, New, %options% +Hwndwindow_handle, %name%
        this._handle := window_handle
        clsUI._windows[window_handle] := this ; create an entry for this UI in the class to look it up when handling built-in, non-object AHK functions like CloseGui
        Gui, Margin, 15, 15
        this.Font() ; reset to default font settings
    }
    Show(options := "") {
        window_handle := this._handle
        Gui, %window_handle%:Show, % options
    }
    IsShown() {
        window_handle := this._handle
        if (WinExist("ahk_id " . window_handle)) {
            return true
        } else {
            return false
        }
    }
    SetTitle(title) {
        window_handle := this._handle
        WinSetTitle, ahk_id %window_handle%,, %title%
    }
    Destroy() {
        window_handle := this._handle
        Gui, %window_handle%:Destroy
    }
    Hide() {
        window_handle := this._handle
        Gui, %window_handle%:Hide
    }
    Disable() {
        window_handle := this._handle
        Gui, %window_handle%:+Disabled
    }
    Enable() {
        window_handle := this._handle
        Gui, %window_handle%:-Disabled
    }
    ; switch to a tab in tabbed dialog or out of tab (if -1)
    Tab(tab_number := -1) {
        window_handle := this._handle
        if (tab_number == -1) {
            Gui, %window_handle%:Tab
        } else {
            Gui, %window_handle%:Tab, %tab_number%
        }
    }
    Margin(x := 15, y := 15) {
        window_handle := this._handle
        Gui, %window_handle%:Margin, %x%, %y%
    }
    Font(options := "cDefault s10 w400 norm", family := "Segoe UI") {
        window_handle := this._handle
        Gui, %window_handle%:Font, %options%, %family%
    }
    Color(window := "Default", control := "Default") {
        window_handle := this._handle
        Gui, %window_handle%:Color, %window%, %control%
    }
    SetTransparency(transparent_color, transparency := "Off") {
        window_handle := this._handle
        WinSet, TransColor, %transparent_color% %transparency%, ahk_id %window_handle%
    }
    ; Called when user closes or escapes the window.
    ; Calls the on_close function, if defined, or hides the window.
    _Close() {
        on_close_fn := this.on_close 
        if (IsObject(on_close_fn))
            %on_close_fn%()
        else
            this.Hide()
    }

    /** 
    * Adds a new control to the window.
    *
    *   Add(<controlobject>, [options])
    *   Add(<type>, [options], [text], [function], [state]) 
    *
    *      <controlobject>    a clsControl object
    *      <type>             A control type: Text, Button, Checkbox, Radio,
    *                         GroupBox, DropDownList etc.
    *      [options]          String with Gui options
    *      [text]             String for the controls text or value
    *      [function]         Function to call upon user interaction
    *      [state]            Boolean for starting as checked or selected
    */
    Add(control_or_type, options:="", text:="", function:="", state:="") {
        window_handle := this._handle
        new_control := new this.clsControl
        if (IsObject(control_or_type)) {
            type := control_or_type.type
            text := control_or_type.text
            function := control_or_type.function
            state := control_or_type.state ? true : false
        } else {
            type := control_or_type
            new_control.type := type
            new_control.text := text
            new_control.state := state
        }
        Switch type {
            Case "Checkbox", "Radio":
                Gui, %window_handle%:Add, %type%, %options% Hwndcontrol_handle Checked%state%, %text%
            Case "Button":
                if (!InStr(options, "w"))
                    options .= " w" . str.TextInPixels(text) + 30
                Gui, %window_handle%:Add, %type%, %options% Hwndcontrol_handle, %text%
            Default:
                Gui, %window_handle%:Add, %type%, %options% Hwndcontrol_handle, %text%
        }
        new_control._handle := control_handle
        this.controls[control_handle] := new_control
        if (function)
            GuiControl +g, %control_handle%, %function%
        if (IsObject(control_or_type)) {
            control_or_type._handle := control_handle
            ObjSetBase(control_or_type, this.clsControl)
        }
        return new_control
    }
}

; We catch and process all the AHK-generated calls when a user closes or escapes _any_ UI. 

GuiClose(handle) {
    clsUI._windows[handle]._Close()
}
GuiEscape(handle) {
    clsUI._windows[handle]._Close()
}

/**
* String Functions
* Methods:
*    HotkeyToText     Returns a human-readable hotkey text.
*    Ellipsisize      Returns a shortened string (if it exceeds the limit) with ellipsis added.
*    TextInPixels     Returns the length of text in pixels.
*    ToAscii          Converts key and modifiers to ASCII
*    JoinArray        Returns a string with array joined by a separator (defaults to ` `)
*    BareFilename     Returns filename without the full path
*    FilenameWithExtension
*/
Class clsStringFunctions {
    HotkeyToText(HK) {
        if (StrLen(RegExReplace(HK, "[\+\^\!]")) == 1) {
            StringUpper, last_char, % SubStr(HK, 0)
            text := SubStr(HK, 1, StrLen(HK)-1) . last_char
        } else text := HK
        text := StrReplace(text, "+", "Shift+")
        text := StrReplace(text, "^", "Ctrl+")
        text := StrReplace(text, "!", "Alt+")
        return text
    }
    ; Sort the string alphabetically
    Arrange(raw) {
        raw := RegExReplace(raw, "(.)", "$1`n")
        Sort raw
        Return StrReplace(raw, "`n")
    }
    ; Convert to ASCII
    ; The following code is from "just me" in https://www.autohotkey.com/boards/viewtopic.php?t=1040
    ToAscii(Key, Modifiers := "") {
        VK_MOD := {Shift: 0x10, Ctrl: 0x11, Alt: 0x12}
        ;@ahk-neko-ignore-fn 1 line; at 4/22/2024, 9:50:51 AM ; var is assigned but never used.
        VK := GetKeyVK(Key)
        ;@ahk-neko-ignore-fn 1 line; at 4/22/2024, 9:51:05 AM ; var is assigned but never used.
        SC := GetKeySC(Key)
        VarSetCapacity(ModStates, 256, 0)
        For _, Modifier In Modifiers
            If VK_MOD.HasKey(Modifier)
                NumPut(0x80, ModStates, VK_MOD[Modifier], "UChar")
        DllCall("USer32.dll\ToAscii", "UInt", VK, "UInt", SC, "Ptr", &ModStates, "UIntP", Ascii, "UInt", 0, "Int")
        Return Chr(Ascii)
    }
    /** Ellipsisize
    *        text         String to shorten.
    *        limit        Limit in pixel length.
    *        to_end       [true|false] add ellipsis to the end (or start), default is false (left).
    *        font         Font to use for adjustment calculation. Default is Segoe UI.    
    *        size         Font size used for adjustment calculation. Default is 10.
    */
    Ellipsisize(text, limit, to_end:=false, font:="Segoe UI", size:=10) {
        if (this.TextInPixels(text, font, size) < limit)
            return text
        While ( (length := this.TextInPixels(text . "...", font, size)) > limit) {
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
    TextInPixels(string, font_name:="Segoe UI", size:=10)
    {
        Gui, strFunc:Font, s%size%, %font_name%
        Gui, strFunc:Add, Text, Hwndtemp, %string%
        GuiControlGet, values, Pos, % temp
        Gui, strFunc:Destroy
        ; GuiControlGet weirdly creates variable names based off the passed `values` variable:
        return valuesW
    }
    JoinArray(array, separator := " ") {
        result := ""
        for index, element in array {
            result .= element
            if (index != array.Length()) {
                result .= separator
            }
        }
        return result
    }
    BareFilename(filename) {
        SplitPath, filename, bare_filename
        return bare_filename
    }
    FilenameWithExtension(filename, extension := ".ini") {
        extension_length := StrLen(extension)
        if (StrLen(filename) <= extension_length
                || SubStr(filename, StrLen(filename) - extension_length + 1) != extension) {
            return filename . extension
        }
        return filename
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
    SaveProperty(value, key, section, filename) {
        IniWrite %value%, %filename%, %section%, %key%
    }
    LoadProperty(key, section, filename) {
        ; IniRead returns "ERROR" if key not found
        IniRead value, %filename%, %section%, %key%
        corrected_value := value == "ERROR" ? "" : value
        return corrected_value
    }
    SaveProperties(object_to_save, ini_section := "Default", ini_filename := "") {
        if (!ini_filename) {
            ini_filename := this.default_ini
        }
        For key, value in object_to_save
            this.SaveProperty(value, key, ini_section, ini_filename)
    }
    ; return true if section not found
    LoadProperties(ByRef object_destination, ini_section := "Default", ini_filename := "") {
        if (!ini_filename) {
            ini_filename := this.default_ini
        }
        IniRead, properties, %ini_filename%, %ini_section%
        if (! properties)
            return true
        Loop, Parse, properties, `n
        {
            key := SubStr(A_LoopField, 1, InStr(A_LoopField, "=")-1)
            value := SubStr(A_LoopField, InStr(A_LoopField, "=")+1)
            if (value != "") {
                object_destination[key] := value
            }
        }
    }
    LoadSections(ini_filename := "") {
        if (!ini_filename)
            ini_filename := this.default_ini
        if (! FileExist(ini_filename))
            return false
        IniRead, sections, %ini_filename%
        return sections
    }
    DeleteSection(section, ini_filename := "") {
        if (!ini_filename)
            ini_filename := this.default_ini
        IniDelete, % ini_filename, % section
    }
}

ReplaceWithVariants(text, enclose_latin_letters:=false) {
    new_str := text
    new_str := StrReplace(new_str, "+", Chr(0x21E7))
    new_str := StrReplace(new_str, " ", Chr(0x2423))
    if (enclose_latin_letters) {
        Loop, 26 {
            new_str := StrReplace(new_str, Chr(96 + A_Index), Chr(0x1F12F + A_Index))
        }
        new_str := RegExReplace(new_str, "(?<=.)(?=.)", " ") ; add spaces between characters
    }
    Return new_str
}

class clsUpdater {
    /** SemVer 2.0.0 comparison
    * SemVerCompare(v1, v2) -> 1 if v1>v2, 0 if equal, -1 if v1<v2
    */
    SemVerCompare(v1, v2) {
        v1 := this._sv_norm(v1)
        v2 := this._sv_norm(v2)

        RegExMatch(v1, "O)^\s*([0-9]+(?:\.[0-9]+){0,})?(?:-([0-9A-Za-z\.-]+))?", m1)
        RegExMatch(v2, "O)^\s*([0-9]+(?:\.[0-9]+){0,})?(?:-([0-9A-Za-z\.-]+))?", m2)

        main1 := (m1[1] = "") ? "0" : m1[1]
        main2 := (m2[1] = "") ? "0" : m2[1]

        a1 := StrSplit(main1, ".")
        a2 := StrSplit(main2, ".")
        max := (a1.MaxIndex() > a2.MaxIndex()) ? a1.MaxIndex() : a2.MaxIndex()
        if (max < 3)
            max := 3

        loop % max {
            n1 := (A_Index <= a1.MaxIndex()) ? a1[A_Index]+0 : 0
            n2 := (A_Index <= a2.MaxIndex()) ? a2[A_Index]+0 : 0
            if (n1 > n2)
                return 1
            if (n1 < n2)
                return -1
        }

        pre1 := m1[2], pre2 := m2[2]
        if (pre1 = "" && pre2 = "")
            return 0
        if (pre1 = "" && pre2 != "")
            return 1
        if (pre1 != "" && pre2 = "")
            return -1

        s1 := StrSplit(pre1, ".")
        s2 := StrSplit(pre2, ".")
        maxp := (s1.MaxIndex() > s2.MaxIndex()) ? s1.MaxIndex() : s2.MaxIndex()

        loop % maxp {
            id1 := s1[A_Index], id2 := s2[A_Index]
            if (id1 = "" && id2 = "")
                continue
            if (id1 = "")
                return -1
            if (id2 = "")
                return 1

            isNum1 := RegExMatch(id1, "^\d+$")
            isNum2 := RegExMatch(id2, "^\d+$")

            if (isNum1 && isNum2) {
                n1 := id1 + 0, n2 := id2 + 0
                if (n1 > n2)
                    return 1
                if (n1 < n2)
                    return -1
            } else if (isNum1 && !isNum2) {
                return -1  ; numeric < non-numeric
            } else if (!isNum1 && isNum2) {
                return 1   ; non-numeric > numeric
            } else {
                cmp := DllCall("lstrcmp", "str", id1, "str", id2, "int")
                if (cmp > 0)
                    return 1
                if (cmp < 0)
                    return -1
            }
        }
        return 0
    }

    _sv_norm(v) {
        v := Trim(v)
        v := RegExReplace(v, "i)^[vV]\s*", "")   ; drop leading v
        v := RegExReplace(v, "\+.*$", "")        ; drop build metadata
        return v
    }
}

; Simple performance measuring using QueryPerformanceCounter
; Call once to start measuring, call again to output elapsed time in ms to debug console

QPC() {
	static frequency
    static start
    if (! frequency)
        DllCall("kernel32\QueryPerformanceFrequency", Int64P, frequency)
	DllCall("kernel32\QueryPerformanceCounter", Int64P, count)
    if (start) {
        OutputDebug, % Format("`nElapsed time (ms): {:.2f}`n",  ((count / frequency) - start) * 1000)
        start := 0
    } else start := count / frequency
}