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
    _folder := ""
    mode {
        get { 
            return this._mode 
        }
    }
    Init() {
        this._mode := TEST_STANDBY
        this._folder := "..\tests\"
        WireHotkeys("Off")
        prompt_fn := ObjBindMethod(this, "Prompt")
        if (A_Args[1] != "test-vs") {
            DllCall("AllocConsole")
            DllCall("SetConsoleTitle", Str, "ZipChord Test Automation")
            this._stdin  := FileOpen("*", "r `n")
            this._stdout := FileOpen("*", "w `n")
        }
        Hotkey, % "^x", % prompt_fn
        this.Write(Format("ZipChord Test Automation Console [Version {}]", version))
        this.Write("`nCopyright (c) 2023 Pavel Soukenik")
        this.Write("This program comes with ABSOLUTELY NO WARRANTY.")
        this.Write("This is free software, and you are welcome to redistribute it")
        this.Write("under certain conditions. Type 'license' for details.")
        this.Write("`nType 'help' for a list of available commands.")
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
                    return -1
                SavePropertiesToIni(settings, "Application", this._folder . filename)
                SavePropertiesToIni(keys, "Locale", this._folder . filename)
                this.Write(Format("Saved current configuration to '{}'.", filename))
            Case "load":
                if (! this._CheckFilename(filename, "cfg", true))
                    return -1
                LoadPropertiesFromIni(settings, "Application", this._folder . filename)
                LoadPropertiesFromIni(keys, "Locale", this._folder .filename)
                this.Write(Format("Loaded configuration from '{}'.", filename))
            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
            Default:
                this._MessageTryHelp(A_ThisFunc)
        }
    }
    Interact(a:="") {
        Switch a {
            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
                return
            Case "":
                
            Default:
                this._MessageTryHelp(A_ThisFunc)
                return
        }
        this._Ready()
        if(settings.chords_enabled || settings.shorthands_enabled) {
            this.Write("Wiring hotkeys...")
            WireHotkeys("On")
        }
        this.Write("Switching to interactive mode...`nPress Ctrl-X to resume in the console.")
        this._mode := TEST_INTERACTIVE
        Return true
    }
    Monitor(what:="", ByRef destination:="console") {
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
                        this[target_var . "_obj"] := FileOpen(this._folder . destination, "w")
                }
                this.Write(Format("Connected ZipChord {} to {}.", what, destination))
            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
            Default:
                this._MessageTryHelp(A_ThisFunc)
        }
    }
    Record(what:="", fname:="", out_file:="") {
        Switch what {
            Case "":
                this._MessageTryHelp(A_ThisFunc)
                return
            Case "both":
                
            Case "input":

            Case "output":

            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
                return
            Default:
                this._RecordCase(what, fname, out_file)
                return
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
    _RecordCase(cfg:="", in_file:="", out_file:="") {
        if (this.Config("save", cfg) == -1)
            return
        if (this.Monitor("input", in_file) == -1)
            return
        if (out_file="")
           out_file := SubStr(cfg, 1, StrLen(cfg)-4) . "__" . SubStr(in_file, 1, StrLen(in_file)-3)
        if (this.Monitor("output", out_file) == -1)
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
    Stop() {
        if (this.mode == TEST_INTERACTIVE) {
            WireHotkeys("Off")
            this._mode := TEST_STANDBY
            this.Write("Stopped interactive mode.")
        }
        this.Monitor("input", "off")
        this.Monitor("output", "off")
    }
    Log(output, is_input := false) {
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
    Play(cfg:="", in_file:="") {
        Switch cfg {
            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
                return
            Case "":
                this._MessageTryHelp(A_ThisFunc)
        }
        if (in_file != "") {
            if (this.Config("load", cfg) == -1)
                return
        } else {
            in_file := cfg
        }
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
        this.Stop()
    }
    Compose(cfg:="", in_file:="", out_file:="") {
        Switch cfg {
            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
                return
            Case "":
                this._MessageTryHelp(A_ThisFunc)
        }
        if (this.Config("load", cfg) == -1)
            return
        if (! this._CheckFilename(in_file, "in", true))
            return
        if (out_file="")
           out_file := SubStr(cfg, 1, StrLen(cfg)-4) . "__" . SubStr(in_file, 1, StrLen(in_file)-3)
        this.Monitor("input", "off")
        if (this.Monitor("output", out_file) == -1)
            return
        if (this.Play(in_file) == -1)
            return
    }
    Test(param:="", filename:="") {
        Switch param {
            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
            Case "":
                this._MessageTryHelp(A_ThisFunc)
            Case "batch":
                this._Batch(filename)
            Default:
                this._TestCase(param)            
        }
    }
    _TestCase(test_case:="") {
        if (! this._CheckFilename(test_case, "out", true))
            Return
        if (! InStr(test_case, "__")) {
            this.Write("Error: You need to provide a test case to use this command. Try TEST HELP.")
            return
        }
        cfg := SubStr(test_case, 1, InStr(test_case, "__")-1)
        in_file := SubStr(test_case, InStr(test_case, "__")+2, StrLen(test_case)-InStr(test_case, "__")-5)
        FileDelete, % this._folder . "temp.out"
        this.Compose(cfg, in_file, "temp.out")
        this.Compare(test_case, "temp.out")
    }
    Compare(a:="", b:="") {
        Switch a {
            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
                return
            Case "":
                this._MessageTryHelp(A_ThisFunc)
        }
        if (! this._CheckFilename(a, "out", true))
            Return
        if (! this._CheckFilename(b, "out", true))
            Return
        RunWait % "fc.exe /a /n " . this._folder . a . " " . this._folder . b
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
                this.Help(ObjFnName(A_ThisFunc))
                return
            Default:
                opts := "dir /b " . mask
        }
        RunWait  %ComSpec% /c %opts%, % this._folder
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
        if (this.mode == TEST_OFF)
            return  ; we don't want to ouput anything if the method is called without the console open
        if (A_Args[1] == "test-vs") {
            OutputDebug, % output . terminator
        } else {
            this._stdout.Write(output . terminator)
            this._stdout.Read(0)
        }
    }
    Prompt() {
        if (this._mode==TEST_INTERACTIVE) {
            WinActivate % "ZipChord Test Automation"
            this.Stop()
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
    Exit(a:="") {
        if (a!="help")
            ExitApp
        this.Help(ObjFnName(A_ThisFunc))
    }
    License(a:="") {
        if (a!="help")
            LinkToLicense()
        this.Help(ObjFnName(A_ThisFunc))
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
        if (should_exist) {
            if (! FileExist(this._folder . filename)) {
                this.Write(Format("Error: The file '{}' does not exists.", filename))
                return false
            }
        } else {
            if (FileExist(this._folder . filename)) {
                this.Write(Format("The file '{}' already exists. Overwrite [Y/N]?", filename), " ")
                if (A_Args[1] == "test-vs")
                    InputBox, answer,% "Overwrite? [Y/N]", % ">"
                else
                    answer := SubStr(Trim(this._stdin.ReadLine()), 1, 1)
                if (answer!="Y")
                    return false
            }
            FileDelete, % this._folder . filename
        }
        return filename
    }
    _MessageTryHelp(fn) {
        this.Write( Format("Could not understand the command. Try 'help {}'.", ObjFnName(fn)) )
    }
    __Call(name, params*) {
        if (!IsFunc(this[name])) {
            this.Write("Error, command not recognized.")
        }
        params := 0  ; to remove compiler warning
    }
    Help(topic:="") {
        Switch topic {
            Case "compare":
                this.Write("TBD")
            Case "compose":
                this.Write("TBD COMPOSE config input`n`n  Creates a test case named 'config__input.out' with the output that was produced by playing 'input' with 'config' settings.`n TK testcase    Run the specified test case file and compare the output against the test case.`n`nThe default 'output' will be a test case 'config_name__input_name.out'")
            Case "config":
                this.Write("
(
Saves or loads ZipChord configuration and keyboard and language settings.
If used without parameters, it displays the current settings.

config [show]
config {save|load} <config_name>
   [show]          Show current ZipChord settings.
   <config_name>   Name of the configuration file to load or save.
)")
            Case "exit":
                this.Write("TBD")
            Case "help":
                this.Write("
(
Displays a list of the available commands or help information about
a specified command. If used without parameters, lists and briefly
describes every command.

help [<command>]

  <command>    Specifies the command for which to show help.
)")
            Case "interact":
                this.Write("TBD")
            Case "license":
                this.Write("TBD")
            Case "list":
                this.Write("TBD")
            Case "monitor":
                this.Write("TBD")
            Case "play":
                this.Write("TBD PLAY [config] input")
            Case "record":
                this.Write("TBD")
            Case "test":
                this.Write("TBD TEST testcase`nTEST BATCH batch`n`n  testcase    Run the specified test case file and compare the output against the test case.`n`nThe default 'output' will be a test case 'config_name__input_name.out")
            Default:
                this.Write("
(
ZipChord Test Automation commands:

compare     Shows differences between two output files.     
compose     Creates a test case from a given configartion and input file.
config      Shows, saves or loads app configuration and keyboard settings. 
exit        Exits the console and ZipChord.
help        Shows help information for ZipChord Test Automation commands.
interact    Temporarily switches to normal interaction with the app.
list        Lists all or specified files in the testing folder.
monitor     Directs the input or output of ZipChord to console or a file.
play        Sends recorded input to ZipChord for processing.
record      Records input and/or output of your interaction to a file. 
test        Runs and compares results of a test case or a set of cases.

For more information on a specific command, type 'help <command>'.
)")
        }

    }
}

; Helper function

ObjFnName(fn) {
    StringLower, fn, % SubStr(fn, InStr(fn, ".")+1)
    return fn
}

global test := New TestingClass()