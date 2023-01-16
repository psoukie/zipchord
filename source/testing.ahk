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
    , TEST_PLAYING := 2
    , TEST_RECORDING := 3
global TEST_TO_CONSOLE := 1
    , TEST_TO_INPUT := 2
    , TEST_TO_OUTPUT := 3

global stdin, stdout

Class TestingClass {
    _test_input_file := ""
    _test_output_file := ""
    _mode := TEST_OFF
    _starting_tick := 0
    mode {
        get { 
            return this._mode 
        }
    }
    __New() {
        this._mode := TEST_STANDBY
        prompt_fn := ObjBindMethod(this, "Prompt")
        if (A_Args[1] != "test-vs") {
            DllCall("AllocConsole")
            stdin  := FileOpen("*", "r `n")
            stdout := FileOpen("*", "w `n")
            this.Write("Press Ctrl-X to interrupt.")
        }
        Hotkey, % "^x", % prompt_fn
    }
    Record() {
        this._mode := TEST_RECORDING
        FileDelete, "test_input.txt"
        this._test_input_file := FileOpen("test_input.txt", "w")
        FileDelete, "test_output.txt"
        this._test_output_file := FileOpen("test_output.txt", "w")
        this.Write("Recording is now in progress...`nPress Ctrl-X to stop.")
        this.Log("<<Start of input>>", TEST_TO_INPUT)
        this.Log("<<Start of output>>", TEST_TO_OUTPUT)
        this._starting_tick := 0
    }
    Play() {
        this.Write("Playing back recording.")
    }
    Stop() {
        this.Log("<<End of input>>", TEST_TO_INPUT)
        this.Log("<<End of output>>", TEST_TO_OUTPUT)
        this.Write("Recording stopped.`nOpening the files for review.`nPress Ctrl-X for another command.")
        this._mode := TEST_STANDBY
        if (this._test_output_file != "") {
            this._test_output_file.Close()
            this._test_output_file := ""
            Run % "test_output.txt"
        }
        if (this._test_input_file != "") {
            this._test_input_file.Close()
            this._test_input_file := ""
            Run % "test_input.txt"
        }
    }
    Log(output, destination := 1) {
        if (A_Args[1] == "test-vs") {
            OutputDebug, % output . terminator
            Return
        }
        Switch destination {
            Case TEST_TO_INPUT:
                if (this._test_input_file != "") {
                    if (!this._starting_tick)
                        this._starting_tick := A_TickCount
                    timestamp := A_TickCount - this._starting_tick
                    this._test_input_file.Write(timestamp . "`t" . output . "`n")
                }
            Case TEST_TO_OUTPUT:
                if (this._test_output_file != "")
                    this._test_output_file.Write(output . "`n")
            Default:
                this.Write(output)                
        }
    }
    Write(output, terminator:="`n") {
        if (A_Args[1] == "test-vs") {
            OutputDebug, % output . terminator
        } else {
            stdout.Write(output . terminator)
            stdout.Read(0)
        }
    }
    Prompt() {
        if (this._mode==TEST_RECORDING)
            this.Stop()
        this.Write("-----`n> ", "")
        command := StrSplit( RTrim(stdin.ReadLine(), "`n"), " ")
        Switch command[1] {
            Case "record":
                this.Record()
            Case "stop":
                this.Stop()
            Default:
                
        }
    }
}

global test := New TestingClass()
