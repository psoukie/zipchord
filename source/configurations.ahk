/*
This file is part of ZipChord.
Copyright (c) 2024 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

Class Configuration {
    Save(filename) {
        ini.SaveProperties(settings, "Application", filename)
        ini.SaveProperty(FROM_CONFIG, "locale", "Application", filename)
        ini.SaveProperties(keys, "Locale", filename)
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
}