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
    _path := ".\"
    mode {
        get { 
            return this._mode 
        }
    }
    Init() {
        this._mode := TEST_STANDBY
        WireHotkeys("Off")
        if (A_Args[1] != "test-vs") {
            DllCall("AllocConsole")
            DllCall("SetConsoleTitle", Str, "ZipChord Test Automation")
            DllCall("SetConsoleTitle", Str, "ZipChord Test Automation")
            this._stdin  := FileOpen("*", "r `n")
            this._stdout := FileOpen("*", "w `n")
        }
        this.Write(Format("ZipChord Test Automation Console [Version {}]", version))
        this.Write("`nCopyright (c) 2023 Pavel Soukenik")
        this.Write("This program comes with ABSOLUTELY NO WARRANTY.")
        this.Write("This is free software, and you are welcome to redistribute it")
        this.Write("under certain conditions. Type 'license' for details.")
        if InStr(FileExist("..\tests\"), "D") {
            this.Write("`nDetected the default testing folder.")
            this.Path("set", "..\tests\")
        }
        this.Write("`nType 'help' for a list of available commands.")
        this._Prompt()
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
                SavePropertiesToIni(settings, "Application", this._path . filename)
                SavePropertiesToIni(keys, "Locale", this._path . filename)
                this.Write(Format("Saved current configuration to '{}'.", filename))
            Case "load":
                if (! this._CheckFilename(filename, "cfg", true))
                    return -1
                LoadPropertiesFromIni(settings, "Application", this._path . filename)
                LoadPropertiesFromIni(keys, "Locale", this._path .filename)
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
        prompt_fn := ObjBindMethod(this, "_Prompt")
        Hotkey, % "^x", % prompt_fn, % "On"
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
                        this[target_var . "_obj"] := FileOpen(this._path . destination, "w")
                }
                this.Write(Format("Connected ZipChord {} to {}.", what, destination))
            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
            Default:
                this._MessageTryHelp(A_ThisFunc)
        }
    }
    Record(what:="", filename:="", out_file:="") {
        if (this._IsBasicHelp(what, A_ThisFunc))
            return
        Switch what {
            Case "both", "input", "output":
                orig_name := filename
                if (what=="input" || what=="both")
                    if (this.Monitor("input", filename) == -1)
                return
                if (what=="output" || what=="both")
                    if (this.Monitor("output", orig_name) == -1)
                return
                return this.Interact()
            Default:
                return this._RecordCase(what, filename, out_file)
        }
    }
    _RecordCase(cfg:="", in_file:="", out_file:="") {
        if (this.Config("load", cfg) == -1)
            return
        if (this.Monitor("input", in_file) == -1)
            return
        if (out_file="")
           out_file := SubStr(cfg, 1, StrLen(cfg)-4) . "__" . SubStr(in_file, 1, StrLen(in_file)-3)
        if (this.Monitor("output", out_file) == -1)
            return
        return this.Interact()
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
            Hotkey, % "^x", % prompt_fn, % "Off"
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
        if (this._IsBasicHelp(cfg, A_ThisFunc))
                return
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
        Loop, Read, % this._path . in_file
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
        if (this._IsBasicHelp(cfg, A_ThisFunc))
                return
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
    Test(testcase:="", filename:="") {
        if (this._IsBasicHelp(testcase, A_ThisFunc))
            return
        if (filename && testcase=="set")
                this._Batch(filename)
        else {
            if (! this._CheckFilename(testcase, "testcase", true))
                Return
            cfg := SubStr(testcase, 1, InStr(testcase, "__")-1)
            in_file := SubStr(testcase, InStr(testcase, "__")+2, StrLen(testcase)-InStr(testcase, "__")-5)
            FileDelete, % this._path . "temp.out"
            this.Compose(cfg, in_file, "temp.out")
            this.Compare(testcase, "temp.out")
        }
    }
    Compare(a:="", b:="") {
        if (this._IsBasicHelp(a, A_ThisFunc))
            return
        if (! this._CheckFilename(a, "out", true))
            Return
        if (! this._CheckFilename(b, "out", true))
            Return
        RunWait % "fc.exe /a /n " . this._path . a . " " . this._path . b
    }
    Add(testcase:="", testset:="") {
        if (this._IsBasicHelp(testcase, A_ThisFunc))
            return
        if (! this._CheckFilename(testcase, "testcase", true))
            Return
        if (! this._CheckFilename(testset, "set", true))
            this.Write(Format("...Creating new test set '{}' and adding '{}'.", testset, testcase))
        FileAppend % testcase, % this._path . testset
        }
    Delete(file:="") {
        if (this._IsBasicHelp(file, A_ThisFunc))
            return
        RunWait %ComSpec% /c del %file%, % this._path
    }
    Path(mode:="", path:="") {        
        Switch mode {
            Case "", "show":
                this.Write("The path to test files is {}." . this._path)
            Case "set":
                if (! InStr(FileExist(path), "D")) {
                    this.Write(Format("The path '{}' does not exist.", path))
                    return
                }
                this._path := path
                this.Write(Format("Changed the path for test files to '{}'.", path))
            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
            Default:
                this._MessageTryHelp(A_ThisFunc)
        }
    }
    List(mask:="*.*") {
        Switch mask {
            Case "configs":
                opts := "dir /b *.cfg"
            Case "inputs":
                opts := "dir /b *.in"
            Case "outputs":
                opts := "dir /b *.out | find /v ""__"""
            Case "sets":
                opts := "dir /b *.out | find /v ""__"""
            Case "cases":
                opts := "dir /b *__*.out"
            Case "help":
                this.Help(ObjFnName(A_ThisFunc))
                return
            Default:
                opts := "dir /b " . mask
        }
        RunWait %ComSpec% /c %opts%, % this._path
    }
    Show(file:="") {
        if (this._IsBasicHelp(file, A_ThisFunc))
            return
        RunWait %ComSpec% /c type %file%, % this._path

    }
    TryMe() {
        this.Write("Try me" . Chr(8))
    }
    _Batch(testset:="") {
        if (! this._CheckFilename(testset, "set", true))
            Return
        Loop, Read, % this._path . testset
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
    _Prompt() {
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
            prompt_fn := ObjBindMethod(this, "_Prompt")
            SetTimer % prompt_fn, -10 ; show prompt again after we're done
        }
    }
    Exit(a:="") {
        if (a!="help")
            ExitApp
        this.Help(ObjFnName(A_ThisFunc))
    }
    License(a:="") {
        if (a!="help") {
            LinkToLicense()
            return
        }
        this.Help(ObjFnName(A_ThisFunc))
    }
    _CheckFilename(ByRef filename, extension, should_exist := false) {
        if (extension=="testcase") {
            if (! InStr(filename, "__")) {
                this.Write("Error: You need to provide a test case to use this command. Try TEST HELP.")
                return false
            }
            extension:="out"
        }
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
            if (! FileExist(this._path . filename)) {
                this.Write(Format("Error: The file '{}' does not exists.", filename))
                return false
            }
        } else {
            if (FileExist(this._path . filename)) {
                this.Write(Format("The file '{}' already exists. Overwrite [y/n]?", filename), " ")
                if (A_Args[1] == "test-vs")
                    InputBox, answer,% "Overwrite? [y/n]", % ">"
                else
                    answer := SubStr(Trim(this._stdin.ReadLine()), 1, 1)
                if (answer!="Y")
                    return false
            }
            FileDelete, % this._path . filename
        }
        return filename
    }
    _IsBasicHelp(param, fn) {
        if (param && param!="help")
            return false
        if (param=="help")
            this.Help(ObjFnName(fn))
        else
            this._MessageTryHelp(fn)
        return true
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