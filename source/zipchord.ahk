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
#SingleInstance Force
#MaxThreadsPerHotkey 1
#MaxThreadsBuffer On
#KeyHistory 0
ListLines Off
SetKeyDelay -1, -1
CoordMode ToolTip, Screen
OnExit("CloseApp")

#Include version.ahk
#Include shared.ahk
#Include app_shortcuts.ahk
#Include locale.ahk
#Include dictionaries.ahk
#Include io.ahk

if (A_Args[1] == "dev") {
    #Include *i visualizer.ahk
    #Include *i testing.ahk
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

;; Classes and Variables
; -----------------------


; This is used in code dynamically to store complex keys that are defined as "{special_key:*}" or "{special_key=*}" (which can be used in the definition of all keys in the UI). The special_key can be something like "PrintScreen" and the asterisk is the character of how it's interpreted (such as "|").
special_key_map := {}

global main_UI := new clsMainUI
global hint_UI := new clsHintUI

; affixes constants
global AFFIX_NONE := 0 ; no prefix or suffix
    , AFFIX_PREFIX := 1 ; expansion is a prefix
    , AFFIX_SUFFIX := 2 ; expansion is a suffix

; Settings constants and class

; capitalization constants
global CAP_OFF = 1 ; no auto-capitalization,
    , CAP_CHORDS = 2 ; auto-capitalize chords only
    , CAP_ALL = 3 ; auto-capitalize all typing
; smart spacing constants
global SPACE_BEFORE_CHORD := 1
    , SPACE_AFTER_CHORD := 2
    , SPACE_PUNCTUATION := 4
; Chord recognition constants
global CHORD_DELETE_UNRECOGNIZED := 1 ; Delete typing that triggers chords that are not in dictionary?
    , CHORD_ALLOW_SHIFT := 2  ; Allow Shift in combination with at least two other keys to form unique chords?
    , CHORD_RESTRICT := 4      ; Disallow chords (except for suffixes) if the chord isn't separated from typing by a space, interruption, or defined punctuation "opener" 
    , CHORD_IMMEDIATE_SHORTHANDS := 8   ; Shorthands fire without waiting for space or punctuation 

; Hints preferences and object
global HINT_ON := 1
    , HINT_ALWAYS := 2
    , HINT_NORMAL := 4
    , HINT_RELAXED := 8
    , HINT_OSD := 16
    , HINT_TOOLTIP := 32
global GOLDEN_RATIO := 1.618
global DELAY_AT_START := 2000

Class HintTimingClass {
    ; private variables
    _delay := DELAY_AT_START   ; this varies based on the hint frequency and hints shown
    _next_tick := A_TickCount  ; stores tick time when next hint is allowed
    ; public functions
    HasElapsed() {
        if (settings.hints & HINT_ALWAYS || A_TickCount > this._next_tick)
            return True
        else
            return False
    }
    Extend() {
        if (settings.hints & HINT_ALWAYS)
            Return
        this._delay := Round( this._delay * ( GOLDEN_RATIO**(OrdinalOfHintFrequency(-1) ) ) )
        this._next_tick := A_TickCount + this._delay
    }
    Shorten() {
        if (settings.hints & HINT_ALWAYS)
            Return
        if (settings.hints & HINT_NORMAL)
            this.Reset()
        else
            this._delay := Round( this._delay / 3 )
    }
    Reset() {
        this._delay := DELAY_AT_START
        this._next_tick := A_TickCount + this._delay
    }
}
hint_delay := New HintTimingClass

; Other preferences constants
global PREF_PREVIOUS_INSTALLATION := 1  ; this config value means that the app has been installed before
    , PREF_SHOW_CLOSING_TIP := 2        ; show tip about re-opening the main dialog and adding chords
    , PREF_FIRST_RUN := 4               ; this value means this is the first run of 2.1.0-beta.2 or higher)

global MODE_CHORDS_ENABLED := 1
    , MODE_SHORTHANDS_ENABLED := 2
    , MODE_ZIPCHORD_ENABLED := 4

; Current application settings
Class settingsClass {
    mode := MODE_ZIPCHORD_ENABLED | MODE_CHORDS_ENABLED | MODE_SHORTHANDS_ENABLED
    preferences := PREF_FIRST_RUN | PREF_SHOW_CLOSING_TIP
    locale := "English US"
    hints := HINT_ON | HINT_NORMAL | HINT_OSD
    hint_offset_x := 0
    hint_offset_y := 0
    hint_size := 32
    hint_color := "3BD511"
    capitalization := CAP_CHORDS
    spacing := SPACE_BEFORE_CHORD | SPACE_AFTER_CHORD | SPACE_PUNCTUATION  ; smart spacing options 
    chording := CHORD_RESTRICT ; Chord recognition options
    chord_file := "chords-en-starting.txt" ; file name for the chord dictionary
    shorthand_file := "shorthands-en-starting.txt" ; file name for the shorthand dictionary
    dictionary_dir := A_ScriptDir
    input_delay := 70
    output_delay := 0
    Read() {
        For key, value in this {
            UpdateVarFromConfig(value, key)
            this[key] := value
        }
        this.mode |= MODE_ZIPCHORD_ENABLED ; settings are read at app startup, so we re-enable ZipChord if it was paused when closed 
    }
    Write() {
        For key, value in this
            SaveVarToConfig(key, value)       
    }
}
global settings := New settingsClass

; Processing input and output 
chord_buffer := ""       ; stores the sequence of simultanously pressed keys
chord_candidate := ""    ; chord candidate which qualifies for chord
shorthand_buffer := ""   ; stores the sequence of uninterrupted typed keys
capitalize_shorthand := false  ; should the shorthand be capitalized
global start := 0 ; tracks start time of two keys pressed at once

; constants to track the difference between key presses and output (because of smart spaces and punctuation)
global DIF_NONE := 0
    , DIF_EXTRA_SPACE := 1
    , DIF_REMOVED_SMART_SPACE := 2
    , DIF_IGNORED_SPACE := 4
    , difference := DIF_NONE   ; tracks the difference between keys pressed and output (because of smart spaces and punctuation)
    , final_difference := DIF_NONE
; Constants for characteristics of last output
global OUT_CHARACTER := 1     ; output is a character
    , OUT_SPACE := 2         ; output was a space
    , OUT_PUNCTUATION := 4   ; output was a punctuation
    , OUT_AUTOMATIC := 8     ; output was automated (i.e. added by ZipChord, instead of manual entry). In combination with OUT_CHARACTER, this means a chord was output, in combination with OUT_SPACE, it means a smart space.
    , OUT_CAPITALIZE := 16   ; output requires capitalization of what follows
    , OUT_PREFIX := 32       ; output is a prefix (or opener punctuation) and doesn't need space in next chord (and can be followed by a chard in restricted mode)
    , OUT_SPACE_AFTER := 64  ; output is a punctuation that needs a space after it
    , OUT_INTERRUPTED := 128   ; output is unknown or it was interrupted by moving the cursor using cursor keys, mouse click etc.
; Because some of the typing is dynamically changed after it occurs, we need to distinguish between the last keyboard output which is already finalized, and the last entry which can still be subject to modifications.
global fixed_output := OUT_INTERRUPTED ; fixed output that preceded any typing currently being processed 
global last_output := OUT_INTERRUPTED  ; last output in the current typing sequence that could be in flux. It is set to fixed_input when there's no such output.
; also "new_output" local variable is used to track the current key / output


; UI string constants
global UI_STR_PAUSE := "&Pause ZipChord"
    , UI_STR_RESUME := "&Resume ZipChord"

Initialize()
Return   ; To prevent execution of any of the following code, except for the always-on keyboard shortcuts below:

; The rest of the code from here on behaves like in normal programming languages: It is not executed unless called from somewhere else in the code, or triggered by dynamically defined hotkeys.

;; Initilization and Wiring
; ---------------------------

Initialize() {
    global app_shortcuts
    global locale
    ; save license file
    ini.SaveLicense()
    app_shortcuts.Init()
    settings.Read()
    SetWorkingDir, % settings.dictionary_dir
    settings.chord_file := CheckDictionaryFileExists(settings.chord_file, "chord")
    settings.shorthand_file := CheckDictionaryFileExists(settings.shorthand_file, "shorthand")
    settings.Write()
    main_UI.Build()
    locale.Init()
    locale.Load(settings.locale)
    main_UI.Show()
    UI_Tray_Build()
    locale.Build()
    hint_UI.Build()
    chords.Load(settings.chord_file)
    shorthands.Load(settings.shorthand_file)
    main_UI.UpdateDictionaryUI()
    main_UI.UI.Enable()
    WireHotkeys("On")
}

; WireHotKeys(["On"|"Off"]): Creates or releases hotkeys for tracking typing and chords
WireHotkeys(state) {
    global keys
    global special_key_map
    global app_shortcuts
    interrupts := "Del|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|LButton|RButton|BS|Tab" ; keys that interrupt the typing flow
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
        MsgBox, , % "ZipChord", % Format("The current keyboard layout does not match ZipChord's Keyboard and Language settings. ZipChord will not detect the following {}: {}`n`nEither change your keyboard layout, or change the custom keyboard layout for your current ZipChord dictionary.", key_str, unrecognized)
    }
    Hotkey, % "~Space", KeyDown, %state%
    Hotkey, % "~+Space", KeyDown, %state%
    Hotkey, % "~Space Up", KeyUp, %state%
    Hotkey, % "~+Space Up", KeyUp, %state%
    Hotkey, % "~Enter", Enter_key, %state%
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
    app_shortcuts.WireHotkeys("On")
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


; Main code. This is where the magic happens. Tracking keys as they are pressed down and released:

;; Shortcuts Detection 
; ---------------------

Shift::
    Critical
    key := "~Shift"
    tick := A_TickCount
    if (A_Args[1] == "dev") {
        if (test.mode == TEST_RUNNING) {
            key := test_key
            tick := test_timestamp
        }
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
    last_output := OUT_INTERRUPTED
    fixed_output := last_output
    if (A_Args[1] == "dev") {
        if (test.mode > TEST_STANDBY) {
            test.Log("*Interrupt*", true)
            test.Log("*Interrupt*")
        }
    }
Return

Enter_key:
    classifier.Interrupt("~Enter")
    last_output := OUT_INTERRUPTED | OUT_CAPITALIZE | OUT_AUTOMATIC  ; the automatic flag is there to allow shorthands after Enter 
    fixed_output := last_output
    if (A_Args[1] == "dev") {
        if (test.mode > TEST_STANDBY) {
            test.Log("~Enter", true)
            test.Log("~Enter")
        }
        if (visualizer.IsOn())
            visualizer.NewLine()
    }
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
                , hints_show:           { type: "Checkbox"
                                        , text: "&Show hints for shortcuts in dictionaries"
                                        , setting: { parent: "hints", const: "HINT_ON"}}
                , hint_destination:     { type: "DropDownList"
                                        , text: "On-screen display|Tooltips"}
                , hint_frequency:       { type: "DropDownList"
                                        , text: "Always|Normal|Relaxed"}
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
        UI.on_close := ObjBindMethod(this, "_Close")

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
        UI.Add(cts.hints_show, "y+20 Section")
        UI.Add("Text", , "Hint &location")
        UI.Add(cts.hint_destination, "AltSubmit xp+150 w140")
        UI.Add("Text", "xs", "Hints &frequency")
        UI.Add(cts.hint_frequency, "AltSubmit xp+150 w140")
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
        cts.hint_destination.Choose( Round((settings.hints & (HINT_OSD | HINT_TOOLTIP)) / 16) ) ; recalculate to option's list position
        cts.hint_frequency.Choose( OrdinalOfHintFrequency() )
        cts.hint_offset_x.value := settings.hint_offset_x
        cts.hint_offset_y.value := settings.hint_offset_y
        cts.hint_size.value := settings.hint_size
        cts.hint_color.value := settings.hint_color
        this.ShowHintCustomization(false)
        cts.tabs.Choose(1) ; switch to first tab
        this.UpdateLocaleInMainUI(settings.locale)
        this.UI.Show()
    }

    _btnOK() {
        if (this._ApplySettings()) {
            this._Close()    
        }
        return
    }
    _ApplySettings() {
        global hint_delay
        global locale
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
        ; recalculate hint settings to HINT_ON, OSD/Tooltip, and frequency ( ** means ^ in AHK)
        settings.hints := cts.hints_show.value + 16 * cts.hint_destination.value + 2**cts.hint_frequency.value
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
        settings.Write()
        ; We always want to rewire hotkeys in case the keys have changed.
        WireHotkeys("Off")
        locale.Load(settings.locale)
        if (settings.mode > MODE_ZIPCHORD_ENABLED) {
            if (previous_mode-1 < MODE_ZIPCHORD_ENABLED) {
                hint_UI.ShowHint("ZipChord Keyboard", "On", , false)
            }
            WireHotkeys("On")
        }
        else if (settings.mode & MODE_ZIPCHORD_ENABLED) {
            ; Here, ZipChord is not paused, but chording and shorthands are both disabled
            hint_UI.ShowHint("ZipChord Keyboard", "Off", , false)
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

    _Close() {
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
        hint_UI.ShowHint("ZipChord Keyboard", state, , false)
    }
    WireHotkeys(state)
    UI_Tray_Update()
    main_UI.controls.tabs.Enable(mode)
}

QuitApp() {
    WireHotkeys("Off")
    hint_UI.ShowHint("Closing ZipChord", state, , false)
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

OrdinalOfHintFrequency(offset := 0) {
    frequency := settings.hints & (HINT_ALWAYS | HINT_NORMAL | HINT_RELAXED )
    frequency := Round(Log(frequency) / Log(2))  ; i.e. log base 2 gives us the desired setting as 1, 2 or 3
    Return frequency + offset
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
        this.UI.Margin(20, 20)
        this.UI.Add("Text", "+Wrap w430", Format("Select a word and {} to define a shortcut for it or to see its existing shortcuts.`n`n{} to open the ZipChord menu again.`n", app_shortcuts.GetHotkeyText("AddShortcut", "press ", "press and hold "), app_shortcuts.GetHotkeyText("ShowMainUI", "Press ", "Press and hold ")))
        this.UI.Add(this.dont_show)
        this.UI.Add("Button", "x370 w80 Default", "OK", ObjBindMethod(this, "Btn_OK"))
        this.UI.Show("w470")
    }
    Btn_OK() {
        if (this.dont_show.value) {
            settings.preferences &= ~PREF_SHOW_CLOSING_TIP
            settings.Write()
            this.UI.Destroy()
            this.UI := {}
        } else {
            this.UI.Hide()
        }
    }
}

;; Shortcut Hint UI
; -------------------

Class clsHintUI {
    UI := {}
    lines := []
    transparency := 0
    ; fallback coordinates if multimonitor detection fails
    pos_x := 0
    pos_y := 0
    _transparent_color := 0
    hide_OSD_fn := ObjBindMethod(this, "_HideOSD")

    transparent_color[] {
        get {
            return this._transparent_color
        }
    }
    SetTransparentColor(source_color) {
        Loop 3 {
            component := "0x" . SubStr(source_color, 2 * A_Index - 1, 2)
            component := component > 0x7f ? component - 1 : component + 1
            new_color .= Format("{:02x}", component)
        }
        this._transparent_color := new_color
    }

    Build() {
        hint_color := settings.hint_color
        this.SetTransparentColor(hint_color)
        this.UI := new clsUI("", "+LastFound +AlwaysOnTop -Caption +ToolWindow") ; +ToolWindow avoids a taskbar button and an alt-tab menu item.
        this.UI.Margin( Round(settings.hint_size/3), Round(settings.hint_size/3))
        this.UI.Color(this.transparent_color)
        this.UI.Font("s" . settings.hint_size . " c" . hint_color, "Consolas")
        ; auto-size the window
        Loop 3 {
            this.lines[A_Index] := this.UI.Add("Text", "Center", "WWWWWWWWWWWWWWWWWWWWW")
        }
        this.UI.Show("NoActivate Center")
        this.UI.SetTransparency(this.transparent_color, 1)
        ; Get and store position of the window in case multiple monitor detection positioning fails
        local_handle := this.UI._handle
        WinGetPos local_pos_x, local_pos_y, , , ahk_id %local_handle%
        this.pos_x := local_pos_x + settings.hint_offset_x
        this.pos_y := local_pos_y + settings.hint_offset_y
        this.UI.Hide()
    }

    Reset() {
        global hint_delay
        hint_delay.Reset()
        this.UI.Destroy()
        this.Build()
    }

    ShowHint(line1, line2:="", line3 :="", follow_settings := true) {
        global hint_delay
        if (A_Args[1] == "dev") {
            if (test.mode > TEST_STANDBY) {
                test.Log("*Hint*")
            }
            if (test.mode == TEST_RUNNING) {
                return
            }
        }
        hint_delay.Extend()
        if ( (settings.hints & HINT_TOOLTIP) && follow_settings) {
            this._GetCaret(x, y, , h)
            ToolTip % " " . ReplaceWithVariants(line2) . " `n " . ReplaceWithVariants(line3) . " "
                    , x-1.5*h+settings.hint_offset_x, y+1.5*h+settings.hint_offset_y
            hide_tooltip_fn := ObjBindMethod(this, "_HideTooltip")
            SetTimer, %hide_tooltip_fn%, -1800   ; hides the tooltip
        } else {
            this.fading := false
            this.transparency := 150
            this.lines[1].value := line1
            this.lines[2].value := ReplaceWithVariants(line2, follow_settings)
            this.lines[3].value := ReplaceWithVariants(line3)
            this.UI.Show("Hide NoActivate")
            coord := this._GetMonitorCenterForWindow()
            current_pos_x := coord.x ? coord.x + settings.hint_offset_x : this.pos_x
            current_pos_y := coord.y ? coord.y + settings.hint_offset_y : this.pos_y
            this.UI.Show("NoActivate X" . current_pos_x . "Y" . current_pos_y)
            this.UI.SetTransparency(this.transparent_color, this.transparency)
            hide_osd_fn := this.hide_OSD_fn
            SetTimer, %hide_osd_fn%, -1900
        }
    }

    _HideOSD() {
        this.fading := true
        if (this.fading && this.transparency > 1) {
            this.transparency -= 10
            this.UI.SetTransparency(this.transparent_color, this.transparency)
            hide_osd_fn := this.hide_OSD_fn
            SetTimer, %hide_osd_fn%, -100
            return
        }
        this.UI.Hide()
    }

    _HideTooltip() {
        Tooltip
    }

    ; The following function for getting caret position more reliably is from a post by plankoe at https://www.reddit.com/r/AutoHotkey/comments/ysuawq/get_the_caret_location_in_any_program/
    _GetCaret(ByRef X:="", ByRef Y:="", ByRef W:="", ByRef H:="") {
        ; UIA caret
        static IUIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
        ; GetFocusedElement
        DllCall(NumGet(NumGet(IUIA+0)+8*A_PtrSize), "ptr", IUIA, "ptr*", FocusedEl:=0)
        ; GetCurrentPattern. TextPatternElement2 = 10024
        DllCall(NumGet(NumGet(FocusedEl+0)+16*A_PtrSize), "ptr", FocusedEl, "int", 10024, "ptr*", patternObject:=0), ObjRelease(FocusedEl)
        if patternObject {
            ; GetCaretRange
            DllCall(NumGet(NumGet(patternObject+0)+10*A_PtrSize), "ptr", patternObject, "int*", 1, "ptr*", caretRange:=0), ObjRelease(patternObject)
            ; GetBoundingRectangles
            DllCall(NumGet(NumGet(caretRange+0)+10*A_PtrSize), "ptr", caretRange, "ptr*", boundingRects:=0), ObjRelease(caretRange)
            ; VT_ARRAY = 0x20000 | VT_R8 = 5 (64-bit floating-point number)
            Rect := ComObject(0x2005, boundingRects)
            if (Rect.MaxIndex() = 3) {
                X:=Round(Rect[0]), Y:=Round(Rect[1]), W:=Round(Rect[2]), H:=Round(Rect[3])
                return
            }
        }
        ; Acc caret
        static _ := DllCall("LoadLibrary", "Str","oleacc", "Ptr")
        idObject := 0xFFFFFFF8 ; OBJID_CARET
        if DllCall("oleacc\AccessibleObjectFromWindow", "Ptr", WinExist("A"), "UInt", idObject&=0xFFFFFFFF, "Ptr", -VarSetCapacity(IID,16)+NumPut(idObject==0xFFFFFFF0?0x46000000000000C0:0x719B3800AA000C81,NumPut(idObject==0xFFFFFFF0?0x0000000000020400:0x11CF3C3D618736E0,IID,"Int64"),"Int64"), "Ptr*", pacc:=0)=0 {
            oAcc := ComObjEnwrap(9,pacc,1)
            oAcc.accLocation(ComObj(0x4003,&_x:=0), ComObj(0x4003,&_y:=0), ComObj(0x4003,&_w:=0), ComObj(0x4003,&_h:=0), 0)
            X:=NumGet(_x,0,"int"), Y:=NumGet(_y,0,"int"), W:=NumGet(_w,0,"int"), H:=NumGet(_h,0,"int")
            if (X | Y) != 0
                return
        }
        ; default caret
        CoordMode Caret, Screen
        X := A_CaretX
        Y := A_CaretY
        W := 4
        H := 20
    }
    _GetMonitorCenterForWindow() {
        ; Uses code for getting monitor info by "kon" from https://www.autohotkey.com/boards/viewtopic.php?t=15501
        ;@ahk-neko-ignore-fn 1 line; at 4/30/2024, 11:46:07 AM ; var is assigned but never used.
        window_Handle := WinExist("A")
        ;@ahk-neko-ignore-fn 1 line; at 4/30/2024, 11:46:26 AM ; var is assigned but never used.
        OSD_handle := this.UI._handle
        VarSetCapacity(monitor_info, 40), NumPut(40, monitor_info)
        ;@ahk-neko-ignore-fn 1 line; at 4/22/2024, 9:51:25 AM ; var is assigned but never used.
        if ((monitorHandle := DllCall("MonitorFromWindow", "Ptr", window_Handle, "UInt", 1)) 
            && DllCall("GetMonitorInfo", "Ptr", monitorHandle, "Ptr", &monitor_info)) {
            monitor_left   := NumGet(monitor_info,  4, "Int")
            monitor_top    := NumGet(monitor_info,  8, "Int")
            monitor_right  := NumGet(monitor_info, 12, "Int")
            monitor_bottom := NumGet(monitor_info, 16, "Int")
            ; From code for multiple monitors by DigiDon from https://www.autohotkey.com/boards/viewtopic.php?t=31716 
            VarSetCapacity(rc, 16)
            DllCall("GetClientRect", "uint", OSD_handle, "uint", &rc)
            window_width := NumGet(rc, 8, "int")
            window_height := NumGet(rc, 12, "int")
            pos_x := (( monitor_right - monitor_left - window_width ) / 2) + monitor_left
            pos_y := (( monitor_bottom - monitor_top - window_height ) / 2) + monitor_top
        } else {
            pos_x := 0
            pos_y := 0
        }
        return {x: pos_x, y: pos_y}
    }
}