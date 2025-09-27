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
        UI.Add("Text", "Section", "Click a key below to set the character that represents that physical key in custom dictionaries.")

        for i, key_name in keys.key_list {
            Switch i {
                Case 1, 14:
                    format := "y+5 xs w30 Section"
                Case 27, 38:
                    format := "y+5 xs+15 w30 Section"
                Default:
                    format := "x+5 w30"
            }
            this.controls[key_name] := UI.Add("Button", format, keys.key_map[key_name].symbol , ObjBindMethod(this, "_OnKeyClick", key_name))
        }

        UI.Add("Button", "w80 xs", "Close", ObjBindMethod(this, "Close"))
        ; set window width based on widest row + padding
        UI.Show()
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
        this.mappings[name] := mapped
        if (IsObject(this.controls[name])) {
            this.controls[name].value := this._ButtonLabel(name)
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
        for _, name in keys.key_list {
            value := ini.LoadProperty("pk_" . name, "Physical Key Mapping", config_filename)
            this.mappings[name] := value
        }
    }

    Close() {
        this.UI.Destroy()
    }
}
