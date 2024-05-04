; Hints preferences and object
global HINT_OFF     := 1
    , HINT_RELAXED  := 2
    , HINT_NORMAL   := 4
    , HINT_ALWAYS   := 8
    , HINT_OSD      := 16
    , HINT_TOOLTIP  := 32
    , HINT_SCORE    := 64
global GOLDEN_RATIO := 1.618
global DELAY_AT_START := 2000

hint_delay := new clsHintTiming
global hint_UI := new clsHintUI(app_settings)
global score := new clsGamification

Class clsHintTiming {
    ; private variables
    _delay := DELAY_AT_START   ; this varies based on the hint frequency and hints shown
    _next_tick := A_TickCount  ; stores tick time when next hint is allowed
    ; public functions
    HasElapsed() {
        if (settings.hints & HINT_ALWAYS || A_TickCount > this._next_tick)
            return True
        else
            return False
    }
    Extend() {
        if (settings.hints & HINT_ALWAYS) {
            return
        }
        exponent := settings.hints & HINT_NORMAL ? 1 : 2
        this._delay := Round( this._delay * ( GOLDEN_RATIO ** exponent ) )
        this._next_tick := A_TickCount + this._delay
    }
    Shorten() {
        if (settings.hints & HINT_ALWAYS)
            Return
        if (settings.hints & HINT_NORMAL)
            this.Reset()
        else
            this._delay := Round( this._delay / 3 )
    }
    Reset() {
        this._delay := DELAY_AT_START
        this._next_tick := A_TickCount + this._delay
    }
}

;; Shortcut Hint UI
; -------------------

Class clsHintUI {
    hint_settings := { hints:           HINT_NORMAL | HINT_OSD | HINT_SCORE
                    , hint_offset_x:    0
                    , hint_offset_y:    0
                    , hint_size:        32
                    , hint_color:       "1CA6BF" }
    DEFAULT_TRANSPARENCY := 150
    UI := {}
    lines := []
    transparency := 0
    ; fallback coordinates if multimonitor detection fails
    pos_x := 0
    pos_y := 0
    _transparent_color := 0
    hide_OSD_fn := ObjBindMethod(this, "_HideOSD")

    transparent_color[] {
        get {
            return this._transparent_color
        }
    }
    SetTransparentColor(source_color) {
        Loop 3 {
            component := "0x" . SubStr(source_color, 2 * A_Index - 1, 2)
            component := component > 0x7f ? component - 1 : component + 1
            new_color .= Format("{:02x}", component)
        }
        this._transparent_color := new_color
    }

    __New(app_settings) {
        For key, value in this.hint_settings {
            app_settings.Register(key, value)
        }
    }

    Build() {
        hint_color := settings.hint_color
        this.SetTransparentColor(hint_color)
        this.UI := new clsUI("", "+LastFound +AlwaysOnTop -Caption +ToolWindow") ; +ToolWindow avoids a taskbar button and an alt-tab menu item.
        this.UI.Margin( Round(settings.hint_size/3), Round(settings.hint_size/3))
        this.UI.Color(this.transparent_color)
        this.UI.Font("s" . settings.hint_size . " c" . hint_color, "Consolas")
        ; auto-size the window
        Loop 3 {
            this.lines[A_Index] := this.UI.Add("Text", "Center", "WWWWWWWWWWWWWWWWWWWWW")
        }
        this.UI.Show("NoActivate Center")
        this.UI.SetTransparency(this.transparent_color, 1)
        ; Get and store position of the window in case multiple monitor detection positioning fails
        local_handle := this.UI._handle
        WinGetPos local_pos_x, local_pos_y, , , ahk_id %local_handle%
        this.pos_x := local_pos_x + settings.hint_offset_x
        this.pos_y := local_pos_y + settings.hint_offset_y
        this.UI.Hide()
    }

    Reset() {
        global hint_delay
        hint_delay.Reset()
        this.UI.Destroy()
        this.Build()
    }

    ShowHint(line1 := "", line2 := "", line3  := "") {
        global hint_delay
        if (A_Args[1] == "dev") {
            if (test.mode > TEST_STANDBY) {
                test.Log("*Hint*")
            }
            if (test.mode == TEST_RUNNING) {
                return
            }
        }
        hint_delay.Extend()
        if (settings.hints & HINT_TOOLTIP) {
            this._GetCaret(x, y, , h)
            ToolTip % " " . ReplaceWithVariants(line2) . " `n " . ReplaceWithVariants(line3) . " "
                    , x-1.5*h+settings.hint_offset_x, y+1.5*h+settings.hint_offset_y
            hide_tooltip_fn := ObjBindMethod(this, "_HideTooltip")
            SetTimer, %hide_tooltip_fn%, -1800   ; hides the tooltip
        } else {
            this.ShowOnOSD(line1, ReplaceWithVariants(line2, true), ReplaceWithVariants(line3))
        }
    }

    ;@ahk-neko-ignore-fn 1 line; at 5/2/2024, 10:07:04 AM ; param is assigned but never used.
    ShowOnOSD(line1 := "", line2 := "", line3  := "") {
        this.fading := false
        this.transparency := this.DEFAULT_TRANSPARENCY
        Loop, 3 {
            this.lines[A_Index].value := line%A_Index%
        }
        this.UI.Show("Hide NoActivate")
        coord := this._GetMonitorCenterForWindow()
        current_pos_x := coord.x ? coord.x + settings.hint_offset_x : this.pos_x
        current_pos_y := coord.y ? coord.y + settings.hint_offset_y : this.pos_y
        this.UI.Show("NoActivate X" . current_pos_x . "Y" . current_pos_y)
        this.UI.SetTransparency(this.transparent_color, this.transparency)
        hide_osd_fn := this.hide_OSD_fn
        SetTimer, %hide_osd_fn%, -1900
    }

    _HideOSD() {
        this.fading := true
        if (this.fading && this.transparency > 1) {
            this.transparency -= 10
            this.UI.SetTransparency(this.transparent_color, this.transparency)
            hide_osd_fn := this.hide_OSD_fn
            SetTimer, %hide_osd_fn%, -100
            return
        }
        this.UI.Hide()
    }

    _HideTooltip() {
        Tooltip
    }

    ; The following function for getting caret position more reliably is from a post by plankoe at https://www.reddit.com/r/AutoHotkey/comments/ysuawq/get_the_caret_location_in_any_program/
    _GetCaret(ByRef X:="", ByRef Y:="", ByRef W:="", ByRef H:="") {
        ; UIA caret
        static IUIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
        ; GetFocusedElement
        DllCall(NumGet(NumGet(IUIA+0)+8*A_PtrSize), "ptr", IUIA, "ptr*", FocusedEl:=0)
        ; GetCurrentPattern. TextPatternElement2 = 10024
        DllCall(NumGet(NumGet(FocusedEl+0)+16*A_PtrSize), "ptr", FocusedEl, "int", 10024, "ptr*", patternObject:=0), ObjRelease(FocusedEl)
        if patternObject {
            ; GetCaretRange
            DllCall(NumGet(NumGet(patternObject+0)+10*A_PtrSize), "ptr", patternObject, "int*", 1, "ptr*", caretRange:=0), ObjRelease(patternObject)
            ; GetBoundingRectangles
            DllCall(NumGet(NumGet(caretRange+0)+10*A_PtrSize), "ptr", caretRange, "ptr*", boundingRects:=0), ObjRelease(caretRange)
            ; VT_ARRAY = 0x20000 | VT_R8 = 5 (64-bit floating-point number)
            Rect := ComObject(0x2005, boundingRects)
            if (Rect.MaxIndex() = 3) {
                X:=Round(Rect[0]), Y:=Round(Rect[1]), W:=Round(Rect[2]), H:=Round(Rect[3])
                return
            }
        }
        ; Acc caret
        static _ := DllCall("LoadLibrary", "Str","oleacc", "Ptr")
        idObject := 0xFFFFFFF8 ; OBJID_CARET
        if DllCall("oleacc\AccessibleObjectFromWindow", "Ptr", WinExist("A"), "UInt", idObject&=0xFFFFFFFF, "Ptr", -VarSetCapacity(IID,16)+NumPut(idObject==0xFFFFFFF0?0x46000000000000C0:0x719B3800AA000C81,NumPut(idObject==0xFFFFFFF0?0x0000000000020400:0x11CF3C3D618736E0,IID,"Int64"),"Int64"), "Ptr*", pacc:=0)=0 {
            oAcc := ComObjEnwrap(9,pacc,1)
            oAcc.accLocation(ComObj(0x4003,&_x:=0), ComObj(0x4003,&_y:=0), ComObj(0x4003,&_w:=0), ComObj(0x4003,&_h:=0), 0)
            X:=NumGet(_x,0,"int"), Y:=NumGet(_y,0,"int"), W:=NumGet(_w,0,"int"), H:=NumGet(_h,0,"int")
            if (X | Y) != 0
                return
        }
        ; default caret
        CoordMode Caret, Screen
        X := A_CaretX
        Y := A_CaretY
        W := 4
        H := 20
    }
    _GetMonitorCenterForWindow() {
        ; Uses code for getting monitor info by "kon" from https://www.autohotkey.com/boards/viewtopic.php?t=15501
        ;@ahk-neko-ignore-fn 1 line; at 4/30/2024, 11:46:07 AM ; var is assigned but never used.
        window_Handle := WinExist("A")
        ;@ahk-neko-ignore-fn 1 line; at 4/30/2024, 11:46:26 AM ; var is assigned but never used.
        OSD_handle := this.UI._handle
        VarSetCapacity(monitor_info, 40), NumPut(40, monitor_info)
        ;@ahk-neko-ignore-fn 1 line; at 4/22/2024, 9:51:25 AM ; var is assigned but never used.
        if ((monitorHandle := DllCall("MonitorFromWindow", "Ptr", window_Handle, "UInt", 1)) 
            && DllCall("GetMonitorInfo", "Ptr", monitorHandle, "Ptr", &monitor_info)) {
            monitor_left   := NumGet(monitor_info,  4, "Int")
            monitor_top    := NumGet(monitor_info,  8, "Int")
            monitor_right  := NumGet(monitor_info, 12, "Int")
            monitor_bottom := NumGet(monitor_info, 16, "Int")
            ; From code for multiple monitors by DigiDon from https://www.autohotkey.com/boards/viewtopic.php?t=31716 
            VarSetCapacity(rc, 16)
            DllCall("GetClientRect", "uint", OSD_handle, "uint", &rc)
            window_width := NumGet(rc, 8, "int")
            window_height := NumGet(rc, 12, "int")
            pos_x := (( monitor_right - monitor_left - window_width ) / 2) + monitor_left
            pos_y := (( monitor_bottom - monitor_top - window_height ) / 2) + monitor_top
        } else {
            pos_x := 0
            pos_y := 0
        }
        return {x: pos_x, y: pos_y}
    }
}

Class clsGamification {
    _buffer := []
    ENTRY_MANUAL       := 0
    ENTRY_CHORD        := 1
    ENTRY_SHORTHAND    := 2
    score_gap := 0

    class Results {
        chord := 0
        shorthand := 0
        maximum := 0

        __New(_chord, _shorthand, _maximum) {
            this.chord := _chord
            this.shorthand := _shorthand
            this.maximum := _maximum
        }
    }

    /** 
    * Tracks the type of completed typing in the _buffer.
    *
    *   used_shortcut   one of ENTRY_  constants
    */
    Score(entry_type) {
        if ( settings.hints & HINT_OFF || ! (settings.hints & HINT_SCORE) ) {
            return
        }
        count_chords := settings.mode & MODE_CHORDS_ENABLED 
        count_shorthands := settings.mode & MODE_SHORTHANDS_ENABLED

        if ( ! count_chords && ! count_shorthands ) {
            return
        }

        this.score_gap++
        gap_frequency := 7 * (3 - OrdinalOfHintFrequency())
        total := this._buffer.Length()

        if (total >= 100) {
            this._buffer.RemoveAt(1)
        } else {
            total++
        }
        ; save a basic entry; percentage is calculated and added later if it was a shortcut, otherwise, it's irrelevant
        entry := {type: entry_type, percentage: 0}
        this._buffer.Push(entry)

        if (entry_type == this.ENTRY_MANUAL || total < 7 || total < gap_frequency) {
            return false
        }
        results := this._GetScores(count_chords, count_shorthands)
        this._buffer[total].percentage := results.chord + results.shorthand
        is_maximum := results.chord + results.shorthand > results.maximum ? true : false 

        if ( results && (settings.hints & HINT_ALWAYS || is_maximum || this.score_gap > gap_frequency) ) {
            this.score_gap := 0
            this.ShowEfficiency(results, is_maximum)
        }
    }

    _GetScores(count_chords := true, count_shorthands := true) {
        chord_count := 0
        shorthand_count := 0
        max_percentage := 0

        for _, value in this._buffer {
            if ( count_chords && value.type == this.ENTRY_CHORD ) {
                chord_count++
            }
            if ( count_shorthands && value.type == this.ENTRY_SHORTHAND ) {
                shorthand_count++
            }
            if ( value.percentage > max_percentage) {
                max_percentage := value.percentage
            }
        }
        total := this._buffer.Length()
        chord_percentage := 100 * chord_count // total
        shorthand_percentage := 100 * shorthand_count // total
        results := New this.Results(chord_percentage, shorthand_percentage, max_percentage)
        return results
    }

    ShowEfficiency(results, is_record := false) {
        global hint_UI
        PROGRESS_BAR_LENGTH := 30
        CHORD_BLOCK := "█"
        SHORTHAND_BLOCK := "▓"
        EMPTY_BLOCK := "░"
        scaling_ratio := 100 / PROGRESS_BAR_LENGTH

        if (is_record) {
            record_text := this._buffer.Length() > 99 ? "New recent best:" : "New best result:"
        } else {
            record_text := ""
        }
        chord_blocks := results.chord // scaling_ratio
        shorthand_blocks := results.shorthand // scaling_ratio
        empty_blocks := PROGRESS_BAR_LENGTH - chord_blocks - shorthand_blocks
        progress_bar := this._RepeatCharacter(CHORD_BLOCK, chord_blocks)
                        . this._RepeatCharacter(SHORTHAND_BLOCK, shorthand_blocks)
                        . this._RepeatCharacter(EMPTY_BLOCK, empty_blocks)
        hint_UI.ShowOnOSD(record_text, progress_bar, results.chord + results.shorthand . "%")
    }

    _RepeatCharacter(char :="", times := 1) {
        result := ""
        Loop, %times% {
            result .= char
        }
        return result
    }
}