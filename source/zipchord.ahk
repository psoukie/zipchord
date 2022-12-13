#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%

; ZipChord by Pavel Soukenik
; Licensed under GPL-3.0
; See https://github.com/psoukie/zipchord/
global version = "1.7.1"

; Default (US English) keyboard and language settings:
global default_keys := "',-./0123456789;=[\]abcdefghijklmnopqrstuvwxyz"
global keys := "" ; Uses default_keys or custom_keys read from the dictionary file.

/*  Preparation for v2
global default_terminators := "',-./;=\]" ; keys that can attach to previous output without a space.
global default_shift_terminators := "',-./0123456789;=\]" ; keys combined with Shift that can attach to previous output without a space.
global default_openers := "'-/=\]" ; keys that can be followed without a space.
global default_shift_openers := "',-./23456789;=\]" ; keys combined with Shift that can be followed without a space.
global default_prefixes := "un|in|dis|inter"   ; will be used to detect normally typed text (regardless of case) so these sequences can be followed by a chord
; Variables holding current keyboard and language settings
global terminators := "" ; Sama as above for custom_terminators, etc. for below
global shift_terminators := ""
global openers := ""
global shift_openers := ""
global prefixes := ""
*/

global cursory := "Del|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|LButton|RButton|BS|Tab"
global chord_file := ""
global chords := {} ; holds pairs of chord key combinations and their full texts
global chord_delay := 0
global output_delay := 0
global capitalization := 2 ; 0 - no auto-capitalization, 1 - auto-capitalize chords only, 2 - auto-capitalize all typing
; constants and variable for smart spacing setttings:
global bBeforeChord := 1
global bAfterChord := 2
global bPunctuation := 4
global spacing := bBeforeChord | bAfterChord

global delnonchords := 0 ; delete typing that triggers chords that are not in dictionary?
global start := 0 ; maps to UIon for whether the chord recognition is enabled
chord := ""
shifted := false ; does the chord entry include a Shift key
uppercase := 0 ; 0 - no need to uppercase, 1 - uppercase next chord, 2 - don't uppercase
prefix := false ; TK: in v2, combine prefix into lastentry
lastentry := 0
lastoutput := -1
/* lastentry values:
-1 - entry was interrupted (cursor moved)
 0 - not a chord or a space
 1 - chord
 2 - manually typed space
 3 - automatically added space
*/

; variables holding the UI selections -- used by AHK Gui 
global UI_chord_delay := 0
global UI_output_delay := 0
global UI_space_before := 0
global UI_space_after := 0
global UI_space_punctuation := 0
global UI_delnonchords := 0
global UIcapitalization
global UIdict := "none"
global UIentries := "0"
global UIon := 1
global UITabMenu := 0


/*
; Variables and Constants -- preparation for v2
global bOutput := 1       ; last output exists (otherwise output flow was interrupted by moving the cursor using cursor keys, mouse click etc.)
global bSpace := 2        ; last output was a space
global bAutomated := 4    ; last output was automated (vs. manual entry)

global bSeparateStart := 8  ; output requires a separation before
global bSeparateEnd := 16  ; output requires a separation after
global bCapitalize := 32  ; output requires capitalization
*/

Initialize()
Return   ; To prevent execution of any of the following code, except for the always-on keyboard shortcuts below:

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

~Enter::
  lastentry := -1
  uppercase := 2
  Return

~Shift::
  uppercase := 1
  Return

; The rest of the code from here on behaves like in normal programming languages: It is not executed unless called from somewhere else in the code, or triggered by dynamically defined hotkeys.

Initialize() {
  ; Prepare UI dialog:
  Gui, Font, s10, Segoe UI
  Gui, Margin, 15, 15
  Gui, Add, Tab3, vUITabMenu, Dictionary|Sensitivity|Behavior|About
  ; Gui, Add, GroupBox, w320 h130 Section, Dictionary
  Gui, Add, Text, w280 vUIdict Left, [file name]
  Gui, Add, Text, xp+10 y+m w280 vUIentries Left, (999 chords)
  Gui, Add, Button, xs+20 gSelectDict y+m w80, &Open
  Gui, Add, Button, gEditDict xp+100 w80, &Edit
  Gui, Add, Button, gReloadDict xp+100 w80, &Reload
  ; Gui, Add, GroupBox, xs ys+150 w320 h100 Section, Sensitivity
  Gui, Tab, 2
  Gui, Add, Text, xs+20 y+m, I&nput delay (ms):
  Gui, Add, Edit, vUI_chord_delay Right xp+150 w40, 99
  Gui, Add, Text, xs+20 y+m, O&utput delay (ms):
  Gui, Add, Edit, vUI_output_delay Right xp+150 w40, 99
  Gui, Add, Checkbox, vUI_delnonchords xs+20 Y+m Checked%delnonchords%, &Delete mistyped chords
  ;Gui, Add, GroupBox, xs ys+120 w320 h100 Section, Chord behavior
  Gui, Tab, 3
  Gui, Add, GroupBox, w290 h120 Section, Smart spaces
  ;Gui, Add, Text, xs+20 ys+m +Wrap, When selected, smart spaces are dynamically added and removed as you type to ensure spaces between words, and avoid extra spaces around punctuation and doubled spaces when a manually typed space is combined with an automatic one.
  Gui, Add, Checkbox, vUI_space_before xs+20 ys+30, In &front of chords
  Gui, Add, Checkbox, vUI_space_after xp y+10, &After chords
  Gui, Add, Checkbox, vUI_space_punctuation xp y+10, After &punctuation
  Gui, Add, Text, xs y+30, Auto-&capitalization:
  Gui, Add, DropDownList, vUIcapitalization Choose%capitalization% AltSubmit Right xp+150 w130, Off|For chords only|For all input

  Gui, Tab
  Gui, Add, Checkbox, gUIControlStatus vUIon xs Y+m Checked%UIon%, Use &chord detection
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

  ; Attempt to read settings and dictionary from Windows Registry
  RegRead chord_delay, HKEY_CURRENT_USER\Software\ZipChord, ChordDelay
  if ErrorLevel
    SetDelays(90, 0)
  RegRead output_delay, HKEY_CURRENT_USER\Software\ZipChord, OutDelay
  if ErrorLevel
    SetDelays(90, 0)
  RegRead delnonchords, HKEY_CURRENT_USER\Software\ZipChord, DelUnknown
  RegRead spacing, HKEY_CURRENT_USER\Software\ZipChord, Spacing
  if ErrorLevel
    spacing := bBeforeChord | bAfterChord
  RegRead capitalization, HKEY_CURRENT_USER\Software\ZipChord, Capitalization
  if ErrorLevel
    capitalization := 2
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

  LoadChords(chord_file)
  WireHotkeys("On")
  ShowMenu()
}

WireHotkeys(state) {
  Loop Parse, keys
  {
    Hotkey, % "~" A_LoopField, KeyDown, %state%
    Hotkey, % "~+" A_LoopField, KeyDown, %state%
    Hotkey, % "~" A_LoopField " Up", KeyUp, %state%
  }
  Hotkey, % "~Space", KeyDown, %state%
  Hotkey, % "~+Space", KeyDown, %state%
  Hotkey, % "~Space Up", KeyUp, %state%
  Loop Parse, cursory, |
  {
    Hotkey, % "~" A_LoopField, Interrupt, %state%
    Hotkey, % "~^" A_LoopField, Interrupt, %state%
  }
}

WebsiteLink:
Run https://github.com/psoukie/zipchord#readme
return

ReleaseLink:
Run https://github.com/psoukie/zipchord/releases
return

ShowMenu() {
  GuiControl Text, UI_chord_delay, %chord_delay%
  GuiControl Text, UI_output_delay, %output_delay%
  GuiControl , Choose, UIcapitalization, %capitalization%
  GuiControl , , UI_space_before, % (spacing & bBeforeChord) ? 1 : 0   
  GuiControl , , UI_space_after, % (spacing & bAfterChord) ? 1 : 0
  GuiControl , , UI_space_punctuation, % (spacing & bPunctuation) ? 1 : 0
  GuiControl , , UIon, % (start==-1) ? 0 : 1
  GuiControl , , UI_delnonchords, %delnonchords%
  GuiControl, Choose, UITabMenu, 1 ; switch to first tab 
  Gui, Show,, ZipChord
  UIControlStatus()
}

UIControlStatus() {
  GuiControlGet, checked,, UIon
  GuiControl, Enable%checked%, UI_chord_delay
  GuiControl, Enable%checked%, UI_output_delay
  GuiControl, Enable%checked%, UI_space_before
  GuiControl, Enable%checked%, UI_space_after
  GuiControl, Enable%checked%, UI_space_punctuation
  GuiControl, Enable%checked%, UIcapitalization
  GuiControl, Enable%checked%, UI_delnonchords
}

ButtonOK:
  Gui, Submit, NoHide
  capitalization := UIcapitalization
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, Capitalization, %capitalization%
  spacing := UI_space_before * bBeforeChord + UI_space_after * bAfterChord + UI_space_punctuation * bPunctuation
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, Spacing, %spacing%
  delnonchords := UI_delnonchords
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, DelUnknown, %delnonchords%
  if SetDelays(UI_chord_delay, UI_output_delay) {
    if (start == -1 && UIon)
      WireHotkeys("On")
    if (start != -1 && !UIon)
      WireHotkeys("Off")
    start := UIon ? 0 : -1
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

; Main code. This is where the magic happens. Tracking keys as they are pressed down and released:

KeyDown:
  key := StrReplace(A_ThisHotkey, "Space", " ")
  last2 := lastentry
  ; First, we differentiate if the key was pressed while holding Shift, and store it under 'key':
  if ( StrLen(A_ThisHotkey)>2 && SubStr(A_ThisHotkey, 2, 1) == "+" ) {
    shifted := true
    uppercase := 1
    key := SubStr(key, 3, 1)
  }
  else {
    shifted := false
    key := SubStr(key, 2, 1)
  }
  chord .= key ; adds to the keys pressed so far, and when we have two simultaneously, we start the clock:
  if (StrLen(chord)==2)
    start:= A_TickCount
  
  ; categorize the input and adjust the immediate output on the fly:
  ; TK -- requires a fix when the adjusted output is then turned into a chord (different length of replacement)
  lastentry := 0
  if (key==" ") {
    if (last2 == 3)
      SendInput {Backspace} ; delete any smart-space
    lastentry := 2
  }
  if ( (! shifted && InStr(".,;", key)) || (shifted && InStr("1/;", key)) ) {  ;  punctuation needing space adjustments
    if (last2==3)
      SendInput {Backspace}{Backspace}%key%
    if ( spacing & bPunctuation ) {
      SendInput {Space}
      lastentry := 3
    }
  }
  if (capitalization==3 && uppercase==2 && Asc(key)>96 && Asc(key)<123) {
    SendInput {Backspace}+%key% ; deletes the lowercase and sends Shift+key instead 
    uppercase := 1
  }
  ; set 'uppercase' for punctuation that capitalizes following text 
  if ( (! shifted && key==".") || (shifted && InStr("1/", key)) )
    uppercase := 2
  Return

KeyUp:
  key := SubStr(StrReplace(A_ThisHotkey, "Space", " "), 2, 1)
  ch := chord
  chord := StrReplace(chord, key) ; removes from the keys pressed so far
  st := start
  start := 0
  if (st && StrLen(ch)>1 && A_TickCount - st > chord_delay) {  ; potential chord was triggered
    chord := ""
    last := lastoutput
    upper := uppercase
    sorted := Arrange(ch)
    Sleep output_delay
    if (chords.HasKey(sorted)) {
      Loop % StrLen(sorted)
        SendInput {Backspace}
      if ( last==0 && (spacing & bBeforeChord) )
        SendInput {Space}
      exp := chords[sorted]
      if (SubStr(exp, StrLen(exp), 1) == "~") {
        exp := SubStr(exp, 1, StrLen(exp)-1)
        prefix := true
      }
      else
        prefix := false
      if ( ! (spacing & bBeforeChord) )
        exp := StrReplace(exp, "{Backspace}") ;  remove the initial {Backspace} from suffixes when we are not inserting space before chord.
      if (upper && capitalization>1)
        SendInput % RegExReplace(exp,"(^.)", "$U1")
      else
        SendInput % exp
      lastoutput := 1
      if (!prefix && (spacing & bAfterChord) ) {
        SendInput {Space}
        lastoutput := 3
      }
      uppercase := 0
      lastentry := lastoutput
    }
    else {
      if (delnonchords) {
        Loop % StrLen(sorted)
          SendInput {Backspace}
      }
    }
  }
  else
    lastoutput := lastentry ; if there was no potential chord, we set the output to the last input.
  Return

Interrupt:
  lastentry := -1
  uppercase := false
  Return

SelectDict() {
  FileSelectFile dict, , %A_ScriptDir%, Open Dictionary, Text files (*.txt)
  if (dict != "")
    LoadChords(dict)
  Return
}

EditDict() {
  Run notepad.exe %chord_file%
}

AddChord() {
  newword := Trim(Clipboard)
  if (!StrLen(newword)) {
    MsgBox ,, ZipChord, % "First, select a word you would like to define a chord for, and then press and hold Ctrl+C again."
    Return
  }
  For ch, wd in chords
    if (wd==newword) {
      MsgBox  ,, ZipChord, % Format("The text '{}' already has the chord {:U} associated with it.", wd, ch)
      Return
    }
  Loop {
    InputBox, newch, ZipChord, % Format("Type the individual keys that will make up the chord for '{}'.`n(Only lowercase letters, numbers, space, and other alphanumerical keys without pressing Shift or function keys.)", newword)
    if ErrorLevel
      Return
  } Until RegisterChord(newch, newword, true)
  UpdateUI()
}

RegisterChord(newch, newword, w := false) {
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
  if (w)
    FileAppend % "`r`n" newch "`t" newword, %chord_file%, UTF-8
  newword := StrReplace(newword, "~", "{Backspace}")
  if (SubStr(newword, -10)=="{Backspace}")
    newword := SubStr(newword, 1, StrLen(newword)-11) "~"
  chords.Insert(newch, newword)
  return true
}

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

Arrange(raw) {
  raw := RegExReplace(raw, "(.)", "$1`n")
  Sort raw
  Return StrReplace(raw, "`n")
}

ReloadDict() {
  WireHotkeys("Off")
  LoadChords(chord_file)
  WireHotkeys("On")
}

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
  UpdateUI()
}

UpdateUI() {
  if StrLen(chord_file) > 35
    filestr := "..." SubStr(chord_file, -34)
  else
    filestr := chord_file
  GuiControl Text, UIdict, %filestr%
  entriesstr := "(" chords.Count()
  entriesstr .= (chords.Count()==1) ? " chord)" : " chords)"
  GuiControl Text, UIentries, %entriesstr%
}
