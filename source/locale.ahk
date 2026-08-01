/*
This file is part of ZipChord.
Copyright (c) 2021-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license.
*/

; Locale settings (keyboard and language settings)

; Key map container class: acts like an associative object but also provides methods.
Class clsKeyMap {
    ; inner per-key class
    Class clsKeyMapping {
        label := ""
        SC := 0
        symbol := ""

        __New(label := "", SC := "", symbol := "") {
            this.label := label
            this.SC := SC
            this.symbol := symbol
        }
    }

    ; Ordered list of physical keys
    KEY_LIST := ["``", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="
        , "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\"
        , "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'"
        , "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"]

    SCAN_CODES := [0x29, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D
          , 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x2B
          , 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28
          , 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35]

    NUMPAD_MAPPING := { 0x52: {symbol: "⓪", ahk: "Numpad0"}
            , 0x4F: {symbol: "①", ahk: "Numpad1"}
            , 0x50: {symbol: "②", ahk: "Numpad2"}
            , 0x51: {symbol: "③", ahk: "Numpad3"}
            , 0x4B: {symbol: "④", ahk: "Numpad4"}
            , 0x4C: {symbol: "⑤", ahk: "Numpad5"}
            , 0x4D: {symbol: "⑥", ahk: "Numpad6"}
            , 0x47: {symbol: "⑦", ahk: "Numpad7"}
            , 0x48: {symbol: "⑧", ahk: "Numpad8"}
            , 0x49: {symbol: "⑨", ahk: "Numpad9"}
            , 0x4E: {symbol: "⊕", ahk: "NumpadAdd"}
            , 0x4A: {symbol: "⊖", ahk: "NumpadSub"}
            , 0x37: {symbol: "⊗", ahk: "NumpadMult"}
            , 0x135: {symbol: "⊘", ahk: "NumpadDiv"}
            , 0x053:  {symbol: "⊙", ahk: "NumpadDot"} }


    __New() {
        ; Build default scan-code to symbols mapping
        symbols := this._SuggestSymbolsFromActiveLayout()

        ; populate entries keyed by name (this["Q"] := km)
        loop % this.KEY_LIST.Length() {
            i := A_Index
            name := this.KEY_LIST[i]
            km := new this.clsKeyMapping(name, this.SCAN_CODES[i], symbols[i])
            this[name] := km
        }
    }

    Keys() {
       return this.KEY_LIST
    }

    ; Save only symbols to INI (km_<name>)
    Save(section, ini_filename) {
        loop % this.KEY_LIST.Length() {
            i := A_Index
            name := this.KEY_LIST[i]
            save_as := (name == "=") ? "eq" : name
            ini.SaveProperty(this[name].symbol, "_km_" . save_as, section, ini_filename)
        }
    }

    ; Load symbols from INI and override defaults
    Load(section, ini_filename) {
        loop % this.KEY_LIST.Length() {
            i := A_Index
            name := this.KEY_LIST[i]
            load_as := (name == "=") ? "eq" : name
            sym := ini.LoadProperty("_km_" . load_as, section, ini_filename)
            if (IsObject(this[name]))
                this[name].symbol := sym
        }
    }

    ; Suggest symbols based on the currently active Windows keyboard layout.
    _SuggestSymbolsFromActiveLayout() {
        static MAPVK_VSC_TO_VK_EX := 3
        symbols_out := []
        ; Reusable buffers
        VarSetCapacity(keyState, 256, 0)      ; BYTE[256]
        VarSetCapacity(outBuf,   32*2,  0)    ; WCHAR[32] (64 bytes on Unicode)

        hkl := kb.GetForegroundHkl()
        if (!hkl) {
            hkl := DllCall("user32.dll\GetKeyboardLayout", "UInt", 0, "Ptr")
        }

        for i, name in this.KEY_LIST
        {
            sc := this.SCAN_CODES[i]
            if (!sc)
                sc := GetKeySC(name)
            if (!sc) {
                symbols_out.Push("")
                continue
            }

            ; Map SC->VK once
            vk := DllCall("user32\MapVirtualKeyEx", "UInt", sc, "UInt", MAPVK_VSC_TO_VK_EX, "Ptr", hkl, "UInt")

            ; Reset keyboard state (no modifiers) for this key
            DllCall("RtlZeroMemory", "Ptr", &keyState, "Ptr", 256)

            ; First translation
            ret := DllCall("user32\ToUnicodeEx"
                , "UInt", vk, "UInt", sc, "Ptr", &keyState
                , "Str", outBuf, "Int", 32  ; cch (WCHAR)
                , "UInt", 0, "Ptr", hkl, "Int")

            if (ret == -1) {
                ; Dead key: clear dead state and treat as no character
                DllCall("user32\ToUnicodeEx"
                    , "UInt", vk, "UInt", sc, "Ptr", &keyState
                    , "Str", "", "Int", 0, "UInt", 0, "Ptr", hkl)
                suggested := ""
            } else if (ret > 0) {
                suggested := SubStr(outBuf, 1, ret)
            } else {
                suggested := ""
            }

            symbols_out.Push(suggested)
        }
        return symbols_out
    }
}

Class clsLocale {
    chord_file := "en-qwerty.chords.txt"
    shorthand_file := "english.shorthands.txt"
    use_chords := true
    use_shorthands := true

    ; default locale settings
    remove_space_plain := ".,;'-/=\]"  ; unmodified keys that delete any smart space before them.
    remove_space_shift := "1/;'-.2356780]=\"  ; keys combined with Shift that delete any smart space before them.
    space_after_plain := ".,;"  ; unmodified keys that should be followed by smart space
    space_after_shift := "1/;" ; keys that -- when modified by Shift -- should be followed by smart space
    capitalizing_plain := "." ; unmodified keys that capitalize the text that folows them
    capitalizing_shift := "1/"  ; keys that -- when modified by Shift --  capitalize the text that folows them
    other_plain := "[" ; unmodified keys for other punctuation
    other_shift := "9,["  ; other punctuation keys when modified by Shift
    numerals_plain := "1234567890"
    numerals_shift := ""
    key_map := new clsKeyMap() ; instantiate key_map object (see above)

    punctuation_plain [] {
        get {
            return (this.remove_space_plain . this.space_after_plain . this.capitalizing_plain . this.other_plain)
        }
    }
    punctuation_shift [] {
        get {
            return (this.remove_space_shift . this.space_after_shift . this.capitalizing_shift . this.other_shift)
        }
    }

    Save(locale_name) {
        if (!locale_name) {
            locale_name := STATIC_LOCALE_NAME
        }
        GetLocaleStorage(locale_name, section, filename)
        ini.SaveProperties(this, section, filename)
    }

    Load(locale_name) {
        if (!locale_name) {
            locale_name := STATIC_LOCALE_NAME
        }
        GetLocaleStorage(locale_name, section, filename)
        ini.LoadProperties(this, section, filename)
    }

    RefreshScanCodeMapping() {
        global SC_to_symbol_map
        global symbol_to_SC_map
        global ahk_numpad_to_symbol_map

        SC_to_symbol_map := {}
        symbol_to_SC_map := {}

        For _, key_name in this.key_map.Keys() {
            if (this.key_map[key_name].symbol == "") {
                continue
            }
            SC := this.key_map[key_name].SC
            symbol := this.key_map[key_name].symbol
            SC_to_symbol_map[SC] := symbol 
            symbol_to_SC_map[symbol] := SC
        }

        For num_SC, num_reps in this.key_map.NUMPAD_MAPPING {
            SC_to_symbol_map[num_SC] := num_reps.symbol
            symbol_to_SC_map[num_reps.symbol] := num_SC
            ahk_numpad_to_symbol_map[num_reps.ahk] := num_reps.symbol
        }
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
    current_key_map := new clsKeyMap
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
                             , text: "&Auto-detect"
                             , function: ObjBindMethod(this, "_Detect")}}
    options := { remove_space_plain: { type: "Edit"}
            , space_after_plain:  { type: "Edit"}
            , capitalizing_plain: { type: "Edit"}
            , other_plain:        { type: "Edit"}
            , numerals_plain: { type: "Edit"}
            , remove_space_shift: { type: "Edit"}
            , space_after_shift:  { type: "Edit"}
            , capitalizing_shift: { type: "Edit"}
            , other_shift:        { type: "Edit"}
            , numerals_shift: { type: "Edit"}}


    Build() {
        UI := new clsUI("Keyboard and language settings")
        handle := main_UI.UI._handle
        Gui, +Owner%handle%
        UI.on_close := ObjBindMethod(this, "Close")
        UI.Add(this.controls.use_auto, "Section w360")
        UI.Add(this.controls.use_static, "y+10 w360")
        UI.Add(this.controls.kb_group, "xs y+20 h160 w490 Section")
        UI.Font("s10", "Consolas")

        for i, key_name in this.current_key_map.Keys() {
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
        UI.Add(this.controls.punctuation_group, "xs-50 y+40 h255 w490 Section")
        UI.Font("s10 w600", "Segoe UI")
        UI.Add("Text", "xs+160 yp+30", "Unmodified keys")
        UI.Add("Text", "xs+330 yp", "If Shift was pressed")
        UI.Font("w400")
        UI.Add("Text", "xs+15 yp+30 Section", "Remove space before")
        UI.Add("Text", "y+20", "Follow by a space")
        UI.Add("Text", "y+20", "Capitalize after")
        UI.Add("Text", "y+20", "Other")
        UI.Add("Text", "y+20", "Numerals")
        UI.Font("s10", "Consolas")
        UI.Add(this.options.remove_space_plain, "xs+140 ys Section w145 r1")
        UI.Add(this.options.space_after_plain, "xs w145 r1")
        UI.Add(this.options.capitalizing_plain, "xs w145 r1")
        UI.Add(this.options.other_plain, "xs w145 r1")
        UI.Add(this.options.numerals_plain, "xs w145 r1")
        UI.Add(this.options.remove_space_shift, "xs+170 ys Section w145 r1")
        UI.Add(this.options.space_after_shift, "xs w145 r1")
        UI.Add(this.options.capitalizing_shift, "xs w145 r1")
        UI.Add(this.options.other_shift, "xs w145 r1")
        UI.Add(this.options.numerals_shift, "xs w145 r1")
        UI.Font("s10", "Segoe UI")
        UI.Add(this.controls.btn_detect, "xs-320 y+40 w120 Section")
        UI.Add(this.controls.btn_apply, "x+170 w80")
        UI.Add(this.controls.btn_ok, "x+10 w80 Default")
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
        loc_obj := new clsLocale
        loc_obj.Load(this.current_locale)

        ; populate options fields
        For key, option in this.options {
            option.value := loc_obj[key]
        }
        this.current_key_map := loc_obj.key_map
        this.controls.use_auto.value := is_locale_static ? 0 : 1
        this.controls.use_static.value := is_locale_static ? 1 : 0

        this.UpdateGroupTitles(this.current_locale)
        this.RenderKeyboard()
    }

    RenderKeyboard() {
        key_map := this.current_key_map
        For _, key_name in key_map.Keys() {
            this.controls[key_name].value := key_map[key_name].symbol
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
    _OnKeyClick(name) {
        key_map := this.current_key_map
        Prompt := "Type a character to represent the key " . name
        InputBox, mapped, % "Set mapping for " . name, %Prompt%, , 300, 120
        if (ErrorLevel)
            return
        mapped := Trim(mapped)

        ; Update key_map and remove duplicates
        if (IsObject(key_map)) {
            ; remove any other key that already uses this symbol
            for _, k in key_map.Keys() {
                if (k != name && IsObject(key_map[k]) && key_map[k].symbol == mapped) {
                    key_map[k].symbol := ""
                    this.controls[k].value := ""  ; update UI button label too
                }
            }
            if (IsObject(key_map[name]))
                key_map[name].symbol := mapped
        }
        ; Update UI button label
        this.controls[name].value := mapped
    }

    _Save() {
        global app_settings
        global runtime_config_file

        new_loc := new clsLocale
        new_loc.Load(this.current_locale)
        For key, option in this.options {
            new_loc[key] := option.value
        }
        new_loc.key_map := this.current_key_map
        if (runtime_config_file) {
            new_loc.Save(false)
            locale := new_loc
            locale.RefreshScanCodeMapping()
            return
        }
        new_loc.Save(this.current_locale)
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
        this.current_key_map := new clsKeyMap
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
    return ini.LoadProperty("chord_file", section, filename) != ""
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
    if (!locale_name || LocaleHasDictionarySettings(locale_name)) {
        return
    }

    target_locale := new clsLocale
    target_locale.Load(locale_name)
    CopyDictionarySettingsToLocale(target_locale)
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
    locale.Load(settings.locale)
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
