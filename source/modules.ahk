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
        with_shift := io._sequence[io.length].attributes & io.WITH_SHIFT 
        ; if the last character is space or punctuation
        if (StrLen(last)==1 && ( last == " " || (! with_shift && InStr(keys.remove_space_plain . keys.space_after_plain . keys.capitalizing_plain . keys.other_plain, last)) || (with_shift && InStr(keys.remove_space_shift . keys.space_after_shift . keys.capitalizing_shift . keys.other_shift, last)) ) ) {
            text := io.GetOutput(2, io.length-1)
            if (! io.chord_in_last_get) {
                this.ShorthandModule(text)
                this.HintModule(text)
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
            If (StrLen(candidate := io.GetInput(A_Index)) < 2)
                Break
            chunk := io.GetChunk(A_Index)
            if (expanded := chords.LookUp(candidate)) {
                hint_delay.Shorten()
                if (io.shift_in_last_get) {
                    chunk.attributes |= io.WAS_CAPITALIZED
                    expanded := RegExReplace(expanded, "(^.)", "$U1")
                }
                expanded := this.OpeningSpace(expanded, chunk)
                io.Replace(expanded, A_Index)
                Break
            }
        }
        ; io.Show()
    }

    ShorthandModule(text) {
        global io
        global hint_delay
        OutputDebug, % "`nHint for: " . text
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

    OpeningSpace(expanded, ByRef chunk) {
        global io
        attached := ProcessAffixes(expanded) & AFFIX_SUFFIX
        ; if there is a smart space, we remove it for suffixes, and we're done
        ; if ( (fixed_output & OUT_SPACE) && (fixed_output & OUT_AUTOMATIC) ) {
        ;     if (attached)
        ;         OutputKeys("{Backspace}")
        ;     Return
        ; }
        ; ; if adding smart spaces before is disabled, we are done too
        ; if (! (settings.spacing & SPACE_BEFORE_CHORD))
        ;     Return
        ; ; if the last output was punctuation that does not ask for a space, we are done 
        ; if ( (fixed_output & OUT_PUNCTUATION) && ! (fixed_output & OUT_SPACE_AFTER) )
        ;     Return
        ; ; and we don't start with a smart space after intrruption, a space, after a prefix, and for suffix
        ; if (fixed_output & OUT_INTERRUPTED || fixed_output & OUT_SPACE || fixed_output & OUT_PREFIX || attached)
        ;     Return
        ; ; if we get here, we probably need a space in front of the chord
        chunk.attributes |= io.ADDED_SPACE_BEFORE | io.ADDED_SPACE_AFTER
        return " " . expanded . " "
    }
}