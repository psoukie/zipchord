/*
This file is part of ZipChord.
Copyright (c) 2021-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license.
*/

global chords := New clsDictionary(true)
global shorthands := New clsDictionary

global assign_shortcut := new clsAssignShortcuts

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
    _file_modified := ""
    _file_size := ""
    _reload_due := 0
    _entries := {}
    _reverse_entries := {}
    _dll_entries_count := 0
    _is_watching := false
    _pause_loading := true

    entries {
        get {
            if (dll.available) {
                return this._dll_entries_count
            }
            return this._entries.Count()
        }
    }

    __New(chorded_keys := false) {
        this._chorded := chorded_keys
    }
    LookUp(shortcut) {
        if (dll.available) {
            if !(this._chorded) {
                ; convert shorthands to lowercase for AHK parity
                StringLower, lcase_shortcut, shortcut
                return dll.LookUp(lcase_shortcut, this._chorded)
            } else {
                return dll.LookUp(shortcut, this._chorded)
            }
        }
        ; else use AHK path
        if ( this._entries.HasKey(shortcut) ) {
            return this._entries[shortcut]
        }
        return false

    }

    ReverseLookUp(expansion) {
        if (dll.available) {
            ; lowercase for parity with AHK (Dll stores lowercase version in reverse lookup)
            StringLower, lcase_expansion, expansion
            return dll.ReverseLookUp(lcase_expansion, this._chorded)
        }
        ; else use AHK path
        if ( this._reverse_entries.HasKey(expansion) ) {
            return this._reverse_entries[expansion]
        }
        return false
    }

    Load(filename := "") {
        if (filename == "") {
            filename := this._file
        }
        this.Unload()
        this._pause_loading := true
        if (filename == "") {
            MsgBox, , % "ZipChord", % "Error: Tried to open a dictionary without specifying the file."
            return false
        }
        filename := this.GetFullFileName(filename)
        if ! FileExist(filename) {
            dictionary_type := this._chorded ? "chord" : "shorthand"
            MsgBox ,, % "ZipChord", % Format("The {} dictionary file '{}' could not be found.", dictionary_type, filename)
            return false
        }
        this._file := this._EnsureV2DictionaryFile(filename)
        if (!this._file) {
            return false
        }
        this._LoadShortcuts()
        this._UpdateTrackedFileState()
        this.StartWatching()

        return true
    }

    Unload() {
        this.StopWatching()
        this._file := ""
        this._entries := {}
        this._reverse_entries := {}
        shortcuts_loaded := 0
        if (dll.available) {
            dll.LoadDictionary("", this._chorded, shortcuts_loaded)
            this._dll_entries_count := shortcuts_loaded
        }
    }
    GetFullFileName(filename) {
        if (filename == "") {
            return ""
        }
        if (DllCall("shlwapi.dll\PathIsRelativeW", "WStr", filename)) {
            base_dir := settings.dictionary_dir ? settings.dictionary_dir : A_WorkingDir
            filename := RTrim(base_dir, "\/") . "\" . filename
        }

        buffer_size := 32768
        VarSetCapacity(full_path, buffer_size * 2, 0)
        length := DllCall("kernel32.dll\GetFullPathNameW"
                , "WStr", filename, "UInt", buffer_size, "Ptr", &full_path, "Ptr", 0, "UInt")
        if (!length || length >= buffer_size) {
            return filename
        }
        return StrGet(&full_path, length, "UTF-16")
    }

    AddShortcut(raw_shortcut, expansion) {
        if (! this.ValidateDictEdit(raw_shortcut)) {
            return false
        }

        fn := dll.available ? ObjBindMethod(dll, "EditDictionary", this._file, "", raw_shortcut, expansion) :ObjBindMethod(this, "_Ahk_AddShortcutToDict", raw_shortcut, expansion)
        return this.TryExecutingDictEdit(fn)
    }

    ChangeShortcut(old_shortcut, new_shortcut) {
        if (! this.ValidateDictEdit(new_shortcut)) {
            return false
        }

        fn := dll.available ? ObjBindMethod(dll, "EditDictionary", this._file, old_shortcut, new_shortcut) : ObjBindMethod(this, "_Ahk_EditDictionary", old_shortcut, new_shortcut)
        return this.TryExecutingDictEdit(fn)
    }

    DeleteShortcut(old_shortcut) {
        if (! this.ValidateDictEdit()) {
            return false
        }

        fn := dll.available ? ObjBindMethod(dll, "EditDictionary", this._file, old_shortcut) : ObjBindMethod(this, "_Ahk_DeleteFromDictionary", old_shortcut)
        return this.TryExecutingDictEdit(fn)
    }

    ValidateDictEdit(raw_shortcut := "") {
        if (this._file == "") {
            MsgBox, , % "ZipChord", % "First, select a dictionary."
            return false
        }

        if (raw_shortcut == "") {
            return true
        }

        ; Check the shortcut does not exist
        return this._ValidateShortcut(raw_shortcut)
    }

    TryExecutingDictEdit(fn) {
        this.PauseWatching()
        if (! fn.Call()) {
            this.StartWatching()
            return false
        }

        this.Load()  ; Provides its own error messages; we throw away the error on purpose here.
        main_UI.UpdateDictionaryUI()
        return true
    }

    _Ahk_AddShortcutToDict(raw_shortcut, expansion) {
        return this._Ahk_EditDictionaryFile("", raw_shortcut, expansion)
    }

    _Ahk_EditDictionary(old_shortcut, new_shortcut) {
        return this._Ahk_EditDictionaryFile(old_shortcut, new_shortcut)
    }

    _Ahk_DeleteFromDictionary(old_shortcut) {
        return this._Ahk_EditDictionaryFile(old_shortcut)
    }

    _Ahk_EditDictionaryFile(old_shortcut := "", new_shortcut := "", expansion := "") {
        if (new_shortcut != "" && expansion != "") {
            operation := "Add"
        } else if (new_shortcut != "" && old_shortcut != "") {
            operation := "Change"
        } else if (old_shortcut != "") {
            operation := "Delete"
        } else {
            MsgBox , , % "ZipChord", % "ZipChord encountered a bad argument while editing the dictionary file."
            return false
        }

        file := FileOpen(this._file, "r", "UTF-8-RAW")
        if (! IsObject(file)) {
            MsgBox , , % "ZipChord", % "ZipChord encountered an error while reading the dictionary file."
            return false
        }
        file_text := file.Read()
        file.Close()
        file := ""

        if (operation == "Add") {
            opening_new_line := "`r`n"
            ending_new_line := "`r`n"
            if (SubStr(file_text, StrLen(file_text), 1) == "`n") {
                if (StrLen(file_text) >= 2 && SubStr(file_text, StrLen(file_text) - 1) == "`r`n") {
                    opening_new_line := ""
                } else {
                    opening_new_line := ""
                    ending_new_line := "`n"
                }
            } else if (! InStr(file_text, "`r`n", true) && InStr(file_text, "`n", true)) {
                opening_new_line := "`n"
                ending_new_line := "`n"
            }
            start_pos := StrLen(file_text) + 1
            end_pos := StrLen(file_text)
            replacement := opening_new_line . new_shortcut . "`t" . expansion . ending_new_line
        } else {
            needle := "`n" . old_shortcut . "`t"
            pos := InStr(file_text, needle, true)
            if (pos) {
                start_pos := pos + 1
            } else if (SubStr(file_text, 1, StrLen(Chr(0xFEFF) . old_shortcut . "`t")) == Chr(0xFEFF) . old_shortcut . "`t") {
                start_pos := 2
            } else if (SubStr(file_text, 1, StrLen(old_shortcut . "`t")) == old_shortcut . "`t") {
                start_pos := 1
            } else {
                MsgBox , , % "ZipChord", % Format("ZipChord could not find the shortcut '{}' in the dictionary file.", old_shortcut)
                return false
            }

            if (operation == "Delete") {
                replacement := ""
                pos := InStr(SubStr(file_text, start_pos), "`n", true)
                if (! pos) {
                    end_pos := StrLen(file_text)
                } else {
                    end_pos := start_pos + pos - 1
                }
            } else {
                replacement := new_shortcut
                end_pos := start_pos + StrLen(old_shortcut) - 1
            }
        }

        new_text := SubStr(file_text, 1, start_pos - 1) . replacement . SubStr(file_text, end_pos + 1)
        temp_file := this._file . ".tmp"
        try {
            if (FileExist(temp_file)) {
                FileDelete, % temp_file
            }
            file := FileOpen(temp_file, "w", "UTF-8-RAW")
            if (! IsObject(file)) {
                throw 1
            }
            file.Write(new_text)
            file.Close()
            file := ""
            FileMove, % temp_file, % this._file, 1
            if (ErrorLevel) {
                throw 1
            }
            return true
        } catch {
            if (IsObject(file)) {
                file.Close()
            }
            if (FileExist(temp_file)) {
                FileDelete, % temp_file
            }
            MsgBox , , % "ZipChord", % "ZipChord encountered an error while editing the dictionary file."
            return false
        }
    }

    StartWatching() {
        this._is_watching := true
    }
    StopWatching() {
        this._is_watching := false
        this._reload_due := 0
        this._file_modified := ""
        this._file_size := ""
    }
    PauseWatching() {
        this._is_watching := false
    }
    _GetDictModifiedTime() {
        filename := this._file
        FileGetTime, last_modified, %filename%
        return last_modified
    }
    _GetDictFileSize() {
        filename := this._file
        FileGetSize, file_size, %filename%
        return file_size
    }
    _UpdateTrackedFileState() {
        this._file_modified := this._GetDictModifiedTime()
        this._file_size := this._GetDictFileSize()
        this._reload_due := 0
    }

    CheckForDictModification() {
        if (! this._is_watching || this._file == "") {
             return
        }
        if (! FileExist(this._file)) {
            this.Unload()
            main_UI.UpdateDictionaryUI()
            return
        }

        current_modified := this._GetDictModifiedTime()
        current_size := this._GetDictFileSize()

        if (current_modified != this._file_modified || current_size != this._file_size) {
            this._reload_due := A_TickCount + 1200
            this._file_modified := current_modified
            this._file_size := current_size
            return
        }
        if (this._reload_due && A_TickCount >= this._reload_due) {
            this.Load()
            main_UI.UpdateDictionaryUI()
        }
    }

    ; Load chords from a dictionary file
    _Ahk_LoadShortcuts() {
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
    _Dll_LoadShortcuts() {
        global dll_buffer
        shortcuts_loaded := 0
        result := dll.LoadDictionary(this._file, this._chorded, shortcuts_loaded)
        if (result < 0) {
            raw_shortcut := dll.GetSavedString()
            type := this._chorded ? "chord" : "shorthand"
            reason := ""
            Switch result {
                Case DllError.REPEATED_KEY:
                    reason := "a repeated key"
                Case DllError.SHORTCUT_EXISTS:
                    shortcut := this._chorded ? dll.NormalizeChord(raw_shortcut) : raw_shortcut
                    occupied := this.LookUp(shortcut)
                    reason := "a shortcut that is already in use for '" . occupied . "'"
                Case DllError.FEWER_THAN_TWO:
                    reason := "a shortcut with less than two characters"
                Default:
                    reason := dll.GetErrorDetails(result)
            }
            MsgBox, , % "ZipChord", % Format("ZipChord encountered {} while processing the {} '{}'.", reason, type, raw_shortcut)
            this._dll_entries_count := shortcuts_loaded
            return
        }
        this._dll_entries_count := shortcuts_loaded
        return
    }
    _LoadShortcuts() {
        if (dll.available) {
            return this._Dll_LoadShortcuts()
        }
        return this._Ahk_LoadShortcuts()
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
        prefix := this._chorded ? "chords-" : "shorthands-"
        filename_start := SubStr(file_no_ext, 1, StrLen(prefix))
        StringLower lowercase_prefix, filename_start
        if (lowercase_prefix == prefix) {
            file_no_ext := SubStr(file_no_ext, StrLen(prefix) + 1)
        }
        return (file_dir ? file_dir . "\" : "") . file_no_ext . (this._chorded ? ".chords.txt" : ".shorthands.txt")
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
    _IsDuplicateChars(shortcut, expansion := "") {
        ; Detect duplicate characters: if length changes after removing duplicates, there are repeats
        if (StrLen(RegExReplace(shortcut,"(.)(?=.*\1)")) != StrLen(shortcut)) {
            if (expansion == "") {
                MsgBox ,, % "ZipChord", % "Each key can be entered only once in the same chord."
            } else {
                MsgBox ,, % "ZipChord", % Format("In the entry for '{}', each key can be entered only once in the same chord.", expansion)
            }
            Return true
        }
        Return false
    }

    _Ahk_ValidateShortcut(raw_shortcut, ByRef shortcut, expansion := "") {
        if (this._chorded) {
            if (InStr(raw_shortcut, "|")) {
                chunks := StrSplit(raw_shortcut, "|")
                shortcut := ""
                For _, chunk in chunks {
                    if (chunk == "") {
                        if (expansion == "") {
                            message := "The chained chord includes an empty chord."
                        } else {
                            message := Format("The chained chord for '{}' includes an empty chord.", expansion)
                        }
                        MsgBox ,, % "ZipChord", % message
                        return false
                    }
                    shortcut .= "|" . str.Arrange(chunk)
                    if (this._IsDuplicateChars(chunk, expansion)) {
                        return false
                    }
                }
                shortcut := SubStr(shortcut, 2)
            } else {
                shortcut := str.Arrange(raw_shortcut)
                if (this._IsDuplicateChars(shortcut, expansion)) {
                    return false
                }
            }
        } else {
            shortcut := raw_shortcut
        }
        return this._IsShortcutOK(shortcut, expansion)
    }

    ; Adds a new pair of chord and its expanded text directly to 'this._entries'
    _Ahk_RegisterShortcut(raw_shortcut, expansion) {
        if (! this._Ahk_ValidateShortcut(raw_shortcut, shortcut, expansion)) {
            return false
        }
        if (expansion == "") {
            MsgBox ,, % "ZipChord", % "There is no expansion being provided for the shortcut."
            return false
        }

        ObjRawSet(this._entries, shortcut, expansion)
        ObjRawSet(this._reverse_entries, expansion, raw_shortcut)
        return true
    }

    _Dll_ValidateShortcut(raw_shortcut) {
        result := dll.ValidateShortcut(raw_shortcut, this._chorded)
        Switch result {
            Case DllError.NONE:
                return true
            Case DllError.SHORTCUT_EXISTS:
                dest := this._chorded ? "chord" : "shorthand"
                shortcut := this._chorded ? dll.NormalizeChord(raw_shortcut) : raw_shortcut
                occupied := this.LookUp(shortcut)
                MsgBox ,, % "ZipChord", % Format("The {1} '{2}' is already in use for '{3}'.`nPlease use a different {1}.", dest, raw_shortcut, occupied)
            Case DllError.FEWER_THAN_TWO:
                MsgBox ,, % "ZipChord", % "The shortcut must be at least two characters."
            Default:
                err_details := dll.GetErrorDetails(result)
                MsgBox , , % "ZipChord", % Format("ZipChord encountered {} error while adding the shortcut.", err_details)
        }
        return false
    }

    _Dll_RegisterShortcut(raw_shortcut, expansion) {
        result := dll.RegisterShortcut(raw_shortcut, expansion, this._chorded)
        Switch result {
            Case DllError.NONE:
                return true
            Case DllError.SHORTCUT_EXISTS:
                dest := this._chorded ? "chord" : "shorthand"
                shortcut := this._chorded ? dll.NormalizeChord(raw_shortcut) : raw_shortcut
                occupied := this.LookUp(shortcut)
                MsgBox ,, % "ZipChord", % Format("The {1} '{2}' is already in use for '{3}'.`nPlease use a different {1} for '{4}'.", dest, raw_shortcut, occupied, expansion)
            Case DllError.FEWER_THAN_TWO:
                MsgBox ,, % "ZipChord", % "The shortcut must be at least two characters."
            Default:
                err_details := dll.GetErrorDetails(result)
                MsgBox , , % "ZipChord", % Format("ZipChord encountered {} error while adding the shortcut.", err_details)
        }
        return false
    }

    _ValidateShortcut(raw_shortcut) {
        if (dll.available) {
            return this._Dll_ValidateShortcut(raw_shortcut)
        }
        return this._Ahk_ValidateShortcut(raw_shortcut, shortcut)
    }

    _RegisterShortcut(raw_shortcut, expansion) {
        if (dll.available) {
            if !(this._Dll_RegisterShortcut(raw_shortcut, expansion)) {
                return false
            }
            this._dll_entries_count += 1
        } else {
            if !(this._Ahk_RegisterShortcut(raw_shortcut, expansion)) {
                return false
            }
        }
        return true
    }

    _IsShortcutOK(shortcut, expansion := "") {
        dest := this._chorded ? "chord" : "shorthand"
        if (occupied := this.LookUp(shortcut)) {
            if (expansion == "") {
                MsgBox ,, % "ZipChord", % Format("The {1} '{2}' is already in use for '{3}'.`nPlease use a different {1}.", dest, shortcut, occupied)
            } else {
                MsgBox ,, % "ZipChord", % Format("The {1} '{2}' is already in use for '{3}'.`nPlease use a different {1} for '{4}'.", dest, shortcut, occupied, expansion)
            }
            Return false
        }
        if (StrLen(shortcut)<2) {
            if (expansion == "") {
                MsgBox ,, % "ZipChord", % "The shortcut must be at least two characters."
            } else {
                MsgBox ,, % "ZipChord", % Format("The {1} for '{2}' needs to be at least two characters.", dest, expansion)
            }
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

    dictionary := dictionary_type == "chord" ? chords : shorthands
    if (! FileExist(dictionary_file) ) {
        ; On the first run only (if we cannot find the dictionary file), offer to download and store dictionaries under My Documents
        if (settings.preferences & PREF_FIRST_RUN) {
            dictionary_dir := A_MyDocuments . "\ZipChord"
            if (InStr(FileExist(dictionary_dir), "D")) {
                _UpdateWorkingDir(dictionary_dir)
            } else {
                MsgBox, 4, % "ZipChord", % Format("Would you like to download starting dictionary files and save them in the '{}' folder?", dictionary_dir)
                IfMsgBox Yes
                {
                    FileCreateDir,  % dictionary_dir
                    _UpdateWorkingDir(dictionary_dir)
                    UrlDownloadToFile, https://raw.githubusercontent.com/psoukie/zipchord/main/dictionaries/en-qwerty.chords.txt, % dictionary_dir . "\en-qwerty.chords.txt"
                    UrlDownloadToFile, https://raw.githubusercontent.com/psoukie/zipchord/main/dictionaries/english.shorthands.txt, % dictionary_dir . "\english.shorthands.txt"
                }
            }
            if (FileExist(dictionary_file)) {
                return dictionary.GetFullFileName(dictionary_file)
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
        Return dictionary.GetFullFileName(new_file)
    }
    Return dictionary.GetFullFileName(dictionary_file)
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
*  Assigning Shortcuts
*/
Class clsAssignShortcuts {
    UI := {}
    saved_shortcuts := { chord: ""
                       , shorthand: ""}
    short_exp := ""
    SHORTCUT_UNDEFINED := "No {1} is assigned to '{2}' in the dictionary. You can add one."
    SHORTCUT_CURRENT := "The current {1} assigned to '{2}' is '{3}'. You can change or remove it."
    SHORTCUT_ADDED := "This {1} for '{2}' was added to the dictionary."
    SHORTCUT_CHANGED := "The {1} assigned to '{2}' was changed in the dictionary."
    SHORTCUT_DELETED := "The {1} assigned to '{2}' was removed from the dictionary."
    BTN_ADD := {chord: "&Add", shorthand: "A&dd"}
    BTN_CHANGE := {chord: "&Change", shorthand: "Ch&ange"}

    controls := { expansion:       { type: "Edit"
                                   , function: ObjBindMethod(this, "_ExpansionChange")}
                , chord:           { type: "Edit"
                                   , function: ObjBindMethod(this, "ShortcutChange", "chord")}
                , shorthand:       { type: "Edit"
                                   , function: ObjBindMethod(this, "ShortcutChange", "shorthand")}
                , note_chord:      { type: "Text"
                                   , text: ""}
                , note_shorthand:  { type: "Text"
                                   , text: ""}
                , save_chord:      { type: "Button"
                                   , text: this.BTN_ADD.chord
                                   , function: ObjBindMethod(this, "_SaveShortcut", "chord")}
                , save_shorthand:  { type: "Button"
                                   , text: this.BTN_ADD.shorthand
                                   , function: ObjBindMethod(this, "_SaveShortcut", "shorthand")}
                , delete_chord:      { type: "Button"
                                   , text: "&Remove"
                                   , function: ObjBindMethod(this, "_DeleteShortcut", "chord")}
                , delete_shorthand:  { type: "Button"
                                   , text: "Re&move"
                                   , function: ObjBindMethod(this, "_DeleteShortcut", "shorthand")}
                , close_button:     { type: "Button"
                                    , text: "Close"
                                    , function: ObjBindMethod(this, "Close")}}

    _backspace_fn := ObjBindMethod(this, "_Backspace")
    _ui_title := "Assign Shortcuts"

    Show(exp := "") {
        kb.SetZipChordToCurrentHkl()
        call := Func("OpenHelp").Bind("AssignShortcuts")
        Hotkey, F1, % call, On
        WireHotkeys("Off")  ; so the user can edit values without interference
        backspace_fn := this._backspace_fn
        Hotkey, $^Backspace, %backspace_fn%, On
        this._Build()
        this.UI.Show()
        this.controls.expansion.value := exp
    }
    Reshow() {
        this.UI.Show()
    }

    _Build() {
        this.UI := new clsUI(this._ui_title)
        this.UI.on_close := ObjBindMethod(this, "Close")
        this.UI.Add("Text", "Section x+20 y+15", "&Output text")
        this.UI.Add(this.controls.expansion, "y+10 w320")
        this._BuildHelper("&Chord", "chord", "xs-20 h120 w360")
        this._BuildHelper("S&horthand", "shorthand")
        this.UI.Add(this.controls.close_button, "Default x265 yp+70 w100")
        DllCall("User32.dll\SendMessageW"
                , "Ptr", this.controls.expansion._handle
                , "UInt", 0x1500+1, "UPtr", true
                , "WStr", "Type text to add, show, or change its shortcuts", "Ptr")
    }
    _BuildHelper(heading, ctrl, opt:="xs-20 yp+70 h120 w360") {
        this.UI.Add("GroupBox", opt, heading)
        this.UI.Font("s10", "Consolas")
        this.UI.Add(this.controls[ctrl], "xp+20 yp+30 Section w125")
        this.UI.Font("s10", "Segoe UI")
        this.UI.Add(this.controls["save_" . ctrl], "x+20 yp w80")
        this.UI.Add(this.controls["delete_" . ctrl], "x+15 yp w80")
        this.UI.Add(this.controls["note_" . ctrl], "xs y+10 +Wrap w320 h50")
    }
    Close() {
        Hotkey, F1, Off
        Hotkey, $^Backspace, Off
        this.UI.Destroy()
        if (settings.mode > MODE_ZIPCHORD_ENABLED)
            WireHotkeys("On")  ; resume normal mode
    }

    _ExpansionChange() {
        expansion := this.controls.expansion.value
        this.short_exp := str.Ellipsisize(expansion, 100, true)
        for _, dict in ["chord", "shorthand"] {
            current_shortcut := ""
            if (expansion != "") {
                dict_obj := dict . "s"
                this.controls[dict].Enable()
                if (shortcut := %dict_obj%.ReverseLookUp(expansion)) {
                    current_shortcut := shortcut
                }
            }
            this.saved_shortcuts[dict] := current_shortcut
            this.controls[dict].value := current_shortcut
            if (expansion == "") {
                this._ShortcutDisable(dict)
            }
        }
        if (expansion == "") {
            this.controls.expansion.Focus()
        }
    }

    _ShortcutDisable(dict) {
        this.controls[dict].Disable()
        this.controls["save_" . dict].Disable()
        this.controls["delete_" . dict].Disable()
        this.controls["note_" . dict].value := ""
    }

    ShortcutChange(dict) {
        save_button := this.controls["save_" . dict]
        delete_button := this.controls["delete_" . dict]
        raw_shortcut := this.controls[dict].value
        saved_value := this.saved_shortcuts[dict]
        note := this.controls["note_" . dict]

        if (saved_value != "") {
            ; shortcut exists
            note.value := Format(this.SHORTCUT_CURRENT, dict, this.short_exp, saved_value)
            delete_button.Enable()
            save_button.value := this.BTN_CHANGE[dict]
        } else {
            note.value := Format(this.SHORTCUT_UNDEFINED, dict, this.short_exp)
            delete_button.Disable()
            save_button.value := this.BTN_ADD[dict]
        }

        save_button.Disable()
        if (raw_shortcut == saved_value || raw_shortcut == "") {
            return
        }

        chorded := dict == "chord" ? true : false
        obj_name := dict . "s"
        ; Live validation is DLL-only.
        err := dll.available ? dll.ValidateShortcut(raw_shortcut, chorded) : DllError.NONE
        Switch err {
            Case DllError.NONE:
                save_button.Enable()
                save_button.MakeDefault()
            Case DllError.REPEATED_KEY:
                note.value := "Each key can be entered only once in the same chord."
            Case DllError.SHORTCUT_EXISTS:
                shortcut := chorded ? dll.NormalizeChord(raw_shortcut) : raw_shortcut
                occupied := %obj_name%.LookUp(shortcut)
                note.value := Format("The {1} '{2}' is already in use for '{3}'.`nUse a different {1} for {4}.", dict, raw_shortcut, occupied, this.short_exp)
            Case DllError.FEWER_THAN_TWO:
                note.value := "The shortcut must be at least two keys."
            Case DllError.EMPTY_CHORD:
                note.value := "A chained chord cannot contain an empty chord."
            Default:
                err_details := dll.GetErrorDetails(err)
                note.value := Format("Encountered {} error while checking the shortcut.", err_details)
        }
    }

    _SaveShortcut(dict) {
        obj_name := dict . "s"
        new_shortcut := this.controls[dict].value
        message_template := ""

        ; asserts this.saved_shortcuts[dict] != this.controls[dict]
        if (this.saved_shortcuts[dict] != "") {
            message_template := this.SHORTCUT_CHANGED
            result := %obj_name%.ChangeShortcut(this.saved_shortcuts[dict], new_shortcut)
            if (! result) {
                return
            }

        } else {
            ; otherwise, we're adding a new shortcut
            message_template := this.SHORTCUT_ADDED
            expansion := this.controls.expansion.value
            if (! %obj_name%.AddShortcut(new_shortcut, expansion)) {
                return
            }
        }

        this.CleanUpAfterModification(dict, new_shortcut, message_template)
    }

    _DeleteShortcut(dict) {
        obj_name := dict . "s"
        ; TK - call a function to delete `this.saved_shortcuts[dict]` from the dictionary
        result := %obj_name%.DeleteShortcut(this.saved_shortcuts[dict])
        if (result) {
            this.CleanUpAfterModification(dict, "", this.SHORTCUT_DELETED)
        }
    }

    CleanUpAfterModification(dict, new_shortcut, message_template) {
        this.saved_shortcuts[dict] := new_shortcut
        this.controls[dict].value := new_shortcut
        this.ShortcutChange(dict)
        message := Format(message_template, dict, this.short_exp)
        Sleep -1
        this.controls["note_" . dict].value := message
        this.controls.close_button.MakeDefault()
    }

    _Backspace() {
        if WinActive(this._ui_title)
            SendInput ^+{Left}{Del}
        else
            SendInput ^{Backspace}
    }
}
