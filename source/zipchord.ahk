#NoEnv
SetWorkingDir %A_ScriptDir%

; ZipChord by Pavel Soukenik
; Licensed under GPL-3.0
; See https://github.com/psoukie/zipchord/

keys := "',-./0123456789;=[\]abcdefghijklmnopqrstuvwxyz"
cursory := "Del|Ins|Home|End|PgUp|PgDn|Up|Down|Left|Right|LButton|RButton|BS|Tab"
global chfile := ""
global chords := {}
global chdelay := 0
global newdelay := 0
global mode := 2
global UIdict := "none"
global UIon := 1
chord := ""
global start := 0
consecutive := false
space := false
uppercase := false

Gui, Font, s10, Segoe UI
Gui, Margin, 15, 15
Gui, Add, GroupBox, w320 h100 Section, Dictionary
Gui, Add, Text, xp+20 yp+30 w280 vUIdict Center, [file name] (999 chords)
Gui, Add, Button, gSelectDict Y+10 w80, &Select
Gui, Add, Button, gEditDict xp+100 yp+0 w80, &Edit
Gui, Add, Button, gReloadDict xp+100 yp+0 w80, &Reload

Gui, Add, GroupBox, xs ys+120 w320 h130 Section, Chord recognition
Gui, Add, Text, xp+20 yp+30, Sensi&tivity (ms):
Gui, Add, Edit, vnewdelay Right xp+150 yp+0 w40, 99
Gui, Add, Text, xp-150 Y+10, Smart &punctuation:
Gui, Add, DropDownList, vUImode Choose%mode% AltSubmit Right xp+150 yp+0 w130, Off|Chords only|All input
Gui, Add, Checkbox, vUIon xp-150 Y+10 Checked%UIon%, E&nabled
Gui, Add, Button, Default w80 xs+120 ys+150, OK
Menu, Tray, Add, Open Settings, ShowMenu
Menu, Tray, Default, Open Settings
Menu, Tray, Tip, ZipChord
Menu, Tray, Click, 1

RegRead chdelay, HKEY_CURRENT_USER\Software\ZipChord, ChordDelay
If ErrorLevel==1
  SetDelay(75)
RegRead mode, HKEY_CURRENT_USER\Software\ZipChord, Punctuation
If ErrorLevel==1
  mode := 2
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
  Sleep 300
  If GetKeyState("c","P")
    ShowMenu()
  Return

ShowMenu() {
  GuiControl Text, newdelay, %chdelay%
  GuiControl , Choose, UImode, %mode%
  if (start==-1)
    GuiControl , , UIon, 0
  else
    GuiControl , , UIon, 1
  Gui, Show,, ZipChord
}

ButtonOK:
  Gui, Submit, NoHide
  mode := UImode
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, Punctuation, %mode%
  if (SetDelay(newdelay)) {
      if (UIon)
        start := 0
      else
        start := -1
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
  if (intro) {
    MsgBox ,, ZipChord, % "Press and hold Ctrl-C to define a new chord for the selected text.`n`nPress and hold Ctrl-Shift-C to open the ZipChord menu again."
    intro := false
  }
}

KeyDown:
  key := SubStr(StrReplace(A_ThisHotkey, "Space", " "), 2, 1)
  chord .= key
  if(StrLen(chord)==2)
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
  if (start==-1)
    Return
  start := 0
  if (st && StrLen(ch)>1 && A_TickCount - st > chdelay) {
    chord := ""
    cons := consecutive | space
    upper := uppercase
    sorted := Arrange(ch)
    If (chords.HasKey(sorted)) {
      Loop % StrLen(sorted)
        SendInput {Backspace}
      if (!cons) {
        SendInput {Space}
        space := true
      }
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
      if (!pref) {
        SendInput {Space}
        space := true
      }
      consecutive := true
      uppercase := 0
    }
  }
  else
    if (ch!="") {
      cons2 := consecutive
      upper2 := uppercase
      consecutive := false
      uppercase := 0
      if (key==" ") {
        space := true
        if (upper2)
          uppercase := upper2
      }
      else
        space := false
      if (InStr(".,;", key)) {
        if (cons2 && mode>1)
          SendInput {Backspace}{Backspace}%key%
        if ((cons2 && mode>1) || mode==3) {
          SendInput {Space}
          space := true
        }
      }
      if (key==".")
        uppercase := 2
  }
  Return

ShiftKeys:
  key := SubStr(A_ThisHotkey, 3, 1)
  if (start==-1)
    Return
  if (InStr("1/;", key)) {
    uppercase := true
    if (consecutive && mode>1)
      SendInput {Backspace}{Backspace}+%key%
    if (consecutive || mode==3) {
      SendInput {Space}
      space := true
    }
  }
  else {
    consecutive := false
    uppercase := 0
    space := false
  }
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
  Sleep 300
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
  if (w) {
    FileAppend % "`r`n" newch "`t" newword, %chfile%, UTF-8
  }
  newword := StrReplace(newword, "~", "{Backspace}")
  if (SubStr(newword, -10)=="{Backspace}")
    newword := SubStr(newword, 1, StrLen(newword)-11) "~"
  chords.Insert(newch, newword)
  return true
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

ReloadDict() {
  LoadChords(chfile)
}

LoadChords(fname) {
  chfile := fname
  RegWrite REG_SZ, HKEY_CURRENT_USER\Software\ZipChord, ChordFile, %chfile%
  chords := {}
  Loop, Read, %chfile%
  {
    pos := InStr(A_LoopReadLine, A_Tab)
    if (pos)
      RegisterChord(Arrange(SubStr(A_LoopReadLine, 1, pos-1)), SubStr(A_LoopReadLine, pos+1))
  }
  UpdateUI()
}

UpdateUI() {
  if StrLen(chfile) > 26
    filestr := "..." SubStr(chfile, -25)
  else
    filestr := chfile
  filestr .= " (" chords.Count()
  GuiControl Text, newdelay, %chdelay%
  if chords.Count()==1
    filestr .= " chord)"
  else
    filestr .= " chords)"
  GuiControl Text, UIdict, %filestr%
}
