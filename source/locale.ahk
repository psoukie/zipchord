/*
This file is part of ZipChord.
Copyright (c) 2021-2024 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

; Locale settings (keyboard and language settings) with default values (US English)

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

    SCAN_CODES := ["29", "02", "03", "04", "05", "06", "07", "08", "09", "0A", "0B", "0C", "0D"
          , "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "1A", "1B", "2B"
          , "1E", "1F", "20", "21", "22", "23", "24", "25", "26", "27", "28"
          , "2C", "2D", "2E", "2F", "30", "31", "32", "33", "34", "35"]

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
        hkl := DllCall("GetKeyboardLayout", "UInt", 0, "Ptr") ; cache per run

        ; Reusable buffers
        VarSetCapacity(keyState, 256, 0)      ; BYTE[256]
        VarSetCapacity(outBuf,   32*2,  0)    ; WCHAR[32] (64 bytes on Unicode)

        for i, name in this.KEY_LIST
        {
            sc := "0x" . this.SCAN_CODES[i]
            sc := sc + 0
            if (!sc)
                sc := GetKeySC(name)
            if (!sc) {
                symbols_out.Push("")
                continue
            }

            ; Map SC->VK once
            vk := DllCall("user32\MapVirtualKeyEx", "UInt", sc, "UInt", MAPVK_VSC_TO_VK_EX, "Ptr", hkl, "UInt")

            ; Reset keyboard state (no modifiers) for this key
            ; (Reuse the same var; zero it instead of re-allocating.)
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
    all := "``1234567890-=qwertyuiop[]\asdfghjkl;'zxcvbnm,./" ; ; keys tracked by ZipChord for typing and chords; should be all keys that produce a character when pressed
    remove_space_plain := ".,;'-/=\]"  ; unmodified keys that delete any smart space before them.
    remove_space_shift := "1/;'-.2356780]=\"  ; keys combined with Shift that delete any smart space before them.
    space_after_plain := ".,;"  ; unmodified keys that should be followed by smart space
    space_after_shift := "1/;" ; keys that -- when modified by Shift -- should be followed by smart space
    capitalizing_plain := "." ; unmodified keys that capitalize the text that folows them
    capitalizing_shift := "1/"  ; keys that -- when modified by Shift --  capitalize the text that folows them
    other_plain := "[" ; unmodified keys for other punctuation
    other_shift := "9,["  ; other punctuation keys when modified by Shift
    special_map := {} ; stores special keys that are defined as "{special_key:*}" or "{special_key=*}" (which can be used in the definition of all keys in the UI). The special_key can be something like "PrintScreen" and the asterisk is the character of how it's interpreted (such as "|").
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
        section := runtime_status.config_file ? "Locale" : locale_name
        ini.SaveProperties(this, section, runtime_status.config_file)
    }
    Load(locale_name) {
        if (runtime_status.config_file) {
            ini.LoadProperties(this, "Locale", runtime_status.config_file)
        } else {
            ini.LoadProperties(this, locale_name)
        }
    }
}

Class clsLocaleInterface {
    current_key_map := new clsKeyMap
    UI := {}
    name     := { type:     "DropDownList"
                , function: ObjBindMethod(this, "_Change")}
    controls := { rename:   { type: "Button"
                            , text: "&Rename" 
                            , function: ObjBindMethod(this, "_Rename")}
                , delete:   { type: "Button"
                            , text: "&Delete" 
                            , function: ObjBindMethod(this, "_Delete")}
                , new:      { type: "Button"
                            , text: "&New (auto-detect)" 
                            , function: ObjBindMethod(this, "_New")}}
    options := { all:             { type: "Edit"}
            , remove_space_plain: { type: "Edit"}
            , space_after_plain:  { type: "Edit"}
            , capitalizing_plain: { type: "Edit"}
            , other_plain:        { type: "Edit"}
            , remove_space_shift: { type: "Edit"}
            , space_after_shift:  { type: "Edit"}
            , capitalizing_shift: { type: "Edit"}
            , other_shift:        { type: "Edit"}}
    
    Init() {
        if ( ! ini.LoadSections() ) {
            default_locale := new clsLocale
            layout_name := this.GetActiveLayoutName()
            default_locale.Save(layout_name)
        }
        this._Build()
    }
    _Build() {
        UI := new clsUI("Keyboard and language settings")
        handle := main_UI.UI._handle
        Gui, +Owner%handle%
        UI.on_close := ObjBindMethod(this, "Close")
        UI.Add("Text", "Section", "&Locale name")
        UI.Add(this.name, "w120")
        UI.Add(this.controls.rename, "y+30 w80")
        UI.Add(this.controls.delete, "w80")
        UI.Add(this.controls.new, "w80")
        UI.Add("Button", "y+250 w80 Default", "&Close", ObjBindMethod(this, "Close"))
        UI.Add("GroupBox", "ys h490 w490", "Locale settings")
        UI.Add("Text", "xp+20 yp+30 Section", "Key mapping for dictionaries (click to edit)")
        
        for i, key_name in this.current_key_map.Keys() {
            Switch i {
                Case 1, 14:
                    format := "y+5 xs w30 Section"
                Case 27, 38:
                    format := "y+5 xs+15 w30 Section"
                Default:
                    format := "x+5 w30"
            }
            this.controls[key_name] := UI.Add("Button", format, "", ObjBindMethod(this, "_OnKeyClick", key_name))
        }

        UI.Add("Text", "xs-30 yp+40 Section", "S&pecial keys")
        UI.Font("s10", "Consolas")
        UI.Add(this.options.all, "y+10 w420 r1")
        UI.Font("s10 w600", "Segoe UI")
        UI.Add("Text", "yp+40", "Punctuation")
        UI.Add("Text", "xs+160 yp", "Unmodified keys")
        UI.Add("Text", "xs+300 yp", "If Shift was pressed")
        UI.Font("w400")
        UI.Add("Text", "xs Section", "Remove space before")
        UI.Add("Text", "y+20", "Follow by a space")
        UI.Add("Text", "y+20", "Capitalize after")
        UI.Add("Text", "y+20", "Other")
        UI.Add("Button", "xs+240 yp+40 w100", "&Save Changes", ObjBindMethod(this, "_Save"))
        UI.Font("s10", "Consolas")
        UI.Add(this.options.remove_space_plain, "xs+160 ys Section w120 r1")
        UI.Add(this.options.space_after_plain, "xs w120 r1")
        UI.Add(this.options.capitalizing_plain, "xs w120 r1")
        UI.Add(this.options.other_plain, "xs w120 r1")
        UI.Add(this.options.remove_space_shift, "xs+140 ys Section w120 r1")
        UI.Add(this.options.space_after_shift, "xs w120 r1")
        UI.Add(this.options.capitalizing_shift, "xs w120 r1")
        UI.Add(this.options.other_shift, "xs w120 r1")
        this.UI := UI
    }
    ; Shows the locale dialog with existing locale matching locale_name; or (if set to 'false') the first available locale.  
    Show(locale_name) {
        call := Func("OpenHelp").Bind("Locale")
        Hotkey, F1, % call, On

        if (runtime_status.config_file) {
            locale_name := false
            this._EnableControls(false)
            this.name.value := str.BareFilename(runtime_status.config_file) . "||"
        } else {
            this._EnableControls(true)
            sections := ini.LoadSections()
            if (! locale_name) {
                locales := StrSplit(sections, "`n")
                locale_name := locales[1]
            }
            this.name.value := "|" StrReplace(sections, "`n", "|")
            this.name.Choose(locale_name)
        }
        loc_obj := new clsLocale
        loc_obj.Load(locale_name)
        this._PopulateFieldsWith(loc_obj)
        this.UI.Show()
    }
    _PopulateFieldsWith(loc_object) {
        For key, option in this.options {
            option.value := loc_object[key]
        }
        this.current_key_map := loc_object.key_map
        key_map := this.current_key_map
        For _, key_name in key_map.Keys() {
            this.controls[key_name].value := key_map[key_name].symbol
        }
    }
    _EnableControls(mode := true) {
        this.name.Enable(mode)
        for _, control in this.controls {
            control.Enable(mode)
        }
    }
    _Change() {
        this.Show(this.name.value)
    }
    _New() {
        default_name := locale.GetActiveLayoutName()
        InputBox, new_name, ZipChord, % "Enter a name for the new keyboard and language setting.", , , , , , , , % default_name
        if ErrorLevel
            Return
        if (this._CheckIfExists(new_name))
            return
        new_loc := New clsLocale
        new_loc.Save(new_name)
        this.Show(new_name)
    }
    _Delete() {
        sections := ini.LoadSections()
        If (! InStr(sections, "`n")) {
            MsgBox ,, % "ZipChord", % Format("The setting '{}' is the only setting on the list and cannot be deleted.", this.name.value)
            Return
        }
        MsgBox, 4, % "ZipChord", % Format("Do you really want to delete the keyboard and language settings for '{}'?", this.name.value)
        IfMsgBox Yes
        {
            ini.DeleteSection(this.name.value)
            this.Show(false)
        }
    }
    _Rename() {
        InputBox, new_name, ZipChord, % Format("Enter a new name for the locale '{}':", this.name.value)
        if ErrorLevel
            Return
        if (this._CheckIfExists(new_name))
            return
        temp_loc := new clsLocale
        temp_loc.Load(this.name.value)
        ini.DeleteSection(this.name.value)
        temp_loc.Save(new_name)
        this.Show(new_name)
    }
    _CheckIfExists(new_name) {
        if(! ini.LoadProperties(locale_exists, new_name)) {
        MsgBox, 4, % "ZipChord", % Format("There are already settings under the name '{}'. Do you wish to overwrite them?", new_name)
            IfMsgBox No
                Return True
            else
                Return False
        }
    }
    _OnKeyClick(name) {
        key_map := this.current_key_map
        Prompt := "Type the character(s) to represent " . name . ":"
        InputBox, mapped, % "Set mapping for " name, %Prompt%, , 300, 120
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
        new_loc.Save(this.name.value)
        if (runtime_status.config_file) {
            keys := new_loc
        }
    }
    Close() {
        main_UI.UpdateLocaleInMainUI(this.name.value)
        main_UI.UI.Enable()
        this.UI.Hide()
    }

    GetActiveLayoutName() {
        VarSetCapacity(buf, 9*2, 0)  ; WCHAR[9] — layout name string like "00000409"
        if (! DllCall("user32.dll\GetKeyboardLayoutName", "Str", buf)) {
            return "Default"
        }
        RegRead, layoutName
            , % "HKLM"
            , % "SYSTEM\CurrentControlSet\Control\Keyboard Layouts\" . buf
            , % "Layout Text"
        return layoutName
    }
}

; Instantiate locale objects after the clsLocale class is defined
global keys := new clsLocale
locale := new clsLocaleInterface