/*

This file is part of ZipChord.

Copyright (c) 2021-2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

global chords := New clsDictionary(true)
global shorthands := New clsDictionary

global add_shortcut := new clsAddShortcut

/**
* Class for dictionaries.
* Initializing:
*    Create the dictionary object with "chorded_keys := true" for it to behave like a dictionary of chords.
* Properties:
*    entries - number of entries in the dictionary
* Methods:
*    LookUp(shortcut)     - returns expanded text or false if not found
*    ReverseLookUp(text)  - returns corresponding shortcut or false if not found
*    Load([file])         - Reloads the dictionary entries from the current dictionary file or from the specified file
*    Add(shortcut, text)  - Adds the entry into the dictionary
*/
Class clsDictionary {
    _chorded := false
    _file := ""
    _entries := {}
    _reverse_entries := {}
    _pause_loading := true
    ; Public properties and methods
    entries {
        get { 
            return this._entries.Count() 
        }
    }
    LookUp(shortcut) {
        if ( this._entries.HasKey(shortcut) )
            return this._entries[shortcut]
        else
            return false
    }
    ReverseLookUp(text) {
        if ( this._reverse_entries.HasKey(text) )
            return this._reverse_entries[text]
        else
            return false
    }
    Load(filename := "") {
        this._pause_loading := true
        if (filename == "")
            filename := this._file
        if (filename != "") {
            this._file := filename
            this._LoadShortcuts()
        } else {
            MsgBox, , % "ZipChord", % "Error: Tried to open a dictionary without specifying the file." 
        }
    }
    Add(shortcut, text) {
        if( ! this._RegisterShortcut(shortcut, text, true) )
            return False
        return True
    }
    ; Private functions
    __New(chorded_keys := false) {
        this._chorded := chorded_keys
    }
    ; Load chords from a dictionary file
    _LoadShortcuts() {
        this._entries := {}
        this._reverse_entries := {}
        Loop, Read, % this._file
        {
            columns := StrSplit(A_LoopReadLine, A_Tab, , 3)
            if (columns[2] && columns[1] != "") {
                if (! this._RegisterShortcut(columns[1], columns[2]))  {
                    if this._AskWhetherToStop()
                        Break
                }
            }
        }
    }
    ; Adds a new pair of chord and its expanded text directly to 'this._entries'
    _RegisterShortcut(newch_unsorted, newword, write_to_file:=false) {
        if (this._chorded)
            newch := Arrange(newch_unsorted)
        else
            newch := newch_unsorted
        if (! this._IsShortcutOK(newch, newword))
            return false
        if (this._chorded && StrLen(RegExReplace(newch,"(.)(?=.*\1)")) != StrLen(newch)) {  ; the RegEx removes duplicate letters to check for repetition of characters
            MsgBox ,, % "ZipChord", % "Each key can be entered only once in the same chord."
            Return false
        }
        ObjRawSet(this._entries, newch, newword)
        if ( ! InStr(newword, " ") )
            ObjRawSet(this._reverse_entries, newword, newch_unsorted)
        if (write_to_file)
            FileAppend % "`r`n" newch_unsorted "`t" newword, % this._file, UTF-8  ; saving unsorted for easier human readability of the dictionary
        return true
    }
    _IsShortcutOK(shortcut, word) {
        dest := this._chorded ? "chord" : "shorthand"
        if (occupied := this.LookUp(shortcut)) {
            MsgBox ,, % "ZipChord", % Format("The {1} '{2}' is already in use for '{3}'.`nPlease use a different {1} for '{4}'.", dest, shortcut, occupied, word)
            Return false
        }
        if (StrLen(shortcut)<2) {
            MsgBox ,, % "ZipChord", % Format("The {1} for '{2}' needs to be at least two characters.", dest, word)
            Return false
        }
        if (word=="") {
            MsgBox ,, % "ZipChord", % "There is no word being provided for the shortcut."
            Return false
        }
        Return True
    }
    _AskWhetherToStop() {
        if (this._pause_loading) {
        MsgBox, 4, % "ZipChord", % "Would you like to continue loading the dictionary file?`n`nIf Yes, you'll see all errors in the dictionary.`nIf No, the rest of the dictionary will be ignored."
        IfMsgBox Yes
            this._pause_loading := false
        else
            Return True
        }
        Return False
    }
}

CheckDictionaryFileExists(dictionary_file, dictionary_type) {
    if (! FileExist(dictionary_file) ) {
        errmsg := Format("The {1} dictionary '{2}' could not be found.`n`n", dictionary_type, dictionary_file)
        ; If we don't have the dictionary, try opening the first file with a matching naming convention.
        new_file := dictionary_type "s*.txt"
        if FileExist(new_file) {
            Loop, Files, %new_file%
                flist .= SubStr(A_LoopFileName, 1, StrLen(A_LoopFileName)-4) "`n"
            Sort flist
            new_file := SubStr(flist, 1, InStr(flist, "`n")-1) ".txt"
            errmsg .= Format("ZipChord detected the dictionary '{}' and is going to open it.", new_file)
        }
        else {
            errmsg .= Format("ZipChord is going to create a new '{}s.txt' dictionary in its own folder.", dictionary_type)
            new_file := dictionary_type "s.txt"
            FileAppend % "This is a " dictionary_type " dictionary for ZipChord. Define " dictionary_type "s and corresponding expanded words in a tab-separated list (one entry per line).`nSee https://github.com/psoukie/zipchord for details.`n`ndm`tdemo", %new_file%, UTF-8
        }
        MsgBox ,, ZipChord, %errmsg%
        Return new_file
    }
    Return dictionary_file
}


/**
* Class for Adding Shortcuts.
*
* Public Methods:
*    Show
*/
Class clsAddShortcut {
    UI := {}

    controls := { text:            { type: "Edit" }
                , chord:           { type: "Edit"
                                   , function: ObjBindMethod(this, "_FocusControl", "chord")}
                , shorthand:       { type: "Edit"
                                   , function: ObjBindMethod(this, "_FocusControl", "shorthand")}
                , adjust_text:     { type: "Button"
                                   , text: "&Adjust"
                                   , function: ObjBindMethod(this, "_AdjustText")}
                , save_chord:  {type: "Button"
                              , text: "&Save"
                              , function: ObjBindMethod(this, "_SaveShortcut", "chord")}
                , save_shorthand:  { type: "Button"
                                   , text: "Sa&ve"
                              , function: ObjBindMethod(this, "_SaveShortcut", "shorthand")}}

    Show(exp) {
        call := Func("OpenHelp").Bind("AddShortcut")
        Hotkey, F1, % call, On
        WireHotkeys("Off")  ; so the user can edit values without interference
        this._Build()
        if (exp=="") {
            this.controls.adjust_text.Hide()
            this.controls.text.Focus()
        } else {
            this.controls.text.Disable()
            this.controls.text.value := exp
            this._ShowHelper("shorthand")
            this._ShowHelper("chord")
        }
        this.UI.Show()
    }
    _ShowHelper(ctrl) {
        obj_name := ctrl . "s"
        if (chord := %obj_name%.ReverseLookUp(this.controls.text.value)) {
            this.controls[ctrl].Disable()
            this.controls[ctrl].value := chord
            this.controls["save_" . ctrl].Disable()
        } else
            this.controls[ctrl].Focus()
    }
    _Build() {
        this.UI := new clsUI("Add Shortcut")
        this.UI.on_close := ObjBindMethod(this, "Close")
        this.UI.Add("Text", "Section", "&Expanded text")
        this.UI.Add(this.controls.text, "y+10 w220")
        this.UI.Add(this.controls.adjust_text, "x+20 yp w100")
        this._BuildHelper("&Chord", "chord", "Individual keys that make up the chord, without pressing Shift or other modifier keys.", "xs h120 w360")
        this._BuildHelper("S&horthand", "shorthand", "Sequence of keys of the shorthand, without pressing Shift or other modifier keys.")
        this.UI.Add("Button", "Default x265 y+30 w100", "Close", ObjBindMethod(this, "Close"))
    }
    _BuildHelper(heading, ctrl, text, opt:="xs-20 y+30 h120 w360") {
        this.UI.Add("GroupBox", opt, heading)
        Gui, Font, s10, Consolas
        this.UI.Add(this.controls[ctrl], "xp+20 yp+30 Section w200")
        Gui, Font, s10, Segoe UI
        this.UI.Add(this.controls["save_" . ctrl], "x+20 yp w100")
        this.UI.Add("Text", "xs +Wrap w320", text)
    }
    Close() {
        Hotkey, F1, Off
        this.UI.Destroy()
        if (settings.mode > MODE_ZIPCHORD_ENABLED)
            WireHotkeys("On")  ; resume normal mode
    }
    _AdjustText() {
        this.controls.chord.value :=""
        this.controls.shorthand.value :=""
        for _, control in this.controls
            control.Enable()
        this.controls.adjust_text.Disable()
        this.controls.text.Focus()
    }
    _SaveShortcut(dictionary) {
        obj_name := dictionary . "s"
        if (%obj_name%.Add(this.controls[dictionary].value, this.controls.text.value)) {
            this.Close()
            UpdateDictionaryUI()
        }
    }
    _FocusControl(ctrl) {
        if (this.controls[ctrl].is_enabled && this.controls[ctrl].value != "")
            this.controls["save_" . ctrl].MakeDefault()
    }
}