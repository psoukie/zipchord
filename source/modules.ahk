/*

This file is part of ZipChord.

Copyright (c) 2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/

modules := new clsSubstitutionModules

Class clsSubstitutionModules {
    chord_module := new this.clsChordModule
    shortcut_module := new this.clsShortcutModule
    hint_module := new this.clsHintModule

    Run(io) {
        global keys
        this.chord_module.Run(io)
        last := io.GetInput(io.length)
        with_shift := io._sequence[io.length].with_shift
        ; if the last character is space or punctuation
        if (StrLen(last)==1 && ( last == " " || (! with_shift && InStr(keys.remove_space_plain . keys.space_after_plain . keys.capitalizing_plain . keys.other_plain, last)) || (with_shift && InStr(keys.remove_space_shift . keys.space_after_shift . keys.capitalizing_shift . keys.other_shift, last)) ) ) {
            text := io.GetOutput(1, io.length-1)
            if (! io.chord_in_last_get) {
                this.shortcut_module.Run(io, text)
                this.hint_module.Run(text)
            }
        }
    }

    Class clsChordModule {
        Run(io) {
            global hint_delay
            if (! (settings.mode & MODE_CHORDS_ENABLED))
                return
            count := io.length
            Loop %count%
            {
                If (StrLen(candidate := io.GetInput(A_Index)) < 2)
                    Break
                if (expanded := chords.LookUp(candidate)) {
                    affixes := ProcessAffixes(expanded)
                    hint_delay.Shorten()
                    DelayOutput()
                    if (io.shift_in_last_get)
                        expanded := RegExReplace(expanded, "(^.)", "$U1")
                    io.Replace(expanded, A_Index)
                    Break
                }
            }
            ; io.Show()
        }
    }

    Class clsShortcutModule {
        Run(io, text) {
            global hint_delay
            if (! (settings.mode & MODE_SHORTHANDS_ENABLED))
                return
            If ( expanded := shorthands.LookUp(text) ) {
                hint_delay.Shorten()
                DelayOutput()
                io.GetOutput(1, 1)
                if (io.shift_in_last_get)
                    expanded := RegExReplace(expanded, "(^.)", "$U1")
                io.Replace(expanded, 1, io.length-1)
            }
        }
    }

    Class clsHintModule {
        Run(text) {
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
}