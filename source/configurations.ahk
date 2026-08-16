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
        global runtime_config_file

        if !(config_file) {
            MsgBox, , % "ZipChord", % "You need to specify the setting file."
            return
        }
        save_locale_override := app_settings.IsStaticMode()
        was_open := CloseAllWindows()
        runtime_config_file := config_file
        app_settings.Save()
        ; Upgrade functionality: A configuration saved by 2.9 no longer needs legacy dictionary ownership.
        IniDelete, %config_file%, Application, chord_file
        IniDelete, %config_file%, Application, shorthand_file
        if (save_locale_override) {
            locale.Save(settings.locale)
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
            MsgBox, , % "ZipChord", % Format("The specified settings file '{}' could not be found.", config_file)
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
        global runtime_config_file

        runtime_config_file := config_file
        WireHotkeys("Off")
        app_settings.Load()
        SetWorkingDir, % settings.dictionary_dir
        this._UpgradeLegacyLocaleSetting()
        if (app_settings.IsStaticMode()) {
            EnsureLocaleExists(settings.locale)
            ApplyLocaleToRuntime()
        } else {
            layout_name := kb.GetActiveLayoutName()
            LocaleSwitchToLayout(layout_name)
        }
        WireHotkeys("On")
    }

    _UpgradeLegacyLocaleSetting() {
        global app_settings

        if (settings.locale = "0") {
            settings.locale := STATIC_LOCALE_NAME
            app_settings.Save()
        }
    }

    LoadMappingFile(filename) {
        if ! (FileExist(filename)) {
            MsgBox, , % "ZipChord", % "The specified mapping file could not be found."
            return false
        }
        filename := this._GetFullPathName(filename)
        SplitPath, filename, , mapping_dir
        Loop, Read, %filename%
        {
            columns := StrSplit(A_LoopReadLine, A_Tab, , 4)
            if ! (columns[1] && columns[2] && columns[3]) {
                continue
            }
            config_file := columns[3]
            if (DllCall("shlwapi.dll\PathIsRelativeW", "WStr", config_file)) {
                config_file := mapping_dir . "\" . config_file
            }
            new_entry := new this.MappingEntry(columns[1], columns[2], config_file)
            this.mapping.Push(new_entry)
        }
        this.use_mapping := true
        hint_UI.ShowOnOSD("Activated automatic", "configuration switching")
    }

    _GetFullPathName(filename) {
        buffer_size := 32768
        VarSetCapacity(full_path, buffer_size * 2, 0)
        length := DllCall("kernel32.dll\GetFullPathNameW"
                , "WStr", filename, "UInt", buffer_size, "Ptr", &full_path, "Ptr", 0, "UInt")
        if (!length || length >= buffer_size) {
            return filename
        }
        return StrGet(&full_path, length, "UTF-16")
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
        global runtime_config_file

        config_file := this.FindMatchingConfig(layout_name)

        if (config_file && str.FilenameWithExtension(config_file) != runtime_config_file) {
            return this.SwitchDuringRuntime(str.FilenameWithExtension(config_file))
        }
        return false
    }
 
    FindMatchingConfig(layout_name) {
        window_names := ["locale_UI", "assign_shortcut", "main_UI"]
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
