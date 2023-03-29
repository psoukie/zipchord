/*

This file is part of ZipChord.

Copyright (c) 2023 Pavel Soukenik

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
        Loop %count%
            if (event_end := this._buffer[first - 1 + A_Index].end)
                end := Min(end, event_end)
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
        key := SubStr(key, 2)
        if (SubStr(key, 1, 1) == "+") {
            with_shift := True
            key := SubStr(key, 2)
        } else with_shift := False

        key := StrReplace(key, "Space", " ")

        if (SubStr(key, -2)==" Up") {
            key := SubStr(key, 1, StrLen(key)-3)
            lifted := true
        } else lifted := false

        if (lifted) {
            index := this._index[key]
            this._buffer[index].end := timestamp
            if (index) {
                this._index.Delete(key)
                this._Classify(index, timestamp)
            }
            ; otherwise, the lifted key was already classified and removed from buffer.
        } else {
            event := new this.clsKeyEvent
            event.key := key
            event.start := timestamp
            event.with_shift := with_shift
            this._buffer.Push(event)
            this._index[key] := this._buffer.Length()
        }
    }
    Interrupt(type := "*Interrupt*") {
        global io
        this._buffer := []
        this._index := {}
        io.Clear(type)
    }
    _Classify(index, timestamp) {
        ; This classification mirrors the 2.1 version of detecting chords.
        global io
        static first_up
        if (this.length == 1) {
            input :=  this._buffer[1].key
            if (this._buffer[1].with_shift)
                with_shift := true
            this._buffer.RemoveAt(1)
            io.Add(input, with_shift)
            return
        }
        if (this.lifted == 1)
            first_up := index
        if (this.lifted == 2) {
            if (this._GetOverlap(1, 2, timestamp) > settings.input_delay && ! this._DetectRoll(first_up)) {
                For _, event in this._buffer {
                    input .= event.key
                    if (event.with_shift)
                        with_shift := true
                }
                io.Add(input, with_shift)
            } else {
                For _, event in this._buffer
                    io.Add(event.key, with_shift)
            }
            this._buffer := []
            this._index := {}
        }
    }
    Show() {
         For _, event in this._buffer
            OutputDebug, % "`nBuffer: " . event.key . "(" . event.with_shift . ")"
    }
} 

Class clsIOrepresentation {
    static NONE := 0
         , WITH_SHIFT := 1
         , ADDED_SPACE_BEFORE := 2 
         , ADDED_SPACE_AFTER := 4
         , EXPECTS_SPACE := 8
         , IS_CHORD := 16
         , IS_PREFIX := 32
         , IS_SUFFIX := 64
         , WAS_CAPITALIZED := 128
         , IS_ENTER := 256
         , IS_INTERRUPT := 512
    _sequence := []
    length [] {
        get {
            return this._sequence.Length()
        }
    }
    _shift_in_last_get := 0
    _chord_in_last_get := 0
    shift_in_last_get [] {
        get {
            return this._shift_in_last_get 
        }
    }
    chord_in_last_get [] {
        get {
            return this._chord_in_last_get 
        }
    }
    Class clsChunk {
        input := ""
        output := ""
        attributes := clsIOrepresentation.NONE
    }
    __New() {
        this.Clear("*Interrupt*")
    }
    Add(in, with_shift) {
        global keys
        chunk := new this.clsChunk
        if (StrLen(in)>1) {
            ;For chords, if Shift is allowed as a separate key in chord key, we add it as part of the entry.
            if (with_shift && (settings.chording & CHORD_ALLOW_SHIFT)) {
                in := "+" . in
                with_shift := false
            }
            in := str.Arrange(in)
        }
        chunk.input := in
        chunk.attributes := this.WITH_SHIFT
        if (StrLen(in)==1 && with_shift)
            chunk.output := str.ToAscii(in, ["Shift"])
        else
            chunk.output := in
        this._sequence.Push(chunk)
        this._Show()
        this._PingModules()
        last := this.GetInput(this.length)
        ; if the last character is space or punctuation
        if (StrLen(last)==1 && ( last == " " || (! with_shift && InStr(keys.remove_space_plain . keys.space_after_plain . keys.capitalizing_plain . keys.other_plain, last)) || (with_shift && InStr(keys.remove_space_shift . keys.space_after_shift . keys.capitalizing_shift . keys.other_shift, last)) ) )
            this.Clear()
    }
    Clear(type := "") {
        first_chunk := new this.clsChunk
        if (type=="~Enter")
            first_chunk.attributes := this.IS_ENTER
        if (type=="*Interrupt*")
            first_chunk.attributes := this.IS_INTERRUPT
        if (type=="") {
            first_chunk := this._sequence[this.length]
        }
        this._sequence := []
        this._sequence.Push(first_chunk)
        this._Show()
        if (visualizer.IsOn())
            visualizer.NewLine()
    }
    SetChunk(index, new_output) {
        this._sequence[index].output := new_output
        this._sequence[index].automated := true
    }
    Replace(new_output, start := 1, end := 0) {
        if (! end)
            end := this.length
        if (start != end)
            this.Combine(start, end)
        old_output := this._sequence[start].output
        this.SetChunk(start, new_output)
        this._ReplaceOutput(old_output, new_output, start)
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
    GetChunk(index) {
        return this._sequence[index] 
    }
    GetInput(start := 1, end := 0) {
        return this._Get(start, end)
    }
    GetOutput(start := 1, end := 0) {
        return this._Get(start, end, true)
    }
    _Get(start := 1, end := 0, get_output := false) {
        this._shift_in_last_get := false
        this._chord_in_last_get := false
        sequence := this._sequence
        what := get_output ? "output" : "input" 
        separator := get_output ? "" : "|"
        if (! end)
            end := this.length 
                if (start > sequence.Length() || end > sequence.Length()) {
            MsgBox, , % "ZipChord", "IO Representation error: Requested getting chunks that exceed the length of _sequence."
            Return true
        }
        count := end - start + 1
        i := start
        Loop, %count%
        {
            if (sequence[i].attributes & this.WITH_SHIFT)
                this._shift_in_last_get := true
            if (StrLen(sequence[i].input) > 1)
                this._chord_in_last_get := true
            representation .= separator . sequence[i++][what]
        }
        Return SubStr(representation, StrLen(separator)+1)
    }
    _PingModules() {
        global modules
        modules.Run()
    }
    _ReplaceOutput(old_output, new_output, start) {
        if (start != this.length)
            backup_content := this.GetOutput(start+1)
        adj := StrLen(old_output . backup_content)
        DelayOutput()
        OutputKeys("{Backspace " . adj . "}")
        ; we send any expanded text that includes { as straight directives:
        if (InStr(new_output, "{"))
            OutputKeys(new_output)
        else
            OutputKeys("{Text}" . new_output . backup_content)
    }
    _Show() {
        OutputDebug, % "`n`nIO sequence:" 
        For i, chunk in this._sequence
            OutputDebug, % "`n" . i . ": " chunk.input . " > " . chunk.output
    }
}
