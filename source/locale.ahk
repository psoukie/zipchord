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

    _GetActiveKeyboardLayoutHandle() {
        WinGet, active_window, ID, A
        thread_id := active_window ? DllCall("user32.dll\GetWindowThreadProcessId", "Ptr", active_window, "UInt", 0, "UInt") : 0
        hkl := DllCall("user32.dll\GetKeyboardLayout", "UInt", thread_id, "Ptr")
        if (!hkl) {
            hkl := DllCall("user32.dll\GetKeyboardLayout", "UInt", 0, "Ptr")
        }
        return hkl
    }

    ; Suggest symbols based on the currently active Windows keyboard layout.
    _SuggestSymbolsFromActiveLayout() {
        ;@ahk-neko-ignore-fn 1 line;
        static MAPVK_VSC_TO_VK_EX := 3

        symbols_out := []
        ;@ahk-neko-ignore-fn 1 line;
        hkl := this._GetActiveKeyboardLayoutHandle()

        ; Reusable buffers
        VarSetCapacity(keyState, 256, 0)      ; BYTE[256]
        VarSetCapacity(outBuf,   32*2,  0)    ; WCHAR[32] (64 bytes on Unicode)

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
            ;@ahk-neko-ignore-fn 1 line;
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

; forward-declare locale objects; instantiate after clsLocale is defined below
global keys := ""
global locale := ""

Class clsLocale {
    remove_space_plain := ".,;'-/=\]"  ; unmodified keys that delete any smart space before them.
    remove_space_shift := "1/;'-.2356780]=\"  ; keys combined with Shift that delete any smart space before them.
    space_after_plain := ".,;"  ; unmodified keys that should be followed by smart space
    space_after_shift := "1/;" ; keys that -- when modified by Shift -- should be followed by smart space
    capitalizing_plain := "." ; unmodified keys that capitalize the text that folows them
    capitalizing_shift := "1/"  ; keys that -- when modified by Shift --  capitalize the text that folows them
    other_plain := "[" ; unmodified keys for other punctuation
    other_shift := "9,["  ; other punctuation keys when modified by Shift
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
        global locale
        if (!locale_name) {
            locale_name := locale.STATIC_LOCALE_NAME
        }
        if (runtime_status.config_file && locale_name == locale.STATIC_LOCALE_NAME) {
            ini.SaveProperties(this, "Locale", runtime_status.config_file)
        } else {
            ini.SaveProperties(this, locale_name)
        }
    }
    Load(locale_name) {
        global locale
        if (!locale_name) {
            locale_name := locale.STATIC_LOCALE_NAME
        }
        if (runtime_status.config_file && locale_name == locale.STATIC_LOCALE_NAME) {
            ini.LoadProperties(this, "Locale", runtime_status.config_file)
        } else {
            ini.LoadProperties(this, locale_name)
        }
    }
}

Class clsLocaleInterface {
    STATIC_LOCALE_NAME := "a fixed layout"
    current_key_map := new clsKeyMap
    UI := {}
    _last_detected_layout := ""
    controls := { use_auto: { type: "Radio"
                            , text: "&Automatically switch with keyboard layout"
                            , function: ObjBindMethod(this, "_LoadCurrentLocale")}
                , use_static: { type: "Radio"
                              , text: "&Fixed across keyboard layout changes"
                              , function: ObjBindMethod(this, "_LoadCurrentLocale")}
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
            , remove_space_shift: { type: "Edit"}
            , space_after_shift:  { type: "Edit"}
            , capitalizing_shift: { type: "Edit"}
            , other_shift:        { type: "Edit"}}

    Init() {
        this.EnsureSelectedLocaleExists()
         this._last_detected_layout := kb.GetActiveLayoutName()
    }
    Build() {
        this._Build()
    }
    IsStaticMode() {
        return (settings.locale == this.STATIC_LOCALE_NAME)
    }
    EnsureLocaleExists(locale_name) {
        if (!locale_name) {
            return
        }
        temp := {}
        if (ini.LoadProperties(temp, locale_name)) {
            default_locale := new clsLocale
            default_locale.Save(locale_name)
        }
    }
    EnsureSelectedLocaleExists() {
        if (runtime_status.config_file) {
            return
        }
        if (this.IsStaticMode()) {
            this.EnsureLocaleExists(this.STATIC_LOCALE_NAME)
            return
        }
        active_layout := kb.GetActiveLayoutName()
        if (!active_layout) {
            return
        }
        settings.locale := active_layout
        this.EnsureLocaleExists(settings.locale)
    }
    SwitchToActiveLayout() {
        if (this.IsStaticMode()) {
            return
        }
        layout_name := kb.GetActiveLayoutName()
        this._SwitchToLayout(layout_name)
    }
    _SwitchToLayout(layout_name) {
        if (!layout_name) {
            return
        }
        this.EnsureLocaleExists(layout_name)
        settings.locale := layout_name
        this._last_detected_layout := layout_name
        if (!runtime_status.config_file) {
            app_settings.Save()
        }
        this._ApplyLocaleToRuntime()
        if (this.UI._handle && this.UI.IsShown() && !this.controls.use_static.value) {
            this._LoadCurrentLocale()
        }
    }
    _ApplyLocaleToRuntime() {
        keys.Load(settings.locale)
        RefreshScanCodeMapping()
        if (IsObject(main_UI)) {
            main_UI.UpdateLocaleInMainUI()
        }
    }

    _Build() {
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
        UI.Add(this.controls.punctuation_group, "xs-50 y+40 h220 w490 Section")
        UI.Font("s10 w600", "Segoe UI")
        UI.Add("Text", "xs+160 yp+30", "Unmodified keys")
        UI.Add("Text", "xs+330 yp", "If Shift was pressed")
        UI.Font("w400")
        UI.Add("Text", "xs+15 yp+30 Section", "Remove space before")
        UI.Add("Text", "y+20", "Follow by a space")
        UI.Add("Text", "y+20", "Capitalize after")
        UI.Add("Text", "y+20", "Other")
        UI.Font("s10", "Consolas")
        UI.Add(this.options.remove_space_plain, "xs+140 ys Section w145 r1")
        UI.Add(this.options.space_after_plain, "xs w145 r1")
        UI.Add(this.options.capitalizing_plain, "xs w145 r1")
        UI.Add(this.options.other_plain, "xs w145 r1")
        UI.Add(this.options.remove_space_shift, "xs+170 ys Section w145 r1")
        UI.Add(this.options.space_after_shift, "xs w145 r1")
        UI.Add(this.options.capitalizing_shift, "xs w145 r1")
        UI.Add(this.options.other_shift, "xs w145 r1")
        UI.Font("s10", "Segoe UI")
        UI.Add(this.controls.btn_detect, "xs-320 y+40 w120 Section")
        UI.Add(this.controls.btn_apply, "x+170 w80")
        UI.Add(this.controls.btn_ok, "x+10 w80 Default")
        this.UI := UI
    }

    Show() {
        call := Func("OpenHelp").Bind("Locale")
        Hotkey, F1, % call, On
        this.controls.use_auto.value := this.IsStaticMode() ? 0 : 1
        this.controls.use_static.value := this.IsStaticMode() ? 1 : 0
        this._LoadCurrentLocale()
        this.UI.Show()
    }
    _LoadCurrentLocale() {
        locale_name := this.controls.use_static.value ? this.STATIC_LOCALE_NAME : kb.GetActiveLayoutName()
        if (!locale_name) {
            locale_name := settings.locale ? settings.locale : this.STATIC_LOCALE_NAME
        }
        this.EnsureLocaleExists(locale_name)
        this._UpdateGroupTitles(locale_name)
        this.controls.use_auto.value := (locale_name == this.STATIC_LOCALE_NAME) ? 0 : 1
        this.controls.use_static.value := (locale_name == this.STATIC_LOCALE_NAME) ? 1 : 0
        loc_obj := new clsLocale
        loc_obj.Load(locale_name)
        this._PopulateFieldsWith(loc_obj)
    }
    _PopulateFieldsWith(loc_object) {
        For key, option in this.options {
            option.value := loc_object[key]
        }
        this.current_key_map := loc_object.key_map
        this._RenderKeyboard()
    }
    _RenderKeyboard() {
        key_map := this.current_key_map
        For _, key_name in key_map.Keys() {
            this.controls[key_name].value := key_map[key_name].symbol
        }
    }

    _UpdateGroupTitles(locale_title) {
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
        new_loc := new clsLocale
        For key, option in this.options {
            new_loc[key] := option.value
        }
        new_loc.key_map := this.current_key_map
        if (runtime_status.config_file) {
            new_loc.Save(false)
            keys := new_loc
            RefreshScanCodeMapping()
            return
        }
        target_locale := this.controls.use_static.value ? this.STATIC_LOCALE_NAME : kb.GetActiveLayoutName()
        if (!target_locale) {
            target_locale := settings.locale ? settings.locale : this.STATIC_LOCALE_NAME
        }
        new_loc.Save(target_locale)
        settings.locale := target_locale
        app_settings.Save()
        active_layout := kb.GetActiveLayoutName()
        if (active_layout) {
            this._last_detected_layout := active_layout
        }
        this._ApplyLocaleToRuntime()
        this._LoadCurrentLocale()
    }
    Close() {
        main_UI.UpdateLocaleInMainUI()
        main_UI.UI.Enable()
        this.UI.Hide()
    }

    ProcessLayoutChange(layout) {
        current_layout := layout.name
        if (!current_layout || current_layout == this._last_detected_layout) {
            return
        }
        this._last_detected_layout := current_layout
        if (this.UI._handle && this.UI.IsShown() && !this.controls.use_static.value) {
            this._UpdateGroupTitles(current_layout)
        }
        if (!this.IsStaticMode()) {
            this._SwitchToLayout(current_layout)
        }
    }

    _Detect() {
        this.current_key_map := new clsKeyMap
        this._RenderKeyboard()
    }
}

; Instantiate locale objects after the clsLocale class is defined
global keys := new clsLocale
locale := new clsLocaleInterface
