/*
This file is part of ZipChord.
Copyright (c) 2024 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

Class Configuration {
    Save() {
        ini.SaveProperties(settings, "Application", filename)
        ini.SaveProperty("_from_config", "locale", "Application", filename)
        ini.SaveProperties(keys, "Locale", filename)
        return true
    }

    Load() {
        WireHotkeys("Off")
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
        WireHotkeys("On")
        return true
    }
}