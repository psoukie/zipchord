/*

This file is part of ZipChord.

Copyright (c) 2023-2024 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

modules := new clsSubstitutionModules

Class clsSubstitutionModules {
    Run() {
        this.ChordModule()
        this.RemoveRawChord()
        ; TK Add separating spaces and punctuation when it gets glued with preceding characters in a false chunk
        this.DoShorthandsAndHints()
    }

    DoShorthandsAndHints() {
        global io
        global keys
        last_chunk := io.GetChunk(io.length)
        attribs := last_chunk.attributes
        ; We check if the last character is a space or punctuation
        if ( attribs & io.IS_MANUAL_SPACE || attribs & io.IS_PUNCTUATION ) {
            text := io.GetOutput(2, io.length-1)
            starting_chunk := this.GetStartingChunkOfText(text)
            if (! io.chord_in_last_get && starting_chunk) {
                trimmed_text := Trim(text)
                this.ShorthandModule(trimmed_text, starting_chunk)
                this.HintModule(trimmed_text)
            }
            this.AddSpaceAfterPunctuation(attribs, last_chunk)
            dont_clear := false
            if (attribs & io.IS_MANUAL_SPACE) {
                dont_clear := this.DeDoubleSpace()
            }
            if (! dont_clear) {
                io.Clear()
            }
        }
    }

    CapitalizeTyping(character, attribs) {
        global io
        global keys
        if ( settings.capitalization != CAP_ALL || (attribs & io.IS_PUNCTUATION)
                || (attribs & io.IS_MANUAL_SPACE) || (attribs & io.WITH_SHIFT) ) {
            return
        }
        capitalize := False
        if (io.length == 2 && (io._sequence[io.length - 1].attributes & io.IS_ENTER) ) {
            capitalize := True
        } else {
            if (io.length > 2 && io.GetOutput(io.length - 1, io.length - 1) == " ") {
                preceding := io.GetInput(io.length - 2, io.length - 2)
                with_shift := io.shift_in_last_get
                if ( StrLen(preceding)==1 && (!with_shift && InStr(keys.capitalizing_plain, preceding))
                    || (with_shift && InStr(keys.capitalizing_shift, preceding)) ) {
                    capitalize := True
                }
            }
        }
        if (capitalize) {
            upper_cased := RegExReplace(character, "(^.)", "$U1")
            io.Replace(upper_cased, io.length)
        }
    }

    PrePunctuation(attribs) {
        global io
        global keys
        if !( (attribs & io.IS_PUNCTUATION) && (io.GetChunk(io.length-1).attributes & io.SMART_SPACE_AFTER) ) {
            return
        }
        chunk := io.GetChunk(io.length)
        if ( (!(chunk.attributes & io.WITH_SHIFT) && InStr(keys.remove_space_plain, chunk.input))
                || ((chunk.attributes & io.WITH_SHIFT) && InStr(keys.remove_space_shift, chunk.input)) ) {
            io.Replace(chunk.output, io.length-1)
            new_chunk := io.GetChunk(io.length)
            new_chunk.input := chunk.input
            new_chunk.attributes := chunk.attributes
        }
    }

    AddSpaceAfterPunctuation(attribs, chunk) {
        global keys
        global io
        if ( (settings.spacing & SPACE_PUNCTUATION) && (attribs & io.IS_PUNCTUATION)
                && (( !(attribs & io.WITH_SHIFT) && InStr(keys.space_after_plain, chunk.input) )
                    || (attribs & io.WITH_SHIFT) && InStr(keys.space_after_shift, chunk.input) )) {
            punctuation_space := new io.clsChunk
            punctuation_space.input := ""
            punctuation_space.output := " "
            punctuation_space.attributes |= io.PUNCTUATION_SPACE
            io._sequence.Push(punctuation_space)
            OutputKeys(" ")
            return
        }
    }

    ; Remove a double space if the user types a space after punctuation space
    DeDoubleSpace() {
        global io
        last_chunk_attrib := io.GetChunk(io.length-1).attributes 
        if ( (last_chunk_attrib & io.PUNCTUATION_SPACE) || (last_chunk_attrib & io.SMART_SPACE_AFTER) ) {
            io.Replace("", io.length)
            io._sequence.RemoveAt(io.length)
            io._Show() 
            return true
        }
        return false
    }

    ChordModule() {
        global io
        global keys
        global hint_delay
        if (! (settings.mode & MODE_CHORDS_ENABLED))
            return
        count := io.length
        Loop %count%
        {
            candidate := io.GetInput(A_Index)
            if (StrLen(candidate) < 2) {
                break
            }
            candidate := StrReplace(candidate, "||", "|")
            expanded := chords.LookUp(candidate)
            if (expanded) {
                chunk := io.GetChunk(A_Index)
                hint_delay.Shorten()
                if (io.shift_in_last_get) {
                    expanded := RegExReplace(expanded, "(^.)", "$U1")
                }
                ; detect affixes to handle opening and closing smart spaces correctly
                affixes := this._DetectAffixes(expanded)
                expanded := this._RemoveAffixSymbols(expanded, affixes)
                previous_chunk := io.GetChunk(A_Index-1)

                if ( this._IsRestricted(previous_chunk) && !(affixes & AFFIX_SUFFIX) ) {
                    return
                }
                
                add_leading_space := true
                replace_offset := 0
                ; if there is a smart space, we have to delete it for suffixes
                if (previous_chunk.attributes & io.SMART_SPACE_AFTER) {
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
                if ( ( !(previous_chunk.attributes & io.WITH_SHIFT)
                        && InStr(keys.punctuation_plain, previous_chunk.input)
                        && !InStr(keys.space_after_plain, previous_chunk.input) )
                        || (previous_chunk.attributes & io.WITH_SHIFT)
                        && InStr(keys.punctuation_shift, previous_chunk.input)
                        && !InStr(keys.space_after_shift, previous_chunk.input) )  {
                    add_leading_space := false
                }
                
                ; and we don't start with a smart space after interruption, a space, after a prefix, and for suffix
                if (previous_chunk.attributes & io.IS_INTERRUPT || previous_chunk.output == " "
                        || previous_chunk.attributes & io.IS_PREFIX || affixes & AFFIX_SUFFIX) {
                    add_leading_space := false
                }
                if (add_leading_space) {
                    expanded := " " . expanded
                }

                io.Replace(expanded, A_Index + replace_offset)
                chunk.attributes |= io.WAS_EXPANDED

                ; ending smart space
                if (affixes & AFFIX_PREFIX) {
                    chunk.attributes |= io.IS_PREFIX
                } else if (settings.spacing & SPACE_AFTER_CHORD) {
                    smart_space := new io.clsChunk
                    smart_space.input := ""
                    smart_space.output := " "
                    smart_space.attributes |= io.SMART_SPACE_AFTER
                    io._sequence.Push(smart_space)
                    OutputKeys(" ")
                }
                break
            }
        }
    }

    /**
    * Remove characters of non-existing chord if 'delete mistyped chords' option is enabled.
    * 
    * Note: When "Restrict chords while typing" and "Delete mistyped chords" are both enabled and a non-existing chord is
    * registered while typing a word, this input is left alone because it is safe to assume it was intended as normal
    * typing.
    */
    RemoveRawChord() {
        global io
        if ((settings.chording & CHORD_DELETE_UNRECOGNIZED)) {
            ; TK Should check for && IsUnrestricted() above but it does not exist yet
            chunk := io.GetChunk(io.length)
            if ( StrLen(chunk.input) > 1 && !(chunk.attributes & io.WAS_EXPANDED) ) {
                io.Replace("", io.length)
            }
        }
    }

    GetStartingChunkOfText(text) {
        global io
        if ( SubStr(text, 1, 1) == " " ) {
            text := SubStr(text, 2)
            first_chunk := 3
        } else {
            first_chunk := 2
        }
        ; don't do shorthand for interrupts
        preceding_chunk := io.GetChunk(first_chunk-1)
        if (preceding_chunk.attributes & io.IS_INTERRUPT) {
            return false
        }
        return first_chunk
    }

    ShorthandModule(text, first_chunk) {
        global io
        global hint_delay
        if (! (settings.mode & MODE_SHORTHANDS_ENABLED)) {
            return
        }
        if ( expanded := shorthands.LookUp(text) ) {
            hint_delay.Shorten()
            io.GetOutput(first_chunk, first_chunk)
            if (io.shift_in_last_get)
                expanded := RegExReplace(expanded, "(^.)", "$U1")
            io.Replace(expanded, first_chunk, io.length-1)
        }
    }

    HintModule(text) {
        global hint_delay
        if (! (settings.hints & HINT_ON) || ! hint_delay.HasElapsed()) {
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
            ShowHint(text, chord_hint, shorthand_hint)
        }
    }

    ; check we can output a chord in this context
    _IsRestricted(chunk) {
        global io
        if !(settings.chording & CHORD_RESTRICT) {
            return false
        }
        ; If last output was automated (smart space or chord), punctuation, a 'prefix' (which  includes opening
        ; punctuation), it was interrupted, or it was a space, we can also go ahead.
        attribs := chunk.attributes
        if ( (attribs & io.WAS_EXPANDED) || (attribs & io.IS_PUNCTUATION) || (attribs & io.IS_PREFIX)
                || (attribs & io.IS_INTERRUPT) || (attribs & io.IS_MANUAL_SPACE) || (attribs & io.PUNCTUATION_SPACE)
                || (attribs & io.SMART_SPACE_AFTER) ) {
            return false
        }
        return true
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
    _RemoveAffixSymbols(expanded_text, affixes) {
        start := affixes & AFFIX_SUFFIX ? 2 : 1
        end_offset := affixes & AFFIX_PREFIX ? -1 : 0
        sanitized_text := SubStr(expanded_text, start, StrLen(expanded_text) + end_offset)
        Return sanitized_text
    }
}