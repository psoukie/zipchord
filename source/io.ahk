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

Class clsTokenTypeEnum {
    CHARACTER       := 0
    INTERRUPT       := 1
    ENTER           := 2
    MANUAL_SPACE    := 3
    SMART_SPACE     := 4
    NUMERAL         := 5
    PUNCTUATION     := 6
    EXPANSION       := 7
}

Class clsTokenAttribsBitSet {
    WITH_SHIFT       := 1
    WAS_CAPITALIZED  := 2
    IS_PREFIX        := 4
    CAPITALIZES_NEXT := 8
    FIRST_IN_CHORD   := 16
    TOMBSTONED       := 32
}

Class clsAffixBitSet {
    AFFIX_NONE   := 0   ; no prefix or suffix
    AFFIX_PREFIX := 1   ; expansion is a prefix
    AFFIX_SUFFIX := 2   ; expansion is a suffix
}

Class clsToken {
    type    := 0     ; of clsTokenType 
    input   := ""
    output  := ""
    attribs := 0     ; of clsAttribs
}

Class clsChordCandidate {
    candidate   := ""
    token_count := 0
    with_shift  := false
}

global TokenType := new clsTokenTypeEnum
global TokenAttribs := new clsTokenAttribsBitSet
global AffixPos := new clsAffixBitSet

global io_keys := []         ; window of overlapping key events 
global io_keys_index := {}   ; indexes _buffer:  _events_index[{key}] points to that key's record in _buffer
first_lift := 0              ; acts as a union of bool (0 - false), and int for first lifted key index 

global io_tokens := []       ; window of tokenized input
global io_chord := new clsChordCandidate
io_new_tokens := []
io_prev_tokens := []

Shift_key() {
    global io
    Critical
    if (A_PriorHotkey != "~Shift") {
        return
    }
    key := "*Shift*"
    if (A_Args[1] == "dev") {
        if (test.mode > TEST_STANDBY) {
            test.Log(key, true)
        }
    }
    if (visualizer.IsOn()) {
        visualizer.Pressed("+", false)
        visualizer.Lifted("+", false)
    }
    io.PreShift()
    Critical Off
}

Simulate_Shift() {
    global io
    io.PreShift()
}

KeyDown() {
    global io
    Critical
    tick := A_TickCount
    key := locale.SCHotkeyToSymbolHotkey(A_ThisHotkey)
    if (key == "") {
        Critical Off
        Return
    }
    if (A_Args[1] == "dev") {
        if (test.mode == TEST_RUNNING) {
            key := locale.SCHotkeyToSymbolHotkey(test_key)
            tick := test_timestamp
        }
        if (test.mode > TEST_STANDBY) {
            test.Log(key, true)
            test.Log(key)
        }
    }
    if (visualizer.IsOn()) {
        modified_key := StrReplace(key, "Space", " ")
        if (SubStr(modified_key, 1, 1) == "~")
            modified_key := SubStr(modified_key, 2)
        ; First, we differentiate if the key was pressed while holding Shift, and store it under 'modified_key':
        if ( StrLen(modified_key)>1 && SubStr(modified_key, 1, 1) == "+" ) {
            shifted := true
            modified_key := SubStr(modified_key, 2)
        } else {
            shifted := false
        }
        visualizer.Pressed(modified_key, shifted)
    }
    ; QPC()
    io.ProcessKey(key, tick)
    ; QPC()
    Critical Off
}

KeyUp() {
    global io
    Critical
    tick_up := A_TickCount
    key := locale.SCHotkeyToSymbolHotkey(A_ThisHotkey)
    if (key == "") {
        Critical Off
        Return
    }
    if (A_Args[1] == "dev") {
        if (test.mode == TEST_RUNNING) {
            tick_up := test_timestamp
            key := locale.SCHotkeyToSymbolHotkey(test_key)
        }
        if (test.mode > TEST_STANDBY) {
            test.Log(key, true)
        }
    }
    if (visualizer.IsOn()) {
        modified_key := StrReplace(key, "Space", " ")
        if (SubStr(modified_key, 1, 1) == "~")
            modified_key := SubStr(modified_key, 2)
        if ( StrLen(modified_key)>1 && SubStr(modified_key, 1, 1) == "+" ) {
            shifted := true
            modified_key := SubStr(modified_key, 2)
        } else {
            shifted := false
        }
        visualizer.Lifted(SubStr(modified_key, 1, 1), shifted)
    }
    ; QPC()
    if (io.ProcessKey(key, tick_up)) {
        edits := io.ProcessTokens() 
        if (edits.Count() > 0) {
            io.ProcessEdits(edits)
        }
    }
    ; QPC()
    Critical Off
}

Interrupt() {
    global io
    io.ClearTokens("*Interrupt*")
    if (A_Args[1] == "dev") {
        if (test.mode > TEST_STANDBY) {
            test.Log("*Interrupt*", true)
            test.Log("*Interrupt*")
        }
    }
}

Enter_key() {
    global io
    io.ClearTokens("~Enter")
    if (A_Args[1] == "dev") {
        if (test.mode > TEST_STANDBY) {
            test.Log("~Enter", true)
            test.Log("~Enter")
        }
        if (visualizer.IsOn())
            visualizer.NewLine()
    }
}

Backspace_key() {
    HandleBackspace()
}

Ctrl_Backspace_key() {
    HandleBackspace(true)
}

HandleBackspace(with_ctrl := false) {
    global io
    Critical
    key  := with_ctrl ? "~^Backspace" : "~Backspace"

    if (A_Args[1] = "dev") {
        if (test.mode > TEST_STANDBY) {
            test.Log(key, true)
            test.Log(key)
        }
    }

    if (visualizer.IsOn()) {
        sym := Chr(0x232B)
        visualizer.Pressed(sym, false)
        visualizer.Lifted(sym, false)
    }

    io.Backspace(with_ctrl)
    Critical Off
}

io := new clsIOrepresentation

Class clsIOrepresentation {
    SEQUENCE_WINDOW := 11
    pre_shifted := false
    expansion_in_last_get := false


    IOKeysReset() {
        global first_lift
        
        io_keys := []
        io_keys_index := {}
        first_lift := false
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
            ev.key := SubStr(ev.key, 1, StrLen(ev.key) - 3)
        }

        ev.key := (StrLen(ev.key) > 1) ? "{" . ev.key . "}" : ev.key

        if (is_key_down) {
            ; Process a key down event
            ev.start := timestamp
            if (this.pre_shifted) {
                ev.with_shift := true
                this.pre_shifted := false
            }
            ; ignore if the key is already registered
            if (io_keys_index.HasKey(ev.key)) {
                return
            }
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
                io_keys_index.Delete(key)
                continue
            }
            io_keys_index[key] := index - count
        }
    }

    KeyToToken(key) {
        token := new clsToken
        entry := "" . key.key
        token.input := entry
        if (key.with_shift) {
            token.attribs |= TokenAttribs.WITH_SHIFT
            token.output := str.ToAscii(entry, ["Shift"])
        } else {
            token.output := entry
        }
    
        if ( !key.with_shift && InStr(locale.punctuation_plain, entry) )
                || ( key.with_shift && InStr(locale.punctuation_shift, entry) ) {
            token.type := TokenType.PUNCTUATION
        }
        if (entry == " ") {
            token.type := TokenType.MANUAL_SPACE
        }
        ; TK - this check needs to be modified (0123... need to be locale definable)
        if (!key.with_shift && InStr("0123456789⓪①②③④⑤⑥⑦⑧⑨", entry)) {
            token.type := TokenType.NUMERAL
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
        accum_input := ""

        io_length := io_keys.Length()
        io_chord.token_count := io_length
        Loop, % io_length
        {
            key := io_keys[A_Index] 
            accum_input .= key.key
            if (key.with_shift) {
                io_chord.with_shift := true
            }
            token := this.KeyToToken(key)
            if (A_Index == 1) {
                token.attribs |= TokenAttribs.FIRST_IN_CHORD
            }
            io_new_tokens.Push(token)
        }
             
        ; If Shift is allowed as a separate key in chords, we add it as part of the sequence.
        if (settings.chording & CHORD_ALLOW_SHIFT && io_chord.with_shift) {
            accum_input := "+" . accum_input
            io_chord.with_shift := false
        }
    
        ; Sort to allow matching against chord dictionaries        
        if (dll.available) {
            io_chord.candidate := dll.NormalizeChord(accum_input)
        } else {
            io_chord.candidate := str.Arrange(accum_input)
        }

        this.IOKeysReset()
    }

    ; Detect rolling typing
    _IsRollingTyping() {
        global first_lift
        first_lift_end := io_keys[first_lift].end
        Loop, % io_keys.Length() - first_lift
        {
            if (io_keys[first_lift + A_Index].start > first_lift_end) {
                return true
            }
        }
        return false
    }

    ; Identifies chords based on the overlap of the first two keys in the chord
    ; with a "rolling typing" protection if more keys were pressed after the first lift.
    _ClassifyByDuration(end, lifted_index) {
        global first_lift

        if (! first_lift) {
            first_lift := lifted_index
            return false
        }
        
        ; Determine the overlap of the first two keys
        overlap_end := end
        Loop 2 {
            if (key_end := io_keys[A_Index].end) {
                overlap_end := Min(overlap_end, key_end)
            }
        }
        ; treat as keys if overlap is too short or we have rolling typing 
        if (overlap_end - io_keys[2].start <= settings.input_delay
                || this._IsRollingTyping()) {
            this.AddKeysToTokens(io_keys.Length())
        } else {
            this.AddChordToTokens()
        }
        return true
    }

    _ClassifyByPercentage(end, lifted_index) {
        ; test the full buffer then drop earlier keys
        common_overlap := end - io_keys[io_keys.Length()].start
        
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

    _Classify(end, lifted_index) {  ; -> bool if keys is empty and ready for token processing
        if (io_keys.Length() == 1) {
            ; process a lone key press in io_keys
            this.AddKeysToTokens(1)
            return true
        }
    
        ; two or more keys were pressed as a potential chord
        if (settings.chording & CHORD_BY_OVERLAP) {
            this._ClassifyByPercentage(end, lifted_index)
            return io_keys.Length() == 0
        } else {
            return this._ClassifyByDuration(end, lifted_index)
        }
    }

    PreShift() {
        this.pre_shifted := !this.pre_shifted
        ; and we cheat to allow shorthands:
        if (LastToken().type == TokenType.INTERRUPT) {
            LastToken().type := TokenType.MANUAL_SPACE
        }
    }
    __New() {
        this.ClearTokens("*Interrupt*")
    }

    ClearTokens(type) {
        this.IOKeysReset()
        io_tokens := []
        new_token := new clsToken

        if (type=="~Enter") {
            new_token.type := TokenType.ENTER
        } else {
            new_token.type := TokenType.INTERRUPT
        }
        if (visualizer.IsOn()) {
            visualizer.NewLine()
        }
        io_tokens.Push(new_token)
    }

    ShortenTokenWindow() {
        items_to_remove := LastTokenId() - this.SEQUENCE_WINDOW
        if (items_to_remove < 1) {
            return
        }
        io_tokens.RemoveAt(1, items_to_remove)
        return        
    }

    Replace(new_output, start := 1, end := -1) {
        if (end == -1) {
            end := LastTokenId()
        }
        if (start != end) {
            Loop, % end - start
            {
                index := A_Index + start
                io_tokens[start].input .= "|" . io_tokens[index].input 
                io_tokens[index].attribs |= TokenAttribs.TOMBSTONED
            }
        }
        io_tokens[start].output := new_output
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
            end := LastTokenId() 
        }
        if (start > LastTokenId() || end > LastTokenId()) {
            MsgBox, , % "ZipChord", "IO Representation error: Requested getting tokens that exceed the length of _io_tokens."
            Return true
        }
        count := end - start + 1
        representation := ""
        Loop, %count%
        {
            index := A_Index + start - 1
            if (io_tokens[index].attribs & TokenAttribs.TOMBSTONED) {
                continue
            }
            if (io_tokens[index].type == TokenType.EXPANSION) {
                this.expansion_in_last_get := true
            }
            representation .= separator . io_tokens[index][what]
        }
        return SubStr(representation, StrLen(separator)+1)
    }

    Backspace(with_ctrl := false) {
        if ( LastTokenId() < 2 || LastToken().type == TokenType.EXPANSION || with_ctrl ) {
            this.ClearTokens("*Interrupt*")
            return
        }
        while (LastToken().attribs & TokenAttribs.TOMBSTONED) {
            io_tokens.Pop()
        }
        token := LastToken()
        if (token.type == TokenType.EXPANSION && StrLen(token.output) > 1) {
            ; TK Can possibly misbehave with a chained chord later since we're leaving .input as is
            token.output := SubStr(token.output, 1, StrLen(token.output) - 1)
            return
        }

        io_tokens.Pop()
    }

    _FindFirstModifiedToken() {
        global io_prev_tokens
        
        for index, prev_token in io_prev_tokens {
            if (index > LastTokenId()) {
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
            if (io_prev_tokens[index].attribs & TokenAttribs.TOMBSTONED) {
                continue
            }
            length += StrLen(io_prev_tokens[index].output)
        }
        return length
    }

    _PushTokenClone(token) {
        global io_prev_tokens

        token_copy := new clsToken
        for key, value in token {
            token_copy[key] := value
        }
        ; Exclude FIRST_IN_CHORD so resolving a rejected candidate does not create a false edit indication.
        token_copy.attribs &= ~TokenAttribs.FIRST_IN_CHORD
        io_prev_tokens.Push(token_copy)
    }
    
    _CopyTokensIntoPrev() {
        global io_prev_tokens
        global io_new_tokens

        io_prev_tokens := []
        for _, token in io_tokens {
            this._PushTokenClone(token)
        }
        for _, token in io_new_tokens {
            this._PushTokenClone(token)
        }
    }

    ProcessTokens() {
        global io_prev_tokens
        global io_new_tokens

        edits := []
        tokens_to_ignore := 0
        this._CopyTokensIntoPrev()

        ; TK - 'SPACE + W' does not work as chord
        while (io_new_tokens.Length() > 0) {
            if (tokens_to_ignore > 0) {
                io_new_tokens.RemoveAt(1)
                tokens_to_ignore -= 1
                continue
            }
            token := io_new_tokens[1]
            io_tokens.Push(token)
            io_new_tokens.RemoveAt(1)
            tokens_to_ignore := this.ProcessLastToken()
        }
        io_chord := new clsChordCandidate  ; reset io_chord

        first_modified := this._FindFirstModifiedToken()
        if (first_modified == -1) {
            return edits  ; no changes
        }

        edits := this.PrepareEdits(first_modified)
        this.ShortenTokenWindow()

        return edits
    }

    ProcessLastToken() {   ; -> int tokens_to_ignore
        tokens_to_ignore := 0
        token := LastToken()

        if (token.attribs & TokenAttribs.FIRST_IN_CHORD) {
            ; Process a chord (which is the last or only token)
            backup_input := token.input
            token.input := io_chord.candidate
            tokens_to_ignore := io_chord.token_count - 1
            if (this.TryChordModule()) {
                token.attribs &= ~TokenAttribs.FIRST_IN_CHORD
                return tokens_to_ignore
            }

            token.input := backup_input
            if (this._RemoveRawChord()) {
                ; if we removed the chord, the first key was popped and we ignore the rest
                return tokens_to_ignore
            }
        }

        token.attribs &= ~TokenAttribs.FIRST_IN_CHORD
        tokens_to_ignore := 0

        ; Process a char
        this._CapitalizeTypingAsNeeded(token)
        this._RemoveSmartSpaceAsNeeded(token)
        ; now, the slightly chaotic immediate mode allowing shorthands triggered as soon as they are completed:
        if (settings.chording & CHORD_IMMEDIATE_SHORTHANDS) {
            this._TryShorthandsAndHints(false, true)
        }

        if (this._DeDoubleSpace()) {
            return tokens_to_ignore
        }
        this._ProcessShorthands(token)
        this._AddSpaceAfterPunctuation()
        return tokens_to_ignore
    }

    _TryShorthandsAndHints(with_hints := false, include_last_token := false) {
        last_token_offset := include_last_token ? 0 : -1
        loop_length := LastTokenId() - 1
        Loop %loop_length%
        {
            text := this.GetOutput(A_Index+1, LastTokenId() + last_token_offset)
            if (this.expansion_in_last_get || this._IsRestricted(A_Index)) {
                continue
            }
            if (this.ShorthandModule(text, A_Index + 1, last_token_offset)) {
                return true
            }
            if (with_hints && this._HintModule(text, A_Index + 1)) {
                return false
            }
        }
        return false
    }

    _ProcessShorthands(token) {
        ; Process shorthands only if we have a space or punctuation
        if (token.type != TokenType.MANUAL_SPACE && token.type != TokenType.PUNCTUATION) {
            return
        }
        
        if (this._TryShorthandsAndHints(true)) {
            score.Score(score.ENTRY_SHORTHAND)
        } else {
            prev_type := PreviousLiveToken().type
            if (prev_type != TokenType.MANUAL_SPACE && prev_type != TokenType.PUNCTUATION) {
                score.Score(score.ENTRY_MANUAL)
            }
        }
    }

    _CapitalizeTypingAsNeeded(token) {
        character := token.input
        if (StrLen(character) != 1) {
            return
        }
        if ( settings.capitalization != CAP_ALL
                || token.type == TokenType.PUNCTUATION
                || token.type == TokenType.MANUAL_SPACE
                || token.attribs & TokenAttribs.WITH_SHIFT ) {
            return
        }

        ; do not capitalize numerals
        if (token.type == TokenType.NUMERAL) {
            return
        }

        if ( this._ShouldCapitalize() ) {
            token.output := RegExReplace(character, "(^.)", "$U1")
            token.attribs |= TokenAttribs.WAS_CAPITALIZED
        }
    }

    _RemoveSmartSpaceAsNeeded(token) {
        if (PreviousLiveToken().type != TokenType.SMART_SPACE) {
            return
        }

        attribs := token.attribs
        type := token.type
        ; for punctuation that removes spaces
        if (type == TokenType.PUNCTUATION) {
            if ( (!(attribs & TokenAttribs.WITH_SHIFT)
                && InStr(locale.remove_space_plain, token.input))
                || ((attribs & TokenAttribs.WITH_SHIFT)
                && InStr(locale.remove_space_shift, token.input)) ) {
                io_tokens.RemoveAt(PreviousLiveTokenId())   ; not tombstoning because we've just added it
                return true
            }
        }
        
        ; for manual_space-punctuation-numeral and numeral-punctuation-numeral
        before_space_token := PreviousLiveToken(2)
        if (type != TokenType.NUMERAL
                || before_space_token == -1
                || before_space_token.type != TokenType.PUNCTUATION) {
            return false
        }
        
        before_punct_token := PreviousLiveToken(3)
        if (before_punct_token == -1) {
            return false
        }
        before_punct_type := before_punct_token.type
        if (before_punct_type == TokenType.NUMERAL
                || before_punct_type == TokenType.MANUAL_SPACE
                || before_punct_type == TokenType.ENTER) {
            io_tokens.RemoveAt(PreviousLiveTokenId())
            return true
        }

        return false
    }

    _AddSpaceAfterPunctuation() {
        token := LastToken()
        attribs := token.attribs
        if ( !(settings.spacing & SPACE_PUNCTUATION)
                || token.type != TokenType.PUNCTUATION
                || PreviousLiveToken().type == TokenType.INTERRUPT ) {
            return
        }
        if (( !(attribs & TokenAttribs.WITH_SHIFT) && InStr(locale.space_after_plain, token.input) )
                || (attribs & TokenAttribs.WITH_SHIFT) && InStr(locale.space_after_shift, token.input) ) {
            this._AddSmartSpace()
        }
    }

    ; Remove a double space if the user types a space after punctuation smart space
    _DeDoubleSpace() {
        if ( PreviousLiveToken().type == TokenType.SMART_SPACE
                && LastToken().type == TokenType.MANUAL_SPACE ) {
            io_tokens.RemoveAt(PreviousLiveTokenId())
            return true
        }
        return false
    }

    TryChordModule() {
        if (! (settings.mode & MODE_CHORDS_ENABLED)) {
            return false
        }
        Loop % LastTokenId()
        {
            if (io_tokens[A_Index].type == TokenType.INTERRUPT || io_tokens[A_Index].type == TokenType.ENTER) {
                continue
            }
            candidate := this.GetInput(A_Index)
            if (StrLen(candidate) < 2) {
                return false
            }
            candidate := StrReplace(candidate, "||", "|")
            expanded := chords.LookUp(candidate)
            if (expanded) {
                ; check whether chord is used to complete typing of a shorthand
                if (this._TryShorthandsAndHints()) {
                    return this._ExpandChord(LastTokenId(), expanded) 
                }
                return this._ExpandChord(A_Index, expanded)
            }
        }
    }

    _ExpandChord(token_id, expanded) {
        global hint_delay
        mark_as_capitalized := false
        add_leading_space := true
        tb_replaced_id := token_id

        hint_delay.Shorten()

        ; capitalize the whole word on Caps Lock or the first character as needed
        if (GetKeyState("CapsLock", "T")) {
            expanded := Format("{:U}", expanded)
            mark_as_capitalized := true
        } else if ( io_tokens[token_id].attribs & TokenAttribs.WITH_SHIFT
                || io_tokens[token_id].attribs & TokenAttribs.WAS_CAPITALIZED
                || io_chord.with_shift
                || ( settings.capitalization != CAP_OFF && this._ShouldCapitalize(token_id) ) ) {
            expanded := RegExReplace(expanded, "(^.)", "$U1")
            mark_as_capitalized := true
        }
        ; detect affixes to handle opening and closing smart spaces correctly
        affixes := this._DetectAffixes(expanded)
        capitalizes_next := this._DetectCapitalizesNext(expanded)
        expanded := this._RemoveCapitalizesNextSymbol(expanded)
        expanded := this._RemoveAffixSymbols(expanded, affixes)
        previous_id := PreviousLiveTokenId(1, token_id)
        prev_token := io_tokens[previous_id]

        if ( (settings.chording & CHORD_RESTRICT)
                && this._IsRestricted(previous_id)
                && !(affixes & AffixPos.AFFIX_SUFFIX) ) {
            return false
        }
        
        ; if there is a smart space, we set the edit point to it for suffixes
        if (prev_token.type == TokenType.SMART_SPACE) {
            add_leading_space := false
            if (affixes & AffixPos.AFFIX_SUFFIX) {
                tb_replaced_id := previous_id
            }
        }
        ; if adding smart spaces before is disabled, we don't add it
        if (! (settings.spacing & SPACE_BEFORE_CHORD)) {
            add_leading_space := false
        }
        
        ; if the last output was punctuation that does not ask for a space
        if ( ( !(prev_token.attribs & TokenAttribs.WITH_SHIFT)
                && InStr(locale.punctuation_plain, prev_token.input)
                && !InStr(locale.space_after_plain, prev_token.input) )
                || (prev_token.attribs & TokenAttribs.WITH_SHIFT)
                && InStr(locale.punctuation_shift, prev_token.input)
                && !InStr(locale.space_after_shift, prev_token.input) )  {
            add_leading_space := false
        }
        
        ; and we don't add a space after interruption, Enter, a space, after a prefix, and for suffix
        if (prev_token.type == TokenType.INTERRUPT
                || prev_token.type == TokenType.ENTER 
                || prev_token.output == " "
                || prev_token.attribs & TokenAttribs.IS_PREFIX
                || affixes & AffixPos.AFFIX_SUFFIX) {
            add_leading_space := false
        }
        if (add_leading_space) {
            expanded := " " . expanded
        }

        this.Replace(expanded, tb_replaced_id)
        io_tokens[tb_replaced_id].type := TokenType.EXPANSION
        if (mark_as_capitalized) {
            io_tokens[tb_replaced_id].attribs |= TokenAttribs.WAS_CAPITALIZED
        }
        if (capitalizes_next) {
            io_tokens[tb_replaced_id].attribs |= TokenAttribs.CAPITALIZES_NEXT
        }

        ; ending smart space
        if (affixes & AffixPos.AFFIX_PREFIX) {
            io_tokens[tb_replaced_id].attribs |= TokenAttribs.IS_PREFIX
        } else {
            if (settings.spacing & SPACE_AFTER_CHORD) {
                this._AddSmartSpace()
            }
        }
        if (! (affixes & (AffixPos.AFFIX_PREFIX | AffixPos.AFFIX_SUFFIX))) {
            score.Score(score.ENTRY_CHORD)
        }
        return true
    }

    ; Remove characters of non-existing chord if 'delete mistyped chords' option is enabled.
    _RemoveRawChord() {
        if !(settings.chording & CHORD_DELETE_UNRECOGNIZED) {
            return false
        }
        ; Note: When "Restrict chords while typing" and "Delete mistyped chords" are both enabled
        ; and a non-existing chord is detected while typing, we leave the mistyped chord because
        ; it is safe to assume it was intended as normal typing.
        if (settings.chording & CHORD_RESTRICT && this._IsRestricted(PreviousLiveTokenId())) {
            return false
        }
        io_tokens.Pop()
        Return true
    }

    ShorthandModule(text, first_token_id, offset := -1) {
        global hint_delay
        if (! (settings.mode & MODE_SHORTHANDS_ENABLED)) {
            return
        }
        
        prev_type := io_tokens[first_token_id - 1].type
        prev_attribs := io_tokens[first_token_id - 1].attribs
        if ( prev_type == TokenType.INTERRUPT
                || (prev_type == TokenType.EXPANSION && !(prev_attribs & TokenAttribs.IS_PREFIX)) ) {
            return
        }
        
        expanded := shorthands.LookUp(text)
        if (! expanded) {
            return false
        }
        
        hint_delay.Shorten()
        ; capitalize the whole word on Caps Lock or the first character as needed
        if (GetKeyState("CapsLock", "T")) {
            expanded := Format("{:U}", expanded)
            io_tokens[first_token_id].attribs |= TokenAttribs.WAS_CAPITALIZED
        } else if ( io_tokens[first_token_id].attribs & TokenAttribs.WITH_SHIFT
                || ( settings.capitalization != CAP_OFF
                && this._ShouldCapitalize(first_token_id) ) ) {
            expanded := RegExReplace(expanded, "(^.)", "$U1")
            io_tokens[first_token_id].attribs |= TokenAttribs.WAS_CAPITALIZED
        }
        ; Ignore strings such as USD, or aptX
        if ( this._DetectShiftWithin(first_token_id + 1, LastTokenId() + offset) ) {
            return
        }
        affixes := this._DetectAffixes(expanded)
        capitalizes_next := this._DetectCapitalizesNext(expanded)
        expanded := this._RemoveCapitalizesNextSymbol(expanded)
        expanded := this._RemoveAffixSymbols(expanded, affixes)
        first_token_offset := affixes & AffixPos.AFFIX_SUFFIX ? -1 : 0 
        tb_replaced_id := first_token_id + first_token_offset
        this.Replace(expanded, tb_replaced_id, LastTokenId() + offset)
        io_tokens[tb_replaced_id].type := TokenType.EXPANSION
        if (capitalizes_next) {
            io_tokens[tb_replaced_id].attribs |= TokenAttribs.CAPITALIZES_NEXT
        }
        return true
    }

    _HintModule(text, first_token_id) {
        global hint_delay
        if ( settings.hints & HINT_OFF || ! (hint_delay.HasElapsed()) ) {
            return
        }

        prev_type := io_tokens[first_token_id - 1].type
        if (prev_type == TokenType.EXPANSION || prev_type == TokenType.INTERRUPT) {
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
        type := io_tokens[token_id].type
        if ( type == TokenType.EXPANSION || type == TokenType.PUNCTUATION
                || type == TokenType.INTERRUPT || type == TokenType.MANUAL_SPACE
                || type == TokenType.ENTER || type == TokenType.SMART_SPACE ) {
            return false
        }
        
        if (io_tokens[token_id].attribs & TokenAttribs.IS_PREFIX) {
            return false
        }

        return true
    }

    _ShouldCapitalize(start := 0) {
        if (start == 0) {
            start := LastTokenId()
        }
        previous_token := PreviousLiveToken(1, start)
        if (previous_token == -1) {
            return false
        }

        ; first character after Enter
        if (previous_token.type == TokenType.ENTER
            || previous_token.attribs & TokenAttribs.CAPITALIZES_NEXT) {
            return true
        }

        ; Capitalize chords after sentence-ending punctuation should even a preceding space.
        if (io_tokens[start].attribs & TokenAttribs.FIRST_IN_CHORD) {
            prev_input := previous_token.input
            with_shift := previous_token.attribs & TokenAttribs.WITH_SHIFT
            if (StrLen(prev_input) == 1
                && (!with_shift && InStr(locale.capitalizing_plain, prev_input))
                || (with_shift && InStr(locale.capitalizing_shift, prev_input)) ) {
                return true
            }
        }
        
        before_previous_token := PreviousLiveToken(2, start)
        if (before_previous_token == -1) {
            return false
        }
        if (previous_token.output == " ") {
            if (before_previous_token.attribs & TokenAttribs.CAPITALIZES_NEXT) {
                return true
            }
            before_prev_input := before_previous_token.input
            with_shift := before_previous_token.attribs & TokenAttribs.WITH_SHIFT
            if ( StrLen(before_prev_input) == 1
                && (!with_shift && InStr(locale.capitalizing_plain, before_prev_input))
                || (with_shift && InStr(locale.capitalizing_shift, before_prev_input)) ) {
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
        if (end_token_id > LastTokenId()) {
            MsgBox ,, % "ZipChord", % "Error: The function _DetectShiftWithin was called with incorrect end range."
            Return false
        }
        Loop {
            if (io_tokens[token_id].attribs & TokenAttribs.WITH_SHIFT) {
                return true
            }
            if (token_id++ >= end_token_id) {
                return false
            }
        }
    }

    ; detect and adjust expansion for suffixes and prefixes
    _DetectAffixes(phrase) {
        affixes := AffixPos.AFFIX_NONE
        if (SubStr(phrase, 1, 1) == "~") {
            affixes |= AffixPos.AFFIX_SUFFIX
        }
        if (SubStr(phrase, 0) == "~" || SubStr(phrase, -1) == "~^") {
            affixes |= AffixPos.AFFIX_PREFIX
        }
        Return affixes
    }
    _RemoveAffixSymbols(text, affixes) {
        if (affixes & AffixPos.AFFIX_SUFFIX) {
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
        smart_space.type := TokenType.SMART_SPACE
        io_tokens.Push(smart_space)
    }

    PrepareEdits(start) {
        global symbol_to_SC_map
        io_edits := []

        DebugTokens()
        chars_to_del := this._GetPrevRemainingLength(start)
        if (chars_to_del > 0) {
            io_edits.Push("{Backspace " . chars_to_del . "}")
        }

        end := LastTokenId()
        count := end - start + 1
        i := start
        Loop % count {
            token := io_tokens[i++]

            if (token.attribs & TokenAttribs.TOMBSTONED
                    || token.type == TokenType.INTERRUPT
                    || token.type == TokenType.ENTER) {
                continue
            }

            if (token.type == TokenType.SMART_SPACE || token.type == TokenType.MANUAL_SPACE) {
                io_edits.Push("{Space}")
                continue
            }

            if (token.type == TokenType.PUNCTUATION) {
                ; exception -- I take token.input to send as original key press, while .output stores potentially the 'shifted' char.
                SC_key := str.SCHexToString(symbol_to_SC_map[token.input])
                SC_prefix := token.attribs & TokenAttribs.WITH_SHIFT ? "+" : ""
                io_edits.Push(SC_prefix . "{" . SC_key . "}")
                continue
            }

            if (token.type == TokenType.EXPANSION
                    || token.attribs & TokenAttribs.WAS_CAPITALIZED) {
                io_edits.Push("{Text}" . token.output)
                continue
            }
        
            ; Should be a regular tracked key
            if ! (symbol_to_SC_map.HasKey(token.output)) {
                MsgBox, % "ZipChord Error", % "Encountered unexpected error while processing the keys."
                continue
            }

            SC_key := str.SCHexToString(symbol_to_SC_map[token.output])
            SC_prefix := token.attribs & TokenAttribs.WITH_SHIFT ? "+" : ""
            io_edits.Push(SC_prefix . "{" . SC_key . "}")
        }

        return io_edits
    }

    _SendOutput(edit) {
        SendInput % edit
        if (settings.output_delay && test.mode != TEST_RUNNING) {
            Sleep settings.output_delay
        }
    }
    
    ProcessEdits(edits) {
        for _, edit in edits {
            if (A_Args[1] != "dev") {
                this._SendOutput(edit)
            } else {
                test.Log(edit)
                if (test.mode != TEST_RUNNING) {
                    this._SendOutput(edit)
                }
            }
        }
    }
}


; Helper Functions
; 
LastTokenId() {
    return io_tokens.Length()
}

LastToken() {
    return io_tokens[LastTokenId()]
}

PreviousLiveTokenId(count := 1, start_id := -1) {
    ; by default, retrieves the next to last token in io_tokens
    index := start_id == -1 ? LastTokenId() : start_id
    counter := 0
    while (index > 1) {
        index -= 1
        if !(io_tokens[index].attribs & TokenAttribs.TOMBSTONED) {
            counter += 1
            if (counter == count) {
                return index
            }
        }
    }
    return -1  ; indicating no previous live token is in the 'window'
}

PreviousLiveToken(count := 1, start_id := -1) {
    token_id := PreviousLiveTokenId(count, start_id)
    if (token_id == -1) {
        return -1  ; does not exist
    }
    return io_tokens[token_id]
}

DebugTokens() {
    if (A_Args[2] != "test-vs") {
        return
    }
    OutputDebug, % "`n`nTokens:"
    For i, token in io_tokens {
        OutputDebug, % "`n" . i . ": " token.input . " > " . token.output . " (type: " . token.type . ", attribs: " . token.attribs . ")"
    }
}