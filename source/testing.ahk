/**
*
*  This file is part of ZipChord.
* 
*  ZipChord is free software: you can redistribute it and/or modify it
*  under the terms of the GNU General Public License as published by
*  the Free Software Foundation, either version 3 of the License, or
*  (at your option) any later version.
*  
*  ZipChord is distributed in the hope that it will be useful, but
*  WITHOUT ANY WARRANTY; without even the implied warranty of
*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
*  GNU General Public License for more details.
*
*  You should have received a copy of the GNU General Public License
*  along with ZipChord. If not, see <https://www.gnu.org/licenses/>.
*  
*  See the official GitHub page for the documentation, source code, and
*  to contact the author: https://github.com/psoukie/zipchord/
*  
*/

global TEST_OFF := 0
    , TEST_STANDBY := 1
    , TEST_RUNNING := 2
    , TEST_INTERACTIVE := 3
global TEST_DEST_NONE := 0
    , TEST_DEST_CONSOLE := 1

global test_key := ""
global test_timestamp := 0

Class TestingClass {
    _stdin := 0
    _stdout := 0
    _input := 0
    _output := 0
    _input_obj := 0
    _output_obj := 0
    _mode := TEST_OFF
    _starting_tick := 0
    mode {
        get { 
            return this._mode 
        }
    }
    Init() {
        this._mode := TEST_STANDBY
        WireHotkeys("Off")
        prompt_fn := ObjBindMethod(this, "Prompt")
        if (A_Args[1] != "test-vs") {
            DllCall("AllocConsole")
            DllCall("SetConsoleTitle", Str, "ZipChord Console")
            this._stdin  := FileOpen("*", "r `n")
            this._stdout := FileOpen("*", "w `n")
        }
        Hotkey, % "^x", % prompt_fn
        this.Write(Format("ZipChord Test Automation Console [Version {}]", version))
        this.Write("`nCopyright (c) 2023 Pavel Soukenik")
        this.Write("This program comes with ABSOLUTELY NO WARRANTY.")
        this.Write("This is free software, and you are welcome to redistribute it")
        this.Write("under certain conditions. Type 'LICENSE' for details.")
        this.Write("`nType 'HELP' to get a list of available commands.")
        %prompt_fn%()
    }
    Config(mode:="", ByRef filename:="") {
        global keys        
        Switch mode {
            Case "", "show":
                this.Write("Current ZipChord configuration:")
                this.Write("Application settings:")
                For key, value in settings
                    this.Write(key . ": " value)
                this.Write("`nKeyboard and Language settings:")
                For key, value in keys
                    this.Write(key . ": " value)
            Case "save":
                if (! this._CheckFilename(filename, "cfg"))
                    return
                SavePropertiesToIni(settings, "Application", filename)
                SavePropertiesToIni(keys, "Locale", filename)
                this.Write(Format("Saved current configuration to '{}'.", filename))
            Case "load":
                if (! this._CheckFilename(filename, "cfg", true))
                    return -1
                LoadPropertiesFromIni(settings, "Application", filename)
                LoadPropertiesFromIni(keys, "Locale", filename)
                this.Write(Format("Loaded configuration from '{}'.", filename))
            Case "help":
                this.Write("TK: config command help")
            Default:
                this.Write("Could not understand the command. Try 'CONFIG HELP'.")
        }
    }
    Interact() {
        this._Ready()
        if(settings.chords_enabled || settings.shorthands_enabled) {
            this.Write("Wiring hotkeys...")
            WireHotkeys("On")
        }
        this.Write("Switching to interactive mode...`nPress Ctrl-X to resume in the console.")
        this._mode := TEST_INTERACTIVE
        Return true
    }
    Monitor(what:="", destination:="console") {
        Switch what {
            Case "", "show":
                this.Write(Format("ZipChord input is monitored to {}.", this._input))
                this.Write(Format("ZipChord output is monitored to {}.", this._output))
            Case "input", "output":
                target_var := "_" . what
                extension := what=="input" ? "in" : "out" 
                Switch destination {
                    Case "console":
                        this[target_var] := TEST_DEST_CONSOLE
                    Case "off":
                        if (this[target_var] == TEST_DEST_NONE)
                            return
                        if (this[target_var . "_obj"]) {
                            this[target_var . "_obj"].Close()
                            this[target_var . "_obj"] := ""
                            this.Write(Format("Disconnected the {} file.", what))
                        }
                        this[target_var] := TEST_DEST_NONE
                    Default:
                        if (! this._CheckFilename(destination, extension))
                            return -1
                        this[target_var] := destination
                        this[target_var . "_obj"] := FileOpen(destination, "w")
                }
                this.Write(Format("Connected ZipChord {} to {}.", what, destination))
            Case "help":
                this.Write("TK: Help. mention 'console' is default.")
                return
            Default:
                this._MessageTryHelp(A_ThisFunc)
        }
    }
    Record(what:="", fname:="") {
        Switch what {
            Case "":
                what:="both"
            Case "both":
                
            Case "input":

            Case "output":

            Case "help":
                this.Write("TK: Help. mention 'both' is default.")
                return
            Default:
                fname:=what
                what:="both"
        }
        if (what=="input" || what=="both")
            if (this.Monitor("input", fname) == -1)
                return
        if (what=="output" || what=="both")
            if (this.Monitor("output", fname) == -1)
                return
        if(this.Interact())
            return true
    }
    _Ready() {
        this.Write("Loading dictionaries...")
        chords.Load(settings.chord_file)
        shorthands.Load(settings.shorthand_file)
        this._starting_tick := 0
        GoSub Interrupt
    }
    _Stop() {
        WireHotkeys("Off")
        this._mode := TEST_STANDBY
        this.Write("Interactive mode stopped.")
        this.Monitor("input", "off")
        this.Monitor("output", "off")
    }
    Log(output, is_input := false) {
        if (A_Args[1] == "test-vs") {
            OutputDebug, % output . terminator
            Return
        }
        if (this._input && is_input) {
            if (!this._starting_tick)
                this._starting_tick := A_TickCount
            timestamp := A_TickCount - this._starting_tick
            if (this._input == TEST_DEST_CONSOLE)
                this.Write("IN: " . timestamp . "`t" . output)
            else
                this._input_obj.Write(timestamp . "`t" . output . "`n")
        }
        if (this._output && !is_input) {
            if (this._output == TEST_DEST_CONSOLE)
                this.Write("OUT: " . output)
            else
                this._output_obj.Write(output . "`n")
        }
    }
    Play(in_file:="") {
        if (! this._CheckFilename(in_file, "in", true))
            return -1
        this.Write("Playback file is: " in_file)
        this._Ready()
        this.Write(Format("Sending the test '{}' to ZipChord...", in_file))
        this._mode := TEST_RUNNING
        Loop, Read, % in_file
        {
            columns := StrSplit(A_LoopReadLine, A_Tab)
            test_timestamp := columns[1]
            test_key := columns[2]
            if (SubStr(test_key, -2)==" Up")
                GoSub KeyUp
            else
                GoSub KeyDown
        }
        this._Stop()
    }
    Test(cfg:="", in_file:="", out_file:="") {
        if (cfg=="help") {
            this.Write("TK: Help. Three uses:`nTEST testcase`nTEST BATCH batch`nTEST config input [output]`n`n  testcase    Run the specified test case file and compare the output against the test case.`n`nThe default 'output' will be a test case 'config_name__input_name.out'")
            return
        }
        if (cfg=="batch") {
            this._Batch(in_file)
            return
        }
        if (cfg:=="" or InStr(cfg, "__"))
            this._Retest(cfg)
        if (this.Config("load", cfg) == -1)
            return
        if (! this._CheckFilename(in_file, "in", true))
            return
        if (out_file=="")
            out_file := SubStr(cfg, 10, StrLen(cfg)-13) . "__" . SubStr(in_file, 10, StrLen(in_file)-12)
        this.Monitor("input", "off")
        if (this.Monitor("output", out_file) == -1)
            return
        if (this.Play(in_file) == -1)
            return
    }
    _Retest(test_case:="") {
        if (! this._CheckFilename(test_case, "out", true))
            Return
        cfg := SubStr(test_case, 10, InStr(test_case, "__")-10)
        in_file := SubStr(test_case, InStr(test_case, "__")+2, StrLen(test_case)-InStr(test_case, "__")-5)
        FileDelete, % "..\tests\temp.out"
        this.Test(cfg, in_file, "temp")
        this.Compare(test_case, "..\tests\temp.out")
    }
    Compare(a:="", b:="") {
        if (a=="help") {
            this.Write("TK: Help.")
            return
        }
        if (! this._CheckFilename(a, "out", true))
            Return
        if (! this._CheckFilename(b, "out", true))
            Return
        RunWait % "fc.exe /a /n " . a . " " . b
    }
    List(mask:="*.*") {
        Switch mask {
            Case "config", "configs":
                opts := "dir /b *.cfg"
            Case "input", "inputs":
                opts := "dir /b *.in"
            Case "output", "outputs":
                opts := "dir /b *.out | find /v ""__"""
            Case "case", "cases":
                opts := "dir /b *__*.out"
            Case "help":
                this.Write("TK: Help.")
                return
            Default:
                opts := "dir /b " . mask
        }
        RunWait  %ComSpec% /c %opts%, % "..\tests\"
    }
    _Batch(set_name:="") {
        if (! this._CheckFilename(set_name, "set", true))
            Return
        Loop, Read, % set_name
        {
            this.Write(Format("Test case '{}':", A_LoopReadLine))
            this.Retest(Trim(A_LoopReadLine))
        }
    }
    Write(output, terminator:="`n") {
        if (A_Args[1] == "test-vs") {
            OutputDebug, % output . terminator
        } else {
            this._stdout.Write(output . terminator)
            this._stdout.Read(0)
        }
    }
    Prompt() {
        if (this._mode==TEST_INTERACTIVE) {
            WinActivate % "ZipChord Console"
            this._Stop()
        }
        this.Write("`n>", "")
        if (A_Args[1] == "test-vs")
            InputBox, raw,% "ZipChord Console", % ">"
        else
            raw := this._stdin.ReadLine()
        parsed := StrSplit(Trim(raw, " `n"), " ")
        StringLower parsed, parsed
        command:= parsed[1]
        StringUpper command, command, T
        parsed.RemoveAt(1)
        cmd_fn := ObjBindMethod(this, command)
        if(! %cmd_fn%(parsed*)) {
            prompt_fn := ObjBindMethod(this, "Prompt")
            SetTimer % prompt_fn, -10 ; show prompt again after we're done
        }
    }
    Exit() {
        ExitApp
    }
    License() {
        LinkToLicense()
    }
    Help() {
        this.Write("Available commands: COMPARE, CONFIG, INTERACT, LIST, MONITOR, RECORD, PLAY, TEST, EXIT")
        this.Write("Type 'command HELP' to learn more about each.")
    }
    _CheckFilename(ByRef filename, extension, should_exist := false) {
        if (! filename) {
            this.Write("Provide file name:", " ")
            filename := Trim(this._stdin.ReadLine(), " `n")
            if (! filename)
                return false
        }
        extension := "." . extension
        if (SubStr(filename, 1-StrLen(extension)) != extension)
            filename .= extension
        if (SubStr(filename,1, 9) != "..\tests\")
            filename := "..\tests\" . filename
        if (should_exist) {
            if (! FileExist(filename)) {
                this.Write(Format("Error: The file '{}' does not exists.", filename))
                return false
            }
        } else {
            if (FileExist(filename)) {
                this.Write(Format("The file '{}' already exists. Overwrite [Y/N]?", filename), " ")
                if (A_Args[1] == "test-vs")
                    InputBox, answer,% "Overwrite? [Y/N]", % ">"
                else
                    answer := SubStr(Trim(this._stdin.ReadLine()), 1, 1)
                if (answer!="Y")
                    return false
            }
            FileDelete, % filename
        }
        return filename
    }
    _MessageTryHelp(fn) {
        fn := SubStr(fn, InStr(fn, ".")+1)
        StringUpper fn, fn
        this.Write(Format("Could not understand the command. Try '{} HELP'.", fn))
    }
    __Call(name, params*) {
        if (!IsFunc(this[name])) {
            this.Write("Error, command not recognized.")
        }
        params := 0  ; to remove compiler warning
    }
}

global test := New TestingClass()
