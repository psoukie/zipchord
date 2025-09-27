/*
Physical Keys Editor for ZipChord
Provides a UI for mapping physical keyboard keys (from `keys.key_list`) to characters used in dictionaries.
*/

physical_keys_editor := new clsPhysicalKeyMapper

Class clsPhysicalKeyMapper {
    controls := {}
    mappings := {}

    Show() {
        this._LoadSettings()
        UI := new clsUI("ZipChord — Physical Keys Editor")
        UI.on_close := ObjBindMethod(this, "Close")
        UI.Margin(15, 15)
        UI.Add("Text", "x+0 y+6", "Click a key below to set the character that represents that physical key in custom dictionaries.")
        UI.Add("Text", "x+0 y+6", "") ; whitespace below the label

        ; per-row column counts (matches keys.key_list ordering in clsLocale)
        counts := [13, 13, 11, 10]

        ; layout parameters
        btn_w := 70
        btn_h := 30
        gap_x := 8
        gap_y := 10

        ; slice keys.key_list into rows
        rows := []
        idx := 1
        for _, c in counts {
            row := []
            loop % c {
                if (idx > keys.key_list.Length())
                    break
                row.Push(keys.key_list[idx])
                idx++
            }
            rows.Push(row)
        }

        ; compute row widths to center rows
        rowWidths := []
        maxRowWidth := 0
        for _, row in rows {
            totalW := 0
            for _, name in row
                totalW += btn_w
            if (row.Length() > 1)
                totalW += (row.Length()-1) * gap_x
            rowWidths.Push(totalW)
            if (totalW > maxRowWidth)
                maxRowWidth := totalW
        }

        ; render rows (centered)
        for rIndex, row in rows {
            totalW := rowWidths[rIndex]
            rowOffset := (maxRowWidth - totalW) / 2
            acc := 0
            for _, name in row {
                xoff := rowOffset + acc
                yoff := (rIndex-1) * (btn_h + gap_y) + 40
                options := Format("x{} y{} w{} h{}", xoff, yoff, btn_w, btn_h)
                this.controls[name] := UI.Add("Button", options, this._ButtonLabel(name), ObjBindMethod(this, "_OnKeyClick", name))
                acc += btn_w + gap_x
            }
        }

        UI.Add("Button", "w80 xs y+12", "Close", ObjBindMethod(this, "Close"))
        ; set window width based on widest row + padding
        window_w := Ceil(maxRowWidth) + 40
        UI.Show("w" . window_w)
        this.UI := UI
    }

    _ButtonLabel(name) {
        val := this.mappings.HasKey(name) ? this.mappings[name] : ""
        if (val == "")
            return name . ": [ ]"
        else
            return name . ": " . val
    }

    _OnKeyClick(name) {
        Prompt := "Type the character(s) to represent " . name . ":"
        InputBox, mapped, % "Set mapping for " name, %Prompt%, , 300, 120
        if (ErrorLevel)
            return
        mapped := Trim(mapped)

        ; determine scan code for this physical key (runtime lookup)
        sc := GetKeySC(name)

        ; remove any other character currently mapped to this scan code (prevent duplicates)
        for k, v in keys.key_map {
            if (v = sc && k != mapped)
                keys.key_map.Delete(k)
        }
        ; set new mapping in keys.key_map
        keys.key_map[mapped] := sc

        ; persist per-key choice so UI remembers it independently (older config)
        config_filename := runtime_status.config_file ? runtime_status.config_file : ""
        ini.SaveProperty(mapped, "pk_" . name, "Physical Key Mapping", config_filename)

        ; update button label
        if (IsObject(this.controls[name])) {
            this.controls[name].value := this._ButtonLabel(name)
        }
    }

    _SaveSettings() {
        config_filename := runtime_status.config_file ? runtime_status.config_file : ""
        For key, val in this.mappings {
            ini.SaveProperty(val, "pk_" . key, "Physical Key Mapping", config_filename)
        }
    }

    _LoadSettings() {
        config_filename := runtime_status.config_file ? runtime_status.config_file : ""
        for _, name in keys.key_list {
            ; 1) if user selected explicit pk_ override, use it
            value := ini.LoadProperty("pk_" . name, "Physical Key Mapping", config_filename)
            if (value != "") {
                mapped := value
            } else {
                ; 2) try to find existing char in keys.key_map that maps to this key's SC
                sc := GetKeySC(name)
                mapped := ""
                for k, v in keys.key_map {
                    if (v = sc) {
                        mapped := k
                        break
                    }
                }
                ; 3) fallback to default QWERTY character
                if (mapped = "") {
                    if RegExMatch(name, "^[A-Z]$")
                        mapped := StrLower(name)
                    else
                        mapped := name
                }
            }
            ; update display value; do not store separately here — keys.key_map is the source of truth
            this.controls[name] := this.controls[name] ? this.controls[name] : ""
            ; if control exists, update its value, otherwise store into mappings for label creation later
            if (IsObject(this.controls[name]))
                this.controls[name].value := this._ButtonLabelFromMapped(name, mapped)
            else
                this.mappings[name] := mapped
        }
    }

    _ButtonLabelFromMapped(name, mapped) {
        if (mapped = "")
            return name . ": [ ]"
        else
            return name . ": " . mapped
    }

    Close() {
        this.UI.Destroy()
    }
}
