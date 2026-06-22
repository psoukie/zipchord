/*
This file is part of ZipChord.
Copyright (c) 2021-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

dll_buffer := ""
global dll := New clsDllBindings

Class clsDllBindings {
    available := false

    _buf_size := 4096
    _init_fn := 0
    _load_dictionary_fn := 0
    _lookup_fn := 0
    _reverse_lookup_fn := 0
    _add_chord_fn := 0
    _register_shortcut_fn := 0

    __New() {
        global dll_buffer
        global zc_version
        
        dllPath := A_ScriptDir . "\zipchord-lib.dll"
        if (! FileExist(dllPath) ) {
            return
        }
        if !(this._Cache_Pointers(dllPath)) {
            return
        }
        ; Initialize DLL state.
        pVersion := this._StringToPtr(zc_version, versionBuf)
        result := DllCall(this._init_fn, "Ptr", pVersion, "Cdecl Int")
        if (result == -11) {
            MsgBox , , % "ZipChord", % "The compiled library has an incompatible version. ZipChord will use its built-in AutoHotkey implementation."
            return
        }
        if (result != 0) {
            MsgBox , , % "ZipChord", % "There was an error while initializing the compiled library. ZipChord will use its built-in AutoHotkey implementation."
            return
        }
        ; Initialize buffer
        capacity := VarSetCapacity(dll_buffer, this._buf_size, 0)
        if (capacity < this._buf_size) {
            return        
        }

        this.available := true
    }

    _Cache_Pointers(dllPath) {  ; Returns true for 'okay'
        ; Load DLL once and keep it loaded.
        hZC := DllCall("LoadLibrary", "Str", dllPath, "Ptr")
        if (!hZC) {
            return false
        }
        ; Cache function pointers.
        this._init_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_init", "Ptr")
        this._destroy_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_destroy", "Ptr")
        this._load_dictionary_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_load_dictionary", "Ptr")
        this._lookup_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_lookup", "Ptr")
        this._reverse_lookup_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_reverse_lookup", "Ptr")
        this._register_shortcut_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_register_shortcut", "Ptr")
        this._get_saved_string_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_get_saved_string", "Ptr")
        
        if (this._init_fn && this._destroy_fn && this._load_dictionary_fn && this._lookup_fn && this._reverse_lookup_fn && this._register_shortcut_fn && this._get_saved_string_fn) {
            return true
        }
        return false
    }

    _StringToPtr(str, ByRef buf) {
       bytes := StrPut(str, "UTF-8")  ; bytes needed, including terminating null
       capacity := VarSetCapacity(buf, bytes, 0)
        if (capacity < bytes) {
            MsgBox , , ZipChord Error TK, Could not allocate
            return        
        }
       StrPut(str, &buf, bytes, "UTF-8")
       return &buf
    }

    Destroy() {
        return DllCall(this._destroy_fn, "Cdecl Int")
    }

    LoadDictionary(dictionary_path, chorded, ByRef shortcuts_loaded) {
        global dll_buffer
        pDictPath := this._StringToPtr(dictionary_path, dictPathBuf)
        return DllCall(this._load_dictionary_fn
                , "Ptr", pDictPath
                , "Int", chorded
                , "IntP", shortcuts_loaded
                , "Cdecl Int")
    }

    RegisterShortcut(raw_shortcut, expansion, chorded) {
        pShortcut := this._StringToPtr(raw_shortcut, shortcutBuf)
        pExpansion := this._StringToPtr(expansion, expansionBuf)
        return DllCall(this._register_shortcut_fn
                , "Ptr", pShortcut
                , "Ptr", pExpansion
                , "Int", chorded
                , "Cdecl Int")
    }

    GetSavedString() {
        global dll_buffer
        result := DllCall(this._get_saved_string_fn
                , "Ptr", &dll_buffer
                , "Int", this._buf_size
                , "Cdecl Int")

        if (result == 0) {
            return StrGet(&dll_buffer, "UTF-8")
        }
        return ""
    }

    Lookup(shortcut, chorded) {
        global dll_buffer
        pShortcut := this._StringToPtr(shortcut, shortcutBuf)
        result := DllCall(this._lookup_fn
                , "Ptr", pShortcut
                , "Int", chorded
                , "Ptr", &dll_buffer
                , "Int", this._buf_size
                , "Cdecl Int")

        if (result == 0) {
            return StrGet(&dll_buffer, "UTF-8")
        }
        return false
    }

    ReverseLookUp(expansion, chorded) {
        global dll_buffer
        pExpansion := this._StringToPtr(expansion, expansionBuf)
        result := DllCall(this._reverse_lookup_fn
                , "Ptr", pExpansion
                , "Int", chorded
                , "Ptr", &dll_buffer
                , "Int", this._buf_size
                , "Cdecl Int")
        if (result == 0) {
            return StrGet(&dll_buffer, "UTF-8")
        }
        return false
    }
}

