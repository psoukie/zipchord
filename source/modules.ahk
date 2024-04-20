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
        last_chunk_output := io.GetOutput(io.length)
        with_shift := io.shift_in_last_get
        ; We check if the last character is a space or punctuation
        OutputDebug, % "`nLast chunk>" . last_chunk_output . "<"
        last := SubStr(last_chunk_output, StrLen(last_chunk_output), 1)
        if ( StrLen(last)==1 && ( last == " "
            || (! with_shift && InStr(keys.remove_space_plain . keys.space_after_plain . keys.capitalizing_plain . keys.other_plain, last))
            || (with_shift && InStr(keys.remove_space_shift . keys.space_after_shift . keys.capitalizing_shift . keys.other_shift, last)) ) ) {
            if (StrLen(last_chunk_output) < 2) {
                text := io.GetOutput(2, io.length-1)
            } else {
                text_with_trailing := io.GetOutput(2, io.length)
                text := SubStr(text_with_trailing, 1, StrLen(text_with_trailing) - 1)
            }
            starting_chunk := this.GetStartingChunkOfText(text)
            if (! io.chord_in_last_get && starting_chunk) {
                trimmed_text := Trim(text)
                this.ShorthandModule(trimmed_text, starting_chunk)
                this.HintModule(trimmed_text)
            }
        }
    }

    CapitalizeTyping(key) {
        global io
        global keys
        if (settings.capitalization != CAP_ALL) {
            return
        }
        capitalize := False
        if (io.length == 2 && io._sequence[io.length - 1].attributes & io.IS_ENTER) {
            capitalize := True
        } else {
            if (io.length > 2 && io.GetInput(io.length - 1, io.length - 1) == " ") {
                punctuation := io.GetInput(io.length - 2, io.length - 2)
                with_shift := io.shift_in_last_get
                if ( StrLen(punctuation)==1 && (! with_shift && InStr(keys.capitalizing_plain, punctuation))
                    || (with_shift && InStr(keys.capitalizing_shift, potential_punctuation)) ) {
                    capitalize := True
                }
            }
        }
        if (capitalize) {
            key := io.GetInput(io.length)
            if (!io.shift_in_last_get) {
                upper_cased := RegExReplace(key, "(^.)", "$U1")
                io.Replace(upper_cased, io.length)
            }
        }
    }

    ChordModule() {
        global io
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
                    chunk.attributes |= io.WAS_CAPITALIZED
                    expanded := RegExReplace(expanded, "(^.)", "$U1")
                }
                ; detect affixes to handle opening and closing smart spaces correctly
                affixes := ProcessAffixes(expanded)
                previous_chunk := io.GetChunk(A_Index-1)
                add_space := true
                replace_offset := 0
                ; if there is a smart space, we remove it for suffixes, and we're done
                if ( previous_chunk.input == "" && previous_chunk.output == " " ) {
                    if (affixes & AFFIX_SUFFIX)
                        replace_offset := -1
                    add_space := false
                }
                ; if adding smart spaces before is disabled, we are done too
                if (! (settings.spacing & SPACE_BEFORE_CHORD))
                    add_space := false
                ; TK ; if the last output was punctuation that does not ask for a space, we are done 
                ; if ( (fixed_output & OUT_PUNCTUATION) && ! (fixed_output & OUT_SPACE_AFTER) )
                ;     Return
                ; and we don't start with a smart space after interruption, a space, after a prefix, and for suffix
                if (previous_chunk.attributes == io.IS_INTERRUPT || previous_chunk.output == " " || previous_chunk.attributes == io.IS_PREFIX || affixes & AFFIX_SUFFIX)
                    add_space := false
                ; if we get here, we probably need a space in front of the chord
                if (add_space) {
                    expanded := " " . expanded
                    chunk.attributes |= io.ADDED_SPACE_BEFORE
                }

                io.Replace(expanded, A_Index - replace_offset)
                chunk.attributes |= io.IS_CHORD
                ; ending smart space
                if (affixes & AFFIX_PREFIX) {
                    chunk.attributes |= io.IS_PREFIX
                } else if (settings.spacing & SPACE_AFTER_CHORD) {
                    smart_space := new io.clsChunk
                    smart_space.input := ""
                    smart_space.output := " "
                    io._sequence.Push(smart_space)
                    last_output := OUT_SPACE | OUT_AUTOMATIC
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
            OutputDebug, % "`nRawremover: " . StrLen(chunk.input)
            if ( StrLen(chunk.input) > 1 && !(chunk.attributes & io.IS_CHORD) ) {
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
}