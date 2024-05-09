/*
This file is part of ZipChord.
Copyright (c) 2024 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

Class Configuration {
    static Save() {
        ini.SaveProperties(settings, "Application", filename)
        ini.SaveProperty("_from_config", "locale", "Application", filename)
        ini.SaveProperties(keys, "Locale", filename)
    }

    static Load() {
        global is_keyboard_wired
        should_rewire := false

        if (is_keyboard_wired) {
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
        if (should_rewire) {
            WireHotkeys("On")
        }
    }
}