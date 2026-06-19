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
        dllPath := A_ScriptDir . "\zipchord-lib.dll"
        if (! FileExist(dllPath) ) {
            return
        }
        if !(this._Cache_Pointers(dllPath)) {
            return
        }
        ; Initialize DLL state.
        if (DllCall(this._init_fn, "Cdecl Int") != 0) {
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
        this._load_dictionary_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_load_dictionary", "Ptr")
        this._lookup_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_lookup", "Ptr")
        this._reverse_lookup_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_reverse_lookup", "Ptr")
        this._register_shortcut_fn := DllCall("GetProcAddress", "Ptr", hZC, "AStr", "zc_register_shortcut", "Ptr")
        
        if (this._init_fn && this._load_dictionary_fn && this._lookup_fn && this._reverse_lookup_fn && this._register_shortcut_fn) {
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

    LoadDictionary(dictionary_path, chorded) {
        pDictPath := this._StringToPtr(dictionary_path, dictPathBuf)
        return DllCall(this._load_dictionary_fn, "Ptr", pDictPath, "Int", chorded, "Cdecl Int")
    }

    RegisterShortcut(raw_shortcut, expansion, chorded) {
        pShortcut := this._StringToPtr(raw_shortcut, shortcutBuf)
        pExpansion := this._StringToPtr(expansion, expansionBuf)
        return DllCall(this._register_shortcut_fn, "Ptr", pShortcut, "Ptr", pExpansion, "Int", chorded, "Cdecl Int")
    }

    Lookup(shortcut, chorded) {
        global dll_buffer
        pShortcut := this._StringToPtr(shortcut, shortcutBuf)
        result := DllCall(this._lookup_fn, "Ptr", pShortcut, "Int", chorded, "Ptr", &dll_buffer, "Int", this._buf_size, "Cdecl Int")

        if (result > 0) {
            return StrGet(&dll_buffer, result, "UTF-8")
        } else {
            return false
        }
    }

    ReverseLookUp(expansion, chorded) {
        global dll_buffer
        pExpansion := this._StringToPtr(expansion, expansionBuf)
        result := DllCall(this._reverse_lookup_fn, "Ptr", pExpansion, "Int", chorded, "Ptr", &dll_buffer, "Int", this._buf_size, "Cdecl Int")

        if (result > 0) {
            return StrGet(&dll_buffer, result, "UTF-8")
        } else {
            return false
        }
    }
}

; pDictPath := ToUtf8Ptr(dictPath, dictPathBuf)
; loadResult := DllCall(zc_load_dictionary, "Ptr", pDictPath, "Int", 1, "Cdecl Int")
; MsgBox, , ZipChord Load Dictionary, % loadResult

; if (loadResult < 0) {
;     MsgBox, 16, ZipChord Error, % "zc_load_dictionary failed: " . loadResult . "`n" . dictPath
;     ExitApp
; }

; chord := "řžť"
; expansion :="řežeť"

; pChord := ToUtf8Ptr(chord, chordBuf)
; pExpansion := ToUtf8Ptr(expansion, expansionBuf)

; saved := DllCall(zc_add_chord, "Ptr", pChord, "Ptr", pExpansion, "Cdecl Int")

; MsgBox, , , % "Save result: " . saved

; QPC()
; bufSize := 4096
; VarSetCapacity(outBuf, bufSize, 0)

; pChord2 := ToUtf8Ptr("ms", chordBuf)

; written := DllCall(zc_lookup_chord, "Ptr", pChord2, "Ptr", &outBuf, "Int", bufSize, "Cdecl Int")
; QPC()

; if (written > 0) {
;     expansion := StrGet(&outBuf, written, "UTF-8")
;     MsgBox, , ZipChord Found, % expansion    
; } else {
;     expansion := ""
;     if (written == -1) {
;         MsgBox, , ZipChord Lookup, "Not found"
;     } else {
;         MsgBox, , ZipChord Error, % written
;     }
; }

