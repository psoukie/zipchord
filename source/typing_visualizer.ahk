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
global UI_monitor_slot1, UI_monitor_slot2, UI_monitor_slot3, UI_monitor_slot4, UI_monitor_slot5
    , UI_monitor_slot6, UI_monitor_slot7, UI_monitor_slot8, UI_monitor_slot9, UI_monitor_slot10
global UI_monitor_duration1, UI_monitor_duration2, UI_monitor_duration3, UI_monitor_duration4, UI_monitor_duration5
    , UI_monitor_duration6, UI_monitor_duration7, UI_monitor_duration8, UI_monitor_duration9, UI_monitor_duration10
global UI_monitor_overlap1, UI_monitor_overlap2, UI_monitor_overlap3, UI_monitor_overlap4, UI_monitor_overlap5
    , UI_monitor_overlap6, UI_monitor_overlap7, UI_monitor_overlap8, UI_monitor_overlap9, UI_monitor_overlap10

Class KeyMonitorClass {
    _slots := {}
    _keys := {}
    _statuses := {}
    _starts := {}
    _ends := {}
    _overlaps := {}
    _next := 1
    _last := 10
    _mode := 0  ; 0 - off, 1 - on, 2 - on with details
    _new_line := false
    __New(details := false) {
        this._mode := details ? 2 : 1
        Gui, UI_monitor:New, , % "ZipChord Key Visualization"
        Gui, Margin, 20 0
        Gui, Color, ffffff
        Loop 10
        {
            posx := (A_Index - 1) * 40
            Gui, Font, s32 bold, Consolas
            Gui, Add, Text, vUI_monitor_slot%A_Index% xm+%posx% ym-14 Center, % "W"
            if (details) {
                Gui, Font, s12, Segoe UI
                Gui, Add, Text, vUI_monitor_duration%A_Index% xm+%posx% ym+70 Center, % "99999"
                posx -= 20
                Gui, Add, Text, vUI_monitor_overlap%A_Index% xm+%posx% ym+100 Center, % "9999"
            }
        }
        Gui, Show, h80
        this._UpdateUI()
        SetTimer Darken, 100
    }
    IsOn() {
        return (this._mode > 0) ? 1 : 0
    }
    Pressed(key){
        if (this._new_line && this._next != 2) {
            this._next := 1
            this._new_line := false
        }
        this._keys[key] := this._next
        this._statuses[this._next] := 255 ; currently pressed
        this._slots[this._next] := key
        if (this._mode == 2)
            this._starts[this._next] := A_TickCount
        if (++this._next == 11)
            this._next := 1
        this._UpdateUI()
    }
    Lifted(key){
        slot := this._keys[key]
        this._ends[slot] := A_TickCount
        this._statuses[slot] := 120
        if (this._mode == 2) {
            this._overlaps[slot] := 0
            if (this._statuses[this._last] == 255)
                this._overlaps[slot] := this._ends[slot] - this._starts[this._last]
            if (this._starts[slot] < this._ends[this._last])
                this._overlaps[slot] := this._ends[this._last] - this._starts[slot] 
            this._last := this._next
            if (++this._last == 11) {
                this._last := 1
            }
        }
        this._UpdateUI()
    }
    NewLine() {
        this._new_line := true
    }
    _UpdateUI(refresh := false){
        Gui, UI_monitor:Default
        Loop 10
        {
            val := this._statuses[%A_Index%]
            if ( (! refresh) && ( val == 255 ||  val == 120) || (refresh && val != 120 && val != 255) ) {
                GuiControl, UI_monitor:, UI_monitor_slot%A_Index%, % ReplaceWithVariants(this._slots[A_Index], true)
                if (this._statuses[A_Index] == 255) {
                    new_color := "Red"    
                } else {
                    new_color := Format("{:02x}", 255 - this._statuses[A_Index])
                    new_color .= new_color . new_color
                }
                GuiControl, +c%new_color% +Redraw, UI_monitor_slot%A_Index%
                if (this._mode == 2) {
                    if (this._statuses[A_Index] == 255) {
                        GuiControl, UI_monitor:, UI_monitor_duration%A_Index%, % "P"
                        GuiControl, UI_monitor:, UI_monitor_overlap%A_Index%, % " "
                    } else {
                        GuiControl, UI_monitor:, UI_monitor_duration%A_Index%, % this._ends[A_Index] - this._starts[A_Index]
                        GuiControl, UI_monitor:, UI_monitor_overlap%A_Index%, % this._overlaps[A_Index]
                    }
                }
            }
        }
    }
    _Darken() {
        Loop 10
        {
            if (this._statuses[A_Index] && this._statuses[A_Index] != 255)
                this._statuses[A_Index] -= 20
        }
        this._UpdateUI(true)
    }
}

key_monitor := New KeyMonitorClass

Darken() {
    key_monitor._Darken()
}