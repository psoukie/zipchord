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
    _mode := TEST_STANDBY
    _starting_tick := 0
    mode {
        get { 
            return this._mode 
        }
    }
    __New() {
        this._mode := 1
    }
    Init() {
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
    Config(mode:="", filename:="") {
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
                if (! this._CheckFilename(filename, "ini"))
                    return
                this.Write(Format("Saving current configuration to '{}'.", filename))
                SavePropertiesToIni(settings, "Application", filename)
                SavePropertiesToIni(keys, "Locale", filename)
            Case "load":
                if (! this._CheckFilename(filename, "ini"))
                    return
                this.Write(Format("Loading configuration from '{}'.", filename))
                LoadPropertiesFromIni(settings, "Application", filename)
                LoadPropertiesFromIni(keys, "Locale", filename)
            Default:
                this.Write("TK: config command help")
        }
    }
    Interact() {
        this._Ready()
        this.Write("Switching to interactive mode...`nPress Ctrl-X to resume in the console.")
        this._mode := TEST_INTERACTIVE
        Return true
    }
    Wire(what:="", destination:="") {
        Switch what {
            Case "", "show":
                this.Write(Format("ZipChord input is wired to {}.", this._input))
                this.Write(Format("ZipChord output is wired to {}.", this._output))
            Case "input", "output":
                target_var := "_" . what
                Switch destination {
                    Case "console":
                        this[target_var] := TEST_DEST_CONSOLE                    
                    Case "off":
                        this[target_var] := TEST_DEST_NONE                    
                    Default:
                        if (! this._CheckFilename(destination, "txt"))
                            return
                        this[target_var] := destination
                        this[target_var . "_obj"] := FileOpen(destination, "w")
                }
                this.Write(Format("Wired ZipChord {} to {}.", what, destination))
            Default:
                this.Write("TK: WIRE command help")
        }
    }
    _Ready() {
        this.Write("Loading dictionaries and wiring hotkeys...")
        chords.Load(settings.chord_file)
        shorthands.Load(settings.shorthand_file)
        WireHotkeys("On")
        this._starting_tick := 0
        GoSub Interrupt
    }
    _Stop() {
        WireHotkeys("Off")
        this._mode := TEST_STANDBY
        this.Write("Interactive mode stopped.")
        this._DisconnectFile("input")
        this._DisconnectFile("output")
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
    Test(case) {
        if (! this._CheckFilename(case, "txt", false))
            return
        this._Ready()
        this.Write("Sending the test to ZipChord.")
        this._mode := TEST_RUNNING
        Loop, Read, % case
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
    Write(output, terminator:="`n") {
        if (A_Args[1] == "test-vs") {
            OutputDebug, % output . terminator
        } else {
            this._stdout.Write(output . terminator)
            this._stdout.Read(0)
        }
    }
    Prompt() {
        if (this._mode==TEST_INTERACTIVE)
            this._Stop()
        this.Write("`n>", "")
        if (A_Args[1] == "test-vs")
            InputBox, raw,% "ZipChord Console", % ">"
        else
            raw := RTrim(this._stdin.ReadLine(), "`n")
        parsed := StrSplit(Trim(raw), " ")
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
        this.Write("Available commands: CONFIG, INTERACT, RECORD, TEST, WIRE, EXIT")
        this.Write("Type 'command-name HELP' to learn more about each.")
    }
    _CheckFilename(ByRef filename, extension, warn_exists := true) {
        if (! filename) {
            this.Write("Provide file name:", " ")
            filename := Trim(RTrim(this._stdin.ReadLine(), "`n"))
            if (! filename)
                return false
        }
        extension := "." . extension
        if (SubStr(filename, -3) != extension)
            filename .= extension
        filename := "..\tests\" . filename
        if (warn_exists) {
            if (FileExist(filename)) {
                this.Write(Format("The file '{}' already exists. Overwrite [Y/n]?", filename)" ")
                answer := SubStr(Trim(this._stdin.ReadLine()), 1, 1)
                if (answer!="Y")
                    return false
            }
            FileDelete, % filename
        }
        return filename
    }
    _DisconnectFile(which) {
        if (this["_" . which . "_obj"]) {
            this["_" . which . "_obj"].Close()
            this["_" . which . "_obj"] := ""
            Run % this["_" . which]
            this.Write(Format("Disconnected the {} file.", which))
        }
    }
    __Call(name, params*) {
        if (!IsFunc(this[name])) {
            this.Write("Error, command not recognized.")
        }
        params := 0  ; to remove compiler warning
    }
}

global test := New TestingClass()
