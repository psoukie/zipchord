#NoEnv
SetWorkingDir %A_ScriptDir%

; ZipChord by Pavel Soukenik
; Licensed under GPL-3.0
; See https://github.com/psoukie/zipchord/

global default_keys := "',-./0123456789;=[\]abcdefghijklmnopqrstuvwxyz"
global keys := "" ; Uses default_keys or custom_keys read from the dictionary file.
global cursory := "Del|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|LButton|RButton|BS|Tab"
global chfile := ""
global chords := {}
global chdelay := 0
global outdelay := 0
global newdelay := 0
global newoutdelay := 0
global mode := 2
global UIdict := "none"
global UIentries := "0"
global UIon := 1
global delnonchords := 0
global start := 0
global UImode
chord := ""
uppercase := false
lastentry := 0
/* lastentry values:
-1 - entry was interrupted (cursor moved)
 0 - not a chord or a space
 1 - chord
 2 - manually typed space
 3 - automatically added space
*/

Initialize()
Return

~^+c::
  Sleep 300
  if GetKeyState("c","P")
    ShowMenu()
  Return

Initialize() {
  Gui, Font, s10, Segoe UI
  Gui, Margin, 10, 10
  Gui, Add, GroupBox, w320 h130 Section, Dictionary
  Gui, Add, Text, xs+20 yp+30 w280 vUIdict Left, [file name]
  Gui, Add, Text, xp+10 y+m w280 vUIentries Left, (999 chords)
  Gui, Add, Button, xs+20 gSelectDict y+m w80, &Open
  Gui, Add, Button, gEditDict xp+100 w80, &Edit
  Gui, Add, Button, gReloadDict xp+100 w80, &Reload

  Gui, Add, GroupBox, xs ys+150 w320 h100 Section, Sensitivity
  Gui, Add, Text, xs+20 yp+30, I&nput delay (ms):
  Gui, Add, Edit, vnewdelay Right xp+150 w40, 99
  Gui, Add, Text, xs+20 y+m, O&utput delay (ms):
  Gui, Add, Edit, vnewoutdelay Right xp+150 w40, 99

  Gui, Add, GroupBox, xs ys+120 w320 h100 Section, Chord behavior
  Gui, Add, Text, xs+20 yp+30, Smart &punctuation:
  Gui, Add, DropDownList, vUImode Choose%mode% AltSubmit Right xp+150 w130, Off|For chords only|For all input
  Gui, Add, Checkbox, vdelnonchords xs+20 Y+m Checked%delnonchords%, &Delete mistyped chords

  Gui, Add, Checkbox, gUIControlStatus vUIon xs Y+40 Checked%UIon%, Re&cognition enabled
  Gui, Add, Button, Default w80 xs+220, OK
  Gui, Font, Underline cBlue
  Gui, Add, Text, xs Y+10 gWebsiteLink, v1.6.2 (updates)

  Menu, Tray, Add, Open Settings, ShowMenu
  Menu, Tray, Default, Open Settings
  Menu, Tray, Tip, ZipChord
  Menu, Tray, Click, 1

  RegRead chdelay, HKEY_CURRENT_USER\Software\ZipChord, ChordDelay
  if ErrorLevel
    SetDelays(90, 0)
  RegRead outdelay, HKEY_CURRENT_USER\Software\ZipChord, OutDelay
  if ErrorLevel
    SetDelays(90, 0)
  RegRead delnonchords, HKEY_CURRENT_USER\Software\ZipChord, DelUnknown
  RegRead mode, HKEY_CURRENT_USER\Software\ZipChord, Punctuation
  if ErrorLevel
    mode := 2
  RegRead chfile, HKEY_CURRENT_USER\Software\ZipChord, ChordFile
  if (ErrorLevel || !FileExist(chfile)) {
    errmsg := ErrorLevel ? "" : Format("The last used dictionary {} could not be found.`n`n", chfile)
    chfile := "chords*.txt"
    if FileExist(chfile) {
      Loop, Files, %chfile%
        flist .= SubStr(A_LoopFileName, 1, StrLen(A_LoopFileName)-4) "`n"
      Sort flist
      chfile := SubStr(flist, 1, InStr(flist, "`n")-1) ".txt"
      errmsg .= Format("ZipChord detected the dictionary '{}' and is going to open it.", chfile)
    }
    else {
      errmsg .= "ZipChord is going to create a new 'chords.txt' dictionary in its own folder."
      chfile := "chords.txt"
      FileAppend % "This is a dictionary for ZipChord. Define chords and corresponding words in a tab-separated list (one entry per line).`nSee https://github.com/psoukie/zipchord for details.`n`ndm`tdemo", %chfile%, UTF-8
    }
    chfile := A_ScriptDir "\" chfile
    MsgBox ,, ZipChord, %errmsg%
  }
  LoadChords(chfile)
  WireHotkeys("On")
  ShowMenu()
}

WireHotkeys(state) {
  Loop Parse, keys
  {
    Hotkey, % "~" A_LoopField, KeyDown, %state%
    Hotkey, % "~" A_LoopField " Up", KeyUp, %state%
    Hotkey, % "~+" A_LoopField, ShiftKeys, %state%
  }
  Hotkey, % "~Space", KeyDown, %state%
  Hotkey, % "~Space Up", KeyUp, %state%
  Loop Parse, cursory, |
  {
    Hotkey, % "~" A_LoopField, Interrupt, %state%
    Hotkey, % "~^" A_LoopField, Interrupt, %state%
  }
}

WebsiteLink:
Run https://github.com/psoukie/zipchord/releases
return

ShowMenu() {
  GuiControl Text, newdelay, %chdelay%
  GuiControl Text, newoutdelay, %outdelay%
  GuiControl , Choose, UImode, %mode%
  GuiControl , , UIon, % (start==-1) ? 0 : 1
  GuiControl , , delnonchords, %delnonchords%
  Gui, Show,, ZipChord
  UIControlStatus()
}

UIControlStatus() {
  GuiControlGet, checked,, UIon
  GuiControl, Enable%checked%, newdelay
  GuiControl, Enable%checked%, newoutdelay
  GuiControl, Enable%checked%, UImode
  GuiControl, Enable%checked%, delnonchords
}

ButtonOK:
  Gui, Submit, NoHide
  mode := UImode
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, Punctuation, %mode%
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, DelUnknown, %delnonchords%
  if SetDelays(newdelay, newoutdelay) {
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

KeyDown:
  key := SubStr(StrReplace(A_ThisHotkey, "Space", " "), 2, 1)
  chord .= key
  if (StrLen(chord)==2)
    start:= A_TickCount
  if (mode==3 && uppercase==2 && Asc(key)>96 && Asc(key)<123) {
    SendInput {Backspace}+%key%
    uppercase := 1
  }
  Return

KeyUp:
  key := SubStr(StrReplace(A_ThisHotkey, "Space", " "), 2, 1)
  ch := chord
  chord := StrReplace(chord, key)
  st := start
  start := 0
  if (st && StrLen(ch)>1 && A_TickCount - st > chdelay) {
    chord := ""
    last := lastentry
    upper := uppercase
    sorted := Arrange(ch)
    Sleep outdelay
    if (chords.HasKey(sorted)) {
      Loop % StrLen(sorted)
        SendInput {Backspace}
      if (last==0)
        SendInput {Space}
      exp := chords[sorted]
      if (SubStr(exp, StrLen(exp), 1) == "~") {
        exp := SubStr(exp, 1, StrLen(exp)-1)
        pref := true
      }
      else
        pref := false
      if (upper && mode>1)
        SendInput % RegExReplace(exp,"(^.)", "$U1")
      else
        SendInput % exp
      lastentry := 1
      if (!pref) {
        SendInput {Space}
        lastentry := 3
      }
      uppercase := 0
    }
    else {
      if (delnonchords) {
        Loop % StrLen(sorted)
          SendInput {Backspace}
      }
    }
  }
  else
    if (ch!="") {
      last2 := lastentry
      upper2 := uppercase
      lastentry := 0
      uppercase := 0
      if (key==" ") {
        if (last2 == 3)
          SendInput {Backspace} ; delete any auto-space
        lastentry := 2
        if (upper2)
          uppercase := upper2
      }
      if (InStr(".,;", key)) {
        if (last2>0 && mode>1)
          SendInput {Backspace}{Backspace}%key%
        if ( (last2>0 && mode>1) || mode==3 ) {
          SendInput {Space}
          lastentry := 3
        }
      }
      if (key==".")
        uppercase := 2
  }
  Return

ShiftKeys:
  key := SubStr(A_ThisHotkey, 3, 1)
  last2 := lastentry
  if (InStr("1/;", key)) {
    uppercase := 2
    lastentry := 0
    if (last2>0 && mode>1)
      SendInput {Backspace}{Backspace}+%key%
    if ( (last2>0 && mode>1) || mode==3 ) {
      SendInput {Space}
      lastentry := 3
    }
  }
  else {
    lastentry := 0
    uppercase := 0
  }
  Return

~Enter::
  lastentry := -1
  uppercase := true
  Return

~Shift::
  uppercase := true
  Return

Interrupt:
  lastentry := -1
  uppercase := false
  Return

~^c::
  Sleep 300
  if GetKeyState("c","P") {
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
  Return

SelectDict() {
  FileSelectFile dict, , %A_ScriptDir%, Open Dictionary, Text files (*.txt)
  if (dict != "")
    LoadChords(dict)
  Return
}

EditDict() {
  Run notepad.exe %chfile%
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
    FileAppend % "`r`n" newch "`t" newword, %chfile%, UTF-8
  newword := StrReplace(newword, "~", "{Backspace}")
  if (SubStr(newword, -10)=="{Backspace}")
    newword := SubStr(newword, 1, StrLen(newword)-11) "~"
  chords.Insert(newch, newword)
  return true
}

SetDelays(newdelay, newoutdelay) {
  newdelay := Round(newdelay + 0)
  newoutdelay := Round(newoutdelay + 0)
  if (newdelay<1 || newoutdelay<0) {
    MsgBox ,, ZipChord, % "The chord sensitivity needs to be entered as a positive number."
    Return false
  }
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, ChordDelay, %newdelay%
  chdelay := newdelay
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, OutDelay, %newoutdelay%
  outdelay := newoutdelay
  Return true
}

Arrange(raw) {
  raw := RegExReplace(raw, "(.)", "$1`n")
  Sort raw
  Return StrReplace(raw, "`n")
}

ReloadDict() {
  WireHotkeys("Off")
  LoadChords(chfile)
  WireHotkeys("On")
}

LoadChords(fname) {
  chfile := fname
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, ChordFile, %chfile%
  chords := {}
  keys := default_keys
  Loop, Read, %chfile%
  {
    pos := InStr(A_LoopReadLine, A_Tab)
    if (pos) {
      if (SubStr(A_LoopReadLine, 1, pos-1) == "custom_keys")
        keys := Arrange(SubStr(A_LoopReadLine, pos+1))
      else
        RegisterChord(Arrange(SubStr(A_LoopReadLine, 1, pos-1)), SubStr(A_LoopReadLine, pos+1))
    }
  }
  UpdateUI()
}

UpdateUI() {
  if StrLen(chfile) > 35
    filestr := "..." SubStr(chfile, -34)
  else
    filestr := chfile
  GuiControl Text, newdelay, %chdelay%
  GuiControl Text, newoutdelay, %outdelay%
  GuiControl Text, UIdict, %filestr%
  entriesstr := "(" chords.Count()
  entriesstr .= (chords.Count()==1) ? " chord)" : " chords)"
  GuiControl Text, UIentries, %entriesstr%
}
