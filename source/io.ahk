/*
This file is part of ZipChord.
Copyright (c) 2023-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

; ; Future refactor:
; Class IO_Key_Cls {
;     key := 0
;     with_shift := false
;     start := 0
;     end := 0
; }

; io_keys := []          ; IO_Key entries
; io_keys_index := -1    ; 'pointer' to current location in io_keys, -1 means not set

; Class IO_Token_Cls {
;     attributes := 0
; }

; io_tokens := []        ; IO_Token entries
; io_tokens_index := -1  ; 'pointer' to current location in io_tokens, -1 means not set


io := new clsIOrepresentation

global io_events := []
global io_events_index := {}         ; indexes _buffer:  _events_index[{key}] points to that key's record in _buffer
global io_events_classified := true

Class clsIOrepresentation {
    static NONE := 0
         , WITH_SHIFT := 1
         , SMART_SPACE_AFTER := 2
         , IS_PUNCTUATION := 4
         , WAS_EXPANDED := 8
         , WAS_CAPITALIZED := 16
         , IS_PREFIX := 32
         , IS_MANUAL_SPACE := 64
         , IS_CHORD := 128
         , IS_ENTER := 256
         , IS_INTERRUPT := 512
         , IS_NUMERAL := 1024
         , CAPITALIZES_NEXT := 2048
    ; affixes constants
    static AFFIX_NONE := 0 ; no prefix or suffix
        , AFFIX_PREFIX := 1 ; expansion is a prefix
        , AFFIX_SUFFIX := 2 ; expansion is a suffix

    Class clsChunk {
        key := 0
        with_shift := false
        start := 0
        end := 0
        input := ""
        output := ""
        attributes := 0
    }

    pre_shifted := false
    _sequence := []

    length [] {
        get {
            return this._sequence.Length()
        }
    }
    _expansion_in_last_get := 0
    expansion_in_last_get [] {
        get {
            return this._expansion_in_last_get 
        }
    }

    output_buffer := ""  ; stores what will be sent as simulated keystrokes
    
    IO_Events_Reset() {
        OutputDebug % "`nEMPTYING EVENTS"
        io_events := []
        io_events_index := {}
        io_events_classified := true
    }

    Input(hotkey, timestamp) {
        ev := new this.clsChunk
        is_key_down := true
        ; io_key := new IO_Key_Cls
        
        ; translate the hotkey string
        ev.key := SubStr(hotkey, 2)
        if (SubStr(ev.key, 1, 1) == "+") {
            ev.with_shift := true
            ev.key := SubStr(ev.key, 2)
        } else {
            ev.with_shift := False
        }

        ev.key := StrReplace(ev.key, "Space", " ")

        if (SubStr(ev.key, -2) == " Up") {
            is_key_down := false
            ev.key := SubStr(ev.key, 1, StrLen(ev.key)-3)
        }

        ev.key := (StrLen(ev.key) > 1) ? "{" . ev.key . "}" : ev.key

        if (is_key_down) {
            ; Process a key down event
            ev.start := timestamp
            this.ProcessKeyDown(ev)
            io_events.Push(ev)
            io_events_classified := false
            io_events_index[ev.key] := io_events.Length()
        } else {
            ; Process a key up event: look up the event, record lift time, and classify
            if !(io_events_index.HasKey(ev.key)) {
                return
            }
            index := io_events_index[ev.key]
            io_events_index.Delete(ev.key)
            if (!index || index > io_events.Length()) {
                return
            }
            io_events[index].end := timestamp
            this._Classify(timestamp, index)
            if (io_events_index.Length() == 0 && io_events.Length() != 0) {
                this.IO_Events_Reset()
            }
        }
        this.DebugSequence()
    }
    
    ProcessKeyDown(ByRef ev) {
        entry := "" . ev.key
        ev.input := entry
        if (ev.with_shift) {
            ev.attributes |= this.WITH_SHIFT
            ev.output := str.ToAscii(entry, ["Shift"])
        } else {
            ev.output := entry
        }
        if ( !ev.with_shift && InStr(keys.punctuation_plain, entry) )
                || ( ev.with_shift && InStr(keys.punctuation_shift, entry) ) {
            ev.attributes |= this.IS_PUNCTUATION
        }
        if (entry == " ") {
            ev.attributes |= this.IS_MANUAL_SPACE
        }
        if (!ev.with_shift && InStr("0123456789⓪①②③④⑤⑥⑦⑧⑨", entry)) {
            ev.attributes |= this.IS_NUMERAL
        }
        if (this.pre_shifted) {
            ev.attributes |= this.WAS_CAPITALIZED
            this.pre_shifted := false
        }
    }

    _Shift_IO_Keys_Window(count) {
        io_events.RemoveAt(1, count)
        
        for key, index in io_events_index {
            if (index <= count) {
                OutputDebug % "`nDeleting index for " . key
                io_events_index.Delete(key)
                continue
            }
            OutputDebug % "`n shifting " . key . " from " index 
            io_events_index[key] := index - count
            OutputDebug % " to " . io_events_index[key] 
        }
    }

    Add_Keys_To_Sequence(count) {
        Loop % count {
            this._sequence.Push(io_events[A_Index])
        }
        if (count == io_events.Length()) {
            this.IO_Events_Reset()
        } else {
            this._Shift_IO_Keys_Window(count)           
        }
    }

    ; Transform key presses into a chord and add to sequence
    Add_Chord_To_Sequence() {
        ev := io_events[1]
        
        ev_length := io_events.Length() - 1
        Loop, % ev_length
        {
            next_ev := io_events[A_Index + 1] 
            ev.key .= next_ev.key     ; store original key sequence
            ev.input .= next_ev.input 
            ev.output .= next_ev.output
            ev.attributes |= next_ev.attributes
        }

        ; Set as chord and clear punctuation and manual space attributes 
        ev.attributes := ev.attributes & ~this.IS_PUNCTUATION & ~this.IS_MANUAL_SPACE | this.IS_CHORD
             
        ;For chords, if Shift is allowed as a separate key in chord key, we add it as part of the entry if it was pressed.
        if ( (settings.chording & CHORD_ALLOW_SHIFT) && (ev.attributes & this.WITH_SHIFT) ) {
            ev.input := "+" . ev.input
            ev.attributes := ev.attributes & ~this.WITH_SHIFT
        }
    
        ; Sort to allow matching against chord dictionaries        
        if (dll.available) {
            ev.input := dll.NormalizeChord(ev.input)
        } else {
            ev.input := str.Arrange(ev.input)
        }

        this._sequence.Push(ev)
        this.IO_Events_Reset()
    }

    _ClassifyByDuration(end) {
        ; get and compare against the overlap of the second key in the chord (regardless of chord length)
        start := io_events[2].start
        if (end - start > settings.input_delay) {
            this.Add_Chord_To_Sequence()
        } else {
            this.Add_Keys_To_Sequence(io_events.Length())
        }
    }

    _ClassifyByPercentage(end, lifted_index) {
        ; test the full buffer then drop earlier keys
        last_start := io_events[io_events.Length()].start
        common_overlap := end - last_start
        
        start_iter := 1    ; because we will convert any prefix keys into key events and shift if not matched
        end_iter := Min(lifted_index, io_events.Length() - 1)
        iters := end_iter - start_iter + 1
        Loop % iters {
            ev := io_events[A_Index]
            candidate_span := end - ev.start
            
            if (candidate_span <= 0) {
                continue
            }
            if (common_overlap / candidate_span >= settings.input_overlap / 100) {
                if (A_Index > 1) {
                    this.Add_Keys_To_Sequence(A_Index - 1)
                }
                this.Add_Chord_To_Sequence()
                return
            }
        }
        this.Add_Keys_To_Sequence(end_iter)
    }

    _Classify(end, index) {
        if (io_events_classified) {
            return
        }
        io_events_classified := true
        if (io_events.Length() == 1) {
            ; process simple key press
            this.Add_Keys_To_Sequence(1)
            this.RunModules()
            return
        }
    
        ; two or more keys were pressed as a potential chord
        if (settings.chording & CHORD_BY_OVERLAP) {
            this._ClassifyByPercentage(end, index)
            if (io_events.Length() == 0) {
                this.RunModules()
            }
        } else {
            this._ClassifyByDuration(end)    
            this.RunModules()
        }
        
    }

    PreShift() {
        this.pre_shifted := !this.pre_shifted
        ; and we cheat to allow shorthands:
        if (this.TestChunkAttributes(this.length, this.IS_INTERRUPT)) {
            this.ClearChunkAttributes(this.length, this.IS_INTERRUPT)
            this.SetChunkAttributes(this.length, this.IS_MANUAL_SPACE)
        }
    }
    __New() {
        this.ClearSequence("*Interrupt*")
    }

; TK - needs to go into IO
; this.CapitalizeTypingAsNeeded(entry, ev.attributes)
; this.RemoveSmartSpaceAsNeeded(ev.attributes)
; now, the slightly chaotic immediate mode allowing shorthands triggered as soon as they are completed:
; if (settings.chording & CHORD_IMMEDIATE_SHORTHANDS) {
;     this.TryImmediateShorthand()
; }

    AugmentedAdd(entry, with_shift) {
        entry := "" . entry
        chunk := new this.clsChunk
        chunk.input := entry
        if (with_shift) {
            chunk.attributes |= this.WITH_SHIFT
            chunk.output := str.ToAscii(entry, ["Shift"])
        } else {
            chunk.output := entry
        }
        if ( !with_shift && InStr(keys.punctuation_plain, entry) )
                || ( with_shift && InStr(keys.punctuation_shift, entry) ) {
            chunk.attributes |= this.IS_PUNCTUATION
        }
        if (entry == " ") {
            chunk.attributes |= this.IS_MANUAL_SPACE
        }
        if (!with_shift && InStr("0123456789⓪①②③④⑤⑥⑦⑧⑨", entry)) {
            chunk.attributes |= this.IS_NUMERAL
        }
        this._sequence.Push(chunk)
    }

    Add(entry, with_shift, chunk) {
        entry := "" . entry
        chunk.input := entry
        if (with_shift) {
            chunk.attributes |= this.WITH_SHIFT
            chunk.output := str.ToAscii(entry, ["Shift"])
        } else {
            chunk.output := entry
        }
        if ( !with_shift && InStr(keys.punctuation_plain, entry) )
                || ( with_shift && InStr(keys.punctuation_shift, entry) ) {
            chunk.attributes |= this.IS_PUNCTUATION
        }
        if (entry == " ") {
            chunk.attributes |= this.IS_MANUAL_SPACE
        }
        if (!with_shift && InStr("0123456789⓪①②③④⑤⑥⑦⑧⑨", entry)) {
            chunk.attributes |= this.IS_NUMERAL
        }
        if (this.pre_shifted) {
            chunk.attributes |= this.WAS_CAPITALIZED
            this.pre_shifted := false
        }
        this.CapitalizeTypingAsNeeded(entry, chunk.attributes)
        this.RemoveSmartSpaceAsNeeded(chunk.attributes)
        ; now, the slightly chaotic immediate mode allowing shorthands triggered as soon as they are completed:
        if (settings.chording & CHORD_IMMEDIATE_SHORTHANDS) {
            this.TryImmediateShorthand()
        }
    }

    Combine(start, end) {
        sequence := this._sequence
        if (start > sequence.Length() || end > sequence.Length()) {
            MsgBox, , % "ZipChord", "IO Representation error: Requested combining chunks that exceed the length of _sequence."
            Return true
        }
        following := start + 1
        count := end - start
        Loop, %count%
        {
            sequence[start].input .= "|" . sequence[following].input 
            sequence[start].output .= sequence[following].output
            sequence.RemoveAt(following)
        }
    }

    ClearSequence(type := "") {
        this.IO_Events_Reset()
        this._sequence := []

        new_chunk := new this.clsChunk
        if (type=="~Enter") {
            new_chunk.attributes := this.IS_ENTER
        }
        if (type=="*Interrupt*") {
            new_chunk.attributes := this.IS_INTERRUPT
        }
        if (visualizer.IsOn()) {
            visualizer.NewLine()
        }
        this._sequence.Push(new_chunk)
    }
    Replace(new_output, start := 1, end := 0) {
        if (! end) {
            end := this.length
        }
        if (start != end) {
            this.Combine(start, end)
        }
        old_output := this._sequence[start].output
        this._sequence[start].output := new_output
        this._ReplaceOutput(old_output, new_output, start)
    }

    SetChunkAttributes(chunk_id, bitmask, set := true) {
        if (set) {
            this._sequence[chunk_id].attributes |= bitmask
        } else {
            this._sequence[chunk_id].attributes &= ~bitmask
        }
    }
    ClearChunkAttributes(chunk_id, bitmask) {
        this.SetChunkAttributes(chunk_id, bitmask, false)
    }
    TestChunkAttributes(chunk_id, bitmask) {
        ; purposefully returns true if one of the bitmask conditions are true (therefore, not comparing to bitmask)
        if (chunk_id > this.length || chunk_id < 1) {
            return false
        }
        return (this._sequence[chunk_id].attributes & bitmask)
    }

    GetChunk(chunk_id) {
        return this._sequence[chunk_id]
    }
    GetInput(start := 1, end := 0) {
        return this._Get(start, end)
    }
    GetOutput(start := 1, end := 0) {
        return this._Get(start, end, true)
    }
    _Get(start := 1, end := 0, get_output := false) {
        this._expansion_in_last_get := false
        sequence := this._sequence
        what := get_output ? "output" : "input" 
        separator := get_output ? "" : "|"
        if (! end) {
            end := this.length 
        }
        if (start > sequence.Length() || end > sequence.Length()) {
            MsgBox, , % "ZipChord", "IO Representation error: Requested getting chunks that exceed the length of _sequence."
            Return true
        }
        count := end - start + 1
        i := start
        Loop, %count%
        {
            if (sequence[i].attributes & this.WAS_EXPANDED) {
                this._expansion_in_last_get := true
            }
            representation .= separator . sequence[i++][what]
        }
        Return SubStr(representation, StrLen(separator)+1)
    }
    _ReplaceOutput(old_output, new_output, start) {
        if (start != this.length) {
            backup_content := this.GetOutput(start+1)
        }
        adj := StrLen(old_output . backup_content)
        if (adj == 1) { 
            this.output_buffer .= "{Backspace}"
        } else {
            this.output_buffer .= "{Backspace " . adj . "}"
        }
        if ( new_output . backup_content != "") {
            this.output_buffer .= new_output . backup_content
        }
    }

    ; Delay output by defined delay
    _DelayOutput() {
        if (settings.output_delay) {
            Sleep settings.output_delay
        }
    }
    Backspace(with_ctrl := false) {
        if ( this.length < 2 || this.TestChunkAttributes(this.length, this.WAS_EXPANDED) || with_ctrl ) {
            this.ClearSequence("*Interrupt*")
            return
        }
        if ( this.TestChunkAttributes(this.length, this.IS_CHORD) ) {
            chunk := this.GetChunk(this.length)
            chunk.input := "XX" ; so the chunk cannot be matched to any chord later
            chunk.output := SubStr(chunk.output, 1, StrLen(chunk.output) - 1)
            if (StrLen(chunk.output) == 1) {
                chunk.attributes &= ~this.IS_CHORD
            }
            return
        }
        this._sequence.RemoveAt(this.length)
    }

    ; Below are the functions that were first attempt at modules.
    ; When I recreate modules, it should be pure functions only.

    RunModules() {
        if (this.ChordModule()) {
            return
        }
        if ( this.TestChunkAttributes(this.length, this.IS_CHORD) ) {
            if (this._RemoveRawChord()) {
                this.OutputKeys()
                return
            }
            this._FixLastChunk()
        }
        if (this.DeDoubleSpace()) {
            return
        }
        if ! ( this.TestChunkAttributes(this.length, this.IS_MANUAL_SPACE | this.IS_PUNCTUATION) ) {
            return
        }
        if (this.DoShorthandsAndHints()) {
            score.Score(score.ENTRY_SHORTHAND)
        } else if ! ( this.TestChunkAttributes(this.length - 1, this.IS_MANUAL_SPACE | this.IS_PUNCTUATION) ) {
            score.Score(score.ENTRY_MANUAL)
        }
        this.AddSpaceAfterPunctuation()
        ; this.ClearSequence()
    }

    DoShorthandsAndHints() {
        loop_length := this.length - 1
        Loop %loop_length%
        {
            text := this.GetOutput(A_Index+1, this.length-1)
            if ( this.expansion_in_last_get || this._IsRestricted(A_Index) ) {
                continue
            }
            if ( this.ShorthandModule(text, A_Index+1) ) {
                return true
            }
            if ( this.HintModule(text, A_Index+1) ) {
                return false
            }
        }
    }

    CapitalizeTypingAsNeeded(character, attribs) {
        if ( settings.capitalization != CAP_ALL || (attribs & this.IS_PUNCTUATION)
                || (attribs & this.IS_MANUAL_SPACE) || (attribs & this.WITH_SHIFT) ) {
            return
        }
        if ( this._ShouldCapitalize() ) {
            upper_cased := RegExReplace(character, "(^.)", "$U1")
            this.Replace(upper_cased, this.length)
            this.OutputKeys()
            this.SetChunkAttributes(this.length, this.WAS_CAPITALIZED)
        }
    }

    RemoveSmartSpaceAsNeeded(attribs) {
        if ! (this.TestChunkAttributes(this.length-1, this.SMART_SPACE_AFTER)) {
            return
        }
        ; for punctuation that removes spaces
        if (attribs & this.IS_PUNCTUATION) {
            chunk := this.GetChunk(this.length)
            if ( (!(chunk.attributes & this.WITH_SHIFT) && InStr(keys.remove_space_plain, chunk.input))
                    || ((chunk.attributes & this.WITH_SHIFT) && InStr(keys.remove_space_shift, chunk.input)) ) {
                return this._RemoveSmartSpace()
            }
        }
        ; for manual_space-punctuation-numeral and numeral-punctuation-numeral
        if (attribs & this.IS_NUMERAL && this.TestChunkAttributes(this.length - 2, this.IS_PUNCTUATION)
                && this.TestChunkAttributes(this.length - 3, this.IS_NUMERAL | this.IS_MANUAL_SPACE | this.IS_ENTER)) {
            return this._RemoveSmartSpace()
        }
    }

    _RemoveSmartSpace() {
        this.Replace("", this.length - 1, this.length - 1)
        this.OutputKeys()
        this._sequence.RemoveAt(this.length - 1)
        return true
    }

    AddSpaceAfterPunctuation() {
        chunk := this.GetChunk(this.length)
        attribs := chunk.attributes
        if ( !(settings.spacing & SPACE_PUNCTUATION) || this.TestChunkAttributes(this.length - 1, this.IS_INTERRUPT) ) {
            return
        }
        if (( !(attribs & this.WITH_SHIFT) && InStr(keys.space_after_plain, chunk.input) )
                || (attribs & this.WITH_SHIFT) && InStr(keys.space_after_shift, chunk.input) ) {
            this._AddSmartSpace()
            this.OutputKeys()
        }
    }

    ; Remove a double space if the user types a space after punctuation smart space
    DeDoubleSpace() {
        if ( this.TestChunkAttributes(this.length - 1, this.SMART_SPACE_AFTER)
                && this.TestChunkAttributes(this.length, this.IS_MANUAL_SPACE) ) {
            this._sequence.RemoveAt(this.length - 1)
            this.output_buffer .= "{Backspace}"
            this.OutputKeys()
            return true
        }
        return false
    }

    ChordModule() {
        if (! (settings.mode & MODE_CHORDS_ENABLED)) {
            return false
        }
        count := this.length
        Loop %count%
        {
            candidate := this.GetInput(A_Index)
            if (StrLen(candidate) < 2) {
                return false
            }
            candidate := StrReplace(candidate, "||", "|")
            expanded := chords.LookUp(candidate)
            if (expanded) {
                ; check whether chord is used to complete typing of a shorthand
                if (this.TryImmediateShorthand(-1)) {
                    return this._ProcessChord(this.length, expanded) 
                }
                return this._ProcessChord(A_Index, expanded)
            }
        }
    }

    _ProcessChord(chunk_id, expanded) {
        global hint_delay
        mark_as_capitalized := false
        add_leading_space := true
        replace_offset := 0

        hint_delay.Shorten()

        ; capitalize the whole word on Caps Lock or the first character as needed
        if (GetKeyState("CapsLock", "T")) {
            expanded := Format("{:U}", expanded)
            mark_as_capitalized := true
        } else if ( this.TestChunkAttributes(chunk_id, this.WITH_SHIFT)
                || this.TestChunkAttributes(chunk_id, this.WAS_CAPITALIZED)
                || ( ( settings.capitalization != CAP_OFF) && this._ShouldCapitalize(chunk_id) ) ) {
            expanded := RegExReplace(expanded, "(^.)", "$U1")
            mark_as_capitalized := true
        }
        ; detect affixes to handle opening and closing smart spaces correctly
        affixes := this._DetectAffixes(expanded)
        capitalizes_next := this._DetectCapitalizesNext(expanded)
        expanded := this._RemoveCapitalizesNextSymbol(expanded)
        expanded := this._RemoveAffixSymbols(expanded, affixes)
        previous := this.GetChunk(chunk_id-1)

        if ( (settings.chording & CHORD_RESTRICT)
                && this._IsRestricted(chunk_id-1)
                && !(affixes & this.AFFIX_SUFFIX) ) {
            return false
        }
        
        ; if there is a smart space, we have to delete it for suffixes
        if (previous.attributes & this.SMART_SPACE_AFTER) {
            add_leading_space := false
            if (affixes & this.AFFIX_SUFFIX) {
                replace_offset := -1
            }
        }
        ; if adding smart spaces before is disabled, we don't add it
        if (! (settings.spacing & SPACE_BEFORE_CHORD)) {
            add_leading_space := false
        }
        
        ; if the last output was punctuation that does not ask for a space
        if (       ( !(previous.attributes & this.WITH_SHIFT)
                && InStr(keys.punctuation_plain, previous.input)
                && !InStr(keys.space_after_plain, previous.input) )
                || (previous.attributes & this.WITH_SHIFT)
                && InStr(keys.punctuation_shift, previous.input)
                && !InStr(keys.space_after_shift, previous.input) )  {
            add_leading_space := false
        }
        
        ; and we don't add a space after interruption, Enter, a space, after a prefix, and for suffix
        if (previous.attributes & this.IS_INTERRUPT || previous.output == " " || previous.attributes & this.IS_ENTER 
                || previous.attributes & this.IS_PREFIX || affixes & this.AFFIX_SUFFIX) {
            add_leading_space := false
        }
        if (add_leading_space) {
            expanded := " " . expanded
        }

        this.Replace(expanded, chunk_id + replace_offset)
        this.SetChunkAttributes(chunk_id + replace_offset, this.WAS_EXPANDED)
        if (mark_as_capitalized) {
            this.SetChunkAttributes(chunk_id + replace_offset, this.WAS_CAPITALIZED)
        }
        if (capitalizes_next) {
            this.SetChunkAttributes(chunk_id + replace_offset, this.CAPITALIZES_NEXT)
        }

        ; ending smart space
        if (affixes & this.AFFIX_PREFIX) {
            this.SetChunkAttributes(chunk_id + replace_offset, this.IS_PREFIX)
        } else {
            if (settings.spacing & SPACE_AFTER_CHORD) {
                this._AddSmartSpace()
            }
        }
        this.OutputKeys()
        if (! (affixes & (this.AFFIX_PREFIX | this.AFFIX_SUFFIX))) {
            score.Score(score.ENTRY_CHORD)
        }
        return true
    }

    _FixLastChunk() {
        chunk := this.GetChunk(this.length)
        last_character := SubStr(chunk.output, StrLen(chunk.output), 1)
        if (last_character == " " ||  InStr(keys.punctuation_plain, last_character) ) {
            chunk.input := StrReplace(chunk.input, last_character)
            chunk.output := StrReplace(chunk.output, last_character)
            if ( StrLen(chunk.input) == 1 ) {
                this.ClearChunkAttributes(this.length, this.IS_CHORD)
            }
            this.AugmentedAdd(last_character, false)
        }
    }

    ; Remove characters of non-existing chord if 'delete mistyped chords' option is enabled.
    _RemoveRawChord() {
        if !(settings.chording & CHORD_DELETE_UNRECOGNIZED) {
            return
        }
        ; Note: When "Restrict chords while typing" and "Delete mistyped chords" are both enabled and a non-existing chord is
        ; registered while typing a word, this input is left alone because it is safe to assume it was intended as normal
        ; typing.
        if (settings.chording & CHORD_RESTRICT && this._IsRestricted(this.length-1) ) {
            Return False
        }
        raw_output := this.GetChunk(this.length).output
        this.output_buffer .= "{Backspace " . StrLen(raw_output) . "}"
        this._sequence.RemoveAt(this.length)
        Return true
    }

    TryImmediateShorthand(last_chunk_offset := 0) {
        loop_length := this.length - 1
        Loop %loop_length%
        {
            text := this.GetOutput(A_Index+1, this.length + last_chunk_offset)
            if ( this.expansion_in_last_get || this._IsRestricted(A_Index) ) {
                continue
            }
            if ( this.ShorthandModule(text, A_Index+1, last_chunk_offset) ) {
                return true
            }
        }
    }

    ShorthandModule(text, first_chunk_id, offset := -1) {
        global hint_delay
        if (! (settings.mode & MODE_SHORTHANDS_ENABLED)) {
            return
        }
        attributes := this.GetChunk(first_chunk_id - 1).attributes
        if ( attributes & this.IS_INTERRUPT
                || (attributes & this.WAS_EXPANDED && !(attributes & this.IS_PREFIX)) ) {
            return
        }
        expanded := shorthands.LookUp(text)
        if (expanded) {
            hint_delay.Shorten()
            ; capitalize the whole word on Caps Lock or the first character as needed
            if (GetKeyState("CapsLock", "T")) {
                expanded := Format("{:U}", expanded)
                this.SetChunkAttributes(first_chunk_id, this.WAS_CAPITALIZED)
            } else if ( this.TestChunkAttributes(first_chunk_id, this.WITH_SHIFT)
                    || ( ( settings.capitalization != CAP_OFF) && this._ShouldCapitalize(first_chunk_id) ) ) {
                expanded := RegExReplace(expanded, "(^.)", "$U1")
                this.SetChunkAttributes(first_chunk_id, this.WAS_CAPITALIZED)
            }
            ; Ignore strings such as USD, or aptX
            if ( this._DetectShiftWithin(first_chunk_id + 1, this.length + offset) ) {
                return
            }
            affixes := this._DetectAffixes(expanded)
            capitalizes_next := this._DetectCapitalizesNext(expanded)
            expanded := this._RemoveCapitalizesNextSymbol(expanded)
            expanded := this._RemoveAffixSymbols(expanded, affixes)
            first_chunk_offset := affixes & this.AFFIX_SUFFIX ? -1 : 0 
            this.Replace(expanded, first_chunk_id + first_chunk_offset, this.length + offset)
            this.OutputKeys()
            this.SetChunkAttributes(first_chunk_id + first_chunk_offset, this.WAS_EXPANDED)
            if (capitalizes_next) {
                this.SetChunkAttributes(first_chunk_id + first_chunk_offset, this.CAPITALIZES_NEXT)
            }
            return true
        }
    }

    HintModule(text, first_chunk_id) {
        global hint_delay
        if ( settings.hints & HINT_OFF || ! (hint_delay.HasElapsed()) ) {
            return
        }
        if ( this.TestChunkAttributes(first_chunk_id - 1, this.WAS_EXPANDED | this.IS_INTERRUPT) ) {
            return
        }
        if (settings.mode & MODE_CHORDS_ENABLED) {
            chord_hint := chords.ReverseLookUp(text)
        }
        if (settings.mode & MODE_SHORTHANDS_ENABLED) {
            shorthand_hint := shorthands.ReverseLookUp(text)
        }
        chord_hint := chord_hint ? chord_hint : "" 
        shorthand_hint := shorthand_hint ? shorthand_hint : "" 
        if (chord_hint || shorthand_hint) {
            hint_UI.ShowHint(text, chord_hint, shorthand_hint)
            return true
        }
    }

    _IsRestricted(chunk_id) {
        ; If last output was automated (smart space or chord), punctuation, a 'prefix' (which  includes opening
        ; punctuation), it was interrupted, after Enter, or it was a space, we can also go ahead.
        if ( this.TestChunkAttributes(chunk_id, this.WAS_EXPANDED | this.IS_PUNCTUATION | this.IS_PREFIX
                | this.IS_INTERRUPT | this.IS_MANUAL_SPACE | this.IS_ENTER | this.SMART_SPACE_AFTER) ) {
            return false
        }
        return true
    }

    _ShouldCapitalize(start := 0) {
        if (start == 0) {
            start := this.length
        }
        ; first character after Enter
        if (start == 2 && (this._sequence[start - 1].attributes & this.IS_ENTER) ) {
            return true
        }
        if (start > 2 && this.GetOutput(start - 1, start - 1) == " ") {
            if (this.TestChunkAttributes(start - 2, this.CAPITALIZES_NEXT)) {
                return true
            }
            preceding := this.GetChunk(start - 2).input
            with_shift := this.TestChunkAttributes(start - 2, this.WITH_SHIFT)
            if ( StrLen(preceding)==1 && (!with_shift && InStr(keys.capitalizing_plain, preceding))
                || (with_shift && InStr(keys.capitalizing_shift, preceding)) ) {
                return true
            }
        }
        if (start > 1 && this.TestChunkAttributes(start - 1, this.CAPITALIZES_NEXT)) {
            return true
        }
        ; Capitalize chords after sentence-ending punctuation should even a preceding space.
        if ( start > 1 && this.TestChunkAttributes(start, this.IS_CHORD) ) {
            preceding := this.GetChunk(start - 1).input
            with_shift := this.TestChunkAttributes(start - 1, this.WITH_SHIFT)
            if ( StrLen(preceding)==1 && (!with_shift && InStr(keys.capitalizing_plain, preceding))
                || (with_shift && InStr(keys.capitalizing_shift, preceding)) ) {
                return true
            }
        }
        return false
    }

    _DetectShiftWithin(start_chunk_id, end_chunk_id) {
        if (start_chunk_id > end_chunk_id) {
            ; edge case with a chord used in typing a short shorthand
            return false
        }
        chunk_id := start_chunk_id
        if (end_chunk_id > this.length) {
            MsgBox ,, % "ZipChord", % "Error: The function _DetectShiftWithin was called with incorrect end range."
            Return false
        }
        Loop {
            if (this.TestChunkAttributes(chunk_id, this.WITH_SHIFT)) {
                return true
            }
            if (chunk_id++ >= end_chunk_id) {
                return false
            }
        }
    }

    ; detect and adjust expansion for suffixes and prefixes
    _DetectAffixes(phrase) {
        affixes := this.AFFIX_NONE
        if (SubStr(phrase, 1, 1) == "~") {
            affixes |= this.AFFIX_SUFFIX
        }
        if (SubStr(phrase, 0) == "~" || SubStr(phrase, -1) == "~^") {
            affixes |= this.AFFIX_PREFIX
        }
        Return affixes
    }
    _RemoveAffixSymbols(text, affixes) {
        if (affixes & this.AFFIX_SUFFIX) {
            text := SubStr(text, 2)
        }
        if (SubStr(text, 0) == "~") {   ; removal of ~^ is handled by RemoveCapitalizesNextSymbol
            text := SubStr(text, 1, StrLen(text) - 1)
        }
        Return text
    }
    _DetectCapitalizesNext(phrase) {
        return SubStr(phrase, 0) == "^" || SubStr(phrase, -1) == "^~"
    }
    _RemoveCapitalizesNextSymbol(text) {
        if (SubStr(text, 0) == "^") {
            return SubStr(text, 1, StrLen(text) - 1)
        }
        if (SubStr(text, -1) == "^~") {
            return SubStr(text, 1, StrLen(text) - 2) . "~"
        }
        Return text
    }

    _AddSmartSpace() {
        smart_space := new this.clsChunk
        smart_space.input := ""
        smart_space.output := " "
        smart_space.attributes |= this.SMART_SPACE_AFTER
        this._sequence.Push(smart_space)
        this.output_buffer .= "{Space}"
    }

    OutputKeys() {
        if (this.output_buffer == "") {
            return
        }
        if (A_Args[1] == "dev") {
            test.Log(this.output_buffer)
            if (test.mode == TEST_RUNNING) {
                this.output_buffer := ""
                return
            }
        }
        this.SendIndividualKeys(this.output_buffer)
        this.output_buffer := ""
    }

    SendIndividualKeys(str) {
        ; expand repeats like {Backspace 2}
        while RegExMatch(str, "\{([A-Za-z]+)\s+(\d+)\}", m) {
            rep := ""
            Loop % m2
                rep .= "{" m1 "}"
            str := StrReplace(str, m, rep)
        }

        pos := 1
        while (pos <= StrLen(str)) {
            this._DelayOutput()
            ch := SubStr(str, pos, 1)
            if (ch = "{") {
                end := InStr(str, "}", false, pos)
                if (!end)  { ; malformed, send rest as text
                    token := SubStr(str, pos)
                    pos := StrLen(str)+1
                }
                else {
                    token := SubStr(str, pos, end-pos+1)
                    pos := end+1
                }
                SendInput % token            ; send special key token
            } else {
                token := SubStr(str, pos, 1), pos++
                SendInput % "{Text}" token   ; send literal character safely
            }
        }
    }


    DebugSequence() {
        if (A_Args[2] != "test-vs") {
            return
        }
        OutputDebug, % "`n`nKeys:"
        OutputDebug, % "Classifying starts at " . this._classification_start
        len := io_events.Length()
        Loop % len
        {
            ev := io_events[A_Index]
            OutputDebug, % "`n" . i . ": " ev.input . " > " . ev.output . " (" . ev.attributes . ")"
        }
        OutputDebug, % "`n`nSequence:"
        For i, chunk in this._sequence {
            OutputDebug, % "`n" . i . ": " chunk.input . " > " . chunk.output . " (" . chunk.attributes . ")"
        }
    }
}
