/*

This file is part of ZipChord.

Copyright (c) 2021-2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

; Locale settings (keyboard and language settings) with default values (US English)
Class localeClass {
    all := "``1234567890-=qwertyuiop[]\asdfghjkl;'zxcvbnm,./" ; ; keys tracked by ZipChord for typing and chords; should be all keys that produce a character when pressed
    remove_space_plain := ".,;'-/=\]"  ; unmodified keys that delete any smart space before them.
    remove_space_shift := "1/;'-.235678]=\"  ; keys combined with Shift that delete any smart space before them.
    space_after_plain := ".,;"  ; unmodified keys that should be followed by smart space
    space_after_shift := "1/;" ; keys that -- when modified by Shift -- should be followed by smart space
    capitalizing_plain := "." ; unmodified keys that capitalize the text that folows them
    capitalizing_shift := "1/"  ; keys that -- when modified by Shift --  capitalize the text that folows them
    other_plain := "[" ; unmodified keys for other punctuation
    other_shift := "9,["  ; other punctuation keys when modified by Shift
}
keys := New localeClass

;; Locale UI
; -----------

global UI_Locale_name
    , UI_Locale_all
    , UI_Locale_space_after_plain
    , UI_Locale_space_after_shift
    , UI_Locale_capitalizing_plain
    , UI_Locale_capitalizing_shift
    , UI_Locale_remove_space_plain
    , UI_Locale_remove_space_shift
    , UI_Locale_other_plain
    , UI_Locale_other_shift

UI_Locale_Build() {
    Gui, UI_Locale:New, , Keyboard and language settings
    Gui, UI_Locale:+OwnerUI_Main
    Gui, Margin, 15, 15
    Gui, Font, s10, Segoe UI
    Gui, Add, Text, Section, &Locale name
    Gui, Add, DropDownList, w120 vUI_Locale_name gUI_Locale_Change
    Gui, Add, Button, y+30 w80 gUI_Locale_btnRename, &Rename
    Gui, Add, Button, w80 gUI_Locale_btnDelete, &Delete 
    Gui, Add, Button, w80 gUI_Locale_btnNew, &New
    Gui, Add, Button, y+90 w80 gUI_Locale_Close Default, Close
    Gui, Add, GroupBox, ys h330 w460, Locale settings
    Gui, Add, Text, xp+20 yp+30 Section, &All keys (except spacebar and dead keys)
    Gui, Font, s10, Consolas
    Gui, Add, Edit, y+10 w420 r1 vUI_Locale_all
    Gui, Font, s10 w700, Segoe UI
    Gui, Add, Text, yp+40, Punctuation
    Gui, Add, Text, xs+160 yp, Unmodified keys
    Gui, Add, Text, xs+300 yp, If Shift was pressed
    Gui, Font, w400
    Gui, Add, Text, xs Section, Remove space before
    Gui, Add, Text, y+20, Follow by a space
    Gui, Add, Text, y+20, Capitalize after
    Gui, Add, Text, y+20, Other
    Gui, Add, Button, xs+240 yp+40 w100 gUI_Locale_btnSave, Save Changes
    Gui, Font, s10, Consolas
    Gui, Add, Edit, xs+160 ys Section w120 r1 vUI_Locale_remove_space_plain
    Gui, Add, Edit, xs w120 r1 vUI_Locale_space_after_plain
    Gui, Add, Edit, xs w120 r1 vUI_Locale_capitalizing_plain
    Gui, Add, Edit, xs w120 r1 vUI_Locale_other_plain
    Gui, Add, Edit, xs+140 ys Section w120 r1 vUI_Locale_remove_space_shift
    Gui, Add, Edit, xs w120 r1 vUI_Locale_space_after_shift
    Gui, Add, Edit, xs w120 r1 vUI_Locale_capitalizing_shift
    Gui, Add, Edit, xs w120 r1 vUI_Locale_other_shift
}

; Shows the locale dialog with existing locale matching locale_name; or (if set to 'false') the first available locale.  
UI_Locale_Show(locale_name) {
    call := Func("OpenHelp").Bind("Locale")
    Hotkey, F1, % call, On
    Gui, UI_Locale:Default
    loc_obj := new localeClass
    ini.LoadSections(sections)
    if (locale_name) {
        ini.LoadProperties(loc_obj, locale_name)
    } else {
        locales := StrSplit(sections, "`n")
        locale_name := locales[1]
    }
    GuiControl, , UI_Locale_name, % "|" StrReplace(sections, "`n", "|")
    GuiControl, Choose, UI_Locale_name, % locale_name
    GuiControl, , UI_Locale_all, % loc_obj.all
    GuiControl, , UI_Locale_remove_space_plain, % loc_obj.remove_space_plain
    GuiControl, , UI_Locale_remove_space_shift, % loc_obj.remove_space_shift
    GuiControl, , UI_Locale_space_after_plain, % loc_obj.space_after_plain
    GuiControl, , UI_Locale_space_after_shift, % loc_obj.space_after_shift
    GuiControl, , UI_Locale_capitalizing_plain, % loc_obj.capitalizing_plain
    GuiControl, , UI_Locale_capitalizing_shift, % loc_obj.capitalizing_shift
    GuiControl, , UI_Locale_other_plain, % loc_obj.other_plain
    GuiControl, , UI_Locale_other_shift, % loc_obj.other_shift
    Gui Submit, NoHide
    Gui, Show
}

; when the locale name dropdown changes: 
UI_Locale_Change() {
    Gui, UI_Locale:Submit
    UI_Locale_Show(UI_Locale_name)
}

UI_Locale_btnNew() {
    InputBox, new_name, ZipChord, % "Enter a name for the new keyboard and language setting."
        if ErrorLevel
            Return
    new_loc := New localeClass
    ini.SaveProperties(new_loc, new_name)
    UI_Locale_Show(new_name)
}

UI_Locale_btnDelete(){
    ini.LoadSections(sections)
    If (! InStr(sections, "`n")) {
        MsgBox ,, % "ZipChord", % Format("The setting '{}' is the only setting on the list and cannot be deleted.", UI_Locale_name)
        Return
    }
    MsgBox, 4, % "ZipChord", % Format("Do you really want to delete the keyboard and language settings for '{}'?", UI_Locale_name)
    IfMsgBox Yes
    {
        ini.DeleteSection(UI_Locale_name)
        UI_Locale_Show(false)
    }
}

UI_Locale_btnRename() {
    InputBox, new_name, ZipChord, % Format("Enter a new name for the locale '{}':", UI_Locale_name)
    if ErrorLevel
        Return
    if (UI_Locale_CheckIfExists(new_name))
        return
    temp_loc := new localeClass
    ini.LoadProperties(temp_loc, UI_Locale_name)
    ini.DeleteSection(UI_Locale_name)
    ini.SaveProperties(temp_loc, new_name)
    UI_Locale_Show(new_name)
}

UI_Locale_CheckIfExists(new_name) {
    if(! ini.LoadProperties(locale_exists, new_name)) {
    MsgBox, 4, % "ZipChord", % Format("There are already settings under the name '{}'. Do you wish to overwrite them?", new_name)
        IfMsgBox No
            Return True
        else
            Return False
    }
}

 UI_Locale_GetSectionNames() {
    ini.LoadSections(sections)
    return sections
 }

UI_LocaleGuiClose() {
    UI_Locale_Close()
}
UI_LocaleGuiEscape() {
    UI_Locale_Close()
}
UI_Locale_Close() {
    Gui, UI_Main:-Disabled
    Gui, UI_Locale:Submit
    UpdateLocaleInMainUI(global UI_Locale_name)
}

UI_Locale_btnSave() {
    new_loc := new localeClass
    Gui, UI_Locale:Submit, NoHide
    new_loc.all := UI_Locale_all
    new_loc.space_after_plain := UI_Locale_space_after_plain
    new_loc.space_after_shift := UI_Locale_space_after_shift
    new_loc.capitalizing_plain := UI_Locale_capitalizing_plain
    new_loc.capitalizing_shift := UI_Locale_capitalizing_shift
    new_loc.remove_space_plain := UI_Locale_remove_space_plain
    new_loc.remove_space_shift := UI_Locale_remove_space_shift
    new_loc.other_plain := UI_Locale_other_plain
    new_loc.other_shift := UI_Locale_other_shift
    ini.SaveProperties(new_loc, UI_Locale_name)
}

UI_locale_InitLocale() {
    if ( ini.LoadSections(testing) ) {  ; will return true (error) if the locales.ini file does not exist
        default_locale := new localeClass
        ini.SaveProperties(default_locale, "English US")
    }
}

UI_Locale_Load(setting) {
    global keys
    ini.LoadProperties(keys, setting)
}
