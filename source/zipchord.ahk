#NoEnv
SetWorkingDir %A_ScriptDir%

keys := "',-./0123456789;=[\]abcdefghijklmnopqrstuvwxyz"
cursory := "Del|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|LButton|RButton|BS|Tab"
global chfile := ""
global chords := {}
global chdelay := 0
global newdelay := 0
global chentries := 0
chord := ""
start := 0
consecutive := false
uppercase := false

Gui, Font, s12, Segoe UI
Gui, Add, Text, , Current dictionary:
Gui, Add, Text, Y+5, Number of chords:
Gui, Add, Button, gSelectDict Y+10 w150, &Select dictionary
Gui, Add, Text, Y+20, Chord sensitivity (ms):
Gui, Add, Button, gPauseChord Y+20 w150, &Pause chording
Gui, Add, Text, vchfile ym w150, no dictionary
Gui, Add, Text, vchentries Y+5 w150, 0
Gui, Add, Button, gEditDict Y+10 w150, &Edit dictionary
Gui, Add, Edit, vnewdelay Right Y+20 w50, 0
Gui, Add, Button, Default w80 Y+50, OK
Menu, Tray, Add, Open Settings, ShowMenu
Menu, Tray, Default, Open Settings
Menu, Tray, Tip, ZipChord
Menu, Tray, Click, 1

RegRead chdelay, HKEY_CURRENT_USER\Software\ZipChord, ChordDelay
If ErrorLevel==1
  SetDelay(75)
RegRead chfile, HKEY_CURRENT_USER\Software\ZipChord, ChordFile
If (ErrorLevel==1 || !FileExist(chfile)) {
  chfile := "chords*.txt"
  if FileExist(chfile) {
    Loop, Files, %chfile%
      flist .= SubStr(A_LoopFileName, 1, StrLen(A_LoopFileName)-4) "`n"
    Sort flist
    chfile := SubStr(flist, 1, InStr(flist, "`n")-1) ".txt"
  }
  else {
    chfile := "chords.txt"
    FileAppend % "This is a dictionary for ZipChord: a tab-separated list of chords and corresponding words (one entry per line).`nSee https://github.com/psoukie/zipchord for details.`n`ndmn`tdemonstration", %chfile%, UTF-8
  }
  chfile := A_ScriptDir "\" chfile
}
LoadChords(chfile)

Loop Parse, keys
{
  Hotkey, % "~" A_LoopField, KeyDown
  Hotkey, % "~" A_LoopField " Up", KeyUp
  Hotkey, % "~+" A_LoopField, ShiftKeys
}
Hotkey, % "~Space", KeyDown
Hotkey, % "~Space Up", KeyUp
Loop Parse, cursory, |
{
  Hotkey, % "~" A_LoopField, Interrupt
  Hotkey, % "~^" A_LoopField, Interrupt
}
ShowMenu()
Return

~^+c::
  Sleep 500
  If GetKeyState("c","P")
    ShowMenu()
  Return

ShowMenu() {
  GuiControl Text, newdelay, %chdelay%
  SplitPath chfile, sname
  GuiControl Text, chfile, %sname%
  GuiControl Text, chentries, % chords.Count()
  Gui, Show,, ZipChord
}

ButtonOK:
  Gui, Submit, NoHide
  if (SetDelay(newdelay))
    CloseMenu()
  Return

GuiClose:
GuiEscape:
  CloseMenu()
  Return

CloseMenu() {
  Gui, Submit
  static intro := true
  if (intro) {
    MsgBox ,, ZipChord, % "Press and hold Ctrl-C to define a new chord for the selected text.`n`nPress and hold Ctrl-Shift-C to open the ZipChord menu again."
    intro := false
  }
}

KeyDown:
  chord .= SubStr(StrReplace(A_ThisHotkey, "Space", " "), 2, 1)
  if (start==-1)
    Return
  if(StrLen(chord)==2)
    start:= A_TickCount
  Return

KeyUp:
  key := SubStr(StrReplace(A_ThisHotkey, "Space", " "), 2, 1)
  if (start==-1)
    Return
  ch := chord
  chord := ""
  cons := consecutive
  upper := uppercase
  st := start
  start := 0
  if (st && StrLen(ch)>1 && A_TickCount - st > chdelay) {
    sorted := Arrange(ch)
    If (chords.HasKey(sorted)) {
      Loop % StrLen(sorted)
        SendInput {Backspace}
      if (!cons)
        SendInput {Space}
      if (upper)
        SendInput % RegExReplace(chords[sorted],"(^.)", "$U1")
      else
        SendInput % chords[sorted]
      SendInput {Space}
      consecutive := true
      uppercase := false
    }
  }
  else {
    if (ch!="") {
      if (InStr(".,;", key) && consecutive)
        SendInput {Backspace}{Backspace}%key%{Space}
      else
        consecutive := false
      if (key==".")
        uppercase := true
      else
        if (uppercase && key!=" ")
          uppercase := false
      if (key==" ")
        consecutive := true
    }
  }
  Return

ShiftKeys:
  key := SubStr(A_ThisHotkey, 3, 1)
  if (start==-1)
    Return
  if (InStr("1/;", key)) {
    uppercase := true
    if (consecutive)
      SendInput {Backspace}{Backspace}+%key%{Space}
    else
      consecutive := false
  }
  else
    consecutive := false
    uppercase:=false
  Return

~Enter::
  consecutive := true
  uppercase := true
  Return

Interrupt:
  uppercase:=false
  consecutive:=false
  Return

~^c::
  Sleep 500
  If GetKeyState("c","P") {
    newword := Trim(Clipboard)
    if (!StrLen(newword)) {
      MsgBox ,, ZipChord, % "First, select a word you would like to define a chord for, and then press and hold Ctrl+C again."
      Return
    }
    Loop {
      InputBox, newch, ZipChord, % Format("Type the individual keys that will make up the chord for '{}'.`n(Only lowercase letters, numbers, space, and other alphanumerical keys without pressing Shift or function keys.)", newword)
      if ErrorLevel
        Return
    } Until RegisterChord(newch, newword, true)
  }
  Return

SelectDict() {
  FileSelectFile dict, , %A_ScriptDir%, Open Dictionary, Text files (*.txt)
  if (dict != "") {
    LoadChords(dict)
    SplitPath chfile, sname
    GuiControl Text, chfile, %sname%
    GuiControl Text, chentries, % chords.Count()
  }
  Return
}

EditDict() {
  Run notepad.exe %chfile%
  CloseMenu()
}

PauseChord:
  CloseMenu()
  if (start==-1) {
    start := 0
    GuiControl Text, Button2, &Pause chording
  }
  else {
    start := -1
    GuiControl Text, Button2, &Resume chording
  }
  Return

RegisterChord(newch, newword, w = false) {
  newch := Arrange(newch)
  if chords.HasKey(newch) {
    MsgBox ,, ZipChord, % "The chord '" newch "' is already in use for '" chords[newch] "'.`nPlease use a different chord for '" newword "'."
    Return false
  }
  if (StrLen(newch)<2) {
    MsgBox ,, ZipChord, The chord needs to be at least two characters.
    Return false
  }
  chords.Insert(newch, newword)
  if (w)
    FileAppend % "`r`n" newch "`t" newword, %chfile%, UTF-8
  Return true
}

SetDelay(newdelay) {
  newdelay := Round(newdelay + 0)
  if (newdelay<1) {
    MsgBox ,, ZipChord, % "The chord sensitivity needs to be entered as only numbers."
    Return false
  }
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, ChordDelay, %newdelay%
  chdelay := newdelay
  Return true
}

Arrange(raw) {
  raw := RegExReplace(raw, "(.)", "$1`n")
  Sort raw
  Return StrReplace(raw, "`n")
}

LoadChords(fname) {
  chfile := fname
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, ChordFile, %chfile%
  chords := {}
  Loop, Read, %chfile%
  {
    pos := InStr(A_LoopReadLine, A_Tab)
    if (pos)
      RegisterChord(Arrange(SubStr(A_LoopReadLine, 1, pos-1)), StrReplace(SubStr(A_LoopReadLine, pos+1), "~", "{Backspace}"))
  }
}
