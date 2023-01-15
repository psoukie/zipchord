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
    , TEST_ON := 1
    , TEST_RUN := 2
    , TEST_RECORD := 3

global UI_Test_btnRecord

Class TestingClass {
    _test_input_file := ""
    _test_output_file := ""
    _mode := TEST_OFF
    mode {
        get { 
            return this._mode 
        }
    }
    __New() {
        if (A_Args[1] == "test-vs")
            this._mode := TEST_ON
        Gui, UI_Test:New, , % "ZipChord Testing"
        Gui, Margin, 15 15
        Gui, Add, Button, , % "Record"
        Gui, Add, Button, , % "Stop"
        fn_ref := ObjBindMethod(this, "Record")
        GuiControl +g,Button1, % fn_ref
        fn_ref := ObjBindMethod(this, "Stop")
        GuiControl +g,Button2, % fn_ref
        Gui, Show
    }
    Record() {
        this._mode := TEST_RECORD
        FileDelete, "test_recording.txt"
        this._test_output_file := FileOpen("test_recording.txt", "w")
        this.Write("This is the start of the recording")
    }
    Run() {
        this.Write("Playing back recording.")
    }
    Write(output) {
        if (A_Args[1] == "test-vs")
            OutputDebug, % output "`n"
        if (this._test_output_file != "")
            this._test_output_file.Write(output "`n")
    }
    Stop() {
        this._mode := TEST_ON
        if (this._test_output_file != "") {
            this._test_output_file.Close()
            this._test_output_file := ""
            Run % "test_recording.txt"
        }
    }
}

testing := New TestingClass
