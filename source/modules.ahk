/*

This file is part of ZipChord.

Copyright (c) 2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

modules := new clsSubstitutionModules

Class clsSubstitutionModules {
    Run() {
        global io
        global keys
        this.ChordModule()
        last := io.GetInput(io.length)
        with_shift := io.shift_in_last_get
        ; if the last character is space or punctuation
        if (StrLen(last)==1 && ( last == " " || (! with_shift && InStr(keys.remove_space_plain . keys.space_after_plain . keys.capitalizing_plain . keys.other_plain, last)) || (with_shift && InStr(keys.remove_space_shift . keys.space_after_shift . keys.capitalizing_shift . keys.other_shift, last)) ) ) {
            text := io.GetOutput(2, io.length-1)
            if (! io.chord_in_last_get) {
                this.ShorthandModule(text)
                this.HintModule(text)
            }
        }
    }

    CapitalizeTyping(key) {
        global io
        global keys
        static wasSpaceLast
        if (key == " ") {
            wasSpaceLast := true
            return
        }
        if (!wasSpaceLast || settings.capitalization != CAP_ALL || io.length < 1 || (io._sequence[io.length].attributes & io.WITH_SHIFT) ) {
            return
        }

        if (io._sequence[io.length].attributes & io.IS_ENTER ) {
            OutputDebug, % "`nwith Enter..."
        }

        potential_punctuation := io.GetInput(io.length - 1, io.length - 1)
        with_shift := io.shift_in_last_get
        if ( StrLen(potential_punctuation)==1 && (! with_shift && InStr(keys.capitalizing_plain, potential_punctuation))
            || (with_shift && InStr(keys.capitalizing_shift, potential_punctuation)) ) {
            ; OutputDebug, % "`nCapping with: " . io.GetInput()
            upper_cased := RegExReplace(key, "(^.)", "$U1")
            OutputKeys("{Backspace}{Text}" . upper_cased)
        }
        wasSpaceLast := false
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
            candidate := str.Arrange(candidate)
            candidate := StrReplace(candidate, "||", "|")
            chunk := io.GetChunk(A_Index)
            if (expanded := chords.LookUp(candidate)) {
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
                Break
            }
        }
        ; io.Show()
    }

    ShorthandModule(text) {
        global io
        global hint_delay
        if (! (settings.mode & MODE_SHORTHANDS_ENABLED))
            return
        If ( expanded := shorthands.LookUp(text) ) {
            hint_delay.Shorten()
            io.GetOutput(1, 1)
            if (io.shift_in_last_get)
                expanded := RegExReplace(expanded, "(^.)", "$U1")
            io.Replace(expanded, 1, io.length-1)
        }
    }

    HintModule(text) {
        global io
        global hint_delay
        if (! (settings.hints & HINT_ON) || ! hint_delay.HasElapsed())
            return
        if (settings.mode & MODE_CHORDS_ENABLED)
            chord_hint := chords.ReverseLookUp(text)
        if (settings.mode & MODE_SHORTHANDS_ENABLED)
            shorthand_hint := shorthands.ReverseLookUp(text)
        chord_hint := chord_hint ? chord_hint : "" 
        shorthand_hint := shorthand_hint ? shorthand_hint : "" 
        if (chord_hint || shorthand_hint)
            ShowHint(text, chord_hint, shorthand_hint)
    }
}