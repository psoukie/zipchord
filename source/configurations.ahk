/*
This file is part of ZipChord.
Copyright (c) 2024-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

global config := new Configuration

Class Configuration {
    mapping := []
    app_id := 0
    use_mapping := false

    Class MappingEntry {
        layout_mask := ""
        window_mask := ""
        config_file := ""

        __New(layout_mask, window_mask, config_file) {
            this.layout_mask := layout_mask
            this.window_mask := window_mask
            this.config_file := config_file
        }
    }

    Save(config_file) {
        global app_settings
        global locale

        if !(config_file) {
            MsgBox, , % "ZipChord", % "You need to specify the setting file."
            return
        }
        save_locale_override := locale.IsStaticMode()
        was_open := CloseAllWindows()
        runtime_status.config_file := config_file
        app_settings.Save()
        if (save_locale_override) {
            keys.Save(settings.locale)
        } else {
            ini.DeleteSection("Locale", config_file)
        }
        hint_UI.ShowOnOSD("Configuration saved to", str.BareFilename(config_file))
        if (was_open) {
            main_UI.Show()
        }
    }

    SwitchDuringRuntime(config_file := false) {
        if (config_file && ! FileExist(config_file)) {
            MsgBox, , % "ZipChord", % Format("The specified settings file '{}' could not be found.", str.BareFilename(config_file))
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
        global locale

        runtime_status.config_file := config_file
        WireHotkeys("Off")
        new_settings := app_settings.settings.Clone()
        ini.LoadProperties(new_settings, app_settings.GetSectionName(), app_settings.GetSettingsFile())
        force_update := new_settings.dictionary_dir != settings.dictionary_dir
        if (force_update || new_settings.chord_file != settings.chord_file) {
            chords.Load(new_settings.chord_file)
        }
        if (force_update || new_settings.shorthand_file != settings.shorthand_file) {
            shorthands.Load(new_settings.shorthand_file)
        }
        app_settings.Load()
        this._UpgradeLegacyLocaleSetting()
        if (locale.IsStaticMode()) {
            keys.Load(settings.locale)
        } else {
            layout_name := kb.GetActiveLayoutName()
            locale.SwitchToLayout(layout_name)
        }
        WireHotkeys("On")
    }

    _UpgradeLegacyLocaleSetting() {
        global app_settings
        global locale

        if (settings.locale = "0") {
            settings.locale := locale.STATIC_LOCALE_NAME
            app_settings.Save()
        }
    }

    LoadMappingFile(filename) {
        if ! (FileExist(filename)) {
            MsgBox, , % "ZipChord", % "The specified mapping file could not be found."
            return false
        }
        Loop, Read, %filename%
        {
            columns := StrSplit(A_LoopReadLine, A_Tab, , 3)
            if ! (columns[1] && columns[2] && columns[3]) {
                continue
            }
            new_entry := new this.MappingEntry(columns[1], columns[2], columns[3])
            this.mapping.Push(new_entry)
        }
        this.use_mapping := true
        hint_UI.ShowOnOSD("Activated automatic", "configuration switching")
    }

    DetectAppSwitch() {
        hwnd := DllCall("user32.dll\GetForegroundWindow", "Ptr")
        if (!hwnd || hwnd == this.app_id) {
            return false
        }

        this.app_id := hwnd
        return true
    }

    ProcessConfigChange(layout_name) {
        config_file := this.FindMatchingConfig(layout_name)

        if (config_file && str.FilenameWithExtension(config_file) != runtime_status.config_file) {
            this.SwitchDuringRuntime(str.FilenameWithExtension(config_file))
        }
    }
 
    FindMatchingConfig(layout_name) {
        window_names := ["locale", "add_shortcut", "main_UI"]
        WinGetActiveTitle, window_title
        if (window_title == "Task Switching") {
            return false
        }
        For _, window in window_names {
            ahk_id_string := "ahk_id " . %window%.UI._handle
            WinGetTitle, zc_window_title, %ahk_id_string%
            if (zc_window_title == window_title) {
                return false
            }
        }
        for _, entry in this.mapping {
            ; Convert wildcard-style pattern to regex
            window_regex_pattern := "^" . RegExReplace(entry.window_mask, "\*", ".*") . "$"
            if (RegExMatch(window_title, window_regex_pattern)) {
                if (entry.layout_mask == "*" || entry.layout_mask == layout_name) {
                    return entry.config_file
                }
            }
        }
        return false
    }
}
