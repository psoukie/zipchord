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
        return true
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
        if (new_settings.dictionary_dir != settings.dictionary_dir
                || new_settings.chord_file != settings.chord_file
                || new_settings.shorthand_file != settings.shorthand_file) {
            ini.LoadProperties(settings, "Application", filename)
            chords.Load(settings.chord_file)
            shorthands.Load(settings.shorthand_file)
        } else {
            ini.LoadProperties(settings, "Application", filename)
        }
        if (should_rewire) {
            WireHotkeys("On")
        }
        return true
    }
}