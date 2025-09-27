/*
Physical Keys Editor for ZipChord
Created to provide a UI for mapping physical keyboard keys to user-defined characters
so those characters can be used in custom dictionaries as representations of the physical keys.

This file follows the same UI helper approach as `app_shortcuts.ahk`.
*/

physical_keys_editor := new clsPhysicalKeyMapper

Class clsPhysicalKeyMapper {
    ; list of keys laid out in physical order (number row, Q-row, A-row, Z-row, bottom row)
    keys := ["``", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="
                , "Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\"
                , "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'"
                , "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"
                , "Space"]

    controls := {}
    mappings := {}

    Show() {
        this._LoadSettings()
        UI := new clsUI("ZipChord — Physical Keys Editor")
        UI.on_close := ObjBindMethod(this, "Close")
        UI.Margin(15, 15) ; ensure a normal left margin and vertical margin
        UI.Add("Text", "x+0 y+6", "Click a key below to set the character that represents that physical key in custom dictionaries.")
        UI.Add("Text", "x+0 y+6", "") ; add some whitespace below the label

        ; define per-row column counts matching a standard physical layout
        counts := [13, 14, 11, 10, 5] ; number row, Q-row (with Tab and backslash), A-row, Z-row, bottom row

        ; layout parameters
        btn_w := 70
        btn_h := 30
        gap_x := 8
        gap_y := 10
        space_w := btn_w * 5 + gap_x * 4 ; wide spacebar width

        ; slice the flat keys array into rows according to counts
        rows := []
        idx := 1
        for _, c in counts {
            row := []
            loop % c {
                if (idx > this.keys.Length())
                    break
                row.Push(this.keys[idx])
                idx++
            }
            rows.Push(row)
        }

        ; compute per-row total widths and the maximum width to center rows and set window width
        rowWidths := []
        maxRowWidth := 0
        for _, row in rows {
            totalW := 0
            for _, key in row {
                w := (key == "Space") ? space_w : btn_w
                totalW += w
            }
            ; add gaps between keys
            if (row.Length() > 1)
                totalW += (row.Length()-1) * gap_x
            rowWidths.Push(totalW)
            if (totalW > maxRowWidth)
                maxRowWidth := totalW
        }

        ; render rows using accumulated x offsets to account for variable widths per key
        for rIndex, row in rows {
            totalW := rowWidths[rIndex]
            rowOffset := (maxRowWidth - totalW) / 2
            acc := 0
            for _, key in row {
                w := (key == "Space") ? space_w : btn_w
                xoff := rowOffset + acc
                yoff := (rIndex-1) * (btn_h + gap_y) + 40 ; move rows down a bit to account for extra label spacing
                options := Format("x{} y{} w{} h{}", xoff, yoff, w, btn_h)
                this.controls[key] := UI.Add("Button", options, this._ButtonLabel(key), ObjBindMethod(this, "_OnKeyClick", key))
                acc += w + gap_x
            }
        }

        UI.Add("Button", "w80 xs y+12", "Close", ObjBindMethod(this, "Close"))
        ; set window width based on maxRowWidth with a small padding
        UI.Show()
        this.UI := UI
    }

    _ButtonLabel(key) {
        val := this.mappings.HasKey(key) ? this.mappings[key] : ""
        if (val == "")
            return key . ": [ ]"
        else
            return key . ": " . val
    }

    _OnKeyClick(key) {
        ; Prompt the user for a character/string to represent that key.
        Prompt := "Type the character(s) to represent " . key . ":"
        InputBox, mapped, % "Set mapping for " key, %Prompt%, , 300, 120
        if (ErrorLevel)
            return
        mapped := Trim(mapped)
        this.mappings[key] := mapped

        ; update the button label for that key
        if (IsObject(this.controls[key])) {
            this.controls[key].value := this._ButtonLabel(key)
        }
        this._SaveSettings()
    }

    _SaveSettings() {
        config_filename := runtime_status.config_file ? runtime_status.config_file : ""
        For key, val in this.mappings {
            ini.SaveProperty(val, "pk_" . key, "Physical Key Mapping", config_filename)
        }
    }

    _LoadSettings() {
        config_filename := runtime_status.config_file ? runtime_status.config_file : ""
        For _, key in this.keys {
            value := ini.LoadProperty("pk_" . key, "Physical Key Mapping", config_filename)
            if (value != "")
                this.mappings[key] := value
        }
    }

    Close() {
        this.UI.Destroy()
    }
}
