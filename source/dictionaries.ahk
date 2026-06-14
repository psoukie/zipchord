/*
This file is part of ZipChord.
Copyright (c) 2021-2026 Pavel Soukenik
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
        if (filename == "") {
            filename := this._file
        }
        if (filename == "") {
            MsgBox, , % "ZipChord", % "Error: Tried to open a dictionary without specifying the file." 
            return
        }
        filename := this._GetFullFileName(filename)
        if ! FileExist(filename) {
            dictionary_type := this._chorded ? "chord" : "shorthand"
            MsgBox ,, % "ZipChord", % Format("The {} dictionary file '{}' could not be found.", dictionary_type, filename)
            return false
        }
        this._file := this._EnsureV2DictionaryFile(filename)
        if (!this._file)
            return false
        this._LoadShortcuts()
        return true
    }
    _GetFullFileName(filename) {
        if (InStr(filename, "\")) {
            return filename
        }
        path := settings.dictionary_dir
        if (SubStr(path, StrLen(path)) != "\") {
            return path . "\" . filename
        } else {
            return path . filename
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
    _IsV2DictionaryFile(filename) {
        v2ext := this._chorded ? ".chords.txt" : ".shorthands.txt"
        if StrLen(v2ext) > StrLen(filename) {
            return False
        }
        ext := SubStr(filename, StrLen(filename) - StrLen(v2ext) + 1)
        StringLower, lowercase_ext, ext
        return lowercase_ext == v2ext
    }
    _GetCanonicalDictionaryFileName(filename) {
        SplitPath, filename, _, file_dir, _, file_no_ext
        MsgBox, % file_no_ext
        prefix := this._chorded ? "chords-" : "shorthands-"
        filename_start := SubStr(file_no_ext, 1, StrLen(prefix))
        StringLower lowercase_prefix, filename_start 
        if (lowercase_prefix == prefix) {
            file_no_ext := SubStr(file_no_ext, StrLen(prefix) + 1)
        } 
        return (file_dir ? file_dir . "\\" : "") . file_no_ext . (this._chorded ? ".chords.txt" : ".shorthands.txt")
    }
    _EnsureV2DictionaryFile(filename) {
        if (this._IsV2DictionaryFile(filename))
            return filename
        canonical_file := this._GetCanonicalDictionaryFileName(filename)
        if FileExist(canonical_file) {
            return canonical_file
        }
        if (this._UpgradeDictionaryFile(filename, canonical_file)) {
            return canonical_file
        }
        return false
    }
    _UpgradeLegacyChordShortcut(shortcut) {
        replaced := StrReplace(shortcut, " ", "|")
        replaced := StrReplace(replaced, "||", "| ") ; situations where the next chord starts with a space
        return SubStr(shortcut, 1, 1) . SubStr(replaced, 2) ; keeping the first space in the first chord
    }
    _UpgradeDictionaryFile(old_file, new_file) {
        upgraded_file := ""
        Loop, Read, % old_file
        {
            line := A_LoopReadLine
            columns := StrSplit(line, A_Tab, , 3)
            if (this._chorded && columns[2] && columns[1] != "") {
                line := this._UpgradeLegacyChordShortcut(columns[1]) . SubStr(line, InStr(line, A_Tab))
            }
            upgraded_file .= (A_Index == 1 ? "" : "`r`n") . line
        }
        FileAppend % upgraded_file, % new_file, UTF-8
        if (ErrorLevel) {
            MsgBox ,, % "ZipChord", % Format("ZipChord could not create the upgraded dictionary file '{}' from '{}'.", new_file, old_file)
            Return false
        }
        Return true
    }
    ; Private helper: check for duplicate letters in a shortcut and show warning if found
    _IsDuplicateChars(shortcut, word) {
        ; Detect duplicate characters: if length changes after removing duplicates, there are repeats
        if (StrLen(RegExReplace(shortcut,"(.)(?=.*\1)")) != StrLen(shortcut)) {
            MsgBox ,, % "ZipChord", % Format("In entry for '{}', each key can be entered only once in the same chord.", word)
            Return true
        }
        Return false
    }

    ; Adds a new pair of chord and its expanded text directly to 'this._entries'
    _RegisterShortcut(newch_unsorted, newword, write_to_file:=false) {
        if (this._chorded) {
            if (InStr(newch_unsorted, "|")) {
                chunks := StrSplit(newch_unsorted, "|")
                For _, chunk in chunks {
                    if (chunk == "") {
                        MsgBox ,, % "ZipChord", % Format("The chained chord for '{}' includes an empty chord.", newword)
                        Return false
                    }
                    newch .= "|" . str.Arrange(chunk)
                    if (this._IsDuplicateChars(chunk, newword)) {
                        Return false
                    }
                }
                newch := SubStr(newch, 2)
            } else {
                newch := str.Arrange(newch_unsorted)
                if (this._IsDuplicateChars(newch, newword)) {
                    Return false
                }
            }
        } else {
            newch := newch_unsorted
        }
        if (! this._IsShortcutOK(newch, newword))
            Return false
        ObjRawSet(this._entries, newch, newword)
        if ( ! InStr(newword, " ") )
            ObjRawSet(this._reverse_entries, newword, newch_unsorted)
        if (write_to_file)
            FileAppend % "`r`n" newch_unsorted "`t" newword, % this._file, UTF-8  ; saving unsorted for easier human readability of the dictionary
        Return true
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
    global app_settings

    if (! FileExist(dictionary_file) ) {
        ; On the first run only (if we cannot find the dictionary file), offer to download and store dictionaries under My Documents
        if (settings.preferences & PREF_FIRST_RUN) {
            dictionary_dir := A_MyDocuments . "\ZipChord"
            if (InStr(FileExist(dictionary_dir), "D")) {
                _UpdateWorkingDir(dictionary_dir)
                return CheckDictionaryFileExists(dictionary_file, dictionary_type)
            }
            MsgBox, 4, % "ZipChord", % Format("Would you like to download starting dictionary files and save them in the '{}' folder?", dictionary_dir)
            IfMsgBox Yes
            {
                if ( ! InStr(FileExist(dictionary_dir), "D")) {
                    FileCreateDir,  % dictionary_dir
                }
                _UpdateWorkingDir(dictionary_dir)
                UrlDownloadToFile, https://raw.githubusercontent.com/psoukie/zipchord/main/dictionaries/en-qwerty.chords.txt, % dictionary_dir . "\en-qwerty.chords.txt"
                UrlDownloadToFile, https://raw.githubusercontent.com/psoukie/zipchord/main/dictionaries/english.shorthands.txt, % dictionary_dir . "\english.shorthands.txt"
                return CheckDictionaryFileExists(dictionary_file, dictionary_type)
            }
        }
        errmsg := Format("The {1} dictionary '{2}' could not be found.`n`n", dictionary_type, dictionary_file)
        canonical_pattern := dictionary_type == "chord" ? "*.chords.txt" : "*.shorthands.txt"
        new_file := _FindFirstDictionaryFile(canonical_pattern)
        if (new_file != "") {
            errmsg .= Format("ZipChord found the dictionary '{}' and is going to open it.", new_file)
        }
        else {
            new_file := dictionary_type == "chord" ? "dictionary.chords.txt" : "dictionary.shorthands.txt"
            errmsg .= Format("ZipChord is going to create a new '{}' dictionary in '{}'.", new_file, A_WorkingDir)
            FileAppend % "This is a " dictionary_type " dictionary for ZipChord. Define " dictionary_type "s and corresponding expanded words in a tab-separated list (one entry per line).`nSee https://github.com/psoukie/zipchord/wiki/shortcut-dictionaries for details.`n`ndm`tdemo", %new_file%, UTF-8
        }
        MsgBox ,, ZipChord, %errmsg%
        Return new_file
    }
    Return dictionary_file
}

_FindFirstDictionaryFile(pattern) {
    flist := ""
    if ! FileExist(pattern)
        return ""
    Loop, Files, %pattern%
        flist .= A_LoopFileName . "`n"
    Sort flist
    return SubStr(flist, 1, InStr(flist, "`n")-1)
}

_UpdateWorkingDir(new_dir) {
    global app_settings
    settings.dictionary_dir := new_dir
    SetWorkingDir, % settings.dictionary_dir
    app_settings.Save()
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
        call := ObjBindMethod(this, "_Backspace")
        Hotkey, $^Backspace, % call, On
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
    Reshow() {
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
        this.UI := new clsUI("Add or Edit Shortcut")
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
        this.UI.Font("s10", "Consolas")
        this.UI.Add(this.controls[ctrl], "xp+20 yp+30 Section w200")
        this.UI.Font("s10", "Segoe UI")
        this.UI.Add(this.controls["save_" . ctrl], "x+20 yp w100")
        this.UI.Add("Text", "xs +Wrap w320", text)
    }
    Close() {
        Hotkey, F1, Off
        Hotkey, $^Backspace, Off
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
            main_UI.UpdateDictionaryUI()
        }
    }
    _FocusControl(ctrl) {
        if (this.controls[ctrl].is_enabled && this.controls[ctrl].value != "")
            this.controls["save_" . ctrl].MakeDefault()
    }
    _Backspace() {
        if WinActive("Add Shortcut")
            SendInput ^+{Left}{Del}
        else
            SendInput ^{Backspace}
    }
}