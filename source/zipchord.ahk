#NoEnv
SetWorkingDir %A_ScriptDir%

keys := "',-./0123456789;=[\]abcdefghijklmnopqrstuvwxyz"
cursory := "Del|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|LButton|RButton|BS|Tab"
global chfile := "chords*.txt"
global chords := {}
global chdelay := 0
chord := ""
start := 0
consecutive := false
uppercase := false

RegRead chdelay, HKEY_CURRENT_USER\Software\ZipChord, ChordDelay
If ErrorLevel==1
  SetDelay(75)
if FileExist(chfile) {
  Loop, Files, %chfile%
    flist .= SubStr(A_LoopFileName, 1, StrLen(A_LoopFileName)-4) "`n"
  Sort flist
  chfile := SubStr(flist, 1, InStr(flist, "`n")-1) ".txt"
}
else {
  chfile := "chords.txt"
  FileAppend % "chord`tword", %chfile%, UTF-8
}
Loop, Read, %chfile%
{
  pos := InStr(A_LoopReadLine, A_Tab)
  RegisterChord(Arrange(SubStr(A_LoopReadLine, 1, pos-1)), StrReplace(SubStr(A_LoopReadLine, pos+1), "~", "{Backspace}"))
}
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
MsgBox ,, ZipChord, % Format("ZipChord is now active and using chords from '{}'.`n`nPress and HOLD for the following functions:`n`nCtrl-C`t`tAdd a new chord for selected text.`nCtrl-Shift-C`tOpen chord definitions for editing.`nCtrl-X`t`tPause or resume chord recognition.`nCtrl-Shift-X`tChange the chord activation sensitivity.", chfile)
Return

KeyDown:
  chord .= SubStr(StrReplace(A_ThisHotkey, "Space", " "), 2, 1)
  if (start==-1)
    Return
  if(StrLen(chord)==2)
    start:= A_TickCount
  Return

KeyUp:
  key := SubStr(StrReplace(A_ThisHotkey, "Space", " "), 2, 1)
  ch := chord
  chord := ""
  cons := consecutive
  upper := uppercase
  st := start
  if (start==-1)
    Return
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
    } Until RegisterChord(newch, newword)
  }
  Return

~^+c::
  Sleep 500
  If GetKeyState("c","P") {
    MsgBox ,, ZipChord, Opening the chord file for editing...
    Run notepad.exe %chfile%
  }
  Return

~^x::
  Sleep 500
  if GetKeyState("x","P") {
    if (start==-1) {
      start := 0
      MsgBox ,, ZipChord, Chord recognition is active.
    }
    else {
      start := -1
      MsgBox ,, ZipChord, % "Chord recognition is paused. Hold Ctrl-X again to resume.`n`n(You can also increase the chord activation delay by holding Ctrl-Shift-X to avoid accidental chording.)"
    }
  }
  Return

~^+x::
  Sleep 500
  If GetKeyState("x","P") {
    Loop {
      InputBox, newdelay, ZipChord, % Format("The delay for detecting chord presses is currently {} ms.`n`nEnter a new delay in milliseconds.", chdelay)
      if ErrorLevel
        Return
    } Until SetDelay(newdelay)
    if (start==-1) {
      start := 0
      MsgBox ,, ZipChord, % Format("Chord recognition is now active with a {}ms activation delay.", chdelay)
    }
  }
  Return

RegisterChord(newch, newword) {
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
  FileAppend % "`r`n" newch "`t" newword, %chfile%, UTF-8
  Return true
}

SetDelay(newdelay) {
  newdelay := Round(newdelay + 0)
  if (newdelay<1) {
    MsgBox ,, ZipChord, % "The delay needs to be a number.`nUse numbers only when entering the delay, for example: 80"
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
