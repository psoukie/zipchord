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

    Save(config_file) {
        global app_settings

        if !(config_file) {
            MsgBox, , % "ZipChord", % "You need to specify the setting file."
            return
        }
        was_open := CloseAllWindows()
        runtime_status.config_file := config_file
        app_settings.Save()
        keys.Save(false)
        hint_UI.ShowOnOSD("Configuration saved to", str.BareFilename(config_file))
        if (was_open) {
            main_UI.Show()
        }
    }

    SwitchDuringRuntime(config_file := false) {
        if (config_file && ! FileExist(config_file)) {
            MsgBox, , % "ZipChord", % "The specified settings file could not be found."
            return false
        }
        was_open := CloseAllWindows()
        this.Load(config_file)
        if (config_file) {
            hint_UI.ShowOnOSD("Loaded configuration from", str.BareFilename(config_file))
        }
        if (was_open) {
            main_UI.Show()
        }
        return true
    }

    Load(config_file) {
        global app_settings

        runtime_status.config_file := config_file
        WireHotkeys("Off")
        new_settings := {}
        ini.LoadProperties(new_settings, app_settings.GetSectionName(), app_settings.GetSettingsFile())
        keys.Load(new_settings.locale)
        force_update := new_settings.dictionary_dir != settings.dictionary_dir
        if (force_update || new_settings.chord_file != settings.chord_file) {
            chords.Load(new_settings.chord_file)
        }
        if (force_update || new_settings.shorthand_file != settings.shorthand_file) {
            shorthands.Load(new_settings.shorthand_file)
        }
        app_settings.Load()
        WireHotkeys("On")
    }

    LoadMappingFile(filename) {
        if ! (FileExist(filename)) {
            MsgBox, , % "ZipChord", % "The specified mapping file could not be found."
            return false
        }
        Loop, Read, %filename%
        {
            columns := StrSplit(A_LoopReadLine, A_Tab, , 2)
            if ! (columns[1] && columns[2]) {
                continue
            }
            new_entry := new this.MappingEntry(columns[1], columns[2])
            this.mapping.Push(new_entry)
        }
        this.use_mapping := true
        hint_UI.ShowOnOSD("Activated automatic", "configuration switching")
        this.DetectAppSwitchLoop()
    }

    DetectAppSwitchLoop() {
        this.app_id := WinExist("A")
        WinWaitNotActive, % "ahk_id " . this.app_id
        if ! (this.use_mapping) {
            return
        }
        config_file := this.FindMatchingConfig()
        if (config_file && config_file != runtime_status.config_file) {
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
}