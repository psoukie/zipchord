/*
This file is part of ZipChord.
Copyright (c) 2023-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/


Class clsKey {
    key := 0
    with_shift := false
    start := 0
    end := 0
}

Class clsToken {
    input := ""
    output := ""
    attribs := 0
    chord := ""
}

global io_keys := []
global io_keys_index := {}      ; indexes _buffer:  _events_index[{key}] points to that key's record in _buffer

io_chord_backup := new clsToken   ; temporarily holds original tokens of a chord candidate
io_restore_tombstones := false

global io_tokens := []
io_new_tokens := []
io_prev_tokens := []
io_tokens_to_ignore := 0

io := new clsIOrepresentation

Class clsIOrepresentation {
    static NONE := 0
         , WITH_SHIFT := 1
         , SMART_SPACE_AFTER := 2
         , IS_PUNCTUATION := 4
         , WAS_EXPANDED := 8
         , WAS_CAPITALIZED := 16
         , IS_PREFIX := 32
         , IS_MANUAL_SPACE := 64
         , CHORD_CANDIDATE := 128
         , IS_ENTER := 256
         , IS_INTERRUPT := 512
         , IS_NUMERAL := 1024
         , CAPITALIZES_NEXT := 2048
         , TOMBSTONED := 4096
    ; affixes constants
    static AFFIX_NONE := 0 ; no prefix or suffix
        , AFFIX_PREFIX := 1 ; expansion is a prefix
        , AFFIX_SUFFIX := 2 ; expansion is a suffix

    pre_shifted := false
    expansion_in_last_get := false


    IOKeysReset() {
        io_keys := []
        io_keys_index := {}
    }

    ProcessKey(hotkey, timestamp) {
        ev := new clsKey
        is_key_down := true
        
        ; translate the hotkey string
        ev.key := SubStr(hotkey, 2)
        if (SubStr(ev.key, 1, 1) == "+") {
            ev.with_shift := true
            ev.key := SubStr(ev.key, 2)
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
            if (this.pre_shifted) {
                ev.with_shift := true
                this.pre_shifted := false
            }
            ; TK - check if key is already in io_keys
            io_keys.Push(ev)
            io_keys_index[ev.key] := io_keys.Length()
        } else {
            ; Process a key up event: look up the event, record lift time, and classify
            if !(io_keys_index.HasKey(ev.key)) {
                return
            }
            index := io_keys_index[ev.key]
            io_keys_index.Delete(ev.key)
            if (!index || index > io_keys.Length()) {
                return
            }
            io_keys[index].end := timestamp
            
            result := this._Classify(timestamp, index)

            if (io_keys_index.Count() == 0 && io_keys.Length() != 0) {
                this.IOKeysReset()
            }

            return result
        }
    }
    
    _Shift_IO_Keys_Window(count) {
        io_keys.RemoveAt(1, count)
        
        for key, index in io_keys_index {
            if (index <= count) {
                OutputDebug % "`nDeleting index for " . key
                io_keys_index.Delete(key)
                continue
            }
            io_keys_index[key] := index - count
        }
    }

    ; TK -- needs to be called when parsing individual tokens
    KeyToToken(key) {
        token := new clsToken
        entry := "" . key.key
        token.input := entry
        if (key.with_shift) {
            token.attribs |= this.WITH_SHIFT
            token.output := str.ToAscii(entry, ["Shift"])
        } else {
            token.output := entry
        }
    
        if ( !key.with_shift && InStr(keys.punctuation_plain, entry) )
                || ( key.with_shift && InStr(keys.punctuation_shift, entry) ) {
            token.attribs |= this.IS_PUNCTUATION
        }
        if (entry == " ") {
            token.attribs |= this.IS_MANUAL_SPACE
        }
        if (!key.with_shift && InStr("0123456789⓪①②③④⑤⑥⑦⑧⑨", entry)) {
            token.attribs |= this.IS_NUMERAL
        }
        return token
    }

    AddKeysToTokens(count) {
        global io_new_tokens
        
        Loop % count {
            token := this.KeyToToken(io_keys[A_Index])
            io_new_tokens.Push(token)
        }
        if (count == io_keys.Length()) {
            this.IOKeysReset()
        } else {
            this._Shift_IO_Keys_Window(count)           
        }
    }

    ; Transform key presses into a chord and add to tokens
    AddChordToTokens() {
        global io_new_tokens

        first := this.KeyToToken(io_keys[1])
        first.attribs |= this.CHORD_CANDIDATE
        first.chord := first.input
        io_new_tokens.Push(first)
        
        Loop, % io_keys.Length() - 1
        {
            key := io_keys[A_Index + 1] 
            first.chord .= key.key
            if (key.with_shift) {
                first.attribs |= this.WITH_SHIFT
            }
            token := this.KeyToToken(key)
            io_new_tokens.Push(token)
        }
             
        ;For chords, if Shift is allowed as a separate key in chord key, we add it as part of the entry if it was pressed.
        if ( (settings.chording & CHORD_ALLOW_SHIFT) && (first.attribs & this.WITH_SHIFT) ) {
            first.chord := "+" . first.chord
            first.attribs := first.attribs & ~this.WITH_SHIFT
        }
    
        ; Sort to allow matching against chord dictionaries        
        if (dll.available) {
            first.chord := dll.NormalizeChord(first.chord)
        } else {
            first.chord := str.Arrange(first.chord)
        }

        this.IOKeysReset()
    }

    _ClassifyByDuration(end) {
        ; get and compare against the overlap of the second key in the chord (regardless of chord length)
        start := io_keys[2].start
        if (end - start > settings.input_delay) {
            this.AddChordToTokens()
        } else {
            this.AddKeysToTokens(io_keys.Length())
        }
    }

    _ClassifyByPercentage(end, lifted_index) {
        ; test the full buffer then drop earlier keys
        last_start := io_keys[io_keys.Length()].start
        common_overlap := end - last_start
        
        end_iter := Min(lifted_index, io_keys.Length() - 1)
        Loop % end_iter {
            candidate_span := end - io_keys[A_Index].start
            
            if (candidate_span <= 0) {
                continue
            }
            if (common_overlap / candidate_span >= settings.input_overlap / 100) {
                if (A_Index > 1) {
                    this.AddKeysToTokens(A_Index - 1)
                }
                this.AddChordToTokens()
                return
            }
        }
        if (lifted_index == io_keys.Length()) {
            this.AddKeysToTokens(lifted_index)
        } else {
            this.AddKeysToTokens(end_iter)
        }
    }

    _Classify(end, index) {  ; -> bool if keys is empty and ready for token processing
        if (io_keys.Length() == 1) {
            ; process a lone key press in io_keys
            this.AddKeysToTokens(1)
            return true
        }
    
        ; two or more keys were pressed as a potential chord
        if (settings.chording & CHORD_BY_OVERLAP) {
            this._ClassifyByPercentage(end, index)
            return io_keys.Length() == 0
        } else {
            this._ClassifyByDuration(end)
            return true    
        }
    }

    PreShift() {
        this.pre_shifted := !this.pre_shifted
        ; and we cheat to allow shorthands:
        if (this.TestTokenAttribs(io_tokens.Length(), this.IS_INTERRUPT)) {
            this.ClearTokenAttribs(io_tokens.Length(), this.IS_INTERRUPT)
            this.SetTokenAttribs(io_tokens.Length(), this.IS_MANUAL_SPACE)
        }
    }
    __New() {
        this.ClearTokens("*Interrupt*")
    }

    ClearTokens(type := "") {
        this.IOKeysReset()
        io_tokens := []

        new_token := new clsToken
        if (type=="~Enter") {
            new_token.attribs := this.IS_ENTER
        }
        if (type=="*Interrupt*") {
            new_token.attribs := this.IS_INTERRUPT
        }
        if (visualizer.IsOn()) {
            visualizer.NewLine()
        }
        io_tokens.Push(new_token)
    }
    
    Replace(new_output, start := 1, end := -1) {
        if (end == -1) {
            end := io_tokens.Length()
        }
        if (start != end) {
            Loop, % end - start
            {
                index := A_Index + start
                io_tokens[start].input .= "|" . io_tokens[index].input 
                this.SetTokenAttribs(index, this.TOMBSTONED)
            }
        }
        io_tokens[start].output := new_output
    }

    SetTokenAttribs(token_id, bitmask, set := true) {
        if (set) {
            io_tokens[token_id].attribs |= bitmask
        } else {
            io_tokens[token_id].attribs &= ~bitmask
        }
    }
    ClearTokenAttribs(token_id, bitmask) {
        this.SetTokenAttribs(token_id, bitmask, false)
    }
    TestTokenAttribs(token_id, bitmask) {
        ; purposefully returns true if one of the bitmask conditions are true (therefore, not comparing to bitmask)
        if (token_id > io_tokens.Length() || token_id < 1) {
            return false
        }
        return (io_tokens[token_id].attribs & bitmask)
    }

    GetInput(start := 1, end := 0) {
        return this._Get(start, end)
    }
    GetOutput(start := 1, end := 0) {
        return this._Get(start, end, true)
    }
    _Get(start := 1, end := 0, get_output := false) {
        this.expansion_in_last_get := false
        what := get_output ? "output" : "input" 
        separator := get_output ? "" : "|"
        if (! end) {
            end := io_tokens.Length() 
        }
        if (start > io_tokens.Length() || end > io_tokens.Length()) {
            MsgBox, , % "ZipChord", "IO Representation error: Requested getting tokens that exceed the length of _io_tokens."
            Return true
        }
        count := end - start + 1
        Loop, %count%
        {
            index := A_Index + start - 1
            if (io_tokens[index].attribs & this.TOMBSTONED) {
                continue
            }
            if (io_tokens[index].attribs & this.WAS_EXPANDED) {
                this.expansion_in_last_get := true
            }
            representation .= separator . io_tokens[index][what]
        }
        return SubStr(representation, StrLen(separator)+1)
    }

    Backspace(with_ctrl := false) {
        if ( io_tokens.Length() < 2 || this.TestTokenAttribs(io_tokens.Length(), this.WAS_EXPANDED) || with_ctrl ) {
            this.ClearTokens("*Interrupt*")
            return
        }
        if ( this.TestTokenAttribs(io_tokens.Length(), this.CHORD_CANDIDATE) ) {
            token := io_tokens[io_tokens.Length()]
            token.input := "XX" ; TK problematic workaround - so the token cannot be matched to any chord later
            token.output := SubStr(token.output, 1, StrLen(token.output) - 1)
            if (StrLen(token.output) == 1) {
                token.attribs &= ~this.CHORD_CANDIDATE
            }
            return
        }
        io_tokens.Pop()
    }

    _FindFirstModifiedToken() {
        global io_prev_tokens
        
        for index, prev_token in io_prev_tokens {
            if (index > io_tokens.Length()) {
                return index
            }
            new_token := io_tokens[index]
            if (new_token.input != prev_token.input || new_token.output != prev_token.output || new_token.attribs != prev_token.attribs) {
                return index
            }
        }
        if (io_prev_tokens.Length() == io_tokens.Length()) {
            return -1  ; identical
        }
        return io_prev_tokens.Length() + 1  ; extra new tokens
    }
    
    _GetPrevRemainingLength(start) {
        global io_prev_tokens

        length := 0
        end := io_prev_tokens.Length()
        count := end - start + 1
        loop % count
        {
            index := A_Index + start - 1
            if (io_prev_tokens[index].attribs & this.TOMBSTONED) {
                continue
            }
            length += StrLen(io_prev_tokens[index].output)
        }
        return length
    }

    _PushTokenClone(token) {
        global io_prev_tokens
        
        token_copy := new clsToken
        token_copy.input := token.input
        token_copy.output := token.output
        token_copy.attribs := token.attribs
        io_prev_tokens.Push(token_copy)
    }
    
    _CopyTokensIntoPrev() {
        global io_prev_tokens
        global io_new_tokens

        io_prev_tokens := []
        for i, token in io_tokens {
            this._PushTokenClone(token)
        }
        for i, token in io_new_tokens {
            this._PushTokenClone(token)
        }
    }

    ProcessTokens() {
        global io_prev_tokens
        global io_new_tokens
        global io_tokens_to_ignore

        io_tokens_to_ignore := 0
        this._CopyTokensIntoPrev()

        ; TK - 'SPACE + W' does not work as chord
        while (io_new_tokens.Length() > 0) {
            if (io_tokens_to_ignore > 0) {
                io_new_tokens.RemoveAt(1)
                io_tokens_to_ignore -= 1
                continue
            }
            token := io_new_tokens[1]
            io_tokens.Push(token)
            io_new_tokens.RemoveAt(1)
            this.ProcessLastToken()
        }    

        first_modified := this._FindFirstModifiedToken()
        if (first_modified == -1) {
            return   ; no changes
        }
        chars_to_del := this._GetPrevRemainingLength(first_modified)
        if (chars_to_del > 0) {
            this.ProcessOutput("{Backspace " . chars_to_del . "}")
        }

        this.SendTokensAsKeys(first_modified)
    }

    ProcessLastToken() {
        global io_tokens_to_ignore

        token := io_tokens[io_tokens.Length()]
        
        if ( token.attribs & this.CHORD_CANDIDATE ) {
            ; Process a chord (which is the last or only token)
            backup_input := token.input
            token.input := token.chord
            io_tokens_to_ignore := StrLen(token.chord) - 1
            if (this.TryChordModule()) {
                return
            }

            io_tokens_to_ignore := 0
            token.input := backup_input
            if (this._RemoveRawChord()) {
                return
            }
        } else {
            ; Process a char
            this.CapitalizeTypingAsNeeded(token.input, token.attribs)
            this.RemoveSmartSpaceAsNeeded(token.attribs)
            ; now, the slightly chaotic immediate mode allowing shorthands triggered as soon as they are completed:
            if (settings.chording & CHORD_IMMEDIATE_SHORTHANDS) {
                this.TryImmediateShorthand()
            }
        }

        if (this.DeDoubleSpace()) {
            return
        }

        ; Process shorthands if we have a space or punctuation
        if ! ( this.TestTokenAttribs(io_tokens.Length(), this.IS_MANUAL_SPACE | this.IS_PUNCTUATION) ) {
            return
        }
        if (this.DoShorthandsAndHints()) {
            score.Score(score.ENTRY_SHORTHAND)
        } else if ! ( this.TestTokenAttribs(io_tokens.Length() - 1, this.IS_MANUAL_SPACE | this.IS_PUNCTUATION) ) {
            score.Score(score.ENTRY_MANUAL)
        }

        this.AddSpaceAfterPunctuation()
    }

    DoShorthandsAndHints() {
        loop_length := io_tokens.Length() - 1
        Loop %loop_length%
        {
            text := this.GetOutput(A_Index+1, io_tokens.Length()-1)
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
        if (StrLen(character) != 1) {
            return
        }
        if ( settings.capitalization != CAP_ALL || (attribs & this.IS_PUNCTUATION)
                || (attribs & this.IS_MANUAL_SPACE) || (attribs & this.WITH_SHIFT) ) {
            return
        }

        token_id := io_tokens.Length()
        
        ; do not capitalize numerals
        if (io_tokens[token_id].attribs & this.IS_NUMERAL) {
            return
        }

        if ( this._ShouldCapitalize() ) {
            io_tokens[token_id].output := RegExReplace(character, "(^.)", "$U1")
            this.SetTokenAttribs(token_id, this.WAS_CAPITALIZED)
        }
    }

    RemoveSmartSpaceAsNeeded(attribs) {
        if ! (this.TestTokenAttribs(io_tokens.Length()-1, this.SMART_SPACE_AFTER)) {
            return
        }
        ; for punctuation that removes spaces
        if (attribs & this.IS_PUNCTUATION) {
            token := io_tokens[io_tokens.Length()]
            if ( (!(token.attribs & this.WITH_SHIFT) && InStr(keys.remove_space_plain, token.input))
                    || ((token.attribs & this.WITH_SHIFT) && InStr(keys.remove_space_shift, token.input)) ) {
                return this._RemoveSmartSpace()
            }
        }
        ; for manual_space-punctuation-numeral and numeral-punctuation-numeral
        if (attribs & this.IS_NUMERAL && this.TestTokenAttribs(io_tokens.Length() - 2, this.IS_PUNCTUATION)
                && this.TestTokenAttribs(io_tokens.Length() - 3, this.IS_NUMERAL | this.IS_MANUAL_SPACE | this.IS_ENTER)) {
            return this._RemoveSmartSpace()
        }
    }

    _RemoveSmartSpace() {
        this.Replace("", io_tokens.Length() - 1, io_tokens.Length() - 1)
        io_tokens.RemoveAt(io_tokens.Length() - 1)
        return true
    }

    AddSpaceAfterPunctuation() {
        token := io_tokens[io_tokens.Length()]
        attribs := token.attribs
        if ( !(settings.spacing & SPACE_PUNCTUATION) || this.TestTokenAttribs(io_tokens.Length() - 1, this.IS_INTERRUPT) ) {
            return
        }
        if (( !(attribs & this.WITH_SHIFT) && InStr(keys.space_after_plain, token.input) )
                || (attribs & this.WITH_SHIFT) && InStr(keys.space_after_shift, token.input) ) {
            this._AddSmartSpace()
        }
    }

    ; Remove a double space if the user types a space after punctuation smart space
    DeDoubleSpace() {
        if ( this.TestTokenAttribs(io_tokens.Length() - 1, this.SMART_SPACE_AFTER)
                && this.TestTokenAttribs(io_tokens.Length(), this.IS_MANUAL_SPACE) ) {
            io_tokens.Pop()
            return true
        }
        return false
    }

    TryChordModule() {
        if (! (settings.mode & MODE_CHORDS_ENABLED)) {
            return false
        }
        count := io_tokens.Length()
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
                    return this._ExpandChord(io_tokens.Length(), expanded) 
                }
                return this._ExpandChord(A_Index, expanded)
            }
        }
    }

    _ExpandChord(token_id, expanded) {
        global hint_delay
        mark_as_capitalized := false
        add_leading_space := true
        replace_offset := 0

        hint_delay.Shorten()

        ; capitalize the whole word on Caps Lock or the first character as needed
        if (GetKeyState("CapsLock", "T")) {
            expanded := Format("{:U}", expanded)
            mark_as_capitalized := true
        } else if ( this.TestTokenAttribs(token_id, this.WITH_SHIFT)
                || this.TestTokenAttribs(token_id, this.WAS_CAPITALIZED)
                || ( ( settings.capitalization != CAP_OFF) && this._ShouldCapitalize(token_id) ) ) {
            expanded := RegExReplace(expanded, "(^.)", "$U1")
            mark_as_capitalized := true
        }
        ; detect affixes to handle opening and closing smart spaces correctly
        affixes := this._DetectAffixes(expanded)
        capitalizes_next := this._DetectCapitalizesNext(expanded)
        expanded := this._RemoveCapitalizesNextSymbol(expanded)
        expanded := this._RemoveAffixSymbols(expanded, affixes)
        previous := io_tokens[token_id-1]

        if ( (settings.chording & CHORD_RESTRICT)
                && this._IsRestricted(token_id-1)
                && !(affixes & this.AFFIX_SUFFIX) ) {
            return false
        }
        
        ; if there is a smart space, we have to delete it for suffixes
        if (previous.attribs & this.SMART_SPACE_AFTER) {
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
        if (       ( !(previous.attribs & this.WITH_SHIFT)
                && InStr(keys.punctuation_plain, previous.input)
                && !InStr(keys.space_after_plain, previous.input) )
                || (previous.attribs & this.WITH_SHIFT)
                && InStr(keys.punctuation_shift, previous.input)
                && !InStr(keys.space_after_shift, previous.input) )  {
            add_leading_space := false
        }
        
        ; and we don't add a space after interruption, Enter, a space, after a prefix, and for suffix
        if (previous.attribs & this.IS_INTERRUPT || previous.output == " " || previous.attribs & this.IS_ENTER 
                || previous.attribs & this.IS_PREFIX || affixes & this.AFFIX_SUFFIX) {
            add_leading_space := false
        }
        if (add_leading_space) {
            expanded := " " . expanded
        }

        this.Replace(expanded, token_id + replace_offset)
        this.SetTokenAttribs(token_id + replace_offset, this.WAS_EXPANDED)
        if (mark_as_capitalized) {
            this.SetTokenAttribs(token_id + replace_offset, this.WAS_CAPITALIZED)
        }
        if (capitalizes_next) {
            this.SetTokenAttribs(token_id + replace_offset, this.CAPITALIZES_NEXT)
        }

        ; ending smart space
        if (affixes & this.AFFIX_PREFIX) {
            this.SetTokenAttribs(token_id + replace_offset, this.IS_PREFIX)
        } else {
            if (settings.spacing & SPACE_AFTER_CHORD) {
                this._AddSmartSpace()
            }
        }
        if (! (affixes & (this.AFFIX_PREFIX | this.AFFIX_SUFFIX))) {
            score.Score(score.ENTRY_CHORD)
        }
        return true
    }

    ; Remove characters of non-existing chord if 'delete mistyped chords' option is enabled.
    _RemoveRawChord() {
        if !(settings.chording & CHORD_DELETE_UNRECOGNIZED) {
            return false
        }
        ; Note: When "Restrict chords while typing" and "Delete mistyped chords" are both enabled and a non-existing chord is
        ; registered while typing a word, this input is left alone because it is safe to assume it was intended as normal
        ; typing.
        if (settings.chording & CHORD_RESTRICT && this._IsRestricted(io_tokens.Length()-1) ) {
            Return false
        }
        io_tokens.Pop()
        Return true
    }

    TryImmediateShorthand(last_token_offset := 0) {
        loop_length := io_tokens.Length() - 1
        Loop %loop_length%
        {
            text := this.GetOutput(A_Index+1, io_tokens.Length() + last_token_offset)
            if ( this.expansion_in_last_get || this._IsRestricted(A_Index) ) {
                continue
            }
            if ( this.ShorthandModule(text, A_Index+1, last_token_offset) ) {
                return true
            }
        }
    }

    ShorthandModule(text, first_token_id, offset := -1) {
        global hint_delay
        if (! (settings.mode & MODE_SHORTHANDS_ENABLED)) {
            return
        }
        attribs := io_tokens[first_token_id - 1].attribs
        if ( attribs & this.IS_INTERRUPT
                || (attribs & this.WAS_EXPANDED && !(attribs & this.IS_PREFIX)) ) {
            return
        }
        expanded := shorthands.LookUp(text)
        if (expanded) {
            hint_delay.Shorten()
            ; capitalize the whole word on Caps Lock or the first character as needed
            if (GetKeyState("CapsLock", "T")) {
                expanded := Format("{:U}", expanded)
                this.SetTokenAttribs(first_token_id, this.WAS_CAPITALIZED)
            } else if ( this.TestTokenAttribs(first_token_id, this.WITH_SHIFT)
                    || ( ( settings.capitalization != CAP_OFF) && this._ShouldCapitalize(first_token_id) ) ) {
                expanded := RegExReplace(expanded, "(^.)", "$U1")
                this.SetTokenAttribs(first_token_id, this.WAS_CAPITALIZED)
            }
            ; Ignore strings such as USD, or aptX
            if ( this._DetectShiftWithin(first_token_id + 1, io_tokens.Length() + offset) ) {
                return
            }
            affixes := this._DetectAffixes(expanded)
            capitalizes_next := this._DetectCapitalizesNext(expanded)
            expanded := this._RemoveCapitalizesNextSymbol(expanded)
            expanded := this._RemoveAffixSymbols(expanded, affixes)
            first_token_offset := affixes & this.AFFIX_SUFFIX ? -1 : 0 
            this.Replace(expanded, first_token_id + first_token_offset, io_tokens.Length() + offset)
            this.SetTokenAttribs(first_token_id + first_token_offset, this.WAS_EXPANDED)
            if (capitalizes_next) {
                this.SetTokenAttribs(first_token_id + first_token_offset, this.CAPITALIZES_NEXT)
            }
            return true
        }
    }

    HintModule(text, first_token_id) {
        global hint_delay
        if ( settings.hints & HINT_OFF || ! (hint_delay.HasElapsed()) ) {
            return
        }
        if ( this.TestTokenAttribs(first_token_id - 1, this.WAS_EXPANDED | this.IS_INTERRUPT) ) {
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

    _IsRestricted(token_id) {
        ; If last output was automated (smart space or chord), punctuation, a 'prefix' (which  includes opening
        ; punctuation), it was interrupted, after Enter, or it was a space, we can also go ahead.
        if ( this.TestTokenAttribs(token_id, this.WAS_EXPANDED | this.IS_PUNCTUATION | this.IS_PREFIX
                | this.IS_INTERRUPT | this.IS_MANUAL_SPACE | this.IS_ENTER | this.SMART_SPACE_AFTER) ) {
            return false
        }
        return true
    }

    _ShouldCapitalize(start := 0) {
        if (start == 0) {
            start := io_tokens.Length()
        }
        ; first character after Enter
        if (start == 2 && (io_tokens[start - 1].attribs & this.IS_ENTER) ) {
            return true
        }
        if (start > 2 && this.GetOutput(start - 1, start - 1) == " ") {
            if (this.TestTokenAttribs(start - 2, this.CAPITALIZES_NEXT)) {
                return true
            }
            preceding := io_tokens[start - 2].input
            with_shift := this.TestTokenAttribs(start - 2, this.WITH_SHIFT)
            if ( StrLen(preceding)==1 && (!with_shift && InStr(keys.capitalizing_plain, preceding))
                || (with_shift && InStr(keys.capitalizing_shift, preceding)) ) {
                return true
            }
        }
        if (start > 1 && this.TestTokenAttribs(start - 1, this.CAPITALIZES_NEXT)) {
            return true
        }
        ; Capitalize chords after sentence-ending punctuation should even a preceding space.
        if ( start > 1 && this.TestTokenAttribs(start, this.CHORD_CANDIDATE) ) {
            preceding := io_tokens[start - 1].input
            with_shift := this.TestTokenAttribs(start - 1, this.WITH_SHIFT)
            if ( StrLen(preceding)==1 && (!with_shift && InStr(keys.capitalizing_plain, preceding))
                || (with_shift && InStr(keys.capitalizing_shift, preceding)) ) {
                return true
            }
        }
        return false
    }

    _DetectShiftWithin(start_token_id, end_token_id) {
        if (start_token_id > end_token_id) {
            ; edge case with a chord used in typing a short shorthand
            return false
        }
        token_id := start_token_id
        if (end_token_id > io_tokens.Length()) {
            MsgBox ,, % "ZipChord", % "Error: The function _DetectShiftWithin was called with incorrect end range."
            Return false
        }
        Loop {
            if (this.TestTokenAttribs(token_id, this.WITH_SHIFT)) {
                return true
            }
            if (token_id++ >= end_token_id) {
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
        smart_space := new clsToken
        smart_space.input := ""
        smart_space.output := " "
        smart_space.attribs |= this.SMART_SPACE_AFTER
        io_tokens.Push(smart_space)
    }

    _SendOutput(sequence) {
        if (settings.output_delay) {
            Sleep settings.output_delay
        }
        SendInput % sequence
    }
    
    ProcessOutput(sequence, symbol_sequence := "") {
        if (A_Args[1] != "dev") {
            this._SendOutput(sequence)
        } else {
            if (symbol_sequence != "") {
                test.Log("~" . symbol_sequence)
            } else {
                test.Log(sequence)
            }
            if (test.mode != TEST_RUNNING) {
                this._SendOutput(sequence)
            }
        }
    }
    
    SendTokensAsKeys(start) {
        global symbol_to_SC_map

        end := io_tokens.Length()
        count := end - start + 1
        i := start
        Loop % count {
            token := io_tokens[i++]

            if (token.attribs & (this.TOMBSTONED | this.IS_INTERRUPT | this.IS_ENTER)) {
                continue
            }

            if (token.attribs & (this.SMART_SPACE_AFTER | this.IS_MANUAL_SPACE)) {
                this.ProcessOutput("{Space}")
                continue
            }

            if (token.attribs & this.IS_PUNCTUATION) {
                ; exception -- I take token.input to send as original key press, while .output stores potentially the 'shifted' char.
                SC_key := str.SCHexToString(symbol_to_SC_map[token.input])
                SC_prefix := token.attribs & this.WITH_SHIFT ? "+" : ""
                this.ProcessOutput(SC_prefix . "{" . SC_key . "}", SC_prefix . token.input)
                continue
            }

            if (token.attribs & (this.WAS_EXPANDED | this.WAS_CAPITALIZED)) {
                this.ProcessOutput("{Text}" . token.output)
                continue
            }
        
            if ! (symbol_to_SC_map.HasKey(token.output)) {
                ; TK -- should remove
                MsgBox , , % "ERROR with attribs: " . token.attribs
                continue
            }

            SC_key := str.SCHexToString(symbol_to_SC_map[token.output])
            SC_prefix := token.attribs & this.WITH_SHIFT ? "+" : ""
            this.ProcessOutput(SC_prefix . "{" . SC_key . "}", SC_prefix . token.output)
        }
    }

    DebugTokens() {
        if (A_Args[2] != "test-vs") {
            return
        }
        OutputDebug, % "`n`nTokens:"
        For i, token in io_tokens {
            OutputDebug, % "`n" . i . ": " token.input . " > " . token.output . " (" . token.attribs . ")"
        }
    }
}
