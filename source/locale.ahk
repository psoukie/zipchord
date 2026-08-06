/*
This file is part of ZipChord.
Copyright (c) 2021-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license.
*/

; Locale settings (keyboard and language settings)

Class clsKeySemantics {
    char := ""
    is_punctuation := false
    is_numeral := false
    removes_space := false
    adds_space := false
    capitalizes := false
}

Class clsKeyProperties {
    SC := 0
    NAME := ""
    symbol := ""
    plain := new clsKeySemantics
    with_shift := new clsKeySemantics
}

Class clsKeyMap {
    keys_by_SC := {}

    ; Ordered list of physical keys
    KEY_NAMES := ["``", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="
            , "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\"
            , "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'"
            , "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"]

    KEY_SCAN_CODES := [0x29, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D
            , 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x2B
            , 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28
            , 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35]

    NUMPAD_MAPPING := { 0x52: {symbol: "⓪", ahk: "Numpad0", output: "0"}
            , 0x4F: {symbol: "①", ahk: "Numpad1", output: "1"}
            , 0x50: {symbol: "②", ahk: "Numpad2", output: "2"}
            , 0x51: {symbol: "③", ahk: "Numpad3", output: "3"}
            , 0x4B: {symbol: "④", ahk: "Numpad4", output: "4"}
            , 0x4C: {symbol: "⑤", ahk: "Numpad5", output: "5"}
            , 0x4D: {symbol: "⑥", ahk: "Numpad6", output: "6"}
            , 0x47: {symbol: "⑦", ahk: "Numpad7", output: "7"}
            , 0x48: {symbol: "⑧", ahk: "Numpad8", output: "8"}
            , 0x49: {symbol: "⑨", ahk: "Numpad9", output: "9"}
            , 0x4E: {symbol: "⊕", ahk: "NumpadAdd", output: "+"}
            , 0x4A: {symbol: "⊖", ahk: "NumpadSub", output: "-"}
            , 0x37: {symbol: "⊗", ahk: "NumpadMult", output: "*"}
            , 0x135: {symbol: "⊘", ahk: "NumpadDiv", output: "/"}
            , 0x053:  {symbol: "⊙", ahk: "NumpadDot", output: "."} }

    __New() {
        ; populate keys_by_SC with static properties
        for i, SC in this.KEY_SCAN_CODES {
            key_prop := new clsKeyProperties
            key_prop.SC := SC
            key_prop.NAME := this.KEY_NAMES[i]
            this.keys_by_SC[SC] := key_prop
        }
    }

    ; Save only symbols to INI (km_<name>)
    Save(section, ini_filename) {
        for _, key_prop in this.keys_by_SC {
            save_as := (key_prop.NAME == "=") ? "eq" : key_prop.NAME
            ini.SaveProperty(key_prop.symbol, "_km_" . save_as, section, ini_filename)
        }
    }

    ; Load symbols from INI and override defaults
    Load(section, ini_filename) {
        for _, key_prop in this.keys_by_SC {
            load_as := (key_prop.NAME == "=") ? "eq" : key_prop.NAME
            symbol := ini.LoadProperty("_km_" . load_as, section, ini_filename)
            key_prop.symbol := symbol
        }
    }
}

Class clsLocale {
    chord_file := "en-qwerty.chords.txt"
    shorthand_file := "english.shorthands.txt"
    use_chords := true
    use_shorthands := true

    semantic_remove_space := ".,;:!?'""])}>@#%^*+-=_/|\"
    semantic_space_after := ".,;:!?"
    semantic_capitalizing := ".!?"
    semantic_other := "[({<"
    semantic_numerals := "0123456789"

    key_map := new clsKeyMap() ; instantiate key_map object (see above)

    __New() {
        this.RefreshLayoutChars()
        this.AssignDefaultSymbols()
    }

    UpgradeToSemanticPunctuation() {
        this.semantic_remove_space := this._DeriveSemPunct(this.remove_space_plain)
                . this._DeriveSemPunct(this.remove_space_shift, true)
        this.semantic_space_after := this._DeriveSemPunct(this.space_after_plain)
                . this._DeriveSemPunct(this.space_after_shift, true)
        this.semantic_capitalizing := this._DeriveSemPunct(this.capitalizing_plain)
                . this._DeriveSemPunct(this.capitalizing_shift, true)
        this.semantic_other := this._DeriveSemPunct(this.other_plain)
                . this._DeriveSemPunct(this.other_shift, true)
    }

    ; As part of an upgrade, remove the legacy key-based punctuation
    _RemoveLegacyPunctuationProps(section, filename) {
        legacy_props := ["remove_space_plain", "remove_space_shift"
                , "space_after_plain", "space_after_shift"
                , "capitalizing_plain", "capitalizing_shift"
                , "other_plain", "other_shift"
                , "numerals_plain", "numerals_shift"]
        for _, legacy_prop in legacy_props {
            IniDelete, %filename%, %section%, %legacy_prop%
        }
    }

    _DeriveSemPunct(keys, with_shift := false) {  ; -> semantic string
        semantic := ""
        Loop, Parse, keys
        {
            for _, key_prop in this.key_map.keys_by_SC {
                if (key_prop.symbol == A_LoopField) {
                    semantic .= with_shift ? key_prop.with_shift.char : key_prop.plain.char
                    break
                }
            }
        }
        return semantic
    }

    Save(locale_name) {
        if (!locale_name) {
            locale_name := STATIC_LOCALE_NAME
        }
        GetLocaleStorage(locale_name, section, filename)
        ini.SaveProperties(this, section, filename)
        this._RemoveLegacyPunctuationProps(section, filename)
    }

    Load(locale_name) {  ; -> bool needs_upgrade
        if (!locale_name) {
            locale_name := STATIC_LOCALE_NAME
        }
        GetLocaleStorage(locale_name, section, filename)
        ini.LoadProperties(this, section, filename)

        ; Logic used for upgrade path
        if (ini.HasProperty("semantic_remove_space", section, filename)) {
            return false
        }
        ; and we guard against empty locales
        return ini.HasProperty("remove_space_plain", section, filename)
    }

    LoadForCurrentLayout(locale_name) {
        needs_upgrade := this.Load(locale_name)
        this.RefreshLayoutChars()

        if (needs_upgrade) {
            this.UpgradeToSemanticPunctuation()
        }

        this.CompileKeySemantics()
    }

    RefreshScanCodeMapping() {
        global SC_to_symbol_map
        global symbol_to_SC_map
        global ahk_numpad_to_symbol_map

        SC_to_symbol_map := {}
        symbol_to_SC_map := {}

        For SC, key_prop in this.key_map.keys_by_SC {
            if (key_prop.symbol == "") {
                continue
            }
            SC_to_symbol_map[SC] := key_prop.symbol
            symbol_to_SC_map[key_prop.symbol] := SC
        }

        For num_SC, num_reps in this.key_map.NUMPAD_MAPPING {
            SC_to_symbol_map[num_SC] := num_reps.symbol
            symbol_to_SC_map[num_reps.symbol] := num_SC
            ahk_numpad_to_symbol_map[num_reps.ahk] := num_reps.symbol
        }
    }

    RefreshLayoutChars() {
        ; Build or update scan-code to symbols mapping for the current keyboard layout
        symbols := kb.SuggestSymbolsFromActiveLayout(this.key_map.KEY_SCAN_CODES)

        for SC, key_prop  in this.key_map.keys_by_SC {
            key_prop.plain.char := symbols[SC].plain
            key_prop.with_shift.char := symbols[SC].with_shift
        }
    }

    AssignDefaultSymbols() {
        for _, key_prop  in this.key_map.keys_by_SC {
            key_prop.symbol := key_prop.plain.char
        }
    }

    CompileKeySemantics() {
        for _, key_prop  in this.key_map.keys_by_SC {
            this._CompileSemantics(key_prop.plain)
            this._CompileSemantics(key_prop.with_shift)
        }
    }

    _CompileSemantics(key_sem) {
        if (key_sem.char == "") {
            key_sem.is_numeral := false
            key_sem.removes_space := false
            key_sem.adds_space := false
            key_sem.capitalizes := false
            key_sem.is_punctuation := false
            return
        }

        char := key_sem.char
        key_sem.is_numeral := InStr(this.semantic_numerals, char) ? true : false
        key_sem.removes_space := InStr(this.semantic_remove_space, char) ? true : false
        key_sem.adds_space := InStr(this.semantic_space_after, char) ? true : false
        key_sem.capitalizes := InStr(this.semantic_capitalizing, char) ? true : false
        key_sem.is_punctuation := (key_sem.removes_space
                || key_sem.adds_space
                || key_sem.capitalizes
                || InStr(this.semantic_other, char)) ? true : false
    }

    ; Replace mapped scan code and named-key tokens inside a hotkey string
    SCHotkeyToSymbolHotkey(key) {
        global SC_to_symbol_map
        global ahk_numpad_to_symbol_map

        pos := 1
        if (pos := InStr(key, "SC", true)) {
            candidate := "0x" . SubStr(key, pos+2, 3)   ; "SC" + 3 chars
            SC := candidate + 0
            if (SC_to_symbol_map.HasKey(SC)) {
                repl := SC_to_symbol_map[SC]
                return SubStr(key, 1, pos-1) . repl . SubStr(key, pos+5)
            }
        }

        if (pos := InStr(key, "Numpad", true)) {
            if (up_pos := InStr(key, " ", true, pos)) {
                candidate := SubStr(key, pos, up_pos - pos)
                suffix := SubStr(key, up_pos)
            } else {
                candidate := SubStr(key, pos)
                suffix := ""
            }
            repl := ahk_numpad_to_symbol_map[candidate]
            return SubStr(key, 1, pos-1) . repl . suffix
        }
    
        return key
    }
}

Class clsLocaleInterface {
    working_locale := new clsLocale
    current_locale := ""
    UI := {}
    controls := { use_auto: { type: "Radio"
                            , text: "&Automatically switch with keyboard layout"
                            , function: ObjBindMethod(this, "_SwitchLocaleMode")}
                , use_static: { type: "Radio"
                              , text: "&Fixed across keyboard layout changes"
                              , function: ObjBindMethod(this, "_SwitchLocaleMode")}
                , kb_group: { type: "GroupBox"
                            , text: "Keyboard mapping"}
                , punctuation_group: { type: "GroupBox"
                                     , text: "Punctuation settings"}
                , btn_apply: { type: "Button"
                             , text: "&Apply"
                             , function: ObjBindMethod(this, "_Save")}
                , btn_ok: { type: "Button"
                          , text: "&OK"
                          , function: ObjBindMethod(this, "_OK")}
                , btn_detect: { type: "Button"
                             , text: "&Auto-detect mapping"
                             , function: ObjBindMethod(this, "_Detect")}}
    options := { semantic_remove_space: {type: "Edit"}
            , semantic_space_after:  {type: "Edit"}
            , semantic_capitalizing: {type: "Edit"}
            , semantic_other:        {type: "Edit"}}

    Build() {
        UI := new clsUI("Keyboard and language settings")
        handle := main_UI.UI._handle
        Gui, +Owner%handle%
        UI.on_close := ObjBindMethod(this, "Close")
        UI.Add(this.controls.use_auto, "x+10 y+15 w360")
        UI.Add(this.controls.use_static, "xp y+10 w360")
        UI.Add(this.controls.kb_group, "xp-10 y+20 h170 w490 Section")
        for i, key_name in this.working_locale.key_map.KEY_NAMES {
            Switch i {
                Case 1:
                    format := "xp+20 yp+30 w30 Section"
                Case 14:
                    format := "y+5 xs w30 Section"
                Case 27, 38:
                    format := "y+5 xs+15 w30 Section"
                Default:
                    format := "x+5 w30"
            }
            this.controls[key_name] := UI.Add("Button", format, "", ObjBindMethod(this, "_OnKeyClick", key_name))
        }

        UI.Font("s10", "Segoe UI")
        UI.Add(this.controls.btn_detect, "xs-35 y+30 w160")
        UI.Add(this.controls.punctuation_group, "xs-50 y+20 h180 w490 Section")
        UI.Add("Text", "xs+15 yp+30 Section", "Remove smart spaces before")
        UI.Add("Text", "y+20", "Add smart spaces after")
        UI.Add("Text", "y+20", "Capitalize after")
        UI.Add("Text", "y+20", "Other punctuation")
        UI.Font("s10", "Consolas")
        UI.Add(this.options.semantic_remove_space, "xs+190 ys Section w260 r1")
        UI.Add(this.options.semantic_space_after, "w260 r1")
        UI.Add(this.options.semantic_capitalizing, "w260 r1")
        UI.Add(this.options.semantic_other, "w260 r1")
        UI.Font("s10", "Segoe UI")
        UI.Add(this.controls.btn_apply, "xs+80 y+20 w80")
        UI.Add(this.controls.btn_ok, "x+20 w80 Default")
        this.UI := UI
    }

    Show() {
        global app_settings
        call := Func("OpenHelp").Bind("Locale")
        Hotkey, F1, % call, On
        WireHotkeys("Off")  ; so we're not processing key presses
        this.current_locale := settings.locale
        this.RefreshUI()
        this.UI.Show()
    }

    LocaleProcessLayoutChange(new_locale) {
        if (this.current_locale == STATIC_LOCALE_NAME) {
            return
        }
        this.current_locale := new_locale 
        this.RefreshUI()
    }

    _SwitchLocaleMode() {
        if (this.controls.use_static.value) {
            this.current_locale := STATIC_LOCALE_NAME
        } else {
            this.current_locale := kb.current_layout_name
        }
        this.RefreshUI()
    }

    RefreshUI() {
        is_locale_static := (this.current_locale == STATIC_LOCALE_NAME)
        EnsureLocaleExists(this.current_locale)
        this.working_locale.LoadForCurrentLayout(this.current_locale)
        ; populate options fields
        For key, option in this.options {
            option.value := this.working_locale[key]
        }
        this.controls.use_auto.value := is_locale_static ? 0 : 1
        this.controls.use_static.value := is_locale_static ? 1 : 0

        this.UpdateGroupTitles(this.current_locale)
        this.RenderKeyboard()
    }

    RenderKeyboard() {
        for _, key_prop in this.working_locale.key_map.keys_by_SC {
            this.controls[key_prop.NAME].value := key_prop.symbol
        }
    }

    UpdateGroupTitles(locale_title) {
        this.controls.kb_group.value := "Keyboard mapping for " . locale_title
        this.controls.punctuation_group.value := "Punctuation settings for " . locale_title
    }
    _OK() {
        this._Save()
        this.Close()
    }
    _OnKeyClick(def_name) {
        Prompt := "Type a character to represent the key " . def_name
        InputBox, mapped, % "Set mapping for " . def_name, %Prompt%, , 300, 120
        if (ErrorLevel) {
            return
        }
        mapped := Trim(mapped)

        ; Update key_map and remove duplicates
        for _, key_prop in this.working_locale.key_map.keys_by_SC {
            if (key_prop.NAME == def_name) {
                key_prop.symbol := mapped
            } else if (key_prop.symbol == mapped) {
                key_prop.symbol := ""
                this.controls[key_prop.NAME].value := ""  ; update UI button name
            }
        }
        ; Update UI button label
        this.controls[def_name].value := mapped
    }

    _Save() {
        global app_settings
        global runtime_config_file

        for key, option in this.options {
            this.working_locale[key] := option.value
        }

        if (runtime_config_file) {
            this.working_locale.Save(false)
            ApplyLocaleToRuntime()
            return
        }

        this.working_locale.Save(this.current_locale)
        settings.locale := this.current_locale
        app_settings.Save()
    }

    Close() {
        global app_settings

        this.UI.Hide()
        if (! app_settings.IsStaticMode()) {
            LocaleSwitchToLayout(kb.current_layout_name)
        } else {
            ApplyLocaleToRuntime()
        }
        WireHotkeys("On")  ; resume processing key presses
        main_UI.UpdateLocaleProfileInMainUI()
        main_UI.UI.Enable()
    }

    _Detect() {
        this.working_locale.RefreshLayoutChars()
        this.working_locale.AssignDefaultSymbols()
        this.RenderKeyboard()
    }
}

global locale := new clsLocale
locale_UI := new clsLocaleInterface

LocaleSwitchToLayout(layout_name) {
    global app_settings
    global locale_UI
    global runtime_config_file

    if (!layout_name) {
        return
    }
    EnsureLocaleExists(layout_name)
    settings.locale := layout_name
    if (!runtime_config_file) {
        app_settings.Save()
    }
    ApplyLocaleToRuntime()
    if (locale_UI.UI.IsShown()) {
        locale_UI.RefreshUI()
    }
}

GetLocaleStorage(locale_name, ByRef section, ByRef filename) {
    global runtime_config_file

    if (runtime_config_file && locale_name == STATIC_LOCALE_NAME) {
        section := "Locale"
        filename := runtime_config_file
    } else {
        section := locale_name
        filename := ini.default_ini
    }
}

LocaleHasDictionarySettings(locale_name) {
    if (!locale_name) {
        return false
    }
    GetLocaleStorage(locale_name, section, filename)
    return ini.HasProperty("chord_file", section, filename)
}

LocaleHasCompleteSettings(locale_name) {
    if (!LocaleHasDictionarySettings(locale_name)) {
        return false
    }
    GetLocaleStorage(locale_name, section, filename)
    return ini.HasProperty("key_map", section, filename)
            && ini.HasProperty("semantic_remove_space", section, filename)
}

CopyDictionarySettingsFromLocale(profile) {
    settings.chord_file := chords.GetFullFileName(profile.chord_file)
    settings.shorthand_file := shorthands.GetFullFileName(profile.shorthand_file)
    settings.mode := (settings.mode & MODE_ZIPCHORD_ENABLED)
        | (profile.use_chords ? MODE_CHORDS_ENABLED : 0)
        | (profile.use_shorthands ? MODE_SHORTHANDS_ENABLED : 0)
}

CopyDictionarySettingsToLocale(profile) {
    profile.chord_file := chords.GetFullFileName(settings.chord_file)
    profile.shorthand_file := shorthands.GetFullFileName(settings.shorthand_file)
    profile.use_chords := (settings.mode & MODE_CHORDS_ENABLED) ? 1 : 0
    profile.use_shorthands := (settings.mode & MODE_SHORTHANDS_ENABLED) ? 1 : 0
}

EnsureLocaleExists(locale_name) {
    if (!locale_name || LocaleHasCompleteSettings(locale_name)) {
        return
    }

    has_dictionary_settings := LocaleHasDictionarySettings(locale_name)
    target_locale := new clsLocale
    target_locale.LoadForCurrentLayout(locale_name)
    if (!has_dictionary_settings) {
        CopyDictionarySettingsToLocale(target_locale)
    }
    target_locale.Save(locale_name)
}

SaveRuntimeDictionarySettingsToLocale() {
    global locale

    CopyDictionarySettingsToLocale(locale)
    GetLocaleStorage(settings.locale, section, filename)
    For _, key in ["chord_file", "shorthand_file", "use_chords", "use_shorthands"] {
        ini.SaveProperty(locale[key], key, section, filename)
    }
}

ApplyLocaleToRuntime() {
    global io

    io.ClearTokens("*Interrupt*")
    locale.LoadForCurrentLayout(settings.locale)
    CopyDictionarySettingsFromLocale(locale)

    if (!settings.chord_file) {
        chords.Unload()
    } else if (chords._file != settings.chord_file) {
        chords.Load(settings.chord_file)
    }
    if (!settings.shorthand_file) {
        shorthands.Unload()
    } else if (shorthands._file != settings.shorthand_file) {
        shorthands.Load(settings.shorthand_file)
    }
    locale.RefreshScanCodeMapping()
    UI_SyncModeState()
}

ProcessLayoutChange(layout_name) {
    global app_settings
    global locale_UI

    if (locale_UI.UI.IsShown()) {
        locale_UI.LocaleProcessLayoutChange(layout_name)
        return
    }

    if (app_settings.IsStaticMode()) {
        locale.RefreshLayoutChars()
        locale.CompileKeySemantics()
        return
    }

    WireHotkeys("Off")
    LocaleSwitchToLayout(layout_name)
    WireHotkeys("On")

    if (main_UI.UI.IsShown()) {
        main_UI.UpdateLocaleProfileInMainUI()
    } else {
        chord_file := settings.chord_file
        shorthand_file := settings.shorthand_file
        SplitPath, chord_file, , , , chord_name
        SplitPath, shorthand_file, , , , shorthand_name
        chord_name := SubStr(chord_name, 1, -7)
        shorthand_name := SubStr(shorthand_name, 1, -11)
        chord_status := settings.mode & MODE_CHORDS_ENABLED ? chord_name : "chords off"
        shorthand_status := settings.mode & MODE_SHORTHANDS_ENABLED ? shorthand_name : "shorthands off"
        hint_UI.ShowOnOSD(layout_name, chord_status, shorthand_status)
    }
}
