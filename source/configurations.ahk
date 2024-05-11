/*
This file is part of ZipChord.
Copyright (c) 2024 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

global config := new Configuration

Class Configuration {
    mapping := []
    app_id := 0
    use_mapping := false

    Class MappingEntry {
        window_mask := ""
        config_file := ""

        __New(window_mask, config_file) {
            this.window_mask := window_mask
            this.config_file := config_file
        }
    }

    Save(filename) {
        ini.SaveProperties(settings, "Application", filename)
        ini.SaveProperty(FROM_CONFIG, "locale", "Application", filename)
        ini.SaveProperties(keys, "Locale", filename)
    }

    SwitchDuringRuntime(config_file) {
        if (! FileExist(config_file)) {
            MsgBox, , % "ZipChord", % "The specified settings file could not be found."
            return false
        }
        CloseAllWindows()
        this.Load(config_file)
        hint_UI.ShowOnOSD("Loaded configuration from", str.BareFilename(config_file))
        return true
    }

    Load(filename) {
        should_rewire := false

        if (runtime_status.is_keyboard_wired) {
            WireHotkeys("Off")
            should_rewire := true
        }
        new_settings := {}
        ini.LoadProperties(keys, "Locale", filename)
        ini.LoadProperties(new_settings, "Application", filename)
        force_update := new_settings.dictionary_dir != settings.dictionary_dir
        if (force_update || new_settings.chord_file != settings.chord_file) {
            chords.Load(new_settings.chord_file)
        }
        if (force_update || new_settings.shorthand_file != settings.shorthand_file) {
            shorthands.Load(new_settings.shorthand_file)
        }
        ini.LoadProperties(settings, "Application", filename)
        runtime_status.config_file := filename
        if (should_rewire) {
            WireHotkeys("On")
        }
    }

    LoadMappingFile() {
        if ! (FileExist("mapping.txt")) {
            return
        }
        Loop, Read, % "mapping.txt"
        {
            columns := StrSplit(A_LoopReadLine, A_Tab, , 2)
            if ! (columns[1] && columns[2]) {
                continue
            }
            new_entry := new this.MappingEntry(columns[1], columns[2])
            this.mapping.Push(new_entry)
        }
        this.use_mapping := true
        this.DetectAppSwitchLoop()
    }

    DetectAppSwitchLoop() {
        this.app_id := WinExist("A")
        WinWaitNotActive, % "ahk_id " . this.app_id
        if ! (this.use_mapping) {
            return
        }
        config_file := this.FindMatchingConfig()
        if (config_file) {
            this.SwitchDuringRuntime(config_file)
        }
        func := ObjBindMethod(this, "DetectAppSwitchLoop")
        SetTimer, %func%, -10
    }

    FindMatchingConfig() {
        WinGetActiveTitle, window_title
        for _, entry in this.mapping {
            regex_pattern := "^" . RegExReplace(entry.window_mask, "\*", ".*") . "$"
            if RegExMatch(window_title, regex_pattern) {
                return entry.config_file
            }
        }
        return false
    }

    MatchWindowTitle(windowTitle, patternsArray) {
        for index, pattern in patternsArray {
            ; Convert wildcard-style pattern to regex
            pattern := "^" . RegExReplace(pattern, "\*", ".*") . "$"
            if RegExMatch(windowTitle, pattern) {
                return index
            }
        }
        return false
    }
}