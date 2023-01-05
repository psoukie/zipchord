#NoEnv
#SingleInstance Force
#MaxThreadsPerHotkey 1
#MaxThreadsBuffer On
#KeyHistory 0
ListLines Off
SetWorkingDir %A_ScriptDir%

; ZipChord by Pavel Soukenik
; Licensed under GPL-3.0
; See https://github.com/psoukie/zipchord/

global version = "2.0.0-alpha.4"

;; Classes and Variables
; -----------------------

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
; stores current locale information 
keys := New localeClass

; affixes constants
global AFFIX_NONE := 0 ; no prefix or suffix
    , AFFIX_PREFIX := 1 ; expansion is a prefix
    , AFFIX_SUFFIX := 2 ; expansion is a suffix

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

; Other preferences constants
global PREF_FIRST_RUN := 1          ; first run of the application (no entry in Registry)
    , PREF_SHOW_CLOSING_TIP := 2    ; show tip about re-opening the main dialog and adding chords
    , PREF_SHOW_SHORTCUTS := 4    ; show tip about re-opening the main dialog and adding chords

; Current application settings
Class settingsClass {
    chords_enabled := 1
    shorthands_enabled := 1
    preferences := PREF_FIRST_RUN | PREF_SHOW_CLOSING_TIP | PREF_SHOW_SHORTCUTS
    locale := "English US"
    capitalization := CAP_CHORDS
    spacing := SPACE_BEFORE_CHORD | SPACE_AFTER_CHORD | SPACE_PUNCTUATION  ; smart spacing options 
    chording := CHORD_RESTRICT ; Chord recognition options
    chord_file := "chords-en-starting.txt" ; file name for the chord dictionary
    shorthand_file := "shorthands-english-starting.txt" ; file name for the shorthand dictionary
    input_delay := 90
    output_delay := 0
    ; Read settings from Windows Registry and locate dictionary file
    Read() {
        For key in this
        {
            RegRead new_value, HKEY_CURRENT_USER\Software\ZipChord, %key%
            if (! ErrorLevel)
                this[key] := new_value
        }
    }
    Write() {
        For key, value in this
        RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, %key%, %value%
    }
}

global settings := New settingsClass
 
/**
* Class for dictionaries.
* Initializing:
*    Create the dictionary object with "chorded_keys := true" for it to behave like a dictionary of chords.
* Properties:
*    entries - number of entries in the dictionary
* Methods:
*    LookUp(shortcut)     - returns expanded text or false if not found
*    ReverseLookUp(text)  - returns corresponding shortcut or false if not found
*    Load([file])         - Reloads the dictionary entries from the current dictionary file or from the specified file
*    Add(shortcut, text)  - Adds the entry into the dictionary
*/
Class DictionaryClass {
    _chorded := false
    _file := ""
    _entries := {}
    _reverse_entries := {}
    _pause_loading := true
    ; Public properties and methods
    entries {
        get { 
            return this._entries.Count() 
        }
    }
    LookUp(shortcut) {
        if ( this._entries.HasKey(shortcut) )
            return this._entries[shortcut]
        else
            return false
    }
    ReverseLookUp(text) {
        if ( this._reverse_entries.HasKey(text) )
            return this._reverse_entries[text]
        else
            return false
    }
    Load(filename := "") {
        this._pause_loading := true
        if (filename == "")
            filename := this._file
        if (filename != "") {
            this._file := filename
            this._LoadShortcuts()
        } else {
            MsgBox, , % "ZipChord", % "Error: Tried to open a dictionary without specifying the file." 
        }
    }
    Add(shortcut, text) {
        if( ! this._RegisterShortcut(shortcut, text, true) )
            return False
        return True
    }
    ; Private functions
    __New(chorded_keys := false) {
        this._chorded := chorded_keys
    }
    ; Load chords from a dictionary file
    _LoadShortcuts() {
        this._entries := {}
        this._reverse_entries := {}
        Loop, Read, % this._file
        {
            columns := StrSplit(A_LoopReadLine, A_Tab, , 3)
            if (columns[2] && columns[1] != "") {
                if (! this._RegisterShortcut(columns[1], columns[2]))  {
                    if this._AskWhetherToStop()
                        Break
                }
            }
        }
    }
    ; Adds a new pair of chord and its expanded text directly to 'this._entries'
    _RegisterShortcut(newch_unsorted, newword, write_to_file:=false) {
        if (this._chorded)
            newch := Arrange(newch_unsorted)
        else
            newch := newch_unsorted
        if (! this._IsShortcutOK(newch, newword))
            return false
        if (this._chorded && StrLen(RegExReplace(newch,"(.)(?=.*\1)")) != StrLen(newch)) {  ; the RegEx removes duplicate letters to check for repetition of characters
            MsgBox ,, % "ZipChord", % "Each key can be entered only once in the same chord."
            Return false
        }
        ObjRawSet(this._entries, newch, newword)
        if ( ! InStr(newword, " ") )
            ObjRawSet(this._reverse_entries, newword, newch_unsorted)
        if (write_to_file)
            FileAppend % "`r`n" newch_unsorted "`t" newword, % this._file, UTF-8  ; saving unsorted for easier human readability of the dictionary
        return true
    }
    _IsShortcutOK(shortcut, word) {
        dest := this._chorded ? "chord" : "shorthand"
        if (occupied := this.LookUp(shortcut)) {
            MsgBox ,, % "ZipChord", % Format("The {1} '{2}' is already in use for '{3}'.`nPlease use a different {1} for '{4}'.", dest, shortcut, occupied, word)
            Return false
        }
        if (StrLen(shortcut)<2) {
            MsgBox ,, % "ZipChord", % Format("The {1} for '{2}' needs to be at least two characters.", dest, word)
            Return false
        }
        if (word=="") {
            MsgBox ,, % "ZipChord", % "There is no word being provided for the shortcut."
            Return false
        }
        Return True
    }
    _AskWhetherToStop() {
        if (this._pause_loading) {
        MsgBox, 4, % "ZipChord", % "Would you like to continue loading the dictionary file?`n`nIf Yes, you'll see all errors in the dictionary.`nIf No, the rest of the dictionary will be ignored."
        IfMsgBox Yes
            this._pause_loading := false
        else
            Return True
        }
        Return False
    }
}

global chords := New DictionaryClass(true)
global shorthands := New DictionaryClass

; Processing input and output 

chord_buffer := ""   ; stores the sequence of simultanously pressed keys
chord_candidate := ""    ; chord candidate which qualifies for chord
shorthand_buffer := ""   ; stores the sequence of uninterrupted typed keys
capitalize_shorthand := false  ; should the shorthand be capitalized

global start := 0 ; tracks start time of two keys pressed at once

; constants and variable to track the difference between key presses and output (because of smart spaces and punctuation)
global DIF_NONE := 0
    , DIF_EXTRA_SPACE := 1
    , DIF_REMOVED_SMART_SPACE := 2
    , DIF_IGNORED_SPACE := 4
    , difference := DIF_NONE   ; tracks the difference between keys pressed and output (because of smart spaces and punctuation)
    , final_difference := DIF_NONE

; Characteristics of last output: constants and variables
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

global debug := New DebugClass

Initialize()
Return   ; To prevent execution of any of the following code, except for the always-on keyboard shortcuts below:

;; Permanent Hotkeys
; -------------------

; An always enabled Ctrl+Shift+C hotkey held long to open ZipChord menu.
~^+c::
    Sleep 300
    if GetKeyState("c","P")
        ShowMainDialog()
    Return

; An always-on Ctrl+C hotkey held long to add a new chord to the dictionary.
~^c::
    Sleep 300
    if GetKeyState("c","P")
        AddShortcut()
    Return

; The rest of the code from here on behaves like in normal programming languages: It is not executed unless called from somewhere else in the code, or triggered by dynamically defined hotkeys.

;; Initilization and Wiring
; ---------------------------

Initialize() {
    settings.Read()
    if (settings.preferences & PREF_FIRST_RUN) {
        settings.preferences &= ~PREF_FIRST_RUN
        FileInstall, ..\dictionaries\chords-en-qwerty.txt, % "chords-en-starting.txt"
        FileInstall, ..\dictionaries\shorthands-english.txt, % "shorthands-english-starting.txt"
    }
    settings.chord_file := CheckDictionaryFileExists(settings.chord_file, "chord")
    settings.shorthand_file := CheckDictionaryFileExists(settings.shorthand_file, "shorthand")
    settings.Write()
    if (!FileExist("locales.ini")) {
        default_locale := new localeClass
        SavePropertiesToIni(default_locale, "English US", "locales.ini")
    }
    BuildMainDialog()
    BuildLocaleDialog()
    BuildOSD()
    UI_AddShortcut_Build()
    chords.Load(settings.chord_file)
    shorthands.Load(settings.shorthand_file)
    UpdateDictionaryUI()
    WireHotkeys("On")
    ShowMainDialog()
}

; WireHotKeys(["On"|"Off"]): Creates or releases hotkeys for tracking typing and chords
WireHotkeys(state) {
    global keys
    interrupts := "Del|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|LButton|RButton|BS|Tab" ; keys that interrupt the typing flow
    Loop Parse, % keys.all
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
    Loop Parse, % interrupts , |
    {
        Hotkey, % "~" A_LoopField, Interrupt, %state%
        Hotkey, % "~^" A_LoopField, Interrupt, %state%
    }
    Hotkey, % "~Enter", Enter_key, %state%
}

; Main code. This is where the magic happens. Tracking keys as they are pressed down and released:

;; Chord Detection
; ------------------

KeyDown:
    key := StrReplace(A_ThisHotkey, "Space", " ")
    debug.Log("KeyDown " key)
    ; First, we differentiate if the key was pressed while holding Shift, and store it under 'key':
    if ( StrLen(A_ThisHotkey)>2 && SubStr(A_ThisHotkey, 2, 1) == "+" ) {
        shifted := true
        key := SubStr(key, 3, 1)
    } else {
        shifted := false
        key := SubStr(key, 2, 1)
    }

    if (chord_candidate != "") {  ; if there is an existing potential chord that is being interrupted with additional key presses
        start := 0
        chord_candidate := ""
    }

    if (settings.chords_enabled)
        chord_buffer .= key ; adds to the keys pressed so far (the buffer is emptied upon each key-up)
    ; and when we have two keys, we start the clock for chord recognition sensitivity:
    if (StrLen(chord_buffer)==2) {
        start := A_TickCount 
        if (shifted)
            chord_buffer .= "+"  ; hack to communicate Shift was pressed
    }

    if (settings.shorthands_enabled || (settings.preferences & PREF_SHOW_SHORTCUTS) ) {
        if (key == " " || (! shifted && InStr(keys.remove_space_plain . keys.space_after_plain . keys.capitalizing_plain . keys.other_plain, key)) || (shifted && InStr(keys.remove_space_shift . keys.space_after_shift . keys.capitalizing_shift . keys.other_shift, key)) ) {
            if (shorthand_buffer != "") {
                ; first, we show a hint for a shortcut, if applicable
                if (settings.preferences & PREF_SHOW_SHORTCUTS) {
                    if (settings.chords_enabled)
                        chord_hint := chords.ReverseLookUp(shorthand_buffer)
                    if (settings.shorthands_enabled)
                        shorthand_hint := shorthands.ReverseLookUp(shorthand_buffer)
                    chord_hint := chord_hint ? chord_hint : "" 
                    shorthand_hint := shorthand_hint ? shorthand_hint : "" 
                    if (chord_hint || shorthand_hint)
                        ShowHint(shorthand_buffer, chord_hint, shorthand_hint)
                }
                ; then, we test if it's a shorthand to be expanded 
                if ( settings.shorthands_enabled && expanded := shorthands.LookUp(shorthand_buffer) )
                    OutputShorthand(expanded, key, shifted)
            }
            shorthand_buffer := ""
        } else {    ; i.e. it was not the end of the word
            if (last_output & OUT_INTERRUPTED || last_output & OUT_AUTOMATIC)
                shorthand_buffer := key
            else
                shorthand_buffer .= key
            ; now, the slightly chaotic immediate mode allowing shorthands triggered as soon as they are completed:
            if ( (settings.chording & CHORD_IMMEDIATE_SHORTHANDS) && (expanded := shorthands.LookUp(shorthand_buffer)) ) {
                OutputShorthand(expanded, key, shifted, true)
                shorthand_buffer := ""
            }
        }

        if ( (settings.capitalization != CAP_OFF) && (StrLen(shorthand_buffer) == 1) ) {
            if ( (last_output & OUT_CAPITALIZE) || shifted )
                capitalize_shorthand := true
            else
                capitalize_shorthand := false
        }
    }

    if (!start)
        difference := DIF_NONE   ; a chord is not being formed, so we reset the diff between keys and output.

    ; Now, we carry over capitalization and categorize the new output on the fly as needed:
    new_output := OUT_CHARACTER | (last_output & OUT_CAPITALIZE)

    ; if the key pressed is a space
    if (key==" ") {
        if ( (last_output & OUT_SPACE) && (last_output & OUT_AUTOMATIC) ) {  ; i.e. if last output is a smart space
            DelayOutput()
            SendInput {Backspace} ; delete any smart-space
            difference |= DIF_IGNORED_SPACE  ; and account for the output being one character shorter than the chord
        }
        new_output := new_output & ~OUT_AUTOMATIC & ~OUT_CHARACTER | OUT_SPACE
    }

    ; if it's punctuation which doesn't do anything but separates words
    if ( (! shifted && InStr(keys.other_plain, key)) || (shifted && InStr(keys.other_shift, key)) )
        new_output := new_output & ~OUT_CHARACTER | OUT_PUNCTUATION

    ; if it's punctuation that removes a smart space before it 
    if ( (! shifted && InStr(keys.remove_space_plain, key)) || (shifted && InStr(keys.remove_space_shift, key)) ) {
        new_output := new_output & ~OUT_CHARACTER | OUT_PUNCTUATION
        if ( (last_output & OUT_SPACE) && (last_output & OUT_AUTOMATIC) ) {  ; i.e. a smart space
            DelayOutput()
            SendInput {Backspace}{Backspace}
            difference |= DIF_REMOVED_SMART_SPACE
            if (shifted)
                SendInput +%key%
            else
                SendInput %key%
        }
    }

    ; if it's punctuation that should be followed by a space
     if ( (!shifted && InStr(keys.space_after_plain, key)) || (shifted && InStr(keys.space_after_shift, key)) ) {
        new_output := new_output & ~OUT_CHARACTER | OUT_PUNCTUATION
        ; if smart spacing for punctuation is enabled, insert a smart space
        if ( settings.spacing & SPACE_PUNCTUATION ) {
            DelayOutput()
            SendInput {Space}
            difference |= DIF_EXTRA_SPACE
            new_output |= OUT_SPACE | OUT_AUTOMATIC
        } else {
            new_output |= OUT_SPACE_AFTER ; we might need to add a space before a chord.
        }
    }

    ; if the user had ben manually typing a word and completed it (which we know because some non-letter was just typed), we reset the auto-capitalization so we don't capitalize the following word 
    if ( (fixed_output & OUT_CHARACTER) && ! (new_output & OUT_CHARACTER) )
         new_output &= ~OUT_CAPITALIZE

    ; set 'uppercase' for punctuation that capitalizes following text 
    if ( (! shifted && InStr(keys.capitalizing_plain, key)) || (shifted && InStr(keys.capitalizing_shift, key)) )
        new_output |= OUT_CAPITALIZE

    ; if it's neither, it should be a regural character, and it might need capitalization
    if ( !(new_output & OUT_PUNCTUATION) && !(new_output & OUT_SPACE) ) {
        if (shifted)
            new_output := new_output & ~OUT_CAPITALIZE ; manually capitalized, so the flag get turned off
        else
            if ( settings.capitalization==CAP_ALL && (! shifted) && (last_output & OUT_CAPITALIZE) ) {
                DelayOutput()
                cap_key := RegExReplace(key, "(.*)", "$U1")
                SendInput % "{Backspace}{Text}" RegExReplace(key, "(.*)", "$U1") ; deletes the character and sends its uppercase version. Uses {Text} because otherwise, Unicode extended characters could not be upper-cased correctly
                new_output := new_output & ~OUT_CAPITALIZE  ; automatically capitalized, and the flag gets turned off
            }
    }

    last_output := new_output
Return

KeyUp:
    Critical
    debug.Log("KeyUp")
    ; if at least two keys were held at the same time for long enough, let's save our candidate chord and exit
    if ( start && chord_candidate == "" && (A_TickCount - start > settings.input_delay) ) {
        chord_candidate := chord_buffer
        final_difference := difference
        chord_buffer := ""
        start := 0
        debug.Log("/KeyUp-chord")
        Critical Off
        Return
    }
    chord_buffer := ""
    start := 0
    ; when another key is lifted (so we could check for false triggers in rolls) we test and expand the chord
    if (chord_candidate != "") {
        if (InStr(chord_candidate, "+")) {
            ;if Shift is not allowed as a chord key, we just capitalize the chord.
            if (!(settings.chording & CHORD_ALLOW_SHIFT)) {
            fixed_output |= OUT_CAPITALIZE
            chord_candidate := StrReplace(chord_candidate, "+")
            }
        }
        chord := Arrange(chord_candidate)
        if ( expanded := chords.LookUp(chord)) {
            shorthand_buffer := ""
            debug.Log("Chord for:" expanded)
            affixes := ProcessAffixes(expanded)
            ; if we aren't restricted, we print a chord
            if ( (affixes & AFFIX_SUFFIX) || IsUnrestricted()) {
                DelayOutput()
                debug.Log("OUTPUTTING")
                RemoveRawChord(chord)
                OpeningSpace(affixes & AFFIX_SUFFIX)
                if (InStr(expanded, "{")) {
                    ; we send any expanded text that includes { as straight directives:
                    SendInput % expanded
                } else {
                    ; and there rest as {Text} that gets capitalized if needed:
                    if ( (fixed_output & OUT_CAPITALIZE) && (settings.capitalization != CAP_OFF) )
                        SendInput % "{Text}" RegExReplace(expanded, "(^.)", "$U1")
                    else
                        SendInput % "{Text}" expanded
                }
                last_output := OUT_CHARACTER | OUT_AUTOMATIC  ; i.e. a chord (automated typing)
                ; ending smart space
                if (affixes & AFFIX_PREFIX) {
                    last_output |= OUT_PREFIX
                } else if (settings.spacing & SPACE_AFTER_CHORD) {
                    SendInput {Space}
                    last_output := OUT_SPACE | OUT_AUTOMATIC
                }
            }
            else {
                ; output was restricted
                fixed_output := last_output
                chord_candidate := ""
                debug.Log("RESTRICTED")
            }
            ; Here, we are not deleting the keys because we assume it was rolled typing.
        }
        else {
            if (settings.chording & CHORD_DELETE_UNRECOGNIZED)
                RemoveRawChord(chord)
        }
        chord_candidate := ""
    }
    fixed_output := last_output ; and this last output is also the last fixed output.
    debug.Log("/KeyUp-fixed")
    Critical Off
Return

;; Helper functions
; ------------------

; Delay output by defined delay
DelayOutput() {
    if (settings.output_delay)
        Sleep settings.output_delay
}

OutputShorthand(expanded, key, shifted, immediate := false) {
    ; needs to access the following variables
    global capitalize_shorthand
    global shorthand_buffer
    DelayOutput()
    affixes := ProcessAffixes(expanded)
    debug.Log("SHORTHAND " expanded)
    adj := StrLen(shorthand_buffer)
    if (! immediate)
        adj++
    if (affixes & AFFIX_SUFFIX)
        adj++
    SendInput {Backspace %adj%}
    if (capitalize_shorthand)
        SendInput % "{Text}" RegExReplace(expanded, "(^.)", "$U1")
    else
        SendInput % "{Text}" expanded
    if (immediate) {
        if ( (settings.spacing & SPACE_AFTER_CHORD) && !(affixes & AFFIX_PREFIX) ) {
            SendInput {Space}
            last_output := OUT_SPACE | OUT_AUTOMATIC
        }
    } else {
        if (shifted)
            SendInput +%key%
        else
            SendInput %key%
        if (key == " " && (affixes & AFFIX_PREFIX))
            SendInput {Backspace}
    }
}

; detect and adjust expansion for suffixes and prefixes
ProcessAffixes(ByRef phrase) {
    affixes := AFFIX_NONE
    if (SubStr(phrase, 1, 1) == "~") {
        phrase := SubStr(phrase, 2)
        affixes |= AFFIX_SUFFIX
    }
    if (SubStr(phrase, StrLen(phrase), 1) == "~") {
        phrase := SubStr(phrase, 1, StrLen(phrase)-1)
        affixes |= AFFIX_PREFIX
    }
    Return affixes
}

;remove raw chord output
RemoveRawChord(output) {
    adj :=0
    ; we remove any Shift from the chord because that is not a real character
    output := StrReplace(output, "+")
    if (final_difference & DIF_EXTRA_SPACE)
        adj++
    if (final_difference & DIF_IGNORED_SPACE)
        adj--
    adj += StrLen(output)
    SendInput {Backspace %adj%}
    if (final_difference & DIF_REMOVED_SMART_SPACE)
        SendInput {Space}
}

; check we can output chord here
IsUnrestricted() {
    ; If we're in unrestricted mode, we're good
    if (!(settings.chording & CHORD_RESTRICT))
        Return true
    ; If last output was automated (smart space or chord), punctuation, a 'prefix' (which  includes opening punctuation), it was interrupted, or it was a space, we can also go ahead.
    if ( (fixed_output & OUT_AUTOMATIC) || (fixed_output & OUT_PUNCTUATION) || (fixed_output & OUT_PREFIX) || (fixed_output & OUT_INTERRUPTED) || (fixed_output & OUT_SPACE) )
        Return true
    Return false
}

; Handles opening spacing as needed (single-use helper function)
OpeningSpace(attached) {
    ; if there is a smart space, we remove it for suffixes, and we're done
    if ( (fixed_output & OUT_SPACE) && (fixed_output & OUT_AUTOMATIC) ) {
        if (attached)
            SendInput {Backspace}
        Return
    }
    ; if adding smart spaces before is disabled, we are done too
    if (! (settings.spacing & SPACE_BEFORE_CHORD))
        Return
    ; if the last output was punctuation that does not ask for a space, we are done 
    if ( (fixed_output & OUT_PUNCTUATION) && ! (fixed_output & OUT_SPACE_AFTER) )
        Return
    ; and we don't start with a smart space after intrruption, a space, after a prefix, and for suffix
    if (fixed_output & OUT_INTERRUPTED || fixed_output & OUT_SPACE || fixed_output & OUT_PREFIX || attached)
        Return
    ; if we get here, we probably need a space in front of the chord
    SendInput {Space}
}

; Sort the string alphabetically
Arrange(raw) {
    raw := RegExReplace(raw, "(.)", "$1`n")
    Sort raw
    Return StrReplace(raw, "`n")
}

ReplaceWithVariants(text, enclose_latin_letters:=false) {
    new_str := text
    new_str := StrReplace(new_str, "+", Chr(8679))
    new_str := StrReplace(new_str, " ", Chr(9251))
    if (enclose_latin_letters) {
        Loop, 26
            new_str := StrReplace(new_str, Chr(96 + A_Index), Chr(127279 + A_Index))
        new_str := RegExReplace(new_str, "(?<=.)(?=.)", " ")
    }
    Return new_str
}

Interrupt:
    last_output := OUT_INTERRUPTED
    fixed_output := last_output
    debug.Write("Interrupted")
Return

Enter_key:
    last_output := OUT_INTERRUPTED | OUT_CAPITALIZE
    fixed_output := last_output
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
    if (!StrLen(copied_text)) {
        MsgBox ,, ZipChord, % "First, select a word you would like to define a chord for, and then press and hold Ctrl+C again."
        Return
    }
    UI_AddShortcut_Show(copied_text)
}

;; Main UI
; ---------

; variables holding the UI elements and selections
global UI_input_delay
    , UI_output_delay
    , UI_space_before
    , UI_space_after
    , UI_space_punctuation
    , UI_delete_unrecognized
    , UI_show_tips
    , UI_immediate_shorthands
    , UI_capitalization
    , UI_allow_shift
    , UI_restrict_chords
    , UI_chord_file
    , UI_shorthand_file
    , UI_chord_entries := "0"
    , UI_shorthand_entries := "0"
    , UI_chords_enabled := 1
    , UI_shorthands_enabled := 1
    , UI_tab := 0
    , UI_locale
    , UI_debugging

; Prepare UI
BuildMainDialog() {
    Gui, UI_main_window:New, , ZipChord
    Gui, Font, s10, Segoe UI
    Gui, Margin, 15, 15
    Gui, Add, Tab3, vUI_tab, % "  Dictionaries  |  Detection  |  Output  |  About  "
    Gui, Add, Text, Section, &Keyboard and language
    Gui, Add, DropDownList, y+10 w150 vUI_locale
    Gui, Add, Button, x+40 w80 gButtonCustomizeLocale, % "C&ustomize"
    Gui, Add, GroupBox, xs w310 h140 vUI_chord_entries, Chord dictionary
    Gui, Add, Text, xp+20 yp+30 Section w260 vUI_chord_file Left, [file name]
    Gui, Add, Button, xs Section gBtnSelectChordDictionary w80, &Open
    Gui, Add, Button, gBtnEditChordDictionary ys w80, &Edit
    Gui, Add, Button, gBtnReloadChordDictionary ys w80, &Reload
    Gui, Add, Checkbox, vUI_chords_enabled xs Checked%UI_chords_enabled%, Use &chords
    Gui, Add, GroupBox, xs-20 y+30 w310 h140 vUI_shorthand_entries, Shorthand dictionary
    Gui, Add, Text, xp+20 yp+30 Section w260 vUI_shorthand_file Left, [file name]
    Gui, Add, Button, xs Section gBtnSelectShorthandDictionary w80, O&pen
    Gui, Add, Button, gBtnEditShorthandDictionary ys w80, Edi&t
    Gui, Add, Button, gBtnReloadShorthandDictionary ys w80, Reloa&d
    Gui, Add, Checkbox, vUI_shorthands_enabled xs Checked%UI_shorthands_enabled%, Use &shorthands
    Gui, Tab, 2
    Gui, Add, Checkbox, vUI_show_tips, % "Show &hints for chords and shorthands"
    Gui, Add, GroupBox, w310 h180, Chords
    Gui, Add, Text, xp+20 yp+30 Section, &Detection delay (ms):
    Gui, Add, Edit, vUI_input_delay Right xp+150 w40, 99
    Gui, Add, Checkbox, vUI_restrict_chords xs, &Restrict chords while typing
    Gui, Add, Checkbox, vUI_allow_shift, Allow &Shift in chords 
    Gui, Add, Checkbox, vUI_delete_unrecognized, % "Delete &mistyped chords"
    Gui, Add, GroupBox, xs-20 y+30 w310 h70, % "Shorthands"
    Gui, Add, Checkbox, vUI_immediate_shorthands xp+20 yp+30 Section, % "E&xpand shorthands immediately"
    Gui, Tab, 3
    Gui, Add, GroupBox, w310 h120 Section, Smart spaces
    Gui, Add, Checkbox, vUI_space_before xs+20 ys+30, In &front of chords
    Gui, Add, Checkbox, vUI_space_after xp y+10, &After chords and shorthands
    Gui, Add, Checkbox, vUI_space_punctuation xp y+10, After &punctuation
    Gui, Add, Text, xs y+30, Auto-&capitalization:
    Gui, Add, DropDownList, vUI_capitalization AltSubmit Right xp+150 w130, Off|For shortcuts|For all input
    Gui, Add, Text, xs y+m, &Output delay (ms):
    Gui, Add, Edit, vUI_output_delay Right xp+150 w40, 99
    Gui, Tab
    Gui, Add, Button, Default w80 xm+240 gButtonOK, OK
    Gui, Tab, 4
    Gui, Add, Text, X+m Y+m, ZipChord`nversion %version%
    Gui, Add, Checkbox, vUI_debugging, &Log this session (debugging)
    Gui, Font, Underline cBlue
    Gui, Add, Text, xp Y+m gWebsiteLink, Help and documentation
    Gui, Add, Text, xp Y+m gReleaseLink, Latest releases (check for updates)

    ; Create taskbar tray menu:
    Menu, Tray, Add, Open Settings, ShowMainDialog
    Menu, Tray, Default, Open Settings
    Menu, Tray, Tip, ZipChord
    Menu, Tray, Click, 1
}

ShowMainDialog() {
    debug.Stop()
    Gui, UI_main_window:Default
    GuiControl Text, UI_input_delay, % settings.input_delay
    GuiControl Text, UI_output_delay, % settings.output_delay
    GuiControl , , UI_allow_shift, % (settings.chording & CHORD_ALLOW_SHIFT) ? 1 : 0
    GuiControl , , UI_restrict_chords, % (settings.chording & CHORD_RESTRICT) ? 1 : 0
    GuiControl , , UI_immediate_shorthands, % (settings.chording & CHORD_IMMEDIATE_SHORTHANDS) ? 1 : 0
    GuiControl , , UI_delete_unrecognized, % (settings.chording & CHORD_DELETE_UNRECOGNIZED) ? 1 : 0
    GuiControl , , UI_show_tips, % (settings.preferences & PREF_SHOW_SHORTCUTS) ? 1 : 0
    GuiControl , Choose, UI_capitalization, % settings.capitalization
    GuiControl , , UI_space_before, % (settings.spacing & SPACE_BEFORE_CHORD) ? 1 : 0
    GuiControl , , UI_space_after, % (settings.spacing & SPACE_AFTER_CHORD) ? 1 : 0
    GuiControl , , UI_space_punctuation, % (settings.spacing & SPACE_PUNCTUATION) ? 1 : 0
    GuiControl , , UI_chords_enabled, % settings.chords_enabled
    GuiControl , , UI_shorthands_enabled, % settings.shorthands_enabled
    ; debugging is always set to disabled
    GuiControl , , UI_debugging, 0
    GuiControl, Choose, UI_tab, 1 ; switch to first tab
    UpdateLocaleInMainUI(settings.locale)
    Gui, Show,, ZipChord
}

UpdateLocaleInMainUI(selected_loc) {
    IniRead, sections, locales.ini
    Gui, UI_main_window:Default
    GuiControl, , UI_locale, % "|" StrReplace(sections, "`n", "|")
    GuiControl, Choose, UI_locale, % selected_loc
}

ButtonOK() {
    Gui, Submit, NoHide
    global keys
    ; gather new settings from UI...
    if (RegExMatch(UI_input_delay,"^\d+$") && RegExMatch(UI_output_delay,"^\d+$")) {
            settings.input_delay := UI_input_delay + 0
            settings.output_delay := UI_output_delay + 0
    } else {
        MsgBox ,, ZipChord, % "The chord sensitivity needs to be entered as a whole number."
        Return
    }
    settings.capitalization := UI_capitalization
    settings.spacing := UI_space_before * SPACE_BEFORE_CHORD + UI_space_after * SPACE_AFTER_CHORD + UI_space_punctuation * SPACE_PUNCTUATION
    settings.chording := UI_delete_unrecognized * CHORD_DELETE_UNRECOGNIZED + UI_allow_shift * CHORD_ALLOW_SHIFT + UI_restrict_chords * CHORD_RESTRICT + UI_immediate_shorthands * CHORD_IMMEDIATE_SHORTHANDS
    settings.locale := UI_locale
    settings.chords_enabled := UI_chords_enabled
    settings.shorthands_enabled := UI_shorthands_enabled
    settings.preferences := UI_show_tips ? (settings.preferences | PREF_SHOW_SHORTCUTS) : (settings.preferences & ~ PREF_SHOW_SHORTCUTS)
    ; ...and save them to Windows Registry
    settings.Write()
    ; We always want to rewire hotkeys in case the keys have changed.
    WireHotkeys("Off")
    LoadPropertiesFromIni(keys, UI_locale, "locales.ini")
    if (UI_chords_enabled || UI_shorthands_enabled)
        WireHotkeys("On")
    if (UI_debugging)
        debug.Start()
    CloseMainDialog()
}

UI_main_windowGuiClose() {
    CloseMainDialog()
}
UI_main_windowGuiEscape() {
    CloseMainDialog()
}

CloseMainDialog() {
    Gui, UI_main_window:Default
    Gui, Submit
    if (settings.preferences & PREF_SHOW_CLOSING_TIP)
        ShowClosingTipDialog()
}

WebsiteLink:
Run https://github.com/psoukie/zipchord#readme
Return

ReleaseLink:
Run https://github.com/psoukie/zipchord/releases
Return

; Functions supporting UI

; Update UI with dictionary details
UpdateDictionaryUI() {
    if StrLen(settings.chord_file) > 40
        filestr := "..." SubStr(settings.chord_file, -34)
    else
        filestr := settings.chord_file
    Gui, UI_main_window:Default
    GuiControl Text, UI_chord_file, %filestr%
    entriesstr := "Chord dictionary (" chords.entries
    entriesstr .= (chords.entries==1) ? " chord)" : " chords)"
    GuiControl Text, UI_chord_entries, %entriesstr%
    if StrLen(settings.shorthand_file) > 40
        filestr := "..." SubStr(settings.shorthand_file, -34)
    else
        filestr := settings.shorthand_file
    GuiControl Text, UI_shorthand_file, %filestr%
    entriesstr := "Shorthand dictionary (" shorthands.entries
    entriesstr .= (shorthands.entries==1) ? " shorthand)" : " shorthands)"
    GuiControl Text, UI_shorthand_entries, %entriesstr%
}

; Run Windows File Selection to open a dictionary
BtnSelectChordDictionary() {
    FileSelectFile dict, , %A_ScriptDir%, Open Chord Dictionary, Text files (*.txt)
    if (dict != "") {
        settings.chord_file := dict
        chords.Load(dict)
        UpdateDictionaryUI()
    }
    Return
}

BtnSelectShorthandDictionary() {
    FileSelectFile dict, , %A_ScriptDir%, Open Shorthand Dictionary, Text files (*.txt)
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

ButtonCustomizeLocale() {
    WireHotkeys("Off")  ; so the user can edit the values without interference
    Gui, Submit, NoHide ; to get the currently selected UI_locale
    ShowLocaleDialog(UI_locale)
}

;; Closing Tip UI
; ----------------

global UI_dont_show_again := 0

ShowClosingTipDialog() {
    Gui, UI_closing_tip:New, , % "ZipChord"
    Gui, Margin, 20, 20
    Gui, Font, s10, Segoe UI
    Gui, Add, Text, +Wrap w430, % "Select a word and press and hold Ctrl-C to define a shortcut for it or to see its existing shortcut.`n`nPress and hold Ctrl-Shift-C to open the ZipChord menu again.`n"
    Gui, Add, Checkbox, vUI_dont_show_again, % "Do &not show this tip again."
    Gui, Add, Button, gBtnCloseTip x370 w80 Default, OK
    Gui, Show, w470
}

BtnCloseTip() {
    Gui, UI_closing_tip:Submit
    if (UI_dont_show_again) {
        settings.preferences &= ~PREF_SHOW_CLOSING_TIP
        settings.Write()
    }
}

UI_closing_tipGuiClose() {
    Gui, UI_closing_tip:Submit
}
UI_closing_tipGuiEscape() {
    Gui, UI_closing_tip:Submit
}


;; Locale UI
; -----------

global UI_locale_window
    , UI_loc_name
    , UI_loc_all
    , UI_loc_space_after_plain
    , UI_loc_space_after_shift
    , UI_loc_capitalizing_plain
    , UI_loc_capitalizing_shift
    , UI_loc_remove_space_plain
    , UI_loc_remove_space_shift
    , UI_loc_other_plain
    , UI_loc_other_shift

BuildLocaleDialog() {
    Gui, UI_locale_window:New, , Keyboard and language settings
    Gui, Margin, 15, 15
    Gui, Font, s10, Segoe UI
    Gui, Add, Text, Section, &Locale name
    Gui, Add, DropDownList, w120 vUI_loc_name gChangeLocaleUI
    Gui, Add, Button, y+30 w80 gButtonRenameLocale, &Rename
    Gui, Add, Button, w80 gButtonDeleteLocale, &Delete 
    Gui, Add, Button, w80 gButtonNewLocale, &New
    Gui, Add, Button, y+90 w80 gClose_Locale_Window Default, Close
    Gui, Add, GroupBox, ys h330 w460, Locale settings
    Gui, Add, Text, xp+20 yp+30 Section, &All keys (except dead keys)
    Gui, Font, s10, Consolas
    Gui, Add, Edit, y+10 w420 r1 vUI_loc_all
    Gui, Font, s10 w700, Segoe UI
    Gui, Add, Text, yp+40, Punctuation
    Gui, Add, Text, xs+160 yp, Unmodified keys
    Gui, Add, Text, xs+300 yp, If Shift was pressed
    Gui, Font, w400
    Gui, Add, Text, xs Section, Remove space before
    Gui, Add, Text, y+20, Follow by a space
    Gui, Add, Text, y+20, Capitalize after
    Gui, Add, Text, y+20, Other
    Gui, Add, Button, xs+240 yp+40 w100 gButtonSaveLocale, Save Changes
    Gui, Font, s10, Consolas
    Gui, Add, Edit, xs+160 ys Section w120 r1 vUI_loc_remove_space_plain
    Gui, Add, Edit, xs w120 r1 vUI_loc_space_after_plain
    Gui, Add, Edit, xs w120 r1 vUI_loc_capitalizing_plain
    Gui, Add, Edit, xs w120 r1 vUI_loc_other_plain
    Gui, Add, Edit, xs+140 ys Section w120 r1 vUI_loc_remove_space_shift
    Gui, Add, Edit, xs w120 r1 vUI_loc_space_after_shift
    Gui, Add, Edit, xs w120 r1 vUI_loc_capitalizing_shift
    Gui, Add, Edit, xs w120 r1 vUI_loc_other_shift
}

; Shows the locale dialog with existing locale matching locale_name; or (if set to 'false') the first available locale.  
ShowLocaleDialog(locale_name) {
    Gui, UI_locale_window:Default
    loc_obj := new localeClass
    IniRead, sections, locales.ini
    if (locale_name) {
        LoadPropertiesFromIni(loc_obj, locale_name, "locales.ini")
    } else {
        locales := StrSplit(sections, "`n")
        locale_name := locales[1]
    }
    GuiControl, , UI_loc_name, % "|" StrReplace(sections, "`n", "|")
    GuiControl, Choose, UI_loc_name, % locale_name
    GuiControl, , UI_loc_all, % loc_obj.all
    GuiControl, , UI_loc_remove_space_plain, % loc_obj.remove_space_plain
    GuiControl, , UI_loc_remove_space_shift, % loc_obj.remove_space_shift
    GuiControl, , UI_loc_space_after_plain, % loc_obj.space_after_plain
    GuiControl, , UI_loc_space_after_shift, % loc_obj.space_after_shift
    GuiControl, , UI_loc_capitalizing_plain, % loc_obj.capitalizing_plain
    GuiControl, , UI_loc_capitalizing_shift, % loc_obj.capitalizing_shift
    GuiControl, , UI_loc_other_plain, % loc_obj.other_plain
    GuiControl, , UI_loc_other_shift, % loc_obj.other_shift
    Gui Submit, NoHide
    Gui, Show
}

; when the locale name dropdown changes: 
ChangeLocaleUI() {
    Gui, UI_locale_window:Submit
    ShowLocaleDialog(UI_loc_name)
}

ButtonNewLocale() {
    InputBox, new_name, ZipChord, % "Enter a name for the new keyboard and language setting."
        if ErrorLevel
            Return
    new_loc := New localeClass
    SavePropertiesToIni(new_loc, new_name, "locales.ini")
    ShowLocaleDialog(new_name)
}

ButtonDeleteLocale(){
    IniRead, sections, locales.ini
    If (! InStr(sections, "`n")) {
        MsgBox ,, % "ZipChord", % Format("The setting '{}' is the only setting on the list and cannot be deleted.", UI_loc_name)
        Return
    }
    MsgBox, 4, % "ZipChord", % Format("Do you really want to delete the keyboard and language settings for '{}'?", UI_loc_name)
    IfMsgBox Yes
    {
        IniDelete, locales.ini, % UI_loc_name
        ShowLocaleDialog(false)
    }
}

ButtonRenameLocale() {
    temp_loc := new localeClass
    InputBox, new_name, ZipChord, % Format("Enter a new name for the locale '{}':", UI_loc_name)
    if ErrorLevel
        Return
    IniRead, locale_exists, locales.ini, % locale_name, all
    if (locale_exists == "ERROR") {
        MsgBox, 4, % "ZipChord", % Format("There are already settings under the name '{}'. Do you wish to overwrite them?", new_name)
            IfMsgBox No
                Return
    }
    LoadPropertiesFromIni(temp_loc, UI_loc_name, "locales.ini")
    IniDelete, locales.ini, % UI_loc_name
    SavePropertiesToIni(temp_loc, new_name, "locales.ini")
    ShowLocaleDialog(new_name)
}

UI_locale_windowGuiClose() {
    Close_Locale_Window()
}
UI_locale_windowGuiEscape() {
    Close_Locale_Window()
}

Close_Locale_Window() {
    Gui, UI_locale_window:Submit
    UpdateLocaleInMainUI(global UI_loc_name)
}

ButtonSaveLocale() {
    new_loc := new localeClass
    Gui, UI_locale_window:Submit, NoHide
    new_loc.all := UI_loc_all
    new_loc.space_after_plain := UI_loc_space_after_plain
    new_loc.space_after_shift := UI_loc_space_after_shift
    new_loc.capitalizing_plain := UI_loc_capitalizing_plain
    new_loc.capitalizing_shift := UI_loc_capitalizing_shift
    new_loc.remove_space_plain := UI_loc_remove_space_plain
    new_loc.remove_space_shift := UI_loc_remove_space_shift
    new_loc.other_plain := UI_loc_other_plain
    new_loc.other_shift := UI_loc_other_shift
    SavePropertiesToIni(new_loc, UI_loc_name, "locales.ini")
}

;; Add Shortcut UI
; -----------------

global UI_AddShortcut_text
    , UI_AddShortcut_chord
    , UI_AddShortcut_shorthand
    , UI_AddShortcut_btnSaveChord
    , UI_AddShortcut_btnSaveShorthand
UI_AddShortcut_Build() {
    Gui, UI_AddShortcut:New, , % "Add Shortcut"
    Gui, Margin, 25, 25
    Gui, Font, s10, Segoe UI
    Gui, Add, Text, Section, % "&Expanded text"
    Gui, Margin, 15, 15
    Gui, Add, Edit, y+10 w220 vUI_AddShortcut_text
    Gui, Add, Button, x+20 yp w100 gUI_AddShortcut_Adjust, % "&Adjust"
    Gui, Add, GroupBox, xs h120 w360, % "&Chord"
    Gui, Add, Edit, xp+20 yp+30 Section w200 vUI_AddShortcut_chord
    Gui, Add, Button, x+20 yp w100 gUI_AddShortcut_SaveChord vUI_AddShortcut_btnSaveChord, % "&Save"
    Gui, Add, Text, xs +Wrap w320, % "Individual keys that make up the chord, without pressing Shift or other modifier keys."
    Gui, Add, GroupBox, xs-20 y+30 h120 w360, % "S&horthand"
    Gui, Add, Edit, xp+20 yp+30 Section w200 vUI_AddShortcut_shorthand
    Gui, Add, Button, x+20 yp w100 gUI_AddShortcut_SaveShorthand vUI_AddShortcut_btnSaveShorthand, % "Sa&ve"
    Gui, Add, Text, xs +Wrap w320, % "Sequence of keys of the shorthand, without pressing Shift or other modifier keys."
    Gui, Margin, 25, 25
    Gui, Add, Button, gUI_AddShortcut_Close x265 y+30 w100, % "Close" 
}
UI_AddShortcut_Show(exp) {
    WireHotkeys("Off")  ; so the user can edit values without interference
    Gui, UI_AddShortcut:Default
    GuiControl, Disable, UI_AddShortcut_text
    GuiControl,, UI_AddShortcut_text, % exp
    if (chord := chords.ReverseLookUp(exp)) {
        GuiControl, Disable, UI_AddShortcut_chord
        GuiControl, , UI_AddShortcut_chord, % chord
        GuiControl, Disable, UI_AddShortcut_btnSaveChord
    } else {
        GuiControl, Enable, UI_AddShortcut_chord
        GuiControl, , UI_AddShortcut_chord, % ""
        GuiControl, Enable, UI_AddShortcut_btnSaveChord
    }
    if (shorthand := shorthands.ReverseLookUp(exp)) {
        GuiControl, Disable, UI_AddShortcut_shorthand
        GuiControl, , UI_AddShortcut_shorthand, % shorthand
        GuiControl, Disable, UI_AddShortcut_btnSaveShorthand
    } else {
        GuiControl, Enable, UI_AddShortcut_shorthand
        GuiControl, , UI_AddShortcut_shorthand, % ""
        GuiControl, Enable, UI_AddShortcut_btnSaveShorthand
    }
    Gui, Show, w410
}
UI_AddShortcutGuiClose() {
    UI_AddShortcut_Close()
}
UI_AddShortcutGuiEscape() {
    UI_AddShortcut_Close()
}
UI_AddShortcut_Close() {
    Gui, UI_AddShortcut:Hide
    if (settings.chords_enabled || settings.shorthands_enabled)
        WireHotkeys("On")  ; resume normal mode
}
UI_AddShortcut_SaveChord(){
    Gui, Submit, NoHide
    if (chords.Add(UI_AddShortcut_chord, UI_AddShortcut_text)) {
        UI_AddShortcut_Close()
        UpdateDictionaryUI()
    }
}
UI_AddShortcut_SaveShorthand(){
    Gui, Submit, NoHide
    if (shorthands.Add(UI_AddShortcut_shorthand, UI_AddShortcut_text)) {
        UI_AddShortcut_Close()
        UpdateDictionaryUI()
    }
}
UI_AddShortcut_Adjust(){
    GuiControl, , UI_AddShortcut_chord, % ""
    GuiControl, Enable, UI_AddShortcut_chord
    GuiControl, Enable, UI_AddShortcut_btnSaveChord
    GuiControl, , UI_AddShortcut_shorthand, % ""
    GuiControl, Enable, UI_AddShortcut_shorthand
    GuiControl, Enable, UI_AddShortcut_btnSaveShorthand
    GuiControl, Enable, UI_AddShortcut_text
}

;; Shortcut Hint OSD
; -------------------

global UI_hint1
    , UI_hint2
    , UI_hint3
    , UI_OSD_transparency
    , UI_OSD_fading
BuildOSD() {
    Gui, UI_OSD:Default
    Gui +LastFound +AlwaysOnTop -Caption +ToolWindow ; +ToolWindow avoids a taskbar button and an alt-tab menu item.
    Gui, Margin, 10, 10
    Gui, Color, 40E812
    Gui, Font, s32, Consolas  ; Set a large font size (32-point).
    Gui, Add, Text, c3BD511 Center vUI_hint1, WWWWWWWWWWWWWWWWWWWWWWWW  ; to auto-size the window.
    Gui, Add, Text, c3BD511 Center vUI_hint2, WWWWWWWWWWWWWWWWWWWWWWWW
    Gui, Add, Text, c3BD511 Center vUI_hint3, WWWWWWWWWWWWWWWWWWWWWWWW
    ; Make all pixels of this color transparent and make the text itself translucent (150):
}
ShowHint(line1, line2:="", line3 :="") {
    UI_OSD_fading := False
    UI_OSD_transparency := 140
    Gui, UI_OSD:Default
    Gui, Show, NoActivate, ZipChord_OSD
    WinSet, TransColor, 40E812 %UI_OSD_transparency%, ZipChord_OSD
    GuiControl,, UI_hint1, % line1
    GuiControl,, UI_hint2, % ReplaceWithVariants(line2, true)
    GuiControl,, UI_hint3, % ReplaceWithVariants(line3)
    SetTimer, HideOSD, -900
}
HideOSD:
    UI_OSD_fading := true
    Sleep 1000
    Gui, UI_OSD:Default
    while(UI_OSD_fading && UI_OSD_transparency) {
        UI_OSD_transparency -= 10
        WinSet, TransColor, 40E812 %UI_OSD_transparency%, ZipChord_OSD
        Sleep 100
    }
    if (UI_OSD_fading)
        Gui, Hide
Return

;; File and registry functions
; -----------------------------

CheckDictionaryFileExists(dictionary_file, dictionary_type) {
    if (! FileExist(dictionary_file) ) {
        errmsg := Format("The {1} dictionary '{2}' could not be found.`n`n", dictionary_type, dictionary_file)
        ; If we don't have the dictionary, try opening the first file with a matching naming convention.
        new_file := dictionary_type "s*.txt"
        if FileExist(new_file) {
            Loop, Files, %new_file%
                flist .= SubStr(A_LoopFileName, 1, StrLen(A_LoopFileName)-4) "`n"
            Sort flist
            new_file := SubStr(flist, 1, InStr(flist, "`n")-1) ".txt"
            errmsg .= Format("ZipChord detected the dictionary '{}' and is going to open it.", new_file)
        }
        else {
            errmsg .= Format("ZipChord is going to create a new '{}s.txt' dictionary in its own folder.", dictionary_type)
            new_file := dictionary_type "s.txt"
            FileAppend % "This is a " dictionary_type " dictionary for ZipChord. Define " dictionary_type "s and corresponding expanded words in a tab-separated list (one entry per line).`nSee https://github.com/psoukie/zipchord for details.`n`ndm`tdemo", %new_file%, UTF-8
        }
        new_file := A_ScriptDir "\" new_file
        MsgBox ,, ZipChord, %errmsg%
        Return new_file
    }
    Return dictionary_file
}

SavePropertiesToIni(object_to_save, ini_section, ini_filename) {
    For key, value in object_to_save
        IniWrite %value%, %ini_filename%, %ini_section%, %key%
}

LoadPropertiesFromIni(object_destination, ini_section, ini_filename) {
    IniRead, properties, %ini_filename%, %ini_section%
    Loop, Parse, properties, `n
    {
        key := SubStr(A_LoopField, 1, InStr(A_LoopField, "=")-1)
        value := SubStr(A_LoopField, InStr(A_LoopField, "=")+1)
        object_destination[key] := value
    }
}

;; Debugging
; -----------

Class DebugClass {
    static debug_file := ""
    Start() {
        global keys
        FileDelete, "debug.txt"
        this.debug_file := FileOpen("debug.txt", "w")
        this.Write("Please copy the actual text output of your typing below:`n`OUTPUT:`n`nZIPCHORD SETTINGS:")
        For key, value in settings
            this.Write(key "=" value)
        this.Write("LOCALE SETTINGS:")
        For key, value in keys
            this.Write(key "=" value)
        this.Write("`nINPUT LOG:`nEvent`tTimestamp`tlast_output`tfixed_output`tchord_buffer`tchord`tstart")       
    }
    Log(output) {
        global chord_buffer
        global chord
        if ( (this.debug_file != "") || (A_Args[1] == "debug-vs") ) {
            output .= "`t" A_TickCount "`t" last_output "`t" fixed_output "`t" chord_buffer "`t" chord "`t" start
            this.Write(output)
        }
    }
    Write(output) {
        if (A_Args[1] == "debug-vs")
            OutputDebug, % output "`n"
        if (this.debug_file != "")
            this.debug_file.Write(output "`n")
    }
    Stop() {
        if (this.debug_file != "") {
            this.debug_file.Close()
            this.debug_file := ""
            Run % "debug.txt"
        }
    }
}
