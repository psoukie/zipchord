/*

ZipChord

A customizable hybrid keyboard input method that augments regular typing with
chords and shorthands.

Copyright (c) 2021-2026 Pavel Soukenik

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

#NoEnv
#SingleInstance Off
#MaxThreadsPerHotkey 1
#MaxThreadsBuffer On
#KeyHistory 0
#HotkeyInterval 0
ListLines Off
SetKeyDelay -1, -1
CoordMode ToolTip, Screen
OnExit("CloseApp")
FileEncoding, UTF-8

; Warnings are enabled for development only
; #Warn All, OutputDebug

#Include version.ahk
#Include library_bindings.ahk
#Include shared.ahk

; Handle messages from second instance in order to support command line manipulation of running script
instance_handler := new clsInstanceHandler
WM_COPYDATA := 0x004A
OnMessage(WM_COPYDATA, "Receive_WM_COPYDATA")

; Settings constants and class

global CAP_OFF      := 1 ; no auto-capitalization,
;@ahk-neko-ignore-fn 1 line; at 9/7/2025, 11:11:56 AM ; global-var is assigned but never used
     , CAP_CHORDS   := 2 ; auto-capitalize chords only
     , CAP_ALL      := 3 ; auto-capitalize all typing
     , SPACE_BEFORE_CHORD := 1
     , SPACE_AFTER_CHORD  := 2
     , SPACE_PUNCTUATION  := 4
     , CHORD_DELETE_UNRECOGNIZED  := 1  ; Delete typing that triggers chords that are not in dictionary?
     ; deprecated and removed: CHORD_ALLOW_SHIFT := 2  ; Allow Shift in combination with at least two other keys to form unique chords?
     , CHORD_RESTRICT             := 4  ; Disallow chords (except for suffixes) if the chord isn't separated from typing by a space, interruption, or defined punctuation "opener"
     , CHORD_IMMEDIATE_SHORTHANDS := 8  ; Shorthands fire without waiting for space or punctuation
     , CHORD_BY_OVERLAP := 16  ; detect chords by percentage of overlap rather than duration

global MODE_CHORDS_ENABLED     := 1
     , MODE_SHORTHANDS_ENABLED := 2
     , MODE_ZIPCHORD_ENABLED   := 4

global PREF_SHOW_CLOSING_TIP := 2        ; show tip about re-opening the main dialog and adding chords
     , PREF_FIRST_RUN        := 4        ; this value means this is the first run (there is no saved config)
     , PREF_SHOW_CONFIG      := 8        ; whether ZipChord configuration UI should be shown on startup
     , PREF_CHECK_UPDATES   := 16       ; whether ZipChord should check for updates on startup

global UI_STR_PAUSE  := "&Pause ZipChord"
     , UI_STR_RESUME := "&Resume ZipChord"

global STATIC_LOCALE_NAME := "a fixed layout"

app_settings := New clsSettings()
global settings := app_settings.settings
runtime_config_file := ""

SC_to_symbol_map := {} ; dynamically created scan-code number to key-symbol mapping
symbol_to_SC_map := {} ; reverse map
ahk_numpad_to_symbol_map := {} 


#Include *i visualizer.ahk
#Include *i testing.ahk

#Include keyboard.ahk
#Include configurations.ahk
#Include hints.ahk
#Include locale.ahk
#Include dictionaries.ahk
#Include io.ahk

global main_UI := new clsMainUI
central_watcher := new clsWatcher


Initialize(zc_version)
Return   ; Prevent execution of any of the following code, except for the always-on keyboard shortcuts below.

; Application settings
Class clsSettings {
    settings_file := A_AppData . "\ZipChord\config.ini"
    settings := { version:          zc_version
                , mode:             MODE_ZIPCHORD_ENABLED | MODE_CHORDS_ENABLED | MODE_SHORTHANDS_ENABLED
                , preferences:      PREF_FIRST_RUN | PREF_SHOW_CLOSING_TIP | PREF_SHOW_CONFIG | PREF_CHECK_UPDATES
                , locale:           ""
                , capitalization:   CAP_CHORDS
                , spacing:          SPACE_BEFORE_CHORD | SPACE_AFTER_CHORD | SPACE_PUNCTUATION
                , chording:         CHORD_RESTRICT ; Chord recognition options
                , chord_file:       "en-qwerty.chords.txt" ; file name for the chord dictionary
                , shorthand_file:   "english.shorthands.txt" ; file name for the shorthand dictionary
                , dictionary_dir:   A_ScriptDir
                , input_delay:      70
                , input_overlap:    65
                , output_delay:     3 }

    GetSettingsFile() {
        global runtime_config_file
        return runtime_config_file ? runtime_config_file : this.settings_file
    }

    GetSectionName() {
        global runtime_config_file
        return runtime_config_file ? "Application" : "Default"
    }

    Register(setting_name, value := 0) {
        if (this.settings.HasKey(setting_name)) {
            return false
        }
        this.settings[setting_name] := value
    }
    Load() {
        this.settings.locale := kb.GetActiveLayoutName()
        ini.LoadProperties(this.settings, this.GetSectionName(), this.GetSettingsFile())
        this.settings.mode |= MODE_ZIPCHORD_ENABLED ; settings are read at app startup, so we re-enable ZipChord if it was paused when closed
    }
    Save() {
        settings_to_save := this.settings.Clone()
        settings_to_save.Delete("chord_file")
        settings_to_save.Delete("shorthand_file")
        settings_to_save.mode &= MODE_ZIPCHORD_ENABLED
        ini.SaveProperties(settings_to_save, this.GetSectionName(), this.GetSettingsFile())
    }
    IsStaticMode() {
        return (settings.locale == STATIC_LOCALE_NAME)
    }
}

;; Initilization and Wiring
; ---------------------------

Initialize(zc_version) {
    global app_settings
    global locale_UI
    global updater
    global central_watcher

    ini.SaveLicense()
    app_settings.Load()
    SetWorkingDir, % settings.dictionary_dir
    ; The last applied locale is the inheritance source if Windows starts with a new layout.
    if (LocaleHasDictionarySettings(settings.locale)) {
        inheritance_locale := new clsLocale
        inheritance_locale.Load(settings.locale)
        CopyDictionarySettingsFromLocale(inheritance_locale)
    }
    ; check whether we need to upgrade existing settings file:
    if (updater.SemVerCompare(zc_version, settings.version) == 1) {
        UpdateSettings(settings.version)
    }
    updater.CheckForUpdates(zc_version)

    if (app_settings.IsStaticMode()) {
        target_locale := STATIC_LOCALE_NAME
    } else {
        target_locale := kb.GetActiveLayoutName()
        if (target_locale) {
            settings.locale := target_locale
        }
    }

    ; Initialize a profile from the current runtime defaults when no locale owns them yet.
    if (!LocaleHasDictionarySettings(target_locale)) {
        settings.chord_file := CheckDictionaryFileExists(settings.chord_file, "chord")
        settings.shorthand_file := CheckDictionaryFileExists(settings.shorthand_file, "shorthand")
        upgraded_chord_file := chords._EnsureV2DictionaryFile(settings.chord_file)
        upgraded_shorthand_file := shorthands._EnsureV2DictionaryFile(settings.shorthand_file)
        if (!upgraded_chord_file || !upgraded_shorthand_file) {
            return
        }
        settings.chord_file := upgraded_chord_file
        settings.shorthand_file := upgraded_shorthand_file
    }
    EnsureLocaleExists(target_locale)

    settings.version := zc_version
    settings.preferences &= ~PREF_FIRST_RUN
    app_settings.Save()

    main_UI.Build()
    UI_Menu_Build()
    locale_UI.Build()
    hint_UI.Build()
    ApplyLocaleToRuntime()
    if (settings.preferences & PREF_SHOW_CONFIG) {
        main_UI.Show()
    } else {
        hint_UI.ShowOnOSD("Starting ZipChord")
    }
    if (A_Args[2] && (A_Args[1] == "load" || A_Args[1] == "follow")) {
        ProcessCommandLine(A_Args[1] . "`n" . A_Args[2])
    }
    main_UI.UpdateDictionaryUI()
    main_UI.UI.Enable()
    WireCommandHotkeys("On")
    WireHotkeys("On")
    central_watcher.Start()
}

UpgradeTo26() {
    global app_settings
    result := false
    config_file := app_settings.settings_file
    locale_file := ini.default_ini
    legacy_config_keys := ["hk_ShowMainUI", "hk_AddShortcut", "hk_PauseApp", "hk_QuitApp"]

    if (FileExist(config_file)) {
        FileCopy, % config_file, % config_file . ".bak", 1
        For _, key in legacy_config_keys {
            IniDelete, % config_file, % CONFIG_SECTION, % key
            settings.Delete(key)
        }
        settings.locale := kb.GetActiveLayoutName()
    }
    if (! FileExist(locale_file)) {
        return result
    }

    sections := ini.LoadSections(locale_file)
    Loop, Parse, sections, `n
    {
        old_all := ini.LoadProperty("all", A_LoopField, locale_file)
        if (RegExMatch(old_all, "\{[^}]+[:=][^}]+\}")) {
            result := true
            break
        }
    }
    FileMove, % locale_file, % locale_file . ".bak", 1
    return result
}

UpgradeTo28() {
    selected_locale := settings.locale
    if (!selected_locale || selected_locale == STATIC_LOCALE_NAME) {
        return false
    }
    active_layout := kb.GetActiveLayoutName()
    if (selected_locale == active_layout) {
        settings.locale := active_layout
        return false
    }
    static_locale := new clsLocale
    static_locale.LoadForCurrentLayout(selected_locale)
    static_locale.Save(STATIC_LOCALE_NAME)
    settings.locale := STATIC_LOCALE_NAME
    return true
}

UpgradeTo29() {
    global app_settings

    settings.chord_file := CheckDictionaryFileExists(settings.chord_file, "chord")
    settings.shorthand_file := CheckDictionaryFileExists(settings.shorthand_file, "shorthand")
    if (!settings.chord_file || !settings.shorthand_file) {
        return
    }

    upgraded_locale := new clsLocale
    upgraded_locale.Load(settings.locale)
    CopyDictionarySettingsToLocale(upgraded_locale)
    GetLocaleStorage(settings.locale, section, filename)
    for _, key in ["chord_file", "shorthand_file", "use_chords", "use_shorthands"] {
        ini.SaveProperty(upgraded_locale[key], key, section, filename)
    }
    config_file := app_settings.GetSettingsFile()
    section := app_settings.GetSectionName()
    IniDelete, %config_file%, %section%, chord_file
    IniDelete, %config_file%, %section%, shorthand_file

    MsgBox, , % "ZipChord Upgrade Note"
            , %  "ZipChord has a new chord-detection mode which identifies chords by relative overlap of keys. You can select it on the Detection tab."
            . "`n`nShortcut dictionary settings now follow the Windows keyboard layout. When you select a different dictionary or deactivate it on the main tab for the active layout, ZipChord will remember this and will change dictionaries automatically as you switch keyboard layouts."
            . "`n`nThe command line configuration feature now expects keyboard layout as the first column in the mapping file. (See the ZipChord wiki for details.)"
}

UpdateSettings(from_version) {
    global updater
    if (updater.SemVerCompare("2.3.0", from_version) == 1) {
        ; Update hints settings from HINT_ON 1, HINT_ALWAYS 2, _NORMAL 4, _RELAXED 8, _OSD 16, _TOOLTIP 32
        ; to  HINT_OFF 1, _RELAXED 2, _NORMAL 4, _ALWAYS 8, _OSD 16, _TOOLTIP 32, _SCORE 64
        if (settings.hints & 1) {
            ; swap ALWAYS and RELAXED if one of them was selected:
            if (settings.hints & 2 || settings.hints & 8) {
                settings.hints := settings.hints ^ 10
            }
        } else {
            settings.hints &= (HINT_OSD | HINT_TOOLTIP) ; if hints were off, we only preserve OSD/TOOLTIP
        }
        settings.hints ^=  1  ; XOR from HINT_ON to HINT_OFF
        settings.hints |= HINT_SCORE
        if (settings.hint_color == "3BD511") {
            settings.hint_color := "1CA6BF"
        }
        MsgBox, , % "ZipChord Upgrade Note", % "ZipChord can now show your typing efficiency.`n`n"
                . "You can change the setting on the Hints tab."
    }
    if (updater.SemVerCompare("2.5.0", from_version) == 1) {
        settings.preferences |= PREF_CHECK_UPDATES | PREF_SHOW_CONFIG
        if (settings.output_delay > 0) {
            settings.output_delay := Round(settings.output_delay / 3)
            MsgBox, , % "ZipChord Upgrade Note", % "The Output Delay is now applied after every simulated keystroke. "
                . "This makes replacements more reliable, but you may need to adjust your Output settings."
        }
    }
    if (updater.SemVerCompare("2.6.0", from_version) == 1) {
        has_special_keys := UpgradeTo26()
        upgrade_note := "ZipChord 2.6 uses a new keyboard detection based on positions of physical keys. Your keyboard settings were backed up, and ZipChord will create a new keyboard mapping based on your current Windows keyboard layout."
            . "`n`n"
            . "Application shortcuts have been replaced by a command menu. Press both Shift keys together to open it."
        if (has_special_keys ) {
            upgrade_note .= "`n`nYour keyboard settings included custom special keys that are no longer supported. Remap shortcuts in your dictionaries that used them to regular keys."
        }
        MsgBox, , % "ZipChord Upgrade Note", % upgrade_note
    }
    if (updater.SemVerCompare("2.8.0", from_version) == 1) {
        if (UpgradeTo28()) {
            MsgBox, , % "ZipChord Upgrade Note", % "ZipChord now follows your active Windows keyboard layout automatically.`n`nYour existing keyboard and language settings did not match the currently active Windows layout, so they were preserved as a fixed layout."
        }
    }
    if (updater.SemVerCompare("2.9.0", from_version) == 1) {
        UpgradeTo29()
    }
}

Class clsWatcher {
    POLL_INTERVAL := 250

    _watch_fn := ObjBindMethod(this, "RunChecks")

    Start() {
        watch_fn := this._watch_fn
        interval := this.POLL_INTERVAL
        SetTimer, %watch_fn%, %interval%
    }

    Stop() {
        watch_fn := this._watch_fn
        SetTimer, %watch_fn%, Off
    }

    RunChecks() {
        global locale_UI
        
        chords.CheckForDictModification()
        shorthands.CheckForDictModification()
        layout_changed := kb.CheckForLayoutChange()
        if (config.use_mapping) {
            window_changed := config.DetectAppSwitch()
            config_switched := false
            if (window_changed || layout_changed) {
                current_layout := layout_changed ? layout_changed : kb.GetActiveLayoutName()
                config_switched := config.ProcessConfigChange(current_layout)
            }
            if (layout_changed && !config_switched) {
                ProcessLayoutChange(layout_changed)
            }
        } else if (layout_changed) {
            ProcessLayoutChange(layout_changed)
        }
    }
}

CloseApp() {
    WireHotkeys("Off")
    ExitApp
}

;;  Adding shortcuts
; -------------------

; Define a new shortcut for the selected text (or check what it is for existing)
AddShortcut() {
    if (add_shortcut.UI.IsShown()) {
        add_shortcut.UI.Reshow()
        Return
    }
    ; we try to copy any currently selected text into the Windows clipboard (while backing up and restoring its content)
    clipboard_backup := ClipboardAll
    Clipboard := ""
    Send ^c
    ClipWait, 1
    copied_text := Trim(Clipboard)
    Clipboard := clipboard_backup
    clipboard_backup := ""
    add_shortcut.Show(copied_text)
}

/**
* Main Dialog UI Class
*
*/
Class clsMainUI {
    UI := {}
    controls := {selected_locale:      { type: "Text"
                                        , text: "Loading..."}
                , btn_customize_locale: { type: "Button"
                                        , text: "C&ustomize"
                                        , function: ObjBindMethod(this, "_btnCustomizeLocale")}
                , chord_enabled:        { type: "Checkbox"
                                        , text: "Use &chords"
                                        , setting: { parent: "mode", const: "MODE_CHORDS_ENABLED"}}
                , shorthand_enabled:    { type: "Checkbox"
                                        , text: "Use &shorthands"
                                        , setting: { parent: "mode", const: "MODE_SHORTHANDS_ENABLED"}}
                , chord_entries:        { type: "GroupBox"
                                        , text: "Chord dictionary"}
                , chord_file:           { type: "Text"
                                        , text: "Loading..."}
                , shorthand_entries:    { type: "GroupBox"
                                        , text: "Shorthand dictionary"}
                , shorthand_file:       { type: "Text"
                                        , text: "Loading..."}
                , input_delay:          { type: "Edit"
                                        , text: "99"}
                , input_overlap:        { type: "Edit"
                                        , text: "99"}
                , output_delay:         { type: "Edit"
                                        , text: "99"}
                , restrict_chords:      { type: "Checkbox"
                                        , text: "&Restrict chords while typing"
                                        , setting: { parent: "chording", const: "CHORD_RESTRICT"}}
                , delete_unrecognized:  { type: "Checkbox"
                                        , text: "Delete &mistyped chords"
                                        , setting: { parent: "chording", const: "CHORD_DELETE_UNRECOGNIZED"}}
                , immediate_shorthands: { type: "Checkbox"
                                        , text: "E&xpand shorthands immediately"
                                        , setting: { parent: "chording", const: "CHORD_IMMEDIATE_SHORTHANDS"}}
                , hint_frequency:       { type: "DropDownList"
                                        , function: ObjBindMethod(this, "HintEnablement")
                                        , text: "Never|Relaxed|Normal|Always"}
                , hint_destination:     { type: "DropDownList"
                                        , text: "On-screen display|Tooltips"}
                , hint_score:           { type: "Checkbox"
                                        , text: "Show typing &efficiency"
                                        , setting: { parent: "hints", const: "HINT_SCORE"}}
                , show_on_startup:      { type: "Checkbox"
                                        , text: "&Open settings when starting ZipChord"
                                        , setting: {parent: "preferences", const: "PREF_SHOW_CONFIG"}}
                , btn_customize_hints:  { type: "Button"
                                        , function: ObjBindMethod(this, "ShowHintCustomization")
                                        , text: "&Adjust OSD >>"}
                , space_before:         { type: "Checkbox"
                                        , text: "In &front of chords"
                                        , setting: { parent: "spacing", const: "SPACE_BEFORE_CHORD"}}
                , space_after:          { type: "Checkbox"
                                        , text: "&After chords and shorthands"
                                        , setting: { parent: "spacing", const: "SPACE_AFTER_CHORD"}}
                , space_punctuation:    { type: "Checkbox"
                                        , text: "After &punctuation"
                                        , setting: { parent: "spacing", const: "SPACE_PUNCTUATION"}}
                , capitalization:       { type: "DropDownList"
                                        , text: "Off|For shortcuts|For all input"}
                , update_check:         { type: "Checkbox"
                                        , text: "Automatically check for &updates"
                                        , setting: {parent: "preferences", const: "PREF_CHECK_UPDATES"}}
                , debugging:            { type: "Checkbox"
                                        , text: "&Log this session (debugging)"}}
                                        
    ; Broken off separately from above due to AHK expression length limits
    controls.btn_pause := { type: "Button"
                            , function: Func("PauseApp").Bind(true)
                            , text: UI_STR_PAUSE}
    controls.hint_offset_x := { type: "Edit" }
    controls.hint_offset_y := { type: "Edit" }
    controls.hint_size := { type: "Edit" }
    controls.hint_color := { type: "Edit" }
    controls.tabs := { type: "Tab3", text: " Language | Detection | Display | Output | About "}
    controls.chord_by_duration := { type: "Radio"
                            , text: "By minimum held &duration"
                            , function: ObjBindMethod(this, "_SetChordModeUI", False)}
    controls.chord_by_overlap := { type: "Radio"
                            , text: "By relative overlap of keys"
                            , function: ObjBindMethod(this, "_SetChordModeUI", True)}
    controls.chord_by_label := { type: "Text"
                            , text: "Loading..."}

    labels := []
    closing_tip := 0

    _help_fn := ObjBindMethod(this, "_Help")
    _reset_hint_fn := ObjBindMethod(hint_UI, "Reset")

    ; Prepare UI
    Build() {
        global zc_version
        global zc_year
        cts := this.controls
        UI := new clsUI("ZipChord")
        UI.on_close := ObjBindMethod(this, "Close")

        UI.Add(cts.tabs)
        UI.Add("Text", "y+20 Section", "&Keyboard and language")
        UI.Add(cts.selected_locale, "y+10 w170")
        UI.Add(cts.btn_customize_locale, "x+20 w100")
        this._BuilderHelper(UI, "chord", "&Open", "&Edit", "xs y+20")
        this._BuilderHelper(UI, "shorthand", "Ope&n", "Edi&t", "xs-20 y+30")

        UI.Tab(2)
        UI.Add("GroupBox", "y+20 w310 h135", "Chord &detection")
        UI.Add(cts.chord_by_duration, "xp+20 yp+30 Section")
        UI.Add(cts.chord_by_overlap, "y+10")
        UI.Add(cts.chord_by_label, "w200")
        UI.Add(cts.input_delay, "Right xp+200 yp-2 w40 Number")
        UI.Add(cts.input_overlap, "Right xp yp w40 Number")
        UI.Add("GroupBox", "xs-20 y+40 w310 h140", "Shortcut options")
        UI.Add(cts.restrict_chords, "xp+20 yp+30")
        UI.Add(cts.delete_unrecognized)
        UI.Add(cts.immediate_shorthands, "Section")

        UI.Tab(3)
        UI.Add("Text", "y+20 Section", "&Show hints")
        UI.Add(cts.hint_frequency, "AltSubmit xp+150 w140")
        UI.Add("Text", "xs", "Hint &location")
        UI.Add(cts.hint_destination, "AltSubmit xp+150 w140")
        UI.Add(cts.hint_score, "xs")
        UI.Add(cts.show_on_startup)
        UI.Add(cts.btn_customize_hints, "w100")
        this.labels[1] := UI.Add("GroupBox", "xs y+20 w310 h180 Section", "Hint customization")
        this.labels[2] := UI.Add("Text", "xp+20 yp+30 Section", "Horizontal offset (px)")
        this.labels[3] := UI.Add("Text", "yp+35", "Vertical offset (px)")
        this.labels[4] := UI.Add("Text", "yp+35", "OSD font size (pt)")
        this.labels[5] := UI.Add("Text", "yp+35", "OSD color (hex code)")
        UI.Add(cts.hint_offset_x, "xp+200 ys w70 Right")
        UI.Add(cts.hint_offset_y, "yp+35 w70 Right")
        UI.Add(cts.hint_size, "yp+35 w70 Right Number")
        UI.Add(cts.hint_color, "yp+35 w70 Right")

        UI.Tab(4)
        UI.Add("GroupBox", "y+20 w310 h120 Section", "Smart spaces")
        UI.Add(cts.space_before, "xs+20 ys+30")
        UI.Add(cts.space_after, "xp y+10")
        UI.Add(cts.space_punctuation, "xp y+10")
        UI.Add("Text", "xs y+30", "Auto-&capitalization")
        UI.Add(cts.capitalization, "AltSubmit xp+150 w130")
        UI.Add("Text", "xs y+m", "&Output delay (ms)")
        UI.Add(cts.output_delay, "Right xp+150 w40 Number")

        UI.Tab(5)
        UI.Add("Text", "Y+20", "ZipChord")
        UI.Add("Text", "Y+20", "Copyright © 2021–" . zc_year . " Pavel Soukenik")
        dll_indicator := dll.available ? " (with a compiled library)" : ""
        UI.Add("Text", "Y+20", "version " . zc_version . dll_indicator)
        UI.Font("underline cBlue")
        UI.Add("Text", , "License information", Func("LinkToLicense"))
        UI.Add("Text", , "Help and documentation", Func("LinkToDocumentation"))
        UI.Add("Text", , "Latest releases", Func("LinkToReleases"))
        UI.Font("norm cDefault")
        UI.Add(cts.update_check, "y+30")
        if (A_Args[1] == "dev") {
            UI.Add(cts.debugging, "y+30")
        }

        UI.Tab()
        UI.Add(cts.btn_pause, "xm ym+450 w130")
        UI.Add("Button", "w80 xm+160 ym+450", "Apply", ObjBindMethod(this, "_ApplySettings"))
        UI.Add("Button", "Default w80 xm+260 ym+450", "OK", ObjBindMethod(this, "_btnOK"))

        UI.Disable()  ; start disabled during loading
        this.UI := UI
    }
    _BuilderHelper(UI, name_modifier, s_open, s_edit, options) {
        cts := this.controls
        UI.Add(cts[name_modifier . "_entries"], options . " w310 h135")
        UI.Add(cts[name_modifier . "_file"], "xp+20 yp+30 Section w270")
        UI.Add("Button", "xs w80 Section", s_open, ObjBindMethod(this, "_btnSelectDictionary", name_modifier))
        UI.Add("Button", "ys w80", s_edit, ObjBindMethod(this, "_btnEditDictionary", name_modifier))
        UI.Add(cts[name_modifier . "_enabled"], "xs")
    }

    Show() {
        global runtime_config_file

        kb.SetZipChordToCurrentHkl()
        cts := this.controls
        if (A_Args[1] == "dev" && cts.debugging.value) {
            FinishDebugging()
        }
        cts.debugging.value := 0 ; debugging is always set to disabled
        help_fn := this._help_fn
        Hotkey, F1, %help_fn%, On
        this._SetChordModeUI(settings.chording & CHORD_BY_OVERLAP)
        cts.input_delay.value := settings.input_delay
        cts.input_overlap.value := settings.input_overlap
        cts.output_delay.value := settings.output_delay
        ; Loop through each control and apply settings from its defined corresponding setting
        for _, control in this.controls {
            if (control.HasKey("setting")) {
                const_name := control.setting.const
                control.value := (settings[control.setting.parent] & %const_name%) ? 1 : 0
            }
        }
        cts.capitalization.Choose(settings.capitalization)
        cts.hint_frequency.Choose( OrdinalOfHintFrequency() + 1)
        cts.hint_destination.Choose( (settings.hints & (HINT_OSD | HINT_TOOLTIP)) // HINT_OSD) ; calculate the option's position; relies on HINT_TOOLTIP being << from HINT_OSD
        cts.hint_offset_x.value := settings.hint_offset_x
        cts.hint_offset_y.value := settings.hint_offset_y
        cts.hint_size.value := settings.hint_size
        cts.hint_color.value := settings.hint_color
        this.ShowHintCustomization(false)
        this.HintEnablement(true)
        cts.tabs.Choose(1) ; switch to first tab
        this.UpdateLocaleProfileInMainUI()
        cts.btn_customize_locale.Enable(!runtime_config_file)
        this.UI.Show()
        UI_SyncModeState()
        if (runtime_config_file) {
            this.UI.SetTitle("ZipChord - " . str.BareFilename(runtime_config_file))
        } else {
            this.UI.SetTitle("ZipChord")
        }
    }

    _btnOK() {
        if (this._ApplySettings()) {
            this.Close()
        }
        return
    }
    _ApplySettings() {
        global app_settings
        global hint_delay

        cts := this.controls
        previous_mode := settings.mode
        ; gather new settings from UI...
        settings.input_delay := cts.input_delay.value + 0
        if ( (temp:=this._SanitizeNumber(cts.input_overlap.value, "percentage")) =="ERROR") {
            MsgBox ,, % "ZipChord", % "The overlap setting needs to be a number between 0 and 100."
            Return false
        } else {
            settings.input_overlap := temp + 0
        }
        settings.output_delay := cts.output_delay.value + 0
        settings.capitalization := cts.capitalization.value
        settings.spacing := cts.space_before.value * SPACE_BEFORE_CHORD
                            + cts.space_after.value * SPACE_AFTER_CHORD
                            + cts.space_punctuation.value * SPACE_PUNCTUATION
        settings.chording := cts.delete_unrecognized.value * CHORD_DELETE_UNRECOGNIZED
                            + cts.restrict_chords.value * CHORD_RESTRICT
                            + cts.immediate_shorthands.value * CHORD_IMMEDIATE_SHORTHANDS
                            + cts.chord_by_overlap.value * CHORD_BY_OVERLAP
        ; settings.mode carries over the current ZIPCHORD_ENABLED setting
        settings.mode := (settings.mode & MODE_ZIPCHORD_ENABLED)
                        + cts.chord_enabled.value * MODE_CHORDS_ENABLED
                        + cts.shorthand_enabled.value * MODE_SHORTHANDS_ENABLED
        ; recalculate hint settings based on frequency (HINT_OFF etc.) and OSD/Tooltip. ( ** is exponent function in AHK)
        settings.hints := 2**(cts.hint_frequency.value - 1) + 16 * cts.hint_destination.value
                            + cts.hint_score.value * HINT_SCORE
        ; update preferences based on selections
        settings.preferences := cts.show_on_startup.value ? (settings.preferences | PREF_SHOW_CONFIG) : (settings.preferences & ~PREF_SHOW_CONFIG)
        settings.preferences := cts.update_check.value ? (settings.preferences | PREF_CHECK_UPDATES) : (settings.preferences & ~PREF_CHECK_UPDATES)

        if ( (temp:=this._SanitizeNumber(cts.hint_offset_x.value, "integer")) == "ERROR") {
            MsgBox ,, % "ZipChord", % "The offset needs to be a positive or negative number."
            Return false
        } else {
            settings.hint_offset_x := temp + 0
        }
        if ( (temp:=this._SanitizeNumber(cts.hint_offset_y.value, "integer")) == "ERROR") {
            MsgBox ,, % "ZipChord", % "The offset needs to be a positive or negative number."
            Return false
        } else {
            settings.hint_offset_y := temp + 0
        }
        settings.hint_size := cts.hint_size.value
        if ( (temp:=this._SanitizeNumber(cts.hint_color.value, "hex_color")) =="ERROR") {
            MsgBox ,, % "ZipChord", % "The color needs to be entered as hex code, such as '34cc97' or '#34cc97'."
            Return false
        } else {
            settings.hint_color := temp
        }
        ; Locale-specific mode bits remain runtime values but are persisted with the locale.
        SaveRuntimeDictionarySettingsToLocale()
        ; ...and save application settings to config.ini
        app_settings.Save()
        ; We always want to rewire hotkeys in case the keys have changed.
        WireHotkeys("Off")
        locale.LoadForCurrentLayout(settings.locale)
        if (settings.mode > MODE_ZIPCHORD_ENABLED) {
            if (previous_mode-1 < MODE_ZIPCHORD_ENABLED) {
                hint_UI.ShowOnOSD("ZipChord Keyboard", "On")
            }
            WireHotkeys("On")
        }
        else if (settings.mode & MODE_ZIPCHORD_ENABLED) {
            ; Here, ZipChord is not paused, but chording and shorthands are both disabled
            hint_UI.ShowOnOSD("ZipChord Keyboard", "Off")
        }
        if (A_Args[1] == "dev" && cts.debugging.value) {
            if (FileExist("debug.txt")) {
                MsgBox, 4, % "ZipChord", % "This will overwrite an existing file with debugging output (debug.txt). Would you like to continue?`n`nSelect Yes to start debugging and overwrite the file.`nSelect No to cancel."
                IfMsgBox No
                    Return false
            } else {
                MsgBox, , % "ZipChord", % "You can type in a text editor to create a log of input and output.`n`nSimply reopen the ZipChord window when done to stop the logging process and save the debug file."
            }
            FileDelete, % A_Temp . "\debug.cfg"
            FileDelete, % A_Temp . "\debug.in"
            FileDelete, % A_Temp . "\debug.out"
            test.Path("set", A_Temp)
            test.Config("save", "debug")
            test.Record("both", "debug")
        }
        UI_SyncModeState()
        ; reflect any changes to OSD UI
        reset_hint_fn := this._reset_hint_fn
        SetTimer, %reset_hint_fn%, -2000
        Return true
    }

    UpdateLocaleProfileInMainUI() {
        this.controls.selected_locale.value := RegExReplace(settings.locale, "^\w", "$U0")
        this.controls.chord_enabled.value := (settings.mode & MODE_CHORDS_ENABLED) ? 1 : 0
        this.controls.shorthand_enabled.value := (settings.mode & MODE_SHORTHANDS_ENABLED) ? 1 : 0
        this.UpdateDictionaryUI()
    }

    ; Update UI with dictionary details
    UpdateDictionaryUI() {
        this._UpdateDictionaryType("chord")
        this._UpdateDictionaryType("shorthand")
    }
    _UpdateDictionaryType(type) {
        cts := this.controls
        pluralized := type . "s"
        StringUpper, uppercased, type, T
        cts[type . "_file"].value := str.Ellipsisize(settings[type . "_file"], 270)
        entriesstr := ""
        entriesstr := uppercased . " dictionary (" %pluralized%.entries
        entriesstr .= (chords.entries==1) ? " " . type . ")" : " " . pluralized . ")"
        cts[type . "_entries"].value := entriesstr
    }

    _SetChordModeUI(by_overlap := -1) {  ; -1 means autodetection; otherwise a boolean
        if (by_overlap == -1) {
            by_overlap := this.controls.chord_by_overlap.value    
        }
        if (by_overlap) {
            this.controls.chord_by_overlap.value := true
            this.controls.chord_by_label.value :=  "Percentage overlap"
            this.controls.input_delay.Hide()
            this.controls.input_overlap.Show()
        } else {
            this.controls.chord_by_duration.value := true
            this.controls.chord_by_label.value := "Duration in milliseconds"
            this.controls.input_delay.Show()
            this.controls.input_overlap.Hide()
        }
    }

    Close() {
        Hotkey, F1, Off
        this.UI.Hide()
        if (settings.preferences & PREF_SHOW_CLOSING_TIP) {
            this.closing_tip := new clsClosingTip
        }
    }
    _Help() {
        current_tab := this.controls.tabs.value
        OpenHelp("Main-" . Trim(current_tab))
    }

    _btnCustomizeLocale() {
        global locale_UI
        global runtime_config_file

        if (runtime_config_file) {
            return
        }

        this.UI.Disable()
        locale_UI.Show()
    }

    _btnSelectDictionary(type_string) {
        type := type_string == "chord" ? "chord" : "shorthand"
        StringUpper, uppercased, type, T
        heading := "Open " . uppercased . " Dictionary"
        file_type := uppercased . " dictionaries (*." . type . "s.txt)"
        FileSelectFile dict, , % settings.dictionary_dir, %heading%, %file_type%
        if (dict == "") {
            return
        }
        pluralized := type . "s"
        if (%pluralized%.Load(dict)) {
            settings[type . "_file"] := %pluralized%._file
            SaveRuntimeDictionarySettingsToLocale()
            this.UpdateDictionaryUI()
        }
    }
    _btnEditDictionary(type) {
        Run % settings[type . "_file"]
    }

    ; Process input to ensure it is an integer (or a color hex code if the second parameter is true), return number or "ERROR"
    _SanitizeNumber(orig, mode) {
        sanitized := Trim(orig)
        if ( mode == "integer" || mode == "percentage" ) {
            if sanitized is not integer
                return "ERROR"
        }

        if (mode == "integer") {
            return sanitized
        }
    
        if (mode == "percentage") {
            if (sanitized < 0 || sanitized > 100) {
                return "ERROR"        
            }
            return sanitized
        }

        if (mode == "hex_color") {
            if (SubStr(orig, 1, 1) == "#") {
                sanitized := SubStr(orig, 2)
            }
            if (StrLen(sanitized) != 6) {
                return "ERROR"
            }
            if sanitized is not xdigit
                return "ERROR"

            return sanitized
        }
    
        MsgBox , , "ZipChord", "Error: Incorrect internal call to _SanitizeNumber"
    }

    ; Shows or hides controls for hints customization (1 = show, 0 = hide)
    ShowHintCustomization(show_controls := true) {
        cts := this.controls
        cts.btn_customize_hints.Disable(show_controls)
        cts.hint_offset_x.Show(show_controls)
        cts.hint_offset_y.Show(show_controls)
        cts.hint_size.Show(show_controls)
        cts.hint_color.Show(show_controls)
        Loop 5 {
            this.labels[A_Index].Show(show_controls)
        }
    }
    HintEnablement() {
        cts := this.controls
        enable := cts.hint_frequency.value == 1 ? 0 : 1
        cts.hint_destination.Enable(enable)
        cts.hint_score.Enable(enable)
        cts.btn_customize_hints.Enable(enable)
        cts.hint_offset_x.Enable(enable)
        cts.hint_offset_y.Enable(enable)
        cts.hint_size.Enable(enable)
        cts.hint_color.Enable(enable)
    }
}

ShowMainUI() {
    main_UI.Show()
}

; App shortcut and double-Shift 'command menu'

ShowKeyboardCommandMenu() {
    kb.SetZipChordToCurrentHkl()
    UI_SyncModeState()
    hint_UI._GetCaret(caret_x, caret_y, caret_w, caret_h)
    if (caret_x != "" && caret_y != "") {
        CoordMode, Menu, Screen
        x := caret_x + Max(1.5 * caret_w, 20)
        y := caret_y + Max(1.5 * caret_h, 28)
        Menu, ZipChordCommand, Show, % x, % y
    } else {
        Menu, ZipChordCommand, Show
    }
}

WireCommandHotkeys(status) {
    call := Func("ShowKeyboardCommandMenu")
    Hotkey, % "~LShift & ~RShift", % call, %status%
    Hotkey, % "~RShift & ~LShift", % call, %status%
}

UI_SyncModeState() {
    mode := settings.mode & MODE_ZIPCHORD_ENABLED
    if (main_UI.UI.IsShown()) {
        main_UI.controls.btn_pause.value := mode ? UI_STR_PAUSE : UI_STR_RESUME
        main_UI.controls.tabs.Enable(mode)
    }
    Update_Menus()
}

ToggleFeature(mode_flag, control_name) {
    disabling := settings.mode & mode_flag
    if (disabling) {
        settings.mode := settings.mode & ~mode_flag
    } else {
        settings.mode := settings.mode | mode_flag
    }
    SaveRuntimeDictionarySettingsToLocale()
    if (main_UI.UI.IsShown()) {
        main_UI.controls[control_name].value := disabling ? 0 : 1
    }

    control_UI_text := (control_name == "chord_enabled") ? "Chords" : "Shorthands"
    hint_UI.ShowOnOSD(control_UI_text, disabling ? "Off" : "On")
    UI_SyncModeState()
}

ToggleChords() {
    ToggleFeature(MODE_CHORDS_ENABLED, "chord_enabled")
}

ToggleShorthands() {
    ToggleFeature(MODE_SHORTHANDS_ENABLED, "shorthand_enabled")
}

; Create taskbar tray menu and command menu:
UI_Menu_Build() {
    Menu, Tray, NoStandard
    Add_Menu_Item("Open settings`t(O)", "ShowMainUI")
    Add_Menu_Item("&Add or edit shortcut`t(A)", "AddShortcut")
    Add_Menu_Item("&Pause ZipChord`t(P)", "PauseApp")
    Add_Menu_Item("Disable &chords`t(C)", "ToggleChords", true)
    Add_Menu_Item("Disable &shorthands`t(S)", "ToggleShorthands", true)
    Add_Menu_Item("", "")
    if (A_Args[1] == "dev") {
        Add_Menu_Item("Open key &visualizer`t(V)", "OpenKeyVisualizer")
        Add_Menu_Item("Open &test console`t(T)", "OpenTestConsole")
        Add_Menu_Item("", "")
    }
    Add_Menu_Item("Quit ZipChord`t(Q)", "QuitApp")

    Menu, Tray, Default, 1&
    Menu, Tray, Tip, % "ZipChord"
    Menu, Tray, Click, 1

    Update_Menus()
}

Add_Menu_Item(label, function, command_only := false) {
    Menu, ZipChordCommand, Add, % label, % function
    if (command_only) {
        Return
    }
    short_label := SubStr(label, 1, StrLen(label)-4)
    Menu, Tray, Add, % short_label, % function
}

Update_Menus() {
    is_running := settings.mode & MODE_ZIPCHORD_ENABLED
    pause_label := is_running ? "&Pause ZipChord`t(P)" : "&Resume ZipChord`t(R)"
    short_pause_label := SubStr(pause_label, 1, StrLen(pause_label)-4)
    Menu, Tray, Rename, 3&, % short_pause_label
    Menu, ZipChordCommand, Rename, 3&, % pause_label
    chord_label := (settings.mode & MODE_CHORDS_ENABLED) ? "Disable &chords`t(C)" : "Enable &chords`t(C)"
    shorthand_label := (settings.mode & MODE_SHORTHANDS_ENABLED) ? "Disable &shorthands`t(S)" : "Enable &shorthands`t(S)"
    Menu, ZipChordCommand, Rename, 4&, % chord_label
    Menu, ZipChordCommand, Rename, 5&, % shorthand_label
    if (is_running) {
        Menu, ZipChordCommand, Enable, 4&
        Menu, ZipChordCommand, Enable, 5&
    } else {
        Menu, ZipChordCommand, Disable, 4&
        Menu, ZipChordCommand, Disable, 5&
    }
}

PauseApp(from_button := false) {
    global central_watcher

    if (settings.mode & MODE_ZIPCHORD_ENABLED) {
        settings.mode := settings.mode & ~MODE_ZIPCHORD_ENABLED
        mode := false
        central_watcher.Stop()
    } else {
        settings.mode := settings.mode | MODE_ZIPCHORD_ENABLED
        mode := true
    }
    state := mode ? "On" : "Off"
    if (from_button != true) {
        hint_UI.ShowOnOSD("ZipChord Keyboard", state)
    }
    WireHotkeys(state)
    UI_SyncModeState()
    if (mode) {
        central_watcher.Start()
    }
}

QuitApp() {
    WireHotkeys("Off")
    hint_UI.ShowOnOSD("Closing ZipChord")
    if (dll.available) {
        dll.Destroy()
    }
    Sleep 1100
    ExitApp
}

OpenKeyVisualizer() {
    visualizer.Init()
}
OpenTestConsole() {
    if (test.mode==TEST_OFF)
        test.Init()
}
FinishDebugging() {
    global zc_version
    test.Stop()
    test.Path("restore")
    test._mode := TEST_OFF
    FileDelete, % "debug.txt"
    FileAppend % "Configuration Settings`n----------------------`nZipChord version: " . zc_version . "`n", % "debug.txt", UTF-8
    FileRead file_content, % A_Temp . "\debug.cfg"
    FileAppend % file_content, % "debug.txt", UTF-8
    FileAppend % "`nInput`n-----`n", % "debug.txt", UTF-8
    FileRead file_content, % A_Temp . "\debug.in"
    FileAppend % file_content, % "debug.txt", UTF-8
    FileAppend % "`nOutput`n------`n", % "debug.txt", UTF-8
    FileRead file_content, % A_Temp . "\debug.out"
    FileAppend % file_content, % "debug.txt", UTF-8
    Run % "debug.txt"
}

OrdinalOfHintFrequency() {
    frequency := settings.hints & (HINT_OFF | HINT_RELAXED | HINT_NORMAL | HINT_ALWAYS)
    frequency := Round(Log(frequency) / Log(2))  ; log base 2 returns e.g. 0 for 1, 1 for 2, 2 for 4 etc.
    Return frequency
}

LinkToLicense() {
    ini.ShowLicense()
}
LinkToDocumentation() {
    Run https://github.com/psoukie/zipchord/wiki
}
LinkToReleases() {
    Run https://github.com/psoukie/zipchord/releases
}

; Functions supporting UI

;; Closing Tip UI
; ----------------

Class clsClosingTip {
    UI := {}
    dont_show :=    { type: "Checkbox"
                    , text: "Do &not show this tip again."}

    __New() {
        this.UI := new clsUI("ZipChord Tips")
        this.UI.on_close := ObjBindMethod(this, "Close")
        this.UI.Margin(20, 20)
        this.UI.Add("Text", "+Wrap w430"
            , "- To reopen the settings window, click on the ZipChord icon in the system tray.`n`n"
            . "- To open a command menu, press both Shift keys together.`n`n"
            . "- Press F1 in any ZipChord tab or window for help.")
        this.UI.Add(this.dont_show)
        this.UI.Add("Button", "x370 w80 Default", "OK", ObjBindMethod(this, "Btn_OK"))
        call := Func("OpenHelp").Bind("")
        Hotkey, F1, % call, On
        this.UI.Show("w470")
    }
    Btn_OK() {
        global app_settings

        this.Close()
        if (this.dont_show.value) {
            settings.preferences &= ~PREF_SHOW_CLOSING_TIP
            app_settings.Save()
            this.UI.Destroy()
            this.UI := {}
        }
    }
    Close() {
        Hotkey, F1, Off
        this.UI.Hide()
    }
}

Class clsInstanceHandler {
    WM_COPYDATA := 0x004A
    UNIQUE_STRING := "ZC ZipChord RUNNING"
    detection_UI := {}

    __New() {
        previousHwnd := this._DetectPreviousInstance()
        if (previousHwnd) {
            message := str.JoinArray(A_Args, "`n")
            if ! (message) {
                MsgBox, , % "ZipChord", % "A ZipChord instance is already running."
                ExitApp
            }
            this._Send_WM_COPYDATA(message, previousHwnd)
            ExitApp
        }
        this.detection_UI := new clsUI(this.UNIQUE_STRING, "-Caption +ToolWindow")
        this.detection_UI.Show()
        WinSet, Transparent, 0, % this.UNIQUE_STRING
        ; WinMinimize , % this.UNIQUE_STRING
    }
    _DetectPreviousInstance() {
        DetectHiddenWindows, On
        WinGet, previousHwnd, PID, % this.UNIQUE_STRING
        DetectHiddenWindows, Off
        return previousHwnd
    }
    ; Reuses example code from AHK documentation
    _Send_WM_COPYDATA(ByRef StringToSend, target_hwnd) {
        VarSetCapacity(CopyDataStruct, 3*A_PtrSize, 0)
        SizeInBytes := (StrLen(StringToSend) + 1) * (A_IsUnicode ? 2 : 1)
        NumPut(SizeInBytes, CopyDataStruct, A_PtrSize)
        NumPut(&StringToSend, CopyDataStruct, 2*A_PtrSize)
        SendMessage, this.WM_COPYDATA, 0, &CopyDataStruct,, ahk_pid %target_hwnd%
        if (ErrorLevel == "FAIL" || ErrorLevel == 0) {
            MsgBox, , % "ZipChord", % "Error: Could not send the command to ZipChord."
        }
    }
}

Receive_WM_COPYDATA(_, lParam) {
    StringAddress := NumGet(lParam + 2*A_PtrSize)
    option_string := StrGet(StringAddress)
    call := Func("ProcessCommandLine").Bind(option_string)
    SetTimer, %call%, -10
    return true
}

ProcessCommandLine(option_string) {
    parsed := StrSplit(option_string, "`n")
    raw_command :=  parsed[1]
    StringLower, command, raw_command
    filename := parsed[2]
    switch (command) {
        case "load":
            config.SwitchDuringRuntime(str.FilenameWithExtension(filename))
        case "save":
            config.Save(str.FilenameWithExtension(filename))
        case "pause":
            if (settings.mode & MODE_ZIPCHORD_ENABLED) {
                PauseApp()
            }
        case "resume":
            if !(settings.mode & MODE_ZIPCHORD_ENABLED) {
                PauseApp()
            }
        case "follow":
            config.LoadMappingFile(str.FilenameWithExtension(filename, ".txt"))
        case "restore":
            config.use_mapping := false
            config.SwitchDuringRuntime()
            hint_UI.ShowOnOSD("Restored settings", "to normal")
        Default:
            MsgBox, , % "ZipChord", % "You can use command line options as follows:`n`n"
            . "zipchord {load|save} <config_file.ini>`n"
            . "zipchord follow <mapping_file.txt>`n"
            . "zipchord {pause|resume}`n"
            . "zipchord restore"
    }
}

CloseAllWindows() {
    window_names := ["locale_UI", "add_shortcut", "main_UI"]

    For _, window in window_names {
        if (WinExist("ahk_id " . %window%.UI._handle)) {
            %window%.Close()
            exists := true
        } else {
            exists := false
        }
    }
    return exists
}
