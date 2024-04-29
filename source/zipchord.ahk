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
    version := zc_version
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
    handle := main_UI.UI._handle
    Gui, %handle%:+Disabled ; for loading
    main_UI.Show()
    UI_Tray_Build()
    locale.Build()
    UI_OSD_Build()
    chords.Load(settings.chord_file)
    shorthands.Load(settings.shorthand_file)
    UpdateDictionaryUI()
    Gui, %handle%:-Disabled
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

; Main code. This is where the magic happens. Tracking keys as they are pressed down and released:

;; Shortcuts Detection 
; ---------------------

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
        visualizer.Pressed(modified_key)
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
        visualizer.Lifted(SubStr(modified_key, 1, 1))
    }
    ; QPC()
    classifier.Input(key, tick_up)
    ; QPC()
    Critical Off
Return


; Helper functions
; ------------------

ReplaceWithVariants(text, enclose_latin_letters:=false) {
    new_str := text
    new_str := StrReplace(new_str, "+", Chr(0x21E7))
    new_str := StrReplace(new_str, " ", Chr(0x2423))
    if (enclose_latin_letters) {
        Loop, 26
            new_str := StrReplace(new_str, Chr(96 + A_Index), Chr(0x1F12F + A_Index))
        new_str := RegExReplace(new_str, "(?<=.)(?=.)", " ")
    }
    Return new_str
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

; variables holding the UI elements and selections (These should technically all be named UI_Main_xyz but I am using UI_xyz as a shortcut for the main dialog vars)
global UI_input_delay
    , UI_output_delay
    , UI_space_before, UI_space_after, UI_space_punctuation
    , UI_delete_unrecognized
    , UI_hints_show, UI_hint_destination, UI_hint_frequency
    , UI_hint_offset_x, UI_hint_offset_y, UI_hint_size, UI_hint_color 
    , UI_btnCustomize, UI_hint_1, UI_hint_2, UI_hint_3, UI_hint_4, UI_hint_5
    , UI_immediate_shorthands
    , UI_capitalization
    , UI_allow_shift
    , UI_restrict_chords
    , UI_chord_file, UI_shorthand_file
    , UI_chord_entries
    , UI_shorthand_entries
    , UI_zipchord_btnPause
    , UI_tab
    , UI_debugging

/**
* Main Dialog UI Class
*
*/
Class clsMainUI {
    UI := {}
    controls := { selected_locale:      { type: "DropDownList"
                                        , text: "&Keyboard and language"}
                , chords_enabled:       { type: "Checkbox"
                                        , text: "Use &chords"}
                , shorthands_enabled:   { type: "Checkbox"
                                        , text: "Use &shorthands"}}
    ; Prepare UI
    Build() {
        global zc_version
        cts := this.controls
        UI := new clsUI("ZipChord")
        UI.on_close := ObjBindMethod(this, "_Close")
        UI.Add("Tab3", , " Dictionaries | Detection | Hints | Output | About ")
        UI.Add("Text", "y+20 Section", "&Keyboard and language")
        UI.Add(cts.selected_locale, "y+10 w150")
        UI.Add("Button", "x+20 w100", "C&ustomize", ObjBindMethod(this, "_btnCustomizeLocale"))
        Gui, Add, GroupBox, xs y+20 w310 h135 vUI_chord_entries, % "Chord dictionary"
        Gui, Add, Text, xp+20 yp+30 Section vUI_chord_file w270, % "Loading..."
        Gui, Add, Button, xs Section gBtnSelectChordDictionary w80, % "&Open"
        Gui, Add, Button, gBtnEditChordDictionary ys w80, % "&Edit"
        Gui, Add, Button, gBtnReloadChordDictionary ys w80, % "&Reload"
        UI.Add(cts.chords_enabled, "xs")
        Gui, Add, GroupBox, xs-20 y+30 w310 h135 vUI_shorthand_entries, % "Shorthand dictionary"
        Gui, Add, Text, xp+20 yp+30 Section vUI_shorthand_file w270, % "Loading..."
        Gui, Add, Button, xs Section gBtnSelectShorthandDictionary w80, % "Ope&n"
        Gui, Add, Button, gBtnEditShorthandDictionary ys w80, % "Edi&t"
        Gui, Add, Button, gBtnReloadShorthandDictionary ys w80, % "Reloa&d"
        UI.Add(cts.shorthands_enabled, "xs")
        Gui, Tab, 2
        Gui, Add, GroupBox, y+20 w310 h175, Chords
        Gui, Add, Text, xp+20 yp+30 Section, % "&Detection delay (ms)"
        Gui, Add, Edit, vUI_input_delay Right xp+200 yp-2 w40 Number, 99
        Gui, Add, Checkbox, vUI_restrict_chords xs, % "&Restrict chords while typing"
        Gui, Add, Checkbox, vUI_allow_shift, % "Allow &Shift in chords"
        Gui, Add, Checkbox, vUI_delete_unrecognized, % "Delete &mistyped chords"
        Gui, Add, GroupBox, xs-20 y+40 w310 h70, % "Shorthands"
        Gui, Add, Checkbox, vUI_immediate_shorthands xp+20 yp+30 Section, % "E&xpand shorthands immediately"
        Gui, Tab, 3
        Gui, Add, Checkbox, y+20 vUI_hints_show Section, % "&Show hints for shortcuts in dictionaries"
        Gui, Add, Text, , % "Hint &location"
        Gui, Add, DropDownList, vUI_hint_destination AltSubmit xp+150 w140, % "On-screen display|Tooltips"
        Gui, Add, Text, xs, % "Hints &frequency"
        Gui, Add, DropDownList, vUI_hint_frequency AltSubmit xp+150 w140, % "Always|Normal|Relaxed"
        Gui, Add, Button, gShowHintCustomization vUI_btnCustomize xs w100, % "&Adjust >>"
        Gui, Add, GroupBox, vUI_hint_1 xs y+20 w310 h200 Section, % "Hint customization"
        Gui, Add, Text, vUI_hint_2 xp+20 yp+30 Section, % "Horizontal offset (px)"
        Gui, Add, Text, vUI_hint_3, % "Vertical offset (px)"
        Gui, Add, Text, vUI_hint_4, % "OSD font size (pt)"
        Gui, Add, Text, vUI_hint_5, % "OSD color (hex code)"
        Gui, Add, Edit, vUI_hint_offset_x ys xp+200 w70 Right
        Gui, Add, Edit, vUI_hint_offset_y w70 Right
        Gui, Add, Edit, vUI_hint_size w70 Right Number
        Gui, Add, Edit, vUI_hint_color w70 Right
        Gui, Tab, 4
        Gui, Add, GroupBox, y+20 w310 h120 Section, Smart spaces
        Gui, Add, Checkbox, vUI_space_before xs+20 ys+30, % "In &front of chords"
        Gui, Add, Checkbox, vUI_space_after xp y+10, % "&After chords and shorthands"
        Gui, Add, Checkbox, vUI_space_punctuation xp y+10, % "After &punctuation"
        Gui, Add, Text, xs y+30, % "Auto-&capitalization"
        Gui, Add, DropDownList, vUI_capitalization AltSubmit xp+150 w130, % "Off|For shortcuts|For all input"
        Gui, Add, Text, xs y+m, % "&Output delay (ms)"
        Gui, Add, Edit, vUI_output_delay Right xp+150 w40 Number, % "99"
        Gui, Tab
        Gui, Add, Button, vUI_zipchord_btnPause Hwndtemp xm ym+450 w130, % UI_STR_PAUSE
        fn := Func("PauseApp").Bind(true)
        GuiControl +g, % temp, % fn
        UI.Add("Button", "w80 xm+160 ym+450", "Apply", ObjBindMethod(this, "_ApplySettings"))
        UI.Add("Button", "Default w80 xm+260 ym+450", "OK", ObjBindMethod(this, "_btnOK"))

        Gui, Tab, 5
        Gui, Add, Text, Y+20, % "ZipChord"
        Gui, Add, Text, , % "Copyright © 2021–2024 Pavel Soukenik"
        Gui, Add, Text, , % "version " . zc_version
        ; Gui, Add, Text, +Wrap w300, % "This program comes with ABSOLUTELY NO WARRANTY. This is free software, and you are welcome to redistribute it under certain conditions."
        Gui, Font, Underline cBlue
        Gui, Add, Text, gLinkToLicense, % "License information"
        Gui, Add, Text, gLinkToDocumentation, % "Help and documentation"
        Gui, Add, Text, gLinkToReleases, % "Latest releases (check for updates)"
        Gui, Font, norm cDefault
        if (A_Args[1] == "dev") {
            Gui, Add, Checkbox, y+30 vUI_debugging, % "&Log this session (debugging)"
        }
        this.UI := UI
    }
    Show() {
        cts := this.controls
        if (A_Args[1] == "dev")
            if (UI_debugging)
                FinishDebugging()
        call := ObjBindMethod(this, "_Help")
        Hotkey, F1, % call, On
        handle := this.UI._handle
        Gui, %handle%:Default
        GuiControl Text, UI_input_delay, % settings.input_delay
        GuiControl Text, UI_output_delay, % settings.output_delay
        GuiControl , , UI_allow_shift, % (settings.chording & CHORD_ALLOW_SHIFT) ? 1 : 0
        GuiControl , , UI_restrict_chords, % (settings.chording & CHORD_RESTRICT) ? 1 : 0
        GuiControl , , UI_immediate_shorthands, % (settings.chording & CHORD_IMMEDIATE_SHORTHANDS) ? 1 : 0
        GuiControl , , UI_delete_unrecognized, % (settings.chording & CHORD_DELETE_UNRECOGNIZED) ? 1 : 0
        GuiControl , Choose, UI_capitalization, % settings.capitalization
        GuiControl , , UI_space_before, % (settings.spacing & SPACE_BEFORE_CHORD) ? 1 : 0
        GuiControl , , UI_space_after, % (settings.spacing & SPACE_AFTER_CHORD) ? 1 : 0
        GuiControl , , UI_space_punctuation, % (settings.spacing & SPACE_PUNCTUATION) ? 1 : 0
        GuiControl , , UI_zipchord_btnPause, % (settings.mode & MODE_ZIPCHORD_ENABLED) ? UI_STR_PAUSE : UI_STR_RESUME
        cts.chords_enabled.value := (settings.mode & MODE_CHORDS_ENABLED) ? 1 : 0
        cts.shorthands_enabled.value := (settings.mode & MODE_SHORTHANDS_ENABLED) ? 1 : 0
        ; debugging is always set to disabled
        GuiControl , , UI_debugging, 0
        GuiControl , , UI_hints_show, % (settings.hints & HINT_ON) ? 1 : 0
        GuiControl , Choose, UI_hint_destination, % Round((settings.hints & (HINT_OSD | HINT_TOOLTIP)) / 16)
        GuiControl , Choose, UI_hint_frequency, % OrdinalOfHintFrequency()
        GuiControl Text, UI_hint_offset_x, % settings.hint_offset_x
        GuiControl Text, UI_hint_offset_y, % settings.hint_offset_y
        GuiControl Text, UI_hint_size, % settings.hint_size
        GuiControl Text, UI_hint_color, % settings.hint_color
        ShowHintCustomization(false)
        GuiControl, Choose, UI_tab, 1 ; switch to first tab
        this.UpdateLocaleInMainUI(settings.locale)
        Gui, Show,, ZipChord
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
        Gui, Submit, NoHide
        ; gather new settings from UI...
        settings.input_delay := UI_input_delay + 0
        settings.output_delay := UI_output_delay + 0
        settings.capitalization := UI_capitalization
        settings.spacing := UI_space_before * SPACE_BEFORE_CHORD + UI_space_after * SPACE_AFTER_CHORD + UI_space_punctuation * SPACE_PUNCTUATION
        settings.chording := UI_delete_unrecognized * CHORD_DELETE_UNRECOGNIZED + UI_allow_shift * CHORD_ALLOW_SHIFT + UI_restrict_chords * CHORD_RESTRICT + UI_immediate_shorthands * CHORD_IMMEDIATE_SHORTHANDS
        settings.locale := cts.selected_locale.value
        ; settings.mode carries over the current ZIPCHORD_ENABLED setting
        settings.mode := (settings.mode & MODE_ZIPCHORD_ENABLED)
                        + cts.chords_enabled.value * MODE_CHORDS_ENABLED
                        + cts.shorthands_enabled.value * MODE_SHORTHANDS_ENABLED   
        settings.hints := UI_hints_show + 16 * UI_hint_destination + 2**UI_hint_frequency ; translates to HINT_ON, OSD/Tooltip, and frequency ( ** means ^ in AHK)
        if ( (temp:=SanitizeNumber(UI_hint_offset_x)) == "ERROR") {
            MsgBox ,, % "ZipChord", % "The offset needs to be a positive or negative number."
            Return false
        } else settings.hint_offset_x := temp
        if ( (temp:=SanitizeNumber(UI_hint_offset_y)) == "ERROR") {
            MsgBox ,, % "ZipChord", % "The offset needs to be a positive or negative number."
            Return false
        } else settings.hint_offset_y := temp
        settings.hint_size := UI_hint_size
        if ( (temp:=SanitizeNumber(UI_hint_color, true)) =="ERROR") {
            MsgBox ,, % "ZipChord", % "The color needs to be entered as hex code, such as '34cc97' or '#34cc97'."
            Return false
        } else settings.hint_color := temp
        ; ...and save them to config.ini
        settings.Write()
        ; We always want to rewire hotkeys in case the keys have changed.
        WireHotkeys("Off")
        locale.Load(settings.locale)
        if (settings.mode > MODE_ZIPCHORD_ENABLED) {
            if (previous_mode-1 < MODE_ZIPCHORD_ENABLED)
                ShowHint("ZipChord Keyboard", "On", , false)
            WireHotkeys("On")
        }
        else if (settings.mode & MODE_ZIPCHORD_ENABLED)
            ShowHint("ZipChord Keyboard", "Off", , false)
        if (A_Args[1] == "dev") {
            if (UI_debugging) {
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
        }
        ; to reflect any changes to OSD UI
        SetTimer,  UI_OSD_Reset, -2000
        Return true
    }

    ReEnable() {
        this.UI.Enable()
    }

    UpdateLocaleInMainUI(selected_loc) {
        sections := ini.LoadSections()
        ; handle := this.UI._handle
        ; Gui, %handle%:Default
        ; GuiControl, , UI_selected_locale, % "|" StrReplace(sections, "`n", "|")
        ; GuiControl, Choose, UI_selected_locale, % selected_loc
        this.controls.selected_locale.value := "|" StrReplace(sections, "`n", "|")
        this.controls.selected_locale.Choose(selected_loc)
    }

    EnableTabs(mode) {
        handle := main_UI.UI._handle
        Gui, %handle%:Default
        GuiControl, Enable%mode%, UI_tab
    }
    _Close() {
        Hotkey, F1, Off
        handle := this.UI._handle
        Gui, %handle%:Default
        Gui, Submit
        if (settings.preferences & PREF_SHOW_CLOSING_TIP)
            UI_ClosingTip_Show()
    }
    _Help() {
        handle := this.UI._handle
        Gui, %handle%:Default
        GuiControlGet, current_tab,, UI_tab
        OpenHelp("Main-" . Trim(current_tab))
    }

    _btnCustomizeLocale() {
        global locale
        WireHotkeys("Off")  ; so the user can edit the values without interference
        this.UI.Disable()
        locale.Show(this.controls.selected_locale.value)
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
    handle := main_UI.UI._handle
    Gui, %handle%:Default
    if (settings.mode & MODE_ZIPCHORD_ENABLED) {
        settings.mode := settings.mode & ~MODE_ZIPCHORD_ENABLED
        mode := false
    } else {
        settings.mode := settings.mode | MODE_ZIPCHORD_ENABLED
        mode := true
    }
    state := mode ? UI_STR_PAUSE : UI_STR_RESUME
    GuiControl , , UI_zipchord_btnPause, % state
    state := mode ? "On" : "Off"
    if (from_button != true) {
        ShowHint("ZipChord Keyboard", state, , false)
    }
    WireHotkeys(state)
    UI_Tray_Update()
    main_UI.EnableTabs(mode)
}

QuitApp() {
    WireHotkeys("Off")
    ShowHint("Closing ZipChord", state, , false)
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
    hint_frequency := settings.hints & (HINT_ALWAYS | HINT_NORMAL | HINT_RELAXED )
    hint_frequency := Round(Log(hint_frequency) / Log(2))  ; i.e. log base 2 gives us the desired setting as 1, 2 or 3
    Return hint_frequency + offset
}

; Shows or hides controls for hints customization (1 = show, 0 = hide)
ShowHintCustomization(show_controls := true) {
    GuiControl, Disable%show_controls%, UI_btnCustomize
    GuiControl, Show%show_controls%, UI_hint_offset_x
    GuiControl, Show%show_controls%, UI_hint_offset_y
    GuiControl, Show%show_controls%, UI_hint_size
    GuiControl, Show%show_controls%, UI_hint_color
    Loop 5 
    {
        GuiControl, Show%show_controls%, UI_hint_%A_Index%
    }
}

LinkToLicense() {
    ini.ShowLicense()
}
Return
LinkToDocumentation:
    Run https://github.com/psoukie/zipchord/wiki
Return
LinkToReleases:
    Run https://github.com/psoukie/zipchord/releases
Return

; Functions supporting UI

; Update UI with dictionary details
UpdateDictionaryUI() {
    handle := main_UI.UI._handle
    Gui, %handle%:Default
    GuiControl Text, UI_chord_file, % str.Ellipsisize(settings.chord_file, 270)
    entriesstr := "Chord dictionary (" chords.entries
    entriesstr .= (chords.entries==1) ? " chord)" : " chords)"
    GuiControl Text, UI_chord_entries, %entriesstr%
    GuiControl Text, UI_shorthand_file, % str.Ellipsisize(settings.shorthand_file, 270)
    entriesstr := "Shorthand dictionary (" shorthands.entries
    entriesstr .= (shorthands.entries==1) ? " shorthand)" : " shorthands)"
    GuiControl Text, UI_shorthand_entries, %entriesstr%
}

; Run Windows File Selection to open a dictionary
BtnSelectChordDictionary() {
    FileSelectFile dict, , % settings.dictionary_dir , Open Chord Dictionary, Text files (*.txt)
    if (dict != "") {
        settings.chord_file := dict
        chords.Load(dict)
        UpdateDictionaryUI()
    }
    Return
}

BtnSelectShorthandDictionary() {
    FileSelectFile dict, , % settings.dictionary_dir, Open Shorthand Dictionary, Text files (*.txt)
    if (dict != "") {
        settings.shorthand_file := dict
        shorthands.Load(dict)
        UpdateDictionaryUI()
    }
    Return
}

; Edit a dictionary in default editor
BtnEditChordDictionary() {
    Run % settings.chord_file
}
BtnEditShorthandDictionary() {
    Run % settings.shorthand_file
}

; Reload a (modified) dictionary file; rewires hotkeys because of potential custom keyboard setting
BtnReloadChordDictionary() {
    chords.Load()
    UpdateDictionaryUI()
}
BtnReloadShorthandDictionary() {
    shorthands.Load()
    UpdateDictionaryUI()
}

;; Closing Tip UI
; ----------------

global UI_ClosingTip_dont_show := 0

UI_ClosingTip_Show() {
    global app_shortcuts
    Gui, UI_ClosingTip:New, , % "ZipChord"
    Gui, Margin, 20, 20
    Gui, Font, s10, Segoe UI
    Gui, Add, Text, +Wrap w430, % Format("Select a word and {} to define a shortcut for it or to see its existing shortcuts.`n`n{} to open the ZipChord menu again.`n", app_shortcuts.GetHotkeyText("AddShortcut", "press ", "press and hold "), app_shortcuts.GetHotkeyText("ShowMainUI", "Press ", "Press and hold "))
    Gui, Add, Checkbox, vUI_ClosingTip_dont_show, % "Do &not show this tip again."
    Gui, Add, Button, gUI_ClosingTip_btnOK x370 w80 Default, OK
    Gui, Show, w470
}
UI_ClosingTip_btnOK() {
    Gui, UI_ClosingTip:Submit
    if (UI_ClosingTip_dont_show) {
        settings.preferences &= ~PREF_SHOW_CLOSING_TIP
        settings.Write()
    }
}
UI_ClosingTipGuiClose() {
    Gui, UI_ClosingTip:Submit
}
UI_ClosingTipGuiEscape() {
    Gui, UI_ClosingTip:Submit
}

;; Shortcut Hint UI
; -------------------

global UI_OSD_line1
    , UI_OSD_line2
    , UI_OSD_line3
    , UI_OSD_transparency
    , UI_OSD_fading
    , UI_OSD_transparent_color  ; gets calculated from settings.hint_color for a nicer effect
    , UI_OSD_pos_x, UI_OSD_pos_y
    , UI_OSD_hwnd

UI_OSD_Build() {
    hint_color := settings.hint_color
    UI_OSD_transparent_color := ShiftHexColor(hint_color, 1)
    Gui, UI_OSD:Default
    Gui +LastFound +AlwaysOnTop -Caption +ToolWindow +HwndUI_OSD_hwnd ; +ToolWindow avoids a taskbar button and an alt-tab menu item.
    size := settings.hint_size
    Gui, Margin, Round(size/3), Round(size/3)
    Gui, Color, %UI_OSD_transparent_color%
    Gui, Font, s%size%, Consolas  ; Set a large font size (32-point).
    Gui, Add, Text, c%hint_color% Center vUI_OSD_line1, WWWWWWWWWWWWWWWWWWWWW  ; to auto-size the window.
    Gui, Add, Text, c%hint_color% Center vUI_OSD_line2, WWWWWWWWWWWWWWWWWWWWW
    Gui, Add, Text, c%hint_color% Center vUI_OSD_line3, WWWWWWWWWWWWWWWWWWWWW
    Gui, Show, NoActivate Center, ZipChord_OSD
    WinSet, TransColor, %UI_OSD_transparent_color% 150, ZipChord_OSD
    ; Get position of the window in case our fancy detection for multiple monitors fails
    WinGetPos UI_OSD_pos_x, UI_OSD_pos_y, , , ZipChord_OSD
    UI_OSD_pos_x += settings.hint_offset_x
    UI_OSD_pos_y += settings.hint_offset_y
    Gui, Hide
}
ShowHint(line1, line2:="", line3 :="", follow_settings := true) {
    active_window_handle := WinExist("A")
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
        GetCaret(x, y, , h)
        ToolTip % " " . ReplaceWithVariants(line2) . " `n " . ReplaceWithVariants(line3) . " ", x-1.5*h+settings.hint_offset_x, y+1.5*h+settings.hint_offset_y
        SetTimer, HideToolTip, -1800
    } else {
        UI_OSD_fading := False
        UI_OSD_transparency := 150
        Gui, UI_OSD:Default
        GuiControl,, UI_OSD_line1, % line1
        GuiControl,, UI_OSD_line2, % ReplaceWithVariants(line2, follow_settings)
        GuiControl,, UI_OSD_line3, % ReplaceWithVariants(line3)
        Gui, %UI_OSD_hwnd%: Show, Hide NoActivate, ZipChord_OSD
        GetMonitorCenterForWindow(active_window_handle, UI_OSD_hwnd, pos_x, pos_y)
        pos_x := pos_x ? pos_x+settings.hint_offset_x : UI_OSD_pos_x
        pos_y := pos_y ? pos_y+settings.hint_offset_y : UI_OSD_pos_y
        Gui, %UI_OSD_hwnd%: Show, NoActivate X%pos_x% Y%pos_y%, ZipChord_OSD
        WinSet, TransColor, %UI_OSD_transparent_color% %UI_OSD_transparency%, ZipChord_OSD
        SetTimer, UI_OSD_Hide, -1900
    }
}

UI_OSD_Reset() {
    hint_delay.Reset()
    Gui, UI_OSD:Destroy
    UI_OSD_Build()
}

HideToolTip:
    ToolTip
Return

UI_OSD_Hide:
    UI_OSD_fading := true
    Gui, UI_OSD:Default
    if (UI_OSD_fading && UI_OSD_transparency > 1) {
        UI_OSD_transparency -= 10
        WinSet, TransColor, %UI_OSD_transparent_color% %UI_OSD_transparency%, ZipChord_OSD
        SetTimer, UI_OSD_Hide, -100
        Return
    }
    Gui, Hide
Return

; Process input to ensure it is an integer (or a color hex code if the second parameter is true), return number or "ERROR" 
SanitizeNumber(orig, hex_color := false) {
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

ShiftHexColor(source_color, offset) {
    Loop 3
    {
        component := "0x" . SubStr(source_color, 2 * A_Index - 1, 2)
        component := component > 0x7f ? component - offset : component + offset
        new_color .= Format("{:02x}", component)
    }
    return new_color
}

; The following function for getting caret position more reliably is from a post by plankoe at https://www.reddit.com/r/AutoHotkey/comments/ysuawq/get_the_caret_location_in_any_program/
GetCaret(ByRef X:="", ByRef Y:="", ByRef W:="", ByRef H:="") {
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

GetMonitorCenterForWindow(window_Handle, OSD_handle, ByRef pos_x, ByRef pos_y ) {
    ; Uses code for getting monitor info by "kon" from https://www.autohotkey.com/boards/viewtopic.php?t=15501
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
}