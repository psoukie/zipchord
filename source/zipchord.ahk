/*

ZipChord

A customizable hybrid keyboard input method that augments regular typing with
chords and shorthands.

Copyright (c) 2021-2024 Pavel Soukenik

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
ListLines Off
SetKeyDelay -1, -1
CoordMode ToolTip, Screen
OnExit("CloseApp")

#Include version.ahk
#Include shared.ahk

; Handle messages from second instance in order to support command line manipulation of running script
instance_handler := new clsInstanceHandler
WM_COPYDATA := 0x004A
OnMessage(WM_COPYDATA, "Receive_WM_COPYDATA")

; Settings constants and class

global CAP_OFF      := 1 ; no auto-capitalization,
     , CAP_CHORDS   := 2 ; auto-capitalize chords only
     , CAP_ALL      := 3 ; auto-capitalize all typing
     , SPACE_BEFORE_CHORD := 1
     , SPACE_AFTER_CHORD  := 2
     , SPACE_PUNCTUATION  := 4
     , CHORD_DELETE_UNRECOGNIZED  := 1  ; Delete typing that triggers chords that are not in dictionary?
     , CHORD_ALLOW_SHIFT          := 2  ; Allow Shift in combination with at least two other keys to form unique chords?
     , CHORD_RESTRICT             := 4  ; Disallow chords (except for suffixes) if the chord isn't separated from typing by a space, interruption, or defined punctuation "opener" 
     , CHORD_IMMEDIATE_SHORTHANDS := 8  ; Shorthands fire without waiting for space or punctuation 

global MODE_CHORDS_ENABLED     := 1
     , MODE_SHORTHANDS_ENABLED := 2
     , MODE_ZIPCHORD_ENABLED   := 4

global PREF_SHOW_CLOSING_TIP := 2        ; show tip about re-opening the main dialog and adding chords
     , PREF_FIRST_RUN        := 4        ; this value means this is the first run (there is no saved config)

global UI_STR_PAUSE  := "&Pause ZipChord"
     , UI_STR_RESUME := "&Resume ZipChord"

app_settings := New clsSettings()
global settings := app_settings.settings

#Include app_shortcuts.ahk
#Include configurations.ahk
#Include hints.ahk
#Include locale.ahk
#Include dictionaries.ahk
#Include io.ahk

if (A_Args[1] == "dev") {
    #Include *i visualizer.ahk
    #Include *i testing.ahk
}

global runtime_status := { is_keyboard_wired: false
                         , config_file      : false}

special_key_map   := {} ; TK: Move to locale. Stores special keys that are defined as "{special_key:*}" or "{special_key=*}" (which can be used in the definition of all keys in the UI). The special_key can be something like "PrintScreen" and the asterisk is the character of how it's interpreted (such as "|").

global main_UI := new clsMainUI


Initialize(zc_version)
Return   ; Prevent execution of any of the following code, except for the always-on keyboard shortcuts below.

; Application settings
Class clsSettings {
    settings_file := A_AppData . "\ZipChord\config.ini"
    settings := { version:          0 ; gets loaded and saved later
                , mode:             MODE_ZIPCHORD_ENABLED | MODE_CHORDS_ENABLED | MODE_SHORTHANDS_ENABLED
                , preferences:      PREF_FIRST_RUN | PREF_SHOW_CLOSING_TIP
                , locale:           "English US"
                , capitalization:   CAP_CHORDS
                , spacing:          SPACE_BEFORE_CHORD | SPACE_AFTER_CHORD | SPACE_PUNCTUATION 
                , chording:         CHORD_RESTRICT ; Chord recognition options
                , chord_file:       "chords-en-starting.txt" ; file name for the chord dictionary
                , shorthand_file:   "shorthands-en-starting.txt" ; file name for the shorthand dictionary
                , dictionary_dir:   A_ScriptDir
                , input_delay:      70
                , output_delay:     0 }
    GetSettingsFile() {
        return runtime_status.config_file ? runtime_status.config_file : this.settings_file
    }
    GetSectionName() {
        return runtime_status.config_file ? "Application" : "Default"
    }
    Register(setting_name, value := 0) {
        if (this.settings.HasKey(setting_name)) {
            return false
        }
        this.settings[setting_name] := value
    }
    Load() {
        ini.LoadProperties(this.settings, this.GetSectionName(), this.GetSettingsFile())
        this.mode |= MODE_ZIPCHORD_ENABLED ; settings are read at app startup, so we re-enable ZipChord if it was paused when closed 
    }
    Save() {
        if (runtime_status.config_file) {
            this.settings.locale := false
        }
        ini.SaveProperties(this.settings, this.GetSectionName(), this.GetSettingsFile())
    }
}

;; Initilization and Wiring
; ---------------------------

Initialize(zc_version) {
    global app_settings
    global app_shortcuts
    global locale
    ; save license file
    ini.SaveLicense()
    app_settings.Load()
    ; check whether we need to upgrade existing settings file:
    if ( ! (settings.preferences & PREF_FIRST_RUN) && CompareSemanticVersions(zc_version, settings.version) ) {
        UpdateSettings(settings.version)
    }
    settings.version := zc_version
    app_shortcuts.Init()
    SetWorkingDir, % settings.dictionary_dir
    settings.chord_file := CheckDictionaryFileExists(settings.chord_file, "chord")
    settings.shorthand_file := CheckDictionaryFileExists(settings.shorthand_file, "shorthand")
    app_settings.Save()
    main_UI.Build()
    locale.Init()
    keys.Load(settings.locale)
    main_UI.Show()
    UI_Tray_Build()
    locale.Build()
    hint_UI.Build()
    if (A_Args[1] == "load" && A_Args[2]) {
        ProcessCommandLine(A_Args[1] . "`n" . A_Args[2])
    }
    chords.Load(settings.chord_file)
    shorthands.Load(settings.shorthand_file)
    main_UI.UpdateDictionaryUI()
    main_UI.UI.Enable()
    WireHotkeys("On")
}

UpdateSettings(from_version) {
    if (CompareSemanticVersions("2.3.0", from_version)) {
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
        MsgBox, , % "ZipChord", % "ZipChord can now show your typing efficiency.`n`n"
                . "You can change the setting on the Hints tab."
    }
}

; WireHotKeys(["On"|"Off"]): Creates or releases hotkeys for tracking typing and chords
WireHotkeys(state) {
    global keys
    global special_key_map
    interrupts := "Del|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|LButton|RButton|Tab" ; keys that interrupt the typing flow
    new_keys := {}
    bypassed_keys := {}
    ParseKeys(keys.all, new_keys, bypassed_keys, special_key_map)
    For _, key in new_keys
    {
        Hotkey, % "~" key, KeyDown, %state% UseErrorLevel
        If ErrorLevel {
            if (state=="On")     
                unrecognized .= key 
            Continue
        }
        Hotkey, % "~+" key, KeyDown, %state%
        Hotkey, % "~" key " Up", KeyUp, %state%
        Hotkey, % "~+" key " Up", KeyUp, %state%
    }
    if (unrecognized) {
        key_str := StrLen(unrecognized)>1 ? "keys" : "key"
        MsgBox, , % "ZipChord", % Format("The current keyboard layout does not match ZipChord's Keyboard and Language settings. "
                . "ZipChord will not detect the following {}: {}`n`nEither change your keyboard layout, or change "
                . "the custom keyboard layout for your current ZipChord dictionary.", key_str, unrecognized)
    }
    Hotkey, % "~Space", KeyDown, %state%
    Hotkey, % "~+Space", KeyDown, %state%
    Hotkey, % "~Space Up", KeyUp, %state%
    Hotkey, % "~+Space Up", KeyUp, %state%
    Hotkey, % "~Shift", Shift_key, %state%
    Hotkey, % "~Shift Up", Shift_key, %state%
    Hotkey, % "~Enter", Enter_key, %state%
    Hotkey, % "~Backspace", Backspace_key, %state%
    Loop Parse, % interrupts , |
    {
        Hotkey, % "~" A_LoopField, Interrupt, %state%
        Hotkey, % "~^" A_LoopField, Interrupt, %state%
    }
    For _, key in bypassed_keys
    {
        Hotkey, % key, KeyDown, %state% UseErrorLevel
        If ErrorLevel {
            MsgBox, , ZipChord, The current keyboard layout does not include the unmodified key '%key%'. ZipChord will not be able to recognize this key.`n`nEither change your keyboard layout, or change the custom keyboard layout for your current ZipChord dictionary.
            Continue
        }
        Hotkey, % "+" key, KeyDown, %state%
        Hotkey, % key " Up", KeyUp, %state%
        Hotkey, % "+" key " Up", KeyUp, %state%
    }
    runtime_status.is_keyboard_wired := state
}

; Translates the raw "old" list of keys into two new lists usable for setting hotkeys ("new" and "bypassed"), returning the special key mapping in the process
ParseKeys(old, ByRef new, ByRef bypassed, ByRef map) {
    new := StrSplit( RegExReplace(old, "\{(.*?)\}", "") )   ; array with all text in between curly braces removed
    segments := StrSplit(old, "{")
    For i, segment in segments {
        if (i > 1) {
            key_definition := StrSplit(segment, "}", , 2)[1] ; the text which was in curly braces
            if (InStr(key_definition, ":")) {
                divider := ":"
                target := new
            } else {
                divider := "="
                target := bypassed
            }
            def_components := StrSplit(key_definition, divider)
            target.push(def_components[1])
            ObjRawSet(map, def_components[1], def_components[2])
        }
    }
}

OutputKeys(output) {
    if (A_Args[1] == "dev") {
        test.Log(output)
        if (test.mode == TEST_RUNNING)
            return
    }
    SendInput % output
}

CloseApp() {
    WireHotkeys("Off")
    ExitApp
}

;; Shortcuts 
; ---------------------

Shift_key:
    Critical
    if (A_PriorHotkey != "~Shift") {
        return
    }
    key := "*Shift*"
    tick := A_TickCount
    if (A_Args[1] == "dev") {
        if (test.mode > TEST_STANDBY) {
            test.Log(key, true)
        }
    }
    if (visualizer.IsOn()) {
        visualizer.Pressed("+", false)
        visualizer.Lifted("+", false)
    }
    io.PreShift()
    Critical Off
Return

Simulate_Shift:
    io.PreShift()
Return

KeyDown:
    Critical
    key := A_ThisHotkey
    tick := A_TickCount
    if (A_Args[1] == "dev") {
        if (test.mode == TEST_RUNNING) {
            key := test_key
            tick := test_timestamp
        }
        if (test.mode > TEST_STANDBY) {
            test.Log(key, true)
            test.Log(key)
        }
    }
    if ( special_key_map.HasKey(key) ) {
        key := "|" . special_key_map[key]
    }
    if (visualizer.IsOn()) {
        modified_key := StrReplace(key, "Space", " ")
        if (SubStr(modified_key, 1, 1) == "~")
            modified_key := SubStr(modified_key, 2)
        ; First, we differentiate if the key was pressed while holding Shift, and store it under 'modified_key':
        if ( StrLen(modified_key)>1 && SubStr(modified_key, 1, 1) == "+" ) {
            shifted := true
            modified_key := SubStr(modified_key, 2)
        } else {
            shifted := false
        }
        visualizer.Pressed(modified_key, shifted)
    }
    ; QPC()
    classifier.Input(key, tick)
    ; QPC()
    Critical Off
Return

KeyUp:
    Critical
    tick_up := A_TickCount
    key := A_ThisHotkey
    if (A_Args[1] == "dev") {
        if (test.mode == TEST_RUNNING) {
            tick_up := test_timestamp
            key := test_key
        }
        if (test.mode > TEST_STANDBY) {
            test.Log(A_ThisHotkey, true)
        }
    }
    stripped := SubStr(key, 1, StrLen(key) - 3)
    if ( special_key_map.HasKey(stripped) ) {
        key := "|" . special_key_map[stripped] . " Up"
    }
    if (visualizer.IsOn()) {
        modified_key := StrReplace(key, "Space", " ")
        if (SubStr(modified_key, 1, 1) == "~")
            modified_key := SubStr(modified_key, 2)
        if ( StrLen(modified_key)>1 && SubStr(modified_key, 1, 1) == "+" ) {
            shifted := true
            modified_key := SubStr(modified_key, 2)
        } else {
            shifted := false
        }
        visualizer.Lifted(SubStr(modified_key, 1, 1), shifted)
    }
    ; QPC()
    classifier.Input(key, tick_up)
    ; QPC()
    Critical Off
Return

Interrupt:
    classifier.Interrupt()
    if (A_Args[1] == "dev") {
        if (test.mode > TEST_STANDBY) {
            test.Log("*Interrupt*", true)
            test.Log("*Interrupt*")
        }
    }
Return

Enter_key:
    classifier.Interrupt("~Enter")
    if (A_Args[1] == "dev") {
        if (test.mode > TEST_STANDBY) {
            test.Log("~Enter", true)
            test.Log("~Enter")
        }
        if (visualizer.IsOn())
            visualizer.NewLine()
    }
Return

Backspace_key:
    Critical
    key := "~Backspace"
    tick := A_TickCount
    if (A_Args[1] == "dev") {
        if (test.mode > TEST_STANDBY) {
            test.Log(key, true)
            test.Log(key)
        }
    }
    if (visualizer.IsOn()) {
        visualizer.Pressed(Chr(0x232B), false)
        visualizer.Lifted(Chr(0x232B), false)
    }
    io.Backspace()
    Critical Off
Return

;;  Adding shortcuts 
; -------------------

; Define a new shortcut for the selected text (or check what it is for existing)
AddShortcut() {
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
    controls := { tabs:                 { type: "Tab3"
                                        , text: " Dictionaries | Detection | Hints | Output | About "}
                , selected_locale:      { type: "DropDownList"
                                        , text: "&Keyboard and language"}
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
                , output_delay:         { type: "Edit"
                                        , text: "99"}
                , restrict_chords:      { type: "Checkbox"
                                        , text: "&Restrict chords while typing"
                                        , setting: { parent: "chording", const: "CHORD_RESTRICT"}}
                , allow_shift:          { type: "Checkbox"
                                        , text: "Allow &Shift in chords"
                                        , setting: { parent: "chording", const: "CHORD_ALLOW_SHIFT"}}
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
                , btn_customize_hints:  { type: "Button"
                                        , function: ObjBindMethod(this, "ShowHintCustomization")
                                        , text: "&Adjust >>"}
                , hint_offset_x:        { type: "Edit" }
                , hint_offset_y:        { type: "Edit" }
                , hint_size:            { type: "Edit" }
                , hint_color:           { type: "Edit" }
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
                , debugging:            { type: "Checkbox"
                                        , text: "&Log this session (debugging)"} 
                , btn_pause:            { type: "Button"
                                        , function: Func("PauseApp").Bind(true)
                                        , text: UI_STR_PAUSE} }
    labels := []
    closing_tip := 0

    ; Prepare UI
    Build() {
        global zc_version
        global zc_year
        cts := this.controls
        UI := new clsUI("ZipChord")
        UI.on_close := ObjBindMethod(this, "Close")

        UI.Add(cts.tabs)
        UI.Add("Text", "y+20 Section", "&Keyboard and language")
        UI.Add(cts.selected_locale, "y+10 w150")
        UI.Add("Button", "x+20 w100", "C&ustomize", ObjBindMethod(this, "_btnCustomizeLocale"))
        this._BuilderHelper(UI, "chord", "&Open", "&Edit", "&Reload", "xs y+20")
        this._BuilderHelper(UI, "shorthand", "Ope&n", "Edi&t", "Reloa&d", "xs-20 y+30")

        UI.Tab(2)
        UI.Add("GroupBox", "y+20 w310 h175", "Chords")
        UI.Add("Text", "xp+20 yp+30 Section", "&Detection delay (ms)")
        UI.Add(cts.input_delay, "Right xp+200 yp-2 w40 Number")
        UI.Add(cts.restrict_chords, "xs")
        UI.Add(cts.allow_shift)
        UI.Add(cts.delete_unrecognized)
        UI.Add("GroupBox", "xs-20 y+40 w310 h70", "Shorthands")
        UI.Add(cts.immediate_shorthands, "xp+20 yp+30 Section")
        
        UI.Tab(3)
        UI.Add("Text", "y+20 Section", "&Show hints")
        UI.Add(cts.hint_frequency, "AltSubmit xp+150 w140")
        UI.Add("Text", "xs", "Hint &location")
        UI.Add(cts.hint_destination, "AltSubmit xp+150 w140")
        UI.Add(cts.hint_score, "xs")
        UI.Add(cts.btn_customize_hints, "xs w100")
        this.labels[1] := UI.Add("GroupBox", "xs y+20 w310 h200 Section", "Hint customization")
        this.labels[2] := UI.Add("Text", "xp+20 yp+30 Section", "Horizontal offset (px)")
        this.labels[3] := UI.Add("Text", , "Vertical offset (px)")
        this.labels[4] := UI.Add("Text", , "OSD font size (pt)")
        this.labels[5] := UI.Add("Text", , "OSD color (hex code)")
        UI.Add(cts.hint_offset_x, "ys xp+200 w70 Right")
        UI.Add(cts.hint_offset_y, "w70 Right")
        UI.Add(cts.hint_size, "w70 Right Number")
        UI.Add(cts.hint_color, "w70 Right")

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
        UI.Add("Text", , "Copyright © 2021–" . zc_year . " Pavel Soukenik")
        UI.Add("Text", , "version " . zc_version)
        UI.Font("underline cBlue")
        UI.Add("Text", , "License information", Func("LinkToLicense"))
        UI.Add("Text", , "Help and documentation", Func("LinkToDocumentation"))
        UI.Add("Text", , "Latest releases (check for updates)", Func("LinkToReleases"))
        UI.Font("norm cDefault")
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
    _BuilderHelper(UI, name_modifier, s_open, s_edit, s_reload, options) {
        cts := this.controls
        UI.Add(cts[name_modifier . "_entries"], options . " w310 h135")
        UI.Add(cts[name_modifier . "_file"], "xp+20 yp+30 Section w270")
        UI.Add("Button", "xs w80 Section", s_open, ObjBindMethod(this, "_btnSelectDictionary", name_modifier))
        UI.Add("Button", "ys w80", s_edit, ObjBindMethod(this, "_btnEditDictionary", name_modifier))
        UI.Add("Button", "ys w80", s_reload, ObjBindMethod(this, "_btnReloadDictionary", name_modifier))
        UI.Add(cts[name_modifier . "_enabled"], "xs")
    }

    Show() {
        cts := this.controls
        if (A_Args[1] == "dev" && cts.debugging.value) {
            FinishDebugging()
        }
        cts.debugging.value := 0 ; debugging is always set to disabled
        call := ObjBindMethod(this, "_Help")
        Hotkey, F1, % call, On
        cts.input_delay.value := settings.input_delay
        cts.output_delay.value := settings.output_delay
        ; Loop through each control and apply settings from its defined corresponding setting 
        for _, control in this.controls {
            if (control.HasKey("setting")) {
                const_name := control.setting.const
                control.value := (settings[control.setting.parent] & %const_name%) ? 1 : 0
            }
        }
        cts.capitalization.Choose(settings.capitalization)
        cts.btn_pause.value := (settings.mode & MODE_ZIPCHORD_ENABLED) ? UI_STR_PAUSE : UI_STR_RESUME
        cts.hint_frequency.Choose( OrdinalOfHintFrequency() + 1)
        cts.hint_destination.Choose( (settings.hints & (HINT_OSD | HINT_TOOLTIP)) // HINT_OSD) ; calculate the option's position; relies on HINT_TOOLTIP being << from HINT_OSD
        cts.hint_offset_x.value := settings.hint_offset_x
        cts.hint_offset_y.value := settings.hint_offset_y
        cts.hint_size.value := settings.hint_size
        cts.hint_color.value := settings.hint_color
        this.ShowHintCustomization(false)
        this.HintEnablement(true)
        cts.tabs.Choose(1) ; switch to first tab
        this.UpdateLocaleInMainUI(settings.locale)
        main_UI.UpdateDictionaryUI()
        this.UI.Show()
        if (runtime_status.config_file) {
            this.UI.SetTitle("ZipChord - " . str.BareFilename(runtime_status.config_file))
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
        settings.output_delay := cts.output_delay.value + 0
        settings.capitalization := cts.capitalization.value
        settings.spacing := cts.space_before.value * SPACE_BEFORE_CHORD
                            + cts.space_after.value * SPACE_AFTER_CHORD
                            + cts.space_punctuation.value * SPACE_PUNCTUATION
        settings.chording := cts.delete_unrecognized.value * CHORD_DELETE_UNRECOGNIZED
                            + cts.allow_shift.value * CHORD_ALLOW_SHIFT
                            + cts.restrict_chords.value * CHORD_RESTRICT
                            + cts.immediate_shorthands.value * CHORD_IMMEDIATE_SHORTHANDS
        settings.locale := cts.selected_locale.value
        ; settings.mode carries over the current ZIPCHORD_ENABLED setting
        settings.mode := (settings.mode & MODE_ZIPCHORD_ENABLED)
                        + cts.chord_enabled.value * MODE_CHORDS_ENABLED
                        + cts.shorthand_enabled.value * MODE_SHORTHANDS_ENABLED
        ; recalculate hint settings based on frequency (HINT_OFF etc.) and OSD/Tooltip. ( ** is exponent function in AHK)
        settings.hints := 2**(cts.hint_frequency.value - 1) + 16 * cts.hint_destination.value
                            + cts.hint_score.value * HINT_SCORE
        if ( (temp:=this._SanitizeNumber(cts.hint_offset_x.value)) == "ERROR") {
            MsgBox ,, % "ZipChord", % "The offset needs to be a positive or negative number."
            Return false
        } else settings.hint_offset_x := temp
        if ( (temp:=this._SanitizeNumber(cts.hint_offset_y.value)) == "ERROR") {
            MsgBox ,, % "ZipChord", % "The offset needs to be a positive or negative number."
            Return false
        } else settings.hint_offset_y := temp
        settings.hint_size := cts.hint_size.value
        if ( (temp:=this._SanitizeNumber(cts.hint_color.value, true)) =="ERROR") {
            MsgBox ,, % "ZipChord", % "The color needs to be entered as hex code, such as '34cc97' or '#34cc97'."
            Return false
        } else settings.hint_color := temp
        ; ...and save them to config.ini
        app_settings.Save()
        ; We always want to rewire hotkeys in case the keys have changed.
        WireHotkeys("Off")
        keys.Load(settings.locale)
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
                MsgBox, , % "ZipChord", % "You can type in a text editor to create a log of input and output.`n`nSimply reopen the ZipChord dialog when done to stop the logging process and save the debug file."
            }
            FileDelete, % A_Temp . "\debug.cfg"
            FileDelete, % A_Temp . "\debug.in"
            FileDelete, % A_Temp . "\debug.out"
            test.Path("set", A_Temp)
            test.Config("save", "debug")
            test.Record("both", "debug")
        }
        ; reflect any changes to OSD UI
        reset_hint_fn := ObjBindMethod(hint_UI, "Reset")
        SetTimer, %reset_hint_fn%, -2000
        Return true
    }

    UpdateLocaleInMainUI(selected_loc) {
        if (runtime_status.config_file) {
            this.controls.selected_locale.value := str.BareFilename(runtime_status.config_file) . "||"
            main_UI.controls.selected_locale.Disable()
            return
        }
        main_UI.controls.selected_locale.Enable()
        sections := ini.LoadSections()
        this.controls.selected_locale.value := "|" StrReplace(sections, "`n", "|")
        this.controls.selected_locale.Choose(selected_loc)
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
        entriesstr := uppercased . " dictionary (" %pluralized%.entries
        entriesstr .= (chords.entries==1) ? " " . type . ")" : " " . pluralized . ")"
        cts[type . "_entries"].value := entriesstr 
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
        global locale
        WireHotkeys("Off")  ; so the user can edit the values without interference
        this.UI.Disable()
        locale.Show(this.controls.selected_locale.value)
    }
 
    _btnSelectDictionary(type_string) {
        type := type_string == "chord" ? "chord" : "shorthand"
        StringUpper, uppercased, type, T
        heading := "Open " . uppercased . " Dictionary"
        FileSelectFile dict, , % settings.dictionary_dir, %heading%, Text files (*.txt)
        if (dict == "") {
            return
        }
        settings[type . "_file"] := dict
        pluralized := type . "s"
        %pluralized%.Load(dict)
        this.UpdateDictionaryUI()
    }
    _btnEditDictionary(type) {
        Run % settings[type . "_file"]
    }
    ; Reload a (modified) dictionary file; rewires hotkeys because of potential custom keyboard setting
    _btnReloadDictionary(type) {
        pluralized := type . "s"
        %pluralized%.Load()
        main_UI.UpdateDictionaryUI()
    }
    ; Process input to ensure it is an integer (or a color hex code if the second parameter is true), return number or "ERROR" 
    _SanitizeNumber(orig, hex_color := false) {
        sanitized := Trim(orig)
        format := "integer"
        if (hex_color) {
            format := "xdigit"
            if (SubStr(orig, 1, 1) == "#")
                sanitized := SubStr(orig, 2)
            if (StrLen(sanitized)!=6)
                return "ERROR"
        }
        if sanitized is %format%
            return sanitized
        else
            return "ERROR"
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

    ; Create taskbar tray menu:
UI_Tray_Build() {
    global app_shortcuts
    Menu, Tray, NoStandard
    Menu, Tray, Add, % "Open ZipChord", ShowMainUI
    Menu, Tray, Add, % "Add Shortcut", AddShortcut
    Menu, Tray, Add, % "Pause ZipChord", PauseApp
    Menu, Tray, Add  ;  adds a horizontal line
    fn := ObjBindMethod(app_shortcuts, "Show")
    Menu, Tray, Add, % "Customize app shortcuts", % fn
    Menu, Tray, Add  ;  adds a horizontal line
    if (A_Args[1] == "dev") {
        Menu, Tray, Add, % "Open Key Visualizer", OpenKeyVisualizer
        Menu, Tray, Add, % "Open Test Console", OpenTestConsole
        Menu, Tray, Add
    }
    Menu, Tray, Add, % "Quit", QuitApp
    Menu, Tray, Default, 1&
    Menu, Tray, Tip, % "ZipChord"
    Menu, Tray, Click, 1
    UI_Tray_Update()
}

UI_Tray_Update() {
    global app_shortcuts
    Menu, Tray, Rename, 1&, % "Open ZipChord`t" . app_shortcuts.GetHotkeyText("ShowMainUI")
    Menu, Tray, Rename, 2&, % "Add Shortcut`t" . app_shortcuts.GetHotkeyText("AddShortcut")
    string :=  (settings.mode & MODE_ZIPCHORD_ENABLED) ? "Pause" : "Resume"
    Menu, Tray, Rename, 3&, % string . " ZipChord`t" . app_shortcuts.GetHotkeyText("PauseApp")
    i := 7
    if (A_Args[1] == "dev")
        i += 3
    Menu, Tray, Rename, %i%&, % "Quit`t" . app_shortcuts.GetHotkeyText("QuitApp")
}

PauseApp(from_button := false) {
    if (settings.mode & MODE_ZIPCHORD_ENABLED) {
        settings.mode := settings.mode & ~MODE_ZIPCHORD_ENABLED
        mode := false
    } else {
        settings.mode := settings.mode | MODE_ZIPCHORD_ENABLED
        mode := true
    }
    main_UI.controls.btn_pause.value := mode ? UI_STR_PAUSE : UI_STR_RESUME
    state := mode ? "On" : "Off"
    if (from_button != true) {
        hint_UI.ShowOnOSD("ZipChord Keyboard", state)
    }
    WireHotkeys(state)
    UI_Tray_Update()
    main_UI.controls.tabs.Enable(mode)
}

QuitApp() {
    WireHotkeys("Off")
    hint_UI.ShowOnOSD("Closing ZipChord")
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
        global app_shortcuts
        this.UI := new clsUI("ZipChord")
        this.UI.on_close := ObjBindMethod(this, "Close")
        this.UI.Margin(20, 20)
        this.UI.Add("Text", "+Wrap w430"
            , Format("Select a word and {} to define a shortcut for it.`n`n{} to open the ZipChord menu again.`n`n"
                    . "Press F1 in any ZipChord tab or window for help." 
            , app_shortcuts.GetHotkeyText("AddShortcut", "press ", "press and hold ")
            , app_shortcuts.GetHotkeyText("ShowMainUI", "Press ", "Press and hold ")))
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
    global locale
    global app_shortcuts

    if (WinExist("ahk_id " . locale.UI._handle)) {
        locale._Close()
    }
    if (WinExist("ahk_id " . add_shortcut._handle)) {
        add_shortcut.Close()
    }
    if (WinExist("ahk_id " . app_shortcuts._handle)) {
        app_shortcuts._CloseUI()
    }
    if (WinExist("ahk_id " . main_UI.UI._handle)) {
        main_UI._Close()
        return true
    }
}