/*

This file is part of ZipChord.

Copyright (c) 2023 Pavel Soukenik

Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 

*/


classifier := new clsClassifier
io := new clsIOrepresentation

Class clsClassifier {
    _buffer := []        ; stores clsKeyEvent objects
    _index := {}     ; associateve arary that indexes _buffer:  _index[{key}] points to that key's record in _buffer
    length [] {
        get {
            return this._buffer.Length()
        }
    }
    lifted [] {
        get {
            For _, event in this._buffer
                if (event.end)
                    lifted++        
            return lifted
        }
    }
    Class clsKeyEvent {
        key := 0
        shifted := false
        start := 0
        end := 0
    }
    _GetOverlap(first, last) {
        start := this._buffer[last].start
        end := this._buffer[first].end
        count := last - first
        Loop %count%
            end := Min(end, this._buffer[first + A_Index].end)
        Return end-start
    }
    _DetectRoll() {
        min := this._buffer[1].end
        For _, event in this._buffer
        {
            min := Min(min, event.end)
            if (min < this._buffer[this.length].start) {
                return true
            }
        }
        return false
    }
    Input(key, timestamp) {
        key := SubStr(key, 2)
        if (SubStr(key, 1, 1) == "+") {
            shifted := True
            key := SubStr(key, 2)
        } else shifted := False

        if (SubStr(key, -2)==" Up") {
            key := SubStr(key, 1, StrLen(key)-3)
            lifted := true
        } else lifted := false

        if (lifted) {
            index := this._index[key]
            this._buffer[index].end := timestamp
            if (! index)
                MsgBox, , % "ZipChord", Format("Classifier error: The key '{}' was lifted, but we do not have it in index.", key)
            this._index.Delete(key)
            this._Classify(index, timestamp)
        } else {
            event := new this.clsKeyEvent
            event.key := key
            event.start := timestamp
            event.shifted := shifted
            this._buffer.Push(event)
            this._index[key] := this._buffer.Length()
        }
    }
    _Classify(count, timestamp) {
        global io
        if (this.length == 1) {
            input :=  this._buffer[1].key
            this._buffer.RemoveAt(1)
            io.Add(input, input)
            ; return
        }
        if (this.lifted == 2) {
            if (this._GetOverlap(1, 2) > settings.input_delay && ! this._DetectRoll()) {
                For _, event in this._buffer
                    input .= event.key
                io.Add(input, input)
            } else {
                For _, event in this._buffer
                    io.Add(event.key, event.key)
            }
            this._buffer := []
        }
    }
} 

Class clsIOrepresentation {
    _sequence := []
    length [] {
        get {
            return this._sequence.Length() 
        }
    }
    Class clsChunk {
        input := ""
        output := ""
    }
    Add(in, out) {
        chunk := new this.clsChunk
        chunk.input := in
        chunk.output := out
        this._sequence.Push(chunk)
    }
    Clear() {
        this._sequence := []
    }
    SetChunk(index, new_output) {
        this._sequence[index].output := new_output
    }
    Replace(new_output, start := 1, end := 0) {
        if (! end)
            end := this.length
        this.Combine(start, end)
        this.SetChunk(start, new_output)
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
            sequence[start].input .= " " . sequence[following].input 
            sequence[start].output .= sequence[following].output
            sequence.RemoveAt(following)
        }
    }
    GetInput(start := 1, end := 0) {
        return this.Get(start, end)
    }
    GetOutput(start := 1, end := 0) {
        return this.Get(start, end, true)
    }
    Get(start := 1, end := 0, get_output := false) {
        sequence := this._sequence
        what := get_output ? "output" : "input" 
        separator := get_output ? "" : " "
        if (! end)
            end := this.length 
                if (start > sequence.Length() || end > sequence.Length()) {
            MsgBox, , % "ZipChord", "IO Representation error: Requested getting chunks that exceed the length of _sequence."
            Return true
        }
        count := end - start + 1
        i := start
        Loop, %count%
            representation .= separator . sequence[i++][what]
        Return SubStr(representation, StrLen(separator)+1)
    }
    Show() {
        OutputDebug, % "`n`nIO _sequence:" 
        For i, chunk in this._sequence
            OutputDebug, % "`n" . i . ": " chunk.input . " > " . chunk.output
    }
}
