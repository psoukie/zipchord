#NoEnv
#SingleInstance Force
#MaxThreadsPerHotkey 10
SetWorkingDir %A_ScriptDir%

; ZipChord by Pavel Soukenik
; Licensed under GPL-3.0
; See https://github.com/psoukie/zipchord/
global version = "1.8.2"

; ------------------
;; Global Variables
; ------------------

; Default (US English) and custom keyboard and language settings:

; keys that interrupt the typing flow (not customizable in dictionary file)
global cursory := "Del|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|LButton|RButton|BS|Tab"

; following are default values based on English keyboard and conventions:
global default_keys := "',-./0123456789;=[\]abcdefghijklmnopqrstuvwxyz" ; English default keyboard layout

/* 
global default_space_after_keys := ".,;" ; unmodified keys that should be followed by smart space
global default_space_after_shift_keys := "1/;" ; keys that -- when modified by Shift -- should be followed by smart space
global default_capitalizing_keys := "." ; unmodified keys that capitalize the text that folows them
global default_capitalizing_shift_keys :="1/"  ; keys that -- when modified by Shift --  capitalize the text that folows them
global default_opener_keys := "'-/=\]" ; unmodified keys that can be followed by a chord without a space.
global default_opener_shift_keys := "',-./23456789;=\]" ; keys combined with Shift that can be followed by a chord without a space.
*/

; Keyboard is customizable using dictionary file only, and not through UI yet
global keys := "" ; Uses default_keys or custom_keys read from the dictionary file.

; The following are not customizable yet through UI or dictionary
global space_after_keys := ".,;"  ; unmodified keys that should be followed by smart space
global space_after_shift_keys := "1/;" ; keys that -- when modified by Shift -- should be followed by smart space
global capitalizing_keys := "." ; unmodified keys that capitalize the text that folows them
global capitalizing_shift_keys := "1/"  ; keys that -- when modified by Shift --  capitalize the text that folows them
global opener_keys := "'-/=\]"  ; unmodified keys that can be followed by a chord without a space.
global opener_shift_keys := "',-./23456789;=\]"  ; keys combined with Shift that can be followed by a chord without a space.

; Current application settings

global recognition_on := 1 ; maps to UI_on for whether the chord recognition is enabled
global chord_file := "" ; file name for the dictionary
global chords := {} ; holds pairs of chord key combinations and their full texts
global chord_delay := 0
global output_delay := 0

; capitalization setting constants and variable:
global CAP_OFF = 1 ; no auto-capitalization,
global CAP_CHORDS = 2 ; auto-capitalize chords only
global CAP_ALL = 3 ; auto-capitalize all typing
global capitalization := CAP_CHORDS

; smart spacing constants (binary) and variable:
global SPACE_BEFORE_CHORD := 1
global SPACE_AFTER_CHORD := 2
global SPACE_PUNCTUATION := 4
global spacing := SPACE_BEFORE_CHORD | SPACE_AFTER_CHORD

global delete_unrecognized := 0 ; delete typing that triggers chords that are not in dictionary?

; Options for recognition - constants (binary) and variable:
global OPT_DELETE_UNRECOGNIZED := 1 ; Delete typing that triggers chords that are not in dictionary?
global OPT_ALLOW_SHIFT := 2  ; Allow Shift in combination with at least two other keys to form unique chords?
global OPT_RESTRICT_CHORDS := 4      ; Disallow chords (except for suffixes) if the chord isn't separated from typing by a space, interruption, or defined punctuation "opener" 
global options:= 0

; Processing input and output 

buffer := ""   ; stores the sequence of simultanously pressed keys
chord := ""    ; chord candidate which qualifies for chord
global start := 0 ; tracks start time of two keys pressed at once

; constants and variable to track the difference between key presses and output (because of smart spaces and punctuation)
global DIF_NONE := 0
global DIF_EXTRA_SPACE := 1
global DIF_REMOVED_SMART_SPACE := 2
global DIF_IGNORED_SPACE := 4
global difference := DIF_NONE   ; tracks the difference between keys pressed and output (because of smart spaces and punctuation)
global final_difference := DIF_NONE

; Characteristics of last output: constants (partially binary) and variables
global OUT_INTERRUPTED := 128   ; output is unknown or it was interrupted by moving the cursor using cursor keys, mouse click etc.
global OUT_CHARACTER := 1     ; output is a character
global OUT_SPACE := 2         ; output was a space
global OUT_PUNCTUATION := 4 ; output was a punctuation
global OUT_AUTOMATIC := 8     ; output was automated (i.e. added by ZipChord, instead of manual entry)
global OUT_CAPITALIZE := 16   ; output requires capitalization of what follows
global OUT_PREFIX := 32       ; output is a prefix (or opener punctuation) and doesn't need space in next chord (and can be followed by a chard in restricted mode)
global OUT_CHORD := OUT_CHARACTER | OUT_AUTOMATIC
global OUT_SMART_SPACE := OUT_SPACE | OUT_AUTOMATIC
; Because some of the typing is dynamically changed after it occurs, we need to distinguish between the last keyboard output which is already finalized, and the last entry which can still be subject to modifications.
global fixed_output := OUT_INTERRUPTED ; fixed output that preceded any typing currently being processed 
global last_output := OUT_INTERRUPTED  ; last output in the current typing sequence that could be in flux. It is set to fixed_input when there's no such output.
; new_output local variable is used to track the current key / output

; variables holding the UI elements and selections -- used by AHK Gui 

global UI_chord_delay
global UI_output_delay
global UI_space_before
global UI_space_after
global UI_space_punctuation
global UI_delete_unrecognized
global UI_capitalization
global UI_allow_shift
global UI_restrict_chords
global UI_dict := "none"
global UI_entries := "0"
global UI_on := 1
global UI_tab := 0


Initialize()
Return   ; To prevent execution of any of the following code, except for the always-on keyboard shortcuts below:

; -------------------
;; Permanent Hotkeys
; -------------------

; An always enabled Ctrl+Shift+C hotkey held long to open ZipChord menu.
~^+c::
    Sleep 300
    if GetKeyState("c","P")
        ShowMenu()
    Return

; An always-on Ctrl+C hotkey held long to add a new chord to the dictionary.
~^c::
    Sleep 300
    if GetKeyState("c","P")
        AddChord()
    Return

; The rest of the code from here on behaves like in normal programming languages: It is not executed unless called from somewhere else in the code, or triggered by dynamically defined hotkeys.

; ---------------------------
;; Initilization and Wiring
; ---------------------------

Initialize() {
    BuildMenu()
    ReadSettings()
    LoadChords(chord_file)
    WireHotkeys("On")
    ShowMenu()
}

; WireHotKeys(["On"|"Off"]): Creates or releases hotkeys for tracking typing and chords
WireHotkeys(state) {
    Loop Parse, keys
    {
        Hotkey, % "~" A_LoopField, KeyDown, %state% UseErrorLevel
        If ErrorLevel {
            MsgBox, , ZipChord, The current keyboard layout does not include the unmodified key '%A_LoopField%'. ZipChord will not be able to recognize this key.`n`nEither change your keyboard layout, or change the custom keyboard layout for your current ZipChord dictionary.
            Break
        }
        Hotkey, % "~+" A_LoopField, KeyDown, %state%
        Hotkey, % "~" A_LoopField " Up", KeyUp, %state%
        Hotkey, % "~+" A_LoopField " Up", KeyUp, %state%
    }
    Hotkey, % "~Space", KeyDown, %state%
    Hotkey, % "~+Space", KeyDown, %state%
    Hotkey, % "~Space Up", KeyUp, %state%
    Loop Parse, cursory, |
    {
        Hotkey, % "~" A_LoopField, Interrupt, %state%
        Hotkey, % "~^" A_LoopField, Interrupt, %state%
    }
    Hotkey, % "~Enter", Enter_key, %state%
}

; Main code. This is where the magic happens. Tracking keys as they are pressed down and released:

; ------------------
;; Chord Detection
; ------------------

KeyDown:
    Critical
    key := StrReplace(A_ThisHotkey, "Space", " ")
    ; First, we differentiate if the key was pressed while holding Shift, and store it under 'key':
    if ( StrLen(A_ThisHotkey)>2 && SubStr(A_ThisHotkey, 2, 1) == "+" ) {
        shifted := true
        key := SubStr(key, 3, 1)
    } else {
        shifted := false
        key := SubStr(key, 2, 1)
    }

    if (chord != "") {  ; if there is an existing potential chord that is being interrupted with additional key presses
        start := 0
        chord := ""
    }

    buffer .= key ; adds to the keys pressed so far (the buffer is emptied upon each key-up)
    ; and when we have two keys, we start the clock for chord recognition sensitivity:
    if (StrLen(buffer)==2) {
        start := A_TickCount 
        if (shifted)
            buffer .= "+"  ; hack to communicate Shift was pressed
    }

    if (!start)
        difference := DIF_NONE   ; a chord is not being formed, so we reset the diff between keys and output.

    ; Now, we categorize the current output and adjust on the fly as needed:
    new_output := OUT_CHARACTER | (last_output & OUT_CAPITALIZE)

    ; if it's a space
    if (key==" ") {
        if ( (last_output & OUT_SMART_SPACE) == OUT_SMART_SPACE ) {
            SendInput {Backspace} ; delete any smart-space
            difference |= DIF_IGNORED_SPACE  ; and account for the output being one character shorter than the chord
        }
        new_output := new_output & ~OUT_AUTOMATIC | OUT_SPACE 
    }

    ; if it's punctuation needing space adjustments
    if ( (!shifted && InStr(space_after_keys, key)) || (shifted && InStr(space_after_shift_keys, key)) ) {
        new_output := OUT_PUNCTUATION
        if ( (last_output & OUT_SMART_SPACE) == OUT_SMART_SPACE) {
            SendInput {Backspace}{Backspace}
            difference |= DIF_REMOVED_SMART_SPACE
            if (shifted)
                SendInput +%key%
            else
                SendInput %key%
        }
        ; if smart spacing for punctuation is enabled, insert a smart space
        if ( spacing & SPACE_PUNCTUATION ) {
            SendInput {Space}
            difference |= DIF_EXTRA_SPACE
            new_output |= OUT_SMART_SPACE
        }
    }

    ; if it's neither, it should be a regural character, and it might need capitalization
    if (new_output & OUT_CHARACTER) {
        if ( capitalization==CAP_ALL && (! shifted) && (last_output & OUT_CAPITALIZE) ) {
            cap_key := RegExReplace(key, "(.*)", "$U1")
            SendInput % "{Backspace}{Text}"RegExReplace(key, "(.*)", "$U1") ; deletes the character and sends its uppercase version.  Uses {Text} because otherwise, Unicode extended characters could not be upper-cased correctly
            new_output := new_output && ~OUT_CAPITALIZE
        }
    }

    ; set 'uppercase' for punctuation that capitalizes following text 
    if ( (! shifted && InStr(capitalizing_keys, key)) || (shifted && InStr(capitalizing_shift_keys, key)) )
        new_output |= OUT_CAPITALIZE

    ; mark output that can be followed by another word/chord without a space 
    if ( (! shifted && InStr(opener_keys, key)) || (shifted && InStr(opener_shift_keys, key)) )
        new_output |= OUT_PREFIX

    last_output := new_output
Return

KeyUp:
    Critical
    tempch := buffer
    st := start
    buffer := ""
    start := 0
    ; if at least two keys were held at the same time for long enough, let's save our candidate chord and exit
    if ( st && chord=="" && (A_TickCount - st > chord_delay) ) {
        chord := tempch ; this is the chord candidate
        final_difference := difference
        start := 0
        Return
    }
    ; when another key is lifted (so we could check for false triggers in rolls) we test and expand the chord
    if (chord != "") {
        if (InStr(chord, "+")) {
            ;if Shift is not allowed as a chord key, we just capitalize the chord.
            if (!(options & OPT_ALLOW_SHIFT)) {
            fixed_output |= OUT_CAPITALIZE
            chord := StrReplace(chord, "+")
            }
        }
        sorted := Arrange(chord)
        Sleep output_delay
        if (chords.HasKey(sorted)) {
            exp := chords[sorted] ; store the expanded text       
            ; detect and adjust expansion for suffixes and prefixes
            if (SubStr(exp, 1, 1) == "~") {
                exp := SubStr(exp, 2)
                suffix := true
            } else {
                suffix := false
            }
             if (SubStr(exp, StrLen(exp), 1) == "~") {
                exp := SubStr(exp, 1, StrLen(exp)-1)
                prefix := true
            } else {
                prefix := false
            }
            ; if we aren't restricted, we print a chord
            if (suffix || IsUnrestricted()) {
                RemoveRawChord(sorted)
                OpeningSpace(suffix)
                if (InStr(exp, "{")) {
                    ; we send any expanded text that includes { as straight directives:
                    SendInput % exp
                } else {
                    ; and there rest as {Text} that's capitalized if needed:
                    if ( NeedsCapitalization() )
                        SendInput % "{Text}"RegExReplace(exp, "(^.)", "$U1")
                    else
                        SendInput % "{Text}"exp
                }
                last_output := OUT_CHORD
                ; ending smart space
                if (prefix) {
                    last_output |= OUT_PREFIX
                } else if (spacing & SPACE_AFTER_CHORD) {
                    SendInput {Space}
                    last_output := OUT_SMART_SPACE
                }
            }
            ; Here, we are not deleting the keys because we assume it was rolled typing.
        }
        else {
            if (delete_unrecognized)
                RemoveRawChord(sorted)
        }
        chord := ""
    }
    fixed_output := last_output ; and this last output is also the last fixed output.
Return

; Helper functions

;remove raw chord output
RemoveRawChord(output) {
    adj :=0
    ; we remove any Shift from the chord because that is not a real character
    output := StrReplace(output, "+")
    if (final_difference & DIF_EXTRA_SPACE)
        adj++
    if (final_difference & DIF_IGNORED_SPACE)
        adj--
    Loop % (StrLen(output) + adj)
        SendInput {Backspace}
    if (final_difference & DIF_REMOVED_SMART_SPACE)
        SendInput {Space}
}

; check we can output chord here
IsUnrestricted() {
    ; If we're in unrestricted mode, we're good
    if (!(options & OPT_RESTRICT_CHORDS))
        Return true
    ; If last output was a prefix (meaning chord prefix or a defined opening punctuation), it was interrupted, or it was a space, we can also go ahead.
    if ( (fixed_output & OUT_PREFIX) || (fixed_output & OUT_INTERRUPTED) || (fixed_output & OUT_SPACE) )
        Return true
    Return false
}


; Handles opening spacing as needed (single-use helper function)
OpeningSpace(attached) {
    ; if there is a smart space, we remove it for suffixes, and we're done
    if ((fixed_output & OUT_SMART_SPACE) == OUT_SMART_SPACE) {
        if (attached)
            SendInput {Backspace}
        Return
    }
    ; if adding smart spaces before is disabled, we are done too
    if (! (spacing & SPACE_BEFORE_CHORD))
        Return
    ; and we don't start with a smart space after intrruption, a space, after a prefix, and for suffix
    if (fixed_output & OUT_INTERRUPTED || fixed_output & OUT_SPACE || fixed_output & OUT_PREFIX || attached)
        Return
    ; if we get here, we probably need a space in front of the chord
    SendInput {Space}
}

; Single-use helper function used for readability
NeedsCapitalization() {
    if ((fixed_output & OUT_CAPITALIZE) && (capitalization != CAP_OFF))
        Return True
    Return False
}

; Sort the string alphabetically
Arrange(raw) {
    raw := RegExReplace(raw, "(.)", "$1`n")
    Sort raw
    Return StrReplace(raw, "`n")
}

Interrupt:
    last_output := OUT_INTERRUPTED
    fixed_output := last_output
Return

Enter_key:
    last_output := OUT_INTERRUPTED | OUT_CAPITALIZE
    fixed_output := last_output
Return


; -----------------
;;  Adding chords 
; -----------------

; Define a new chord for the selected text (or check what it is for existing)
AddChord() {
    newword := Trim(Clipboard)
    if (!StrLen(newword)) {
        MsgBox ,, ZipChord, % "First, select a word you would like to define a chord for, and then press and hold Ctrl+C again."
        Return
    }
    For ch, wd in chords
        if (wd==newword) {
            MsgBox    ,, ZipChord, % Format("The text '{}' already has the chord {:U} associated with it.", wd, ch)
            Return
        }
    Loop {
        InputBox, newch, ZipChord, % Format("Type the individual keys that will make up the chord for '{}'.`n(Only lowercase letters, numbers, space, and other alphanumerical keys without pressing Shift or function keys.)", newword)
        if ErrorLevel
            Return
    } Until RegisterChord(newch, newword, true)
    UpdateDictionaryUI()
}

; RegisterChord(chord, expanded[, true|false])  Adds a new pair of chord and its expanded text to 'chords' and to the dictionary file
RegisterChord(newch, newword, write_to_dictionary := false) {
    newch := Arrange(newch)
    if chords.HasKey(newch) {
        MsgBox ,, ZipChord, % "The chord '" newch "' is already in use for '" chords[newch] "'.`nPlease use a different chord for '" newword "'."
        Return false
    }
    if (StrLen(newch)<2) {
        MsgBox ,, ZipChord, The chord needs to be at least two characters.
        Return false
    }
    if (StrLen(RegExReplace(newch,"(.)(?=.*\1)")) != StrLen(newch)) {
        MsgBox ,, ZipChord, Each key can be entered only once in the same chord.
        Return false
    }
    if (write_to_dictionary)
        FileAppend % "`r`n" newch "`t" newword, %chord_file%, UTF-8
    chords.Insert(newch, newword)
    return true
}

; ------------------
;;      GUI
; ------------------

; Prepare UI
BuildMenu() {
    Gui, Font, s10, Segoe UI
    Gui, Margin, 15, 15
    Gui, Add, Tab3, vUI_tab, Dictionary|Chord detection|Output|About
    ; Gui, Add, GroupBox, w320 h130 Section, Dictionary
    Gui, Add, Text, w280 vUI_dict Left, [file name]
    Gui, Add, Text, xp+10 y+m w280 vUI_entries Left, (999 chords)
    Gui, Add, Button, xs+20 gSelectDict y+m w80, &Open
    Gui, Add, Button, gEditDict xp+100 w80, &Edit
    Gui, Add, Button, gReloadDict xp+100 w80, &Reload
    ; Gui, Add, GroupBox, xs ys+150 w320 h100 Section, Sensitivity
    Gui, Tab, 2
    Gui, Add, Text, , &Detection delay (ms):
    Gui, Add, Edit, vUI_chord_delay Right xp+150 w40, 99
    Gui, Add, Checkbox, vUI_restrict_chords xs+20 y+m, &Restrict chords while typing
    Gui, Add, Checkbox, vUI_allow_shift, Allow &Shift in chords 
    Gui, Add, Checkbox, vUI_delete_unrecognized, Delete &mistyped chords
    Gui, Tab, 3
    Gui, Add, GroupBox, w290 h120 Section, Smart spaces
    ;Gui, Add, Text, xs+20 ys+m +Wrap, When selected, smart spaces are dynamically added and removed as you type to ensure spaces between words, and avoid extra spaces around punctuation and doubled spaces when a manually typed space is combined with an automatic one.
    Gui, Add, Checkbox, vUI_space_before xs+20 ys+30, In &front of chords
    Gui, Add, Checkbox, vUI_space_after xp y+10, &After chords
    Gui, Add, Checkbox, vUI_space_punctuation xp y+10, After &punctuation
    Gui, Add, Text, xs y+30, Auto-&capitalization:
    Gui, Add, DropDownList, vUI_capitalization AltSubmit Right xp+150 w130, Off|For chords only|For all input
    Gui, Add, Text, xs y+m, O&utput delay (ms):
    Gui, Add, Edit, vUI_output_delay Right xp+150 w40, 99

    Gui, Tab
    Gui, Add, Checkbox, gEnableDisableControls vUI_on xs Y+m Checked%UI_on%, Use &chord detection
    Gui, Add, Button, Default w80 xs+220 yp, OK
    Gui, Tab, 4
    Gui, Add, Text, X+m Y+m, ZipChord`nversion %version%
    Gui, Font, Underline cBlue
    Gui, Add, Text, xp Y+m gWebsiteLink, Help and documentation
    Gui, Add, Text, xp Y+m gReleaseLink, Latest releases (check for updates)

    ; Create taskbar tray menu:
    Menu, Tray, Add, Open Settings, ShowMenu
    Menu, Tray, Default, Open Settings
    Menu, Tray, Tip, ZipChord
    Menu, Tray, Click, 1
}

ShowMenu() {
    GuiControl Text, UI_chord_delay, %chord_delay%
    GuiControl Text, UI_output_delay, %output_delay%
    GuiControl , , UI_allow_shift, % (options & OPT_ALLOW_SHIFT) ? 1 : 0
    GuiControl , , UI_restrict_chords, % (options & OPT_RESTRICT_CHORDS) ? 1 : 0
    GuiControl , , UI_delete_unrecognized, % (options & OPT_DELETE_UNRECOGNIZED) ? 1 : 0
    GuiControl , Choose, UI_capitalization, %capitalization%
    GuiControl , , UI_space_before, % (spacing & SPACE_BEFORE_CHORD) ? 1 : 0
    GuiControl , , UI_space_after, % (spacing & SPACE_AFTER_CHORD) ? 1 : 0
    GuiControl , , UI_space_punctuation, % (spacing & SPACE_PUNCTUATION) ? 1 : 0
    GuiControl , , UI_on, %recognition_on%
    GuiControl, Choose, UI_tab, 1 ; switch to first tab 
    EnableDisableControls()
    Gui, Show,, ZipChord
}

; sets UI controls to enabled/disabled to reflect chord recognition setting 
EnableDisableControls() {
    GuiControlGet, checked,, UI_on
    GuiControl, Enable%checked%, UI_chord_delay
    GuiControl, Enable%checked%, UI_output_delay
    GuiControl, Enable%checked%, UI_restrict_chords
    GuiControl, Enable%checked%, UI_allow_shift
    GuiControl, Enable%checked%, UI_space_before
    GuiControl, Enable%checked%, UI_space_after
    GuiControl, Enable%checked%, UI_space_punctuation
    GuiControl, Enable%checked%, UI_capitalization
    GuiControl, Enable%checked%, UI_delete_unrecognized
}

ButtonOK:
    Gui, Submit, NoHide
    capitalization := UI_capitalization
    RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, Capitalization, %capitalization%
    spacing := UI_space_before * SPACE_BEFORE_CHORD + UI_space_after * SPACE_AFTER_CHORD + UI_space_punctuation * SPACE_PUNCTUATION
    RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, Spacing, %spacing%
    options := UI_delete_unrecognized * OPT_DELETE_UNRECOGNIZED + UI_allow_shift * OPT_ALLOW_SHIFT + UI_restrict_chords * OPT_RESTRICT_CHORDS
    RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, Options, %options%
    if SetDelays(UI_chord_delay, UI_output_delay) {
        if (UI_on && !recognition_on)
            WireHotkeys("On")
        if (recognition_on && !UI_on)
            WireHotkeys("Off")
        recognition_on := UI_on
        CloseMenu()
    }
Return

GuiClose:
GuiEscape:
    CloseMenu()
Return

CloseMenu() {
    Gui, Submit
    static intro := true
    if intro {
        MsgBox ,, ZipChord, % "Select a word and press and hold Ctrl-C to define a chord for it or to see its existing chord.`n`nPress and hold Ctrl-Shift-C to open the ZipChord menu again."
        intro := false
    }
}

WebsiteLink:
Run https://github.com/psoukie/zipchord#readme
return

ReleaseLink:
Run https://github.com/psoukie/zipchord/releases
return

; Functions supporting UI

; Update UI with dictionary details
UpdateDictionaryUI() {
    if StrLen(chord_file) > 35
        filestr := "..." SubStr(chord_file, -34)
    else
        filestr := chord_file
    GuiControl Text, UI_dict, %filestr%
    entriesstr := "(" chords.Count()
    entriesstr .= (chords.Count()==1) ? " chord)" : " chords)"
    GuiControl Text, UI_entries, %entriesstr%
}

; Run Windows File Selection to open a dictionary
SelectDict() {
    FileSelectFile dict, , %A_ScriptDir%, Open Dictionary, Text files (*.txt)
    if (dict != "")
        LoadChords(dict)
    Return
}

; Edit a dictionary in default editor
EditDict() {
    Run %chord_file%
}

; Reload a (modified) dictionary file; rewires hotkeys because of potential custom keyboard setting
ReloadDict() {
    WireHotkeys("Off")
    LoadChords(chord_file)
    WireHotkeys("On")
}

; ---------------------
;;  Saving and Loading
; ---------------------

; Read settings from Windows Registry and locate dictionary file
ReadSettings() {
    RegRead chord_delay, HKEY_CURRENT_USER\Software\ZipChord, ChordDelay
    if ErrorLevel
        SetDelays(90, 0)
    RegRead output_delay, HKEY_CURRENT_USER\Software\ZipChord, OutDelay
    if ErrorLevel
        SetDelays(90, 0)
    RegRead options, HKEY_CURRENT_USER\Software\ZipChord, Options
    if ErrorLevel
        options := 0
    RegRead spacing, HKEY_CURRENT_USER\Software\ZipChord, Spacing
    if ErrorLevel
        spacing := SPACE_BEFORE_CHORD | SPACE_AFTER_CHORD
    RegRead capitalization, HKEY_CURRENT_USER\Software\ZipChord, Capitalization
    if ErrorLevel
        capitalization := CAP_CHORDS
    RegRead chord_file, HKEY_CURRENT_USER\Software\ZipChord, ChordFile
    if (ErrorLevel || !FileExist(chord_file)) {
        errmsg := ErrorLevel ? "" : Format("The last used dictionary {} could not be found.`n`n", chord_file)
        ; If we don't have the dictionary, try other files with the following filename convention instead. (This is useful if the user downloaded ZipChord and a preexisting dictionary and has them in the same folder.)
        chord_file := "chords*.txt"
        if FileExist(chord_file) {
            Loop, Files, %chord_file%
                flist .= SubStr(A_LoopFileName, 1, StrLen(A_LoopFileName)-4) "`n"
            Sort flist
            chord_file := SubStr(flist, 1, InStr(flist, "`n")-1) ".txt"
            errmsg .= Format("ZipChord detected the dictionary '{}' and is going to open it.", chord_file)
        }
        else {
            errmsg .= "ZipChord is going to create a new 'chords.txt' dictionary in its own folder."
            chord_file := "chords.txt"
            FileAppend % "This is a dictionary for ZipChord. Define chords and corresponding words in a tab-separated list (one entry per line).`nSee https://github.com/psoukie/zipchord for details.`n`ndm`tdemo", %chord_file%, UTF-8
        }
        chord_file := A_ScriptDir "\" chord_file
        MsgBox ,, ZipChord, %errmsg%
    }
}

; Save delay settings
SetDelays(new_input_delay, new_output_delay) {
    ; first check we have integers
    if (RegExMatch(new_input_delay,"^\d+$") && RegExMatch(new_output_delay,"^\d+$")) {
            chord_delay := new_input_delay + 0
            RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, ChordDelay, %chord_delay%
            output_delay := new_output_delay + 0
            RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, OutDelay, %output_delay%
            Return true
    }
    MsgBox ,, ZipChord, % "The chord sensitivity needs to be entered as a whole number."
    Return false
}

; Load chords from a dictionary file
LoadChords(file_name) {
    chord_file := file_name
    pause_loading := true
    RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, ChordFile, %chord_file%
    chords := {}
    keys := default_keys
    Loop, Read, %chord_file%
    {
        pos := InStr(A_LoopReadLine, A_Tab)
        if (pos) {
            if (SubStr(A_LoopReadLine, 1, pos-1) == "custom_keys")
                keys := Arrange(SubStr(A_LoopReadLine, pos+1))
            else
                if (! RegisterChord(Arrange(SubStr(A_LoopReadLine, 1, pos-1)), SubStr(A_LoopReadLine, pos+1)) ) {
                    if (pause_loading) {
                        MsgBox, 4, ZipChord, Would you like to continue loading the dictionary file?`n`nIf Yes, you'll see all errors in the dictionary.`nIf No, the rest of the dictionary will be ignored.
                        IfMsgBox Yes
                            pause_loading := false
                        else
                            Break
                    }
                }
        }
    }
    UpdateDictionaryUI()
}