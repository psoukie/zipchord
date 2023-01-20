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
                Run % "Notepad.exe"
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
            this.Write("Stopped interactive mode.")
        }
        this._mode := TEST_STANDBY
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
    Show(opt:="", file:="") {
        if (this._IsBasicHelp(opt, A_ThisFunc))
            return
        if (file && opt=="raw") {
        RunWait %ComSpec% /c type %file%, % this._path
            Return
        }
        file := opt
        if (SubStr(file, InStr(file, ".", false, 0)) == ".out") { ; searches for "." from the back
            Loop, Read, % this._path . file
            {
                key := A_LoopReadLine
                if (SubStr(key, 1, 1) == "~")
                    key := SubStr(key, 2)
                Switch key {
                    Case "Enter":
                        out .= "`n"
                    Case "Space", "{Space}":
                        out .= " "
                    Case "{Backspace}":
                        out := SubStr(out, 1, StrLen(out)-1)
                    Case "{Backspace 2}":
                        out := SubStr(out, 1, StrLen(out)-2)
                    Case "*Hint*":

                    Default:
                        if (SubStr(key, 1, 17)=="{Backspace}{Text}") {
                            out := SubStr(out, 1, StrLen(out)-1) . SubStr(key, 18)
                            Continue
    }
                        if (SubStr(key, 1, 6)=="{Text}") {
                            out .= SubStr(key, 7)
                            Continue
                        }
                        if (SubStr(key, 1, 1) == "+")
                            out .= ToAscii(SubStr(key, 2, 1), ["Shift"])
                        else
                            out .= key
                }
            }
            this.Write(out)
            return
        }
        RunWait %ComSpec% /c type %file%, % this._path
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
            Case "add":
                this.Write("
(
Adds a specified existing test case to a test set.

add <testcase> <testset>

  <testcase>    The name of an existing test case file to add.
  <testset>     The name of the test set the case will be added to. 
)")
            Case "compare":
                this.Write("
(
Runs a comparison and shows differences between two output files.

compare <output1> <output2>

  <output1>    Specifies the first output file to compare.
  <output2>    Specifies the second output file to compare.
)")
            Case "compose":
                this.Write("
(
Creates a test case from the specified configartion and input files.
If you don't specify the output file, the result is saved in an
automatically named test case file.  

compose <configfile> <inputfile> [<outputfile>]

  <configfile>    The settings to be applied for creation of this test.
  <inputfile>     The input to be played to generate the test's output.
  <outputfile>    The output file with the result of the test. If omitted,
                  saves a test case as '<configfile>__<inputfile>.out'. 
)")
            Case "config":
                this.Write("
(
Shows, saves or loads ZipChord configuration and keyboard and language
settings. If used without parameters, it displays the current settings.

config [show]
config {save|load} <configfile>

   show            Shows current ZipChord settings. (Default behavior when
                   used without parameters.)
   save            Saves current ZipChord settings to the specified file.
   load            Loads settings from the specified file to ZipChord.
   <configfile>    Name of the configuration file to load or save.
)")
            Case "delete":
                this.Write("
(
Deletes the specified file.

delete <filename>

  <filename>    The file name, including extension, of the file to delete. 
)")
            Case "exit":
                this.Write("
(
Quits the console and ZipChord. (ZipChord is terminated because the
console is linked to the application.)
)")
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
                this.Write("
(
Resumes ZipChord in an interactive mode.

ZipChord is paused whenever the Test Automation prompt is available.
Use this command to make changes in ZipChord user interface or to monitor
or capture ZipChord's input and output using this console.

Press Ctrl+X to pause ZipChord and return to the console.  
)")
            Case "license":
                this.Write("
(
Shows the license for this product in a text file, or (if the license file
is unavailable) opens the text on website. 
)")
            Case "list":
                this.Write("
(
Lists all files in the testing folder or only files of the specified type.

list [<type>]

  <type>    When omitted, lists all the files in the testing folder.
            The <type> can be one of the following:
               inputs     input files 
               outputs    output files (execept test cases)
               cases      test case files 
               sets       test set files
)")
            Case "monitor":
                this.Write("
(
Shows or changes the destination of ZipChord's input (detected key
presses) and output streams. The input and output destinations can be
individually sent to console, a file, or turned off.

monitor [show]
monitor {input | output} {console | off | <filename>}

   show          Shows current destinations of input and output streams.
                 (Default behavior when used without parameters.)
   input         Changes the destination of the input stream.
   output        Changes the destination of the output stream.
   console       The specified stream will be shown on the console.
   off           The stream will be ignored. 
   <filename>    The stream will be recorded to the specified file.
)")
            Case "path":
                this.Write("
(
Shows or sets the working folder where the testing files are stored
and read from. This can be an abosolute or relative path. If used
without parameters, it displays the current folder.

path [show | set <path>]

   show      Shows the current path to test files.
   set       Sets the relative or absolute path to test files.
   <path>    Name of the configuration file to load or save.
)")
            Case "play":
                this.Write("
(
Sends recorded keyboard input to ZipChord for processing.

play [configfile] <inputfile>

  <configfile>    The settings to be applied for sending this input.
  <inputfile>     The input to be sent to ZipChord.

Note: The output from ZipChord may be handled depending on the output
setting. See also 'monitor'.
)")
            Case "record":
                this.Write("
(
Records input and/or output of an interactive session into specified
file(s) or into a test case with a corresponding name.

record {input | output | both} <filename>
record <configfile> <inputfile> [<outputfile>]

  input           Only keyboard input detected by ZipChord will be
                  recorded.
  output          Only ZipChord's output will be recorded.
  both            Both input and output will be recorded simultaneously
                  into files named '<filename>.in' and '<filename>.out'.
                  (Do not include the file extension in <filename> when
                  using this option.)
  <filename>      File where the input and/or output of the interaction
                  will be recorded.
  <configfile>    The settings to be applied for this recording.
  <inputfile>     File where the detected input will be recorded.
  <outputfile>    Optional name for the file where the session output
                  will be recorded. When omitted, the output is saved as
                  a test case named '<configfile>__<inputfile>.out'.
)")
            Case "show":
                this.Write("
(
Shows the contents of a file in the console. Output and test case files
are formatted as they would look in text editor, unless the 'raw' option
is specified.

show [raw] <filename>

  <filename>    The name (including extension) of the file to show. 
  raw           Forces the raw output for test case and output files.  
)")
            Case "test":
                this.Write("
(
Runs a test case or a set of cases and compares the output that this
generates against the original output stored in the test cases.

test <testcase>
test set <testset>

  <testcase>    Run the specified test case file and compare the output
                against the test case.
  <testset>     Run a set of test cases listed in the specified test set.
                (Use 'add' to add test cases to a test set.)
)")
            Default:
                this.Write("
(
Available commands:

add         Adds an existing test case to a test set.
compare     Shows differences between two output files.     
compose     Creates a test case from a given configartion and input file.
config      Shows, saves or loads app configuration and keyboard settings.
delete      Deletes the specified file.
exit        Exits the console and ZipChord.
path        Shows or sets the path to the folder for testing files.
help        Shows help information for ZipChord Test Automation commands.
interact    Resumes ZipChord in an interactive mode.
license     Shows the license information.
list        Lists all files (or files of a type) in the testing folder.
monitor     Directs the input or output of ZipChord to console or a file.
play        Sends recorded input to ZipChord for processing.
record      Records input and/or output of your interaction to a file.
show        Shows the contents of a file.
test        Runs and compares results of a test case or a set of cases.

Note: Including file extensions in file names is optional except in
commands 'show' and 'delete'.

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

; The following code is from "just me" in https://www.autohotkey.com/boards/viewtopic.php?t=1040

ToAscii(Key, Modifiers := "") {
   VK_MOD := {Shift: 0x10, Ctrl: 0x11, Alt: 0x12}
   VK := GetKeyVK(Key)
   SC := GetKeySC(Key)
   VarSetCapacity(ModStates, 256, 0)
   For _, Modifier In Modifiers
      If VK_MOD.HasKey(Modifier)
         NumPut(0x80, ModStates, VK_MOD[Modifier], "UChar")
   DllCall("USer32.dll\ToAscii", "UInt", VK, "UInt", SC, "Ptr", &ModStates, "UIntP", Ascii, "UInt", 0, "Int")
   Return Chr(Ascii)
}

global test := New TestingClass()
