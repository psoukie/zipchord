/*
This file is part of ZipChord.
Copyright (c) 2021-2024 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

; Locale settings (keyboard and language settings) with default values (US English)

global keys := new clsLocale
locale := new clsLocaleInterface

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
}

Class clsLocaleInterface {
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
                            , text: "&New" 
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
        if ( ini.LoadSections() == -1 ) {  ; -1 means the locales.ini file does not exist
            default_locale := new clsLocale
            ini.SaveProperties(default_locale, "English US")
        }
        this._Build()
    }
    Load(setting) {
        if (setting == FROM_CONFIG) {
            ini.LoadProperties(keys, "Locale", runtime_status.config_file)
        } else {
            ini.LoadProperties(keys, setting)
        }
    }
    _Build() {
        UI := new clsUI("Keyboard and language settings")
        handle := main_UI.UI._handle
        Gui, +Owner%handle%
        UI.on_close := ObjBindMethod(this, "_Close")
        UI.Add("Text", "Section", "&Locale name")
        UI.Add(this.name, "w120")
        UI.Add(this.controls.rename, "y+30 w80")
        UI.Add(this.controls.delete, "w80")
        UI.Add(this.controls.new, "w80")
        UI.Add("Button", "y+90 w80 Default", "&Close", ObjBindMethod(this, "_Close"))
        UI.Add("GroupBox", "ys h330 w460", "Locale settings")
        UI.Add("Text", "xp+20 yp+30 Section", "&All keys (except spacebar and dead keys)")
        UI.Font("s10", "Consolas")
        UI.Add(this.options.all, "y+10 w420 r1")
        UI.Font("s10 w700", "Segoe UI")
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

        enable_controls := true
        if (runtime_status.config_file) {
            enable_controls := false
            this.name.value := str.BareFilename(runtime_status.config_file) . "||"
            loc_obj := keys
        } else {
            sections := ini.LoadSections()
            loc_obj := new clsLocale
            if (locale_name) {
                ini.LoadProperties(loc_obj, locale_name)
            } else {
                locales := StrSplit(sections, "`n")
                locale_name := locales[1]
            }
            this.name.value := "|" StrReplace(sections, "`n", "|")
            this.name.Choose(locale_name)
        }
        this._PopulateFieldsWith(loc_obj)
        this._EnableControls(enable_controls)
        this.UI.Show()
    }
    _PopulateFieldsWith(loc_object) {
        For key, option in this.options {
            option.value := loc_object[key]
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
        InputBox, new_name, ZipChord, % "Enter a name for the new keyboard and language setting."
        if ErrorLevel
            Return
        if (this._CheckIfExists(new_name))
            return
        new_loc := New clsLocale
        ini.SaveProperties(new_loc, new_name)
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
        ini.LoadProperties(temp_loc, this.name.value)
        ini.DeleteSection(this.name.value)
        ini.SaveProperties(temp_loc, new_name)
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
    _Save() {
        new_loc := new clsLocale
        For key, option in this.options {
            new_loc[key] := option.value
        }
        section := runtime_status.config_file ? runtime_status.config_file : this.name.value
        ini.SaveProperties(new_loc, section, runtime_status.config_file)
    }
    _Close() {
        main_UI.UpdateLocaleInMainUI(this.name.value)
        main_UI.UI.Enable()
        this.UI.Hide()
    }
}