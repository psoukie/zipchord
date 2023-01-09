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

; Global variables that can be hooked up to AHK Gui
global UI_monitor_slot1
    , UI_monitor_slot2
    , UI_monitor_slot3
    , UI_monitor_slot4
    , UI_monitor_slot5

Class KeyMonitorClass {
    _slots := {}
    _keys := {}
    _next_available := 1
    _used := 0
    __New() {
        UI_Monitor_Build()
    }
    Pressed(key){
        this._slots[this._next_available] := key
        this._keys[key] := this._next_available
        this._next_available++
        this._used++
        this._UpdateUI()
    }
    Lifted(key){
        this._slots[this._keys[key]] := ""
        if (--this._used == 0)
        this._next_available := 1
        this._UpdateUI()
    }
    _UpdateUI(){
        Gui, UI_monitor:Default
        Loop 5
        {
            output .= this._slots[A_Index] . " "
            GuiControl, UI_monitor_slot%slot%, key
        }
        OutputDebug, % output . "`n"
    }
}

key_monitor := New KeyMonitorClass

UI_Monitor_Build() {
        Gui, UI_locale_window:New, +AlwaysOnTop +ToolWindow, % "ZipChord Key Monitor"
        Gui, Font, s10, Consolas
        Loop 5
        {
            Gui, Add, Text,  vUI_monitor_slot%A_Index% Center, % "W"
        }
        Gui, Show
}