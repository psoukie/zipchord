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

Class TokenType {
    static UNDEFINED := 0
         , CHARACTER := 1  ; other than those listed below
         , CHORD := 2
         , MANUAL_SPACE := 3
         , NUMERAL := 4
         , PUNCTUATION := 5
}

Class clsToken {
    type := TokenType.UNDEFINED
    raw_input := ""
    input := ""
    output := ""
    attributes := 0
}

global io_keys := []
global io_keys_index := {}         ; indexes _buffer:  _events_index[{key}] points to that key's record in _buffer

global io_tokens := []
global io_tokens_start := 1

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
         , IS_CHORD := 128
         , IS_ENTER := 256
         , IS_INTERRUPT := 512
         , IS_NUMERAL := 1024
         , CAPITALIZES_NEXT := 2048
    ; affixes constants
    static AFFIX_NONE := 0 ; no prefix or suffix
        , AFFIX_PREFIX := 1 ; expansion is a prefix
        , AFFIX_SUFFIX := 2 ; expansion is a suffix


    pre_shifted := false
    expansion_in_last_get := false

    output_buffer := ""  ; stores what will be sent as simulated keystrokes
    
    IO_Keys_Reset() {
        OutputDebug % "`nEMPTYING EVENTS"
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
                this.IO_Keys_Reset()
            }

            return result
        }
        this.DebugTokens()
    }
    
    _Shift_IO_Keys_Window(count) {
        io_keys.RemoveAt(1, count)
        
        for key, index in io_keys_index {
            if (index <= count) {
                OutputDebug % "`nDeleting index for " . key
                io_keys_index.Delete(key)
                continue
            }
            OutputDebug % "`n shifting " . key . " from " index 
            io_keys_index[key] := index - count
            OutputDebug % " to " . io_keys_index[key] 
        }
    }

    ; TK -- needs to be called when parsing individual tokens
    Key_To_Token(key) {
        token := new clsToken
        entry := "" . key.key
        token.raw_input := entry
        token.input := entry
        if (key.with_shift) {
            token.attributes |= this.WITH_SHIFT
            token.output := str.ToAscii(entry, ["Shift"])
        } else {
            token.output := entry
        }
    
        if ( !key.with_shift && InStr(keys.punctuation_plain, entry) )
                || ( key.with_shift && InStr(keys.punctuation_shift, entry) ) {
            token.attributes |= this.IS_PUNCTUATION
            token.type := TokenType.PUNCTUATION
        }
        if (entry == " ") {
            token.attributes |= this.IS_MANUAL_SPACE
            token.type := TokenType.MANUAL_SPACE
        }
        if (!token.with_shift && InStr("0123456789⓪①②③④⑤⑥⑦⑧⑨", entry)) {
            token.attributes |= this.IS_NUMERAL
            token.type := TokenType.NUMERAL
        }
        return token
    }

    Add_Keys_To_Tokens(count) {
        Loop % count {
            key := io_keys[A_Index]
            token := this.Key_To_Token(key)
            io_tokens.Push(token)
        }
        if (count == io_keys.Length()) {
            this.IO_Keys_Reset()
        } else {
            this._Shift_IO_Keys_Window(count)           
        }
    }

    ; Transform key presses into a chord and add to tokens
    Add_Chord_To_Tokens() {
        token := new clsToken
        
        Loop, % io_keys.Length()
        {
            key := io_keys[A_Index] 
            token.raw_input .= key.key     ; store original key tokens
            token.input .= key.key     ; store original key tokens
            token.output .= key.key
            if (key.with_shift) {
                token.attributes |= this.WITH_SHIFT
            }
        }

        token.attributes |= this.IS_CHORD
        token.type := TokenType.CHORD
             
        ;For chords, if Shift is allowed as a separate key in chord key, we add it as part of the entry if it was pressed.
        if ( (settings.chording & CHORD_ALLOW_SHIFT) && (token.attributes & this.WITH_SHIFT) ) {
            token.input := "+" . ev.input
            token.attributes := ev.attributes & ~this.WITH_SHIFT
        }
    
        ; Sort to allow matching against chord dictionaries        
        if (dll.available) {
            token.input := dll.NormalizeChord(token.input)
        } else {
            token.input := str.Arrange(token.input)
        }

        io_tokens.Push(token)
        this.IO_Keys_Reset()
    }

    _ClassifyByDuration(end) {
        ; get and compare against the overlap of the second key in the chord (regardless of chord length)
        start := io_keys[2].start
        if (end - start > settings.input_delay) {
            this.Add_Chord_To_Tokens()
        } else {
            this.Add_Keys_To_Tokens(io_keys.Length())
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
                    this.Add_Keys_To_Tokens(A_Index - 1)
                }
                this.Add_Chord_To_Tokens()
                return
            }
        }
        if (lifted_index == io_keys.Length()) {
            this.Add_Keys_To_Tokens(lifted_index)
        } else {
            this.Add_Keys_To_Tokens(end_iter)
        }
    }

    _Classify(end, index) {  ; -> bool if keys is empty and ready for token processing
        if (io_keys.Length() == 1) {
            ; process a lone key press in io_keys
            this.Add_Keys_To_Tokens(1)
            return true
        }
    
        ; two or more keys were pressed as a potential chord
        if (settings.chording & CHORD_BY_OVERLAP) {
            this._ClassifyByPercentage(end, index)
        } else {
            this._ClassifyByDuration(end)    
        }
        return io_keys.Length() == 0
    }

    PreShift() {
        this.pre_shifted := !this.pre_shifted
        ; and we cheat to allow shorthands:
        if (this.TestTokenAttributes(io_tokens.Length(), this.IS_INTERRUPT)) {
            this.ClearTokenAttributes(io_tokens.Length(), this.IS_INTERRUPT)
            this.SetTokenAttributes(io_tokens.Length(), this.IS_MANUAL_SPACE)
        }
    }
    __New() {
        this.ClearTokens("*Interrupt*")
    }

    AugmentedAdd(entry, with_shift) {
        entry := "" . entry
        token := new clsToken
        token.input := entry
        if (with_shift) {
            token.attributes |= this.WITH_SHIFT
            token.output := str.ToAscii(entry, ["Shift"])
        } else {
            token.output := entry
        }
        if ( !with_shift && InStr(keys.punctuation_plain, entry) )
                || ( with_shift && InStr(keys.punctuation_shift, entry) ) {
            token.attributes |= this.IS_PUNCTUATION
        }
        if (entry == " ") {
            token.attributes |= this.IS_MANUAL_SPACE
        }
        if (!with_shift && InStr("0123456789⓪①②③④⑤⑥⑦⑧⑨", entry)) {
            token.attributes |= this.IS_NUMERAL
        }
        io_tokens.Push(token)
    }

    Combine(start, end) {
        if (start > io_tokens.Length() || end > io_tokens.Length()) {
            MsgBox, , % "ZipChord", "IO Representation error: Requested combining tokens that exceed the length of _io_tokens."
            Return true
        }
        following := start + 1
        count := end - start
        Loop, %count%
        {
            io_tokens[start].input .= "|" . io_tokens[following].input 
            io_tokens[start].output .= io_tokens[following].output
            io_tokens.RemoveAt(following)
        }
    }

    ClearTokens(type := "") {
        this.IO_keys_Reset()
        io_tokens := []

        new_token := new clsToken
        if (type=="~Enter") {
            new_token.attributes := this.IS_ENTER
        }
        if (type=="*Interrupt*") {
            new_token.attributes := this.IS_INTERRUPT
        }
        if (visualizer.IsOn()) {
            visualizer.NewLine()
        }
        io_tokens.Push(new_token)
    }
    Replace(new_output, start := 1, end := 0) {
        if (! end) {
            end := io_tokens.Length()
        }
        if (start != end) {
            this.Combine(start, end)
        }
        old_output := io_tokens[start].output
        io_tokens[start].output := new_output
        this._ReplaceOutput(old_output, new_output, start)
    }

    SetTokenAttributes(token_id, bitmask, set := true) {
        if (set) {
            io_tokens[token_id].attributes |= bitmask
        } else {
            io_tokens[token_id].attributes &= ~bitmask
        }
    }
    ClearTokenAttributes(token_id, bitmask) {
        this.SetTokenAttributes(token_id, bitmask, false)
    }
    TestTokenAttributes(token_id, bitmask) {
        ; purposefully returns true if one of the bitmask conditions are true (therefore, not comparing to bitmask)
        if (token_id > io_tokens.Length() || token_id < 1) {
            return false
        }
        return (io_tokens[token_id].attributes & bitmask)
    }

    GetInput(start := 1, end := 0) {
        return this._Get(start, end)
    }
    GetOutput(start := 1, end := 0) {
        return this._Get(start, end, true)
    }
    _Get(start := 1, end := 0, get_output := false) {
        this._expansion_in_last_get := false
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
        i := start
        Loop, %count%
        {
            if (io_tokens[i].attributes & this.WAS_EXPANDED) {
                this._expansion_in_last_get := true
            }
            representation .= separator . io_tokens[i++][what]
        }
        Return SubStr(representation, StrLen(separator)+1)
    }
    _ReplaceOutput(old_output, new_output, start) {
        if (start != io_tokens.Length()) {
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
        if ( io_tokens.Length() < 2 || this.TestTokenAttributes(io_tokens.Length(), this.WAS_EXPANDED) || with_ctrl ) {
            this.ClearTokens("*Interrupt*")
            return
        }
        if ( this.TestTokenAttributes(io_tokens.Length(), this.IS_CHORD) ) {
            token := io_tokens[io_tokens.Length()]
            token.input := "XX" ; so the token cannot be matched to any chord later
            token.output := SubStr(token.output, 1, StrLen(token.output) - 1)
            if (StrLen(token.output) == 1) {
                token.attributes &= ~this.IS_CHORD
            }
            return
        }
        io_tokens.RemoveAt(io_tokens.Length())
    }

    ; Below are the functions that were first attempt at modules.
    ; When I recreate modules, it should be pure functions only.
    
    ProcessTokens() {
        ; Add code that gets and loops through the new tokens
        if (io_tokens_start >= io_tokens.Length()) {
            ; should not happen
            this.ClearTokens("*Interrupt*")
            return
        }
        loop % io_tokens.Length() - io_tokens_start + 1
        {
            token := io_tokens[A_Index + io_tokens_start - 1]
            if ( token && this.IS_CHORD ) {
                this._ProcessChord()  ; should be the last or only token
            } else {
                this._ProcessToken(token)
            }
        }
    }

    _ProcessToken(token) {
        this.CapitalizeTypingAsNeeded(token.key, token.attributes)
        this.RemoveSmartSpaceAsNeeded(ev.attributes)
        ; now, the slightly chaotic immediate mode allowing shorthands triggered as soon as they are completed:
        if (settings.chording & CHORD_IMMEDIATE_SHORTHANDS) {
            this.TryImmediateShorthand()
        }
    }
    
    _ProcessChord() {
        if (this.ChordModule()) {
            return
        }
        if ( this.TestTokenAttributes(io_tokens.Length(), this.IS_CHORD) ) {
            if (this._RemoveRawChord()) {
                this.OutputKeys()
                return
            }
            this._FixLastToken()
        }
        if (this.DeDoubleSpace()) {
            return
        }
        if ! ( this.TestTokenAttributes(io_tokens.Length(), this.IS_MANUAL_SPACE | this.IS_PUNCTUATION) ) {
            return
        }
        if (this.DoShorthandsAndHints()) {
            score.Score(score.ENTRY_SHORTHAND)
        } else if ! ( this.TestTokenAttributes(io_tokens.Length() - 1, this.IS_MANUAL_SPACE | this.IS_PUNCTUATION) ) {
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
        if ( settings.capitalization != CAP_ALL || (attribs & this.IS_PUNCTUATION)
                || (attribs & this.IS_MANUAL_SPACE) || (attribs & this.WITH_SHIFT) ) {
            return
        }
        if ( this._ShouldCapitalize() ) {
            upper_cased := RegExReplace(character, "(^.)", "$U1")
            this.Replace(upper_cased, io_tokens.Length())
            this.OutputKeys()
            this.SetTokenAttributes(io_tokens.Length(), this.WAS_CAPITALIZED)
        }
    }

    RemoveSmartSpaceAsNeeded(attribs) {
        if ! (this.TestTokenAttributes(io_tokens.Length()-1, this.SMART_SPACE_AFTER)) {
            return
        }
        ; for punctuation that removes spaces
        if (attribs & this.IS_PUNCTUATION) {
            token := io_tokens[io_tokens.Length()]
            if ( (!(token.attributes & this.WITH_SHIFT) && InStr(keys.remove_space_plain, token.input))
                    || ((token.attributes & this.WITH_SHIFT) && InStr(keys.remove_space_shift, token.input)) ) {
                return this._RemoveSmartSpace()
            }
        }
        ; for manual_space-punctuation-numeral and numeral-punctuation-numeral
        if (attribs & this.IS_NUMERAL && this.TestTokenAttributes(io_tokens.Length() - 2, this.IS_PUNCTUATION)
                && this.TestTokenAttributes(io_tokens.Length() - 3, this.IS_NUMERAL | this.IS_MANUAL_SPACE | this.IS_ENTER)) {
            return this._RemoveSmartSpace()
        }
    }

    _RemoveSmartSpace() {
        this.Replace("", io_tokens.Length() - 1, io_tokens.Length() - 1)
        this.OutputKeys()
        io_tokens.RemoveAt(io_tokens.Length() - 1)
        return true
    }

    AddSpaceAfterPunctuation() {
        token := io_tokens[io_tokens.Length()]
        attribs := token.attributes
        if ( !(settings.spacing & SPACE_PUNCTUATION) || this.TestTokenAttributes(io_tokens.Length() - 1, this.IS_INTERRUPT) ) {
            return
        }
        if (( !(attribs & this.WITH_SHIFT) && InStr(keys.space_after_plain, token.input) )
                || (attribs & this.WITH_SHIFT) && InStr(keys.space_after_shift, token.input) ) {
            this._AddSmartSpace()
            this.OutputKeys()
        }
    }

    ; Remove a double space if the user types a space after punctuation smart space
    DeDoubleSpace() {
        if ( this.TestTokenAttributes(io_tokens.Length() - 1, this.SMART_SPACE_AFTER)
                && this.TestTokenAttributes(io_tokens.Length(), this.IS_MANUAL_SPACE) ) {
            io_tokens.RemoveAt(io_tokens.Length() - 1)
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
        } else if ( this.TestTokenAttributes(token_id, this.WITH_SHIFT)
                || this.TestTokenAttributes(token_id, this.WAS_CAPITALIZED)
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

        this.Replace(expanded, token_id + replace_offset)
        this.SetTokenAttributes(token_id + replace_offset, this.WAS_EXPANDED)
        if (mark_as_capitalized) {
            this.SetTokenAttributes(token_id + replace_offset, this.WAS_CAPITALIZED)
        }
        if (capitalizes_next) {
            this.SetTokenAttributes(token_id + replace_offset, this.CAPITALIZES_NEXT)
        }

        ; ending smart space
        if (affixes & this.AFFIX_PREFIX) {
            this.SetTokenAttributes(token_id + replace_offset, this.IS_PREFIX)
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

    _FixLastToken() {
        token := io_tokens[io_tokens.Length()]
        last_character := SubStr(token.output, StrLen(token.output), 1)
        if (last_character == " " ||  InStr(keys.punctuation_plain, last_character) ) {
            token.input := StrReplace(token.input, last_character)
            token.output := StrReplace(token.output, last_character)
            if ( StrLen(token.input) == 1 ) {
                this.ClearTokenAttributes(io_tokens.Length(), this.IS_CHORD)
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
        if (settings.chording & CHORD_RESTRICT && this._IsRestricted(io_tokens.Length()-1) ) {
            Return False
        }
        raw_output := io_tokens[io_tokens.Length()].output
        this.output_buffer .= "{Backspace " . StrLen(raw_output) . "}"
        io_tokens.RemoveAt(io_tokens.Length())
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
        attributes := io_tokens[first_token_id - 1].attributes
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
                this.SetTokenAttributes(first_token_id, this.WAS_CAPITALIZED)
            } else if ( this.TestTokenAttributes(first_token_id, this.WITH_SHIFT)
                    || ( ( settings.capitalization != CAP_OFF) && this._ShouldCapitalize(first_token_id) ) ) {
                expanded := RegExReplace(expanded, "(^.)", "$U1")
                this.SetTokenAttributes(first_token_id, this.WAS_CAPITALIZED)
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
            this.OutputKeys()
            this.SetTokenAttributes(first_token_id + first_token_offset, this.WAS_EXPANDED)
            if (capitalizes_next) {
                this.SetTokenAttributes(first_token_id + first_token_offset, this.CAPITALIZES_NEXT)
            }
            return true
        }
    }

    HintModule(text, first_token_id) {
        global hint_delay
        if ( settings.hints & HINT_OFF || ! (hint_delay.HasElapsed()) ) {
            return
        }
        if ( this.TestTokenAttributes(first_token_id - 1, this.WAS_EXPANDED | this.IS_INTERRUPT) ) {
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
        if ( this.TestTokenAttributes(token_id, this.WAS_EXPANDED | this.IS_PUNCTUATION | this.IS_PREFIX
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
        if (start == 2 && (io_tokens[start - 1].attributes & this.IS_ENTER) ) {
            return true
        }
        if (start > 2 && this.GetOutput(start - 1, start - 1) == " ") {
            if (this.TestTokenAttributes(start - 2, this.CAPITALIZES_NEXT)) {
                return true
            }
            preceding := io_tokens[start - 2].input
            with_shift := this.TestTokenAttributes(start - 2, this.WITH_SHIFT)
            if ( StrLen(preceding)==1 && (!with_shift && InStr(keys.capitalizing_plain, preceding))
                || (with_shift && InStr(keys.capitalizing_shift, preceding)) ) {
                return true
            }
        }
        if (start > 1 && this.TestTokenAttributes(start - 1, this.CAPITALIZES_NEXT)) {
            return true
        }
        ; Capitalize chords after sentence-ending punctuation should even a preceding space.
        if ( start > 1 && this.TestTokenAttributes(start, this.IS_CHORD) ) {
            preceding := io_tokens[start - 1].input
            with_shift := this.TestTokenAttributes(start - 1, this.WITH_SHIFT)
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
            if (this.TestTokenAttributes(token_id, this.WITH_SHIFT)) {
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
        smart_space.attributes |= this.SMART_SPACE_AFTER
        io_tokens.Push(smart_space)
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


    DebugTokens() {
        if (A_Args[2] != "test-vs") {
            return
        }
        OutputDebug, % "`n`nKeys:"
        OutputDebug, % "Classifying starts at " . this._classification_start
        len := io_keys.Length()
        Loop % len
        {
            ev := io_keys[A_Index]
            OutputDebug, % "`n" . i . ": " ev.input . " > " . ev.output . " (" . ev.attributes . ")"
        }
        OutputDebug, % "`n`nTokens:"
        For i, token in io_tokens {
            OutputDebug, % "`n" . i . ": " token.input . " > " . token.output . " (" . token.attributes . ")"
        }
    }
}
