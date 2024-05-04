/*

This file is part of ZipChord.

Copyright (c) 2023-2024 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/


classifier := new clsClassifier
io := new clsIOrepresentation

Class clsClassifier {
    _buffer := []    ; stores clsKeyEvent objects
    Class clsKeyEvent {
        key := 0
        with_shift := false
        start := 0
        end := 0
    }
    _index := {}     ; associateve arary that indexes _buffer:  _index[{key}] points to that key's record in _buffer
    length [] {      ; number of entries in buffer
        get {
            return this._buffer.Length()
        }
    }
    lifted [] {      ; number of keys in buffer that were already released
        get {
            For _, event in this._buffer
                if (event.end)
                    lifted++        
            return lifted
        }
    }
    _GetOverlap(first, last, timestamp) {
        start := this._buffer[last].start
        end := timestamp
        count := last - first + 1
        Loop %count% {
            if (event_end := this._buffer[first - 1 + A_Index].end) {
                end := Min(end, event_end)
            }
        }
        Return end-start
    }
    _DetectRoll(cutoff) {
        time := this._buffer[cutoff].end
        count := this.length - cutoff
        Loop %count%
        {
            if (this._buffer[cutoff + A_Index].start > time)
                return true
        }
        return false
    }
    Input(key, timestamp) {
        global io
        is_special_key := false
        
        if ( SubStr(key, 1, 1) == "|" ) {
            is_special_key := true
        }
        key := SubStr(key, 2)
        if (SubStr(key, 1, 1) == "+") {
            with_shift := True
            key := SubStr(key, 2)
        } else with_shift := False

        key := StrReplace(key, "Space", " ")

        if (SubStr(key, -2)==" Up") {
            key := SubStr(key, 1, StrLen(key)-3)
            lifted := true
        } else {
            lifted := false
        }

        if (lifted) {
            index := this._index[key]
            this._buffer[index].end := timestamp
            if (index) {
                this._index.Delete(key)
                this._Classify(index, timestamp)
            }
            ; otherwise, the lifted key was already classified and removed from buffer.
            return
        }
        ; Process a key down:
        event := new this.clsKeyEvent
        event.key := key
        event.start := timestamp
        event.with_shift := with_shift
        this._buffer.Push(event)
        this._index[key] := this._buffer.Length()

        io.Add(key, with_shift, false, is_special_key)
    }
    Interrupt(type := "*Interrupt*") {
        global io
        this._buffer := []
        this._index := {}
        io.ClearSequence(type)
    }
    _Classify(index, timestamp) {
        ; This classification mirrors the 2.1 version of detecting chords.
        global io
        static first_up
        if (this.length == 1) {
            this._buffer.RemoveAt(1)
            io.Chord(0)
            return
        }
        if (this.lifted == 1)
            first_up := index
        if (this.lifted == 2) {
            if (this._GetOverlap(1, 2, timestamp) > settings.input_delay && ! this._DetectRoll(first_up)) {
                io.Chord(this.length)
            } else {
                io.Chord(0)
            }
            this._buffer := []
            this._index := {}
        }
    }
} 

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
    pre_shifted := false
    _sequence := []
    SEQUENCE_WINDOW := 6 ; sequence length to maintain

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
    PreShift() {
        this.pre_shifted := !this.pre_shifted
    }
    Class clsChunk {
        __New() {
            this.input := ""
            this.output := ""
            this.attributes := 0
        }
    }
    __New() {
        this.ClearSequence("*Interrupt*")
    }

    Add(entry, with_shift, adjustment := false, is_special_key := false) {
        chunk := new this.clsChunk
        chunk.input := entry
        if (with_shift) {
            chunk.attributes |= this.WITH_SHIFT
            chunk.output := str.ToAscii(entry, ["Shift"])
        } else {
            chunk.output := entry
        }
        if (is_special_key) {
            chunk.output := ""
        }
        if ( !with_shift && InStr(keys.punctuation_plain, entry) )
                || ( with_shift && InStr(keys.punctuation_shift, entry) ) {
            chunk.attributes |= this.IS_PUNCTUATION
        }
        if (entry == " ") {
            chunk.attributes |= this.IS_MANUAL_SPACE
        }
        if (!with_shift && InStr("0123456789", entry)) {
            chunk.attributes |= this.IS_NUMERAL
        }
        if (this.pre_shifted) {
            chunk.attributes |= this.WAS_CAPITALIZED
            this.pre_shifted := false
        }
        this._sequence.Push(chunk)
        if (adjustment) {
            return
        }
        this.CapitalizeTypingAsNeeded(entry, chunk.attributes)
        this.RemoveSmartSpaceAsNeeded(chunk.attributes)
        ; now, the slightly chaotic immediate mode allowing shorthands triggered as soon as they are completed:
        if (settings.chording & CHORD_IMMEDIATE_SHORTHANDS) {
            this.TryImmediateShorthand()
        }
    }

    /**
    * Transform chord key presses received from Classifier into chunks
    */
    Chord(count) {
        sequence := this._sequence
        if (count>1) {
            start := 1 + this.length - count
            count -= 1
            chunk := sequence[start]
            Loop, %count%
            {
                next_chunk := sequence[start+1] 
                chunk.input .= next_chunk.input 
                chunk.output .= next_chunk.output
                chunk.attributes |= next_chunk.attributes
                sequence.RemoveAt(start+1)
            }
            ; Sort to allow matching against chord dictionaries
            chunk.input := str.Arrange(chunk.input)
            ; Set as chords, and clear punctuation and manual space attributes 
            chunk.attributes := chunk.attributes & ~this.IS_PUNCTUATION & ~this.IS_MANUAL_SPACE | this.IS_CHORD
                 
            ;For chords, if Shift is allowed as a separate key in chord key, we add it as part of the entry if it was pressed.
            if ( (settings.chording & CHORD_ALLOW_SHIFT) && (chunk.attributes & this.WITH_SHIFT) ) {
                chunk.input := "+" . chunk.input
                chunk.attributes := chunk.attributes & ~this.WITH_SHIFT
            }
        }
        this.RunModules()
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
        if (type=="") {
            items_to_remove := this.length - this.SEQUENCE_WINDOW
            if (items_to_remove < 1) {
                return
            }
            this._sequence.RemoveAt(1, items_to_remove)
            return
        }
        new_chunk := new this.clsChunk
        if (type=="~Enter") {
            new_chunk.attributes := this.IS_ENTER
        }
        if (type=="*Interrupt*") {
            new_chunk.attributes := this.IS_INTERRUPT
        }
        this._sequence := []
        this._sequence.Push(new_chunk)
        if (visualizer.IsOn()) {
            visualizer.NewLine()
        }
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
        ; purposefully return true if one of the bitmask conditions are true (therefore, not comparing to bitmask)
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
        this._DelayOutput()
        if (adj != 1) {  ; this test is for compatibility with ZipChord 2.1 sending often just "{Backspace}" - TK: simplify later
            OutputKeys("{Backspace " . adj . "}")
        } else {
            OutputKeys("{Backspace}")
        }
        if ( new_output . backup_content == "") {
            return
        }
        ; we send any expanded text that includes { as straight directives:
        if (! InStr(new_output, "{")) {
            OutputKeys("{Text}" . new_output . backup_content)
        } else {
            OutputKeys(new_output)
        }
    }

    ; Delay output by defined delay
    _DelayOutput() {
        if (settings.output_delay) {
            Sleep settings.output_delay
        }
    }
    Backspace() {
        global classifier
        if ( this.length < 2 || this.TestChunkAttributes(this.length, this.WAS_EXPANDED) ) {
            classifier.Interrupt()
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
            score.Score(score.ENTRY_CHORD)
            return
        }
        if ( this.TestChunkAttributes(this.length, this.IS_CHORD) ) {
            if (this._RemoveRawChord()) {
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
        this.ClearSequence()
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
        }
    }

    ; Remove a double space if the user types a space after punctuation smart space
    DeDoubleSpace() {
        if ( this.TestChunkAttributes(this.length - 1, this.SMART_SPACE_AFTER)
                && this.TestChunkAttributes(this.length, this.IS_MANUAL_SPACE) ) {
            OutputKeys("{Backspace}")
            this._sequence.RemoveAt(this.length - 1)
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
        if (       this.TestChunkAttributes(chunk_id, this.WITH_SHIFT)
                || this.TestChunkAttributes(chunk_id, this.WAS_CAPITALIZED)
                || ( ( settings.capitalization != CAP_OFF) && this._ShouldCapitalize(chunk_id) ) ) {
            expanded := RegExReplace(expanded, "(^.)", "$U1")
            mark_as_capitalized := true
        }
        ; detect affixes to handle opening and closing smart spaces correctly
        affixes := this._DetectAffixes(expanded)
        expanded := this._RemoveAffixSymbols(expanded, affixes)
        previous := this.GetChunk(chunk_id-1)

        if ( (settings.chording & CHORD_RESTRICT) && this._IsRestricted(chunk_id-1) && !(affixes & AFFIX_SUFFIX) ) {
            return false
        }
        
        ; if there is a smart space, we have to delete it for suffixes
        if (previous.attributes & this.SMART_SPACE_AFTER) {
            add_leading_space := false
            if (affixes & AFFIX_SUFFIX) {
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
                || previous.attributes & this.IS_PREFIX || affixes & AFFIX_SUFFIX) {
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

        ; ending smart space
        if (affixes & AFFIX_PREFIX) {
            this.SetChunkAttributes(chunk_id + replace_offset, this.IS_PREFIX)
        } else {
            if (settings.spacing & SPACE_AFTER_CHORD) {
                this._AddSmartSpace()
            }
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
            this.Add(last_character, false, true)
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
            return
        }
        raw_output := this.GetChunk(this.length).output
        OutputKeys("{Backspace " . StrLen(raw_output) . "}")
        this._sequence.RemoveAt(this.length)
        return true
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
        if ( expanded := shorthands.LookUp(text) ) {
            hint_delay.Shorten()
            if (    this.TestChunkAttributes(first_chunk_id, this.WITH_SHIFT)
                    || ( ( settings.capitalization != CAP_OFF) && this._ShouldCapitalize(first_chunk_id) ) ) {
                expanded := RegExReplace(expanded, "(^.)", "$U1")
                this.SetChunkAttributes(first_chunk_id, this.WAS_CAPITALIZED)
            }
            if ( this._DetectShiftWithin(first_chunk_id + 1, this.length + offset) ) {
                return
            }
            this.Replace(expanded, first_chunk_id, this.length + offset)
            this.SetChunkAttributes(first_chunk_id, this.WAS_EXPANDED)
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
            preceding := this.GetChunk(start - 2).input
            with_shift := this.TestChunkAttributes(start - 2, this.WITH_SHIFT)
            if ( StrLen(preceding)==1 && (!with_shift && InStr(keys.capitalizing_plain, preceding))
                || (with_shift && InStr(keys.capitalizing_shift, preceding)) ) {
                return true
            }
        }
        return false
    }

    _DetectShiftWithin(start_chunk_id, end_chunk_id) {
        chunk_id := start_chunk_id
        if (end_chunk_id > this.length) {
            MsgBox ,, % "ZipChord", % "Error: The function _DetectShiftWithin was called with incorrect end range."
            Return false
        }
        Loop {
            if (this.TestChunkAttributes(chunk_id, this.WITH_SHIFT)) {
                return true
            }
            if (chunk_id++ == end_chunk_id) {
                return false
            }
        }
    }

    ; detect and adjust expansion for suffixes and prefixes
    _DetectAffixes(phrase) {
        affixes := AFFIX_NONE
        if (SubStr(phrase, 1, 1) == "~") {
            affixes |= AFFIX_SUFFIX
        }
        if (SubStr(phrase, StrLen(phrase), 1) == "~") {
            affixes |= AFFIX_PREFIX
        }
        Return affixes
    }
    _RemoveAffixSymbols(text, affixes) {
        if (affixes & AFFIX_SUFFIX) {
            text := SubStr(text, 2)
        }
        if (affixes & AFFIX_PREFIX) {
            text := SubStr(text, 1, StrLen(text) - 1)
        }
        Return text
    }

    _AddSmartSpace() {
        smart_space := new this.clsChunk
        smart_space.input := ""
        smart_space.output := " "
        smart_space.attributes |= this.SMART_SPACE_AFTER
        this._sequence.Push(smart_space)
        OutputKeys("{Space}")
    }

    DebugSequence() {
        if (A_Args[2] != "test-vs") {
            return
        }
        OutputDebug, % "`n`nIO sequence:" 
        For i, chunk in this._sequence {
            OutputDebug, % "`n" . i . ": " chunk.input . " > " . chunk.output . " (" . chunk.attributes . ")"
        }
    }
}
