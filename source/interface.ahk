/*
This file is part of ZipChord.
Copyright (c) 2021-2026 Pavel Soukenik
Refer to the LICENSE file in the root folder for the BSD-3-Clause license. 
*/

global dll := { available: false
    , buf_size: 4096
    , init: 0
    , load_dictionary: 0
    , lookup: 0
    , reverse_lookup: 0
    , add_chord: 0 }

global dll_buffer := ""

Try_Dll_Init() {
    dllPath := A_ScriptDir . "\zipchord-lib.dll"
    if (! FileExist(dllPath) ) {
        return
    }
    ; Load DLL once and keep it loaded.
    hZipChord := DllCall("LoadLibrary", "Str", dllPath, "Ptr")
    if (!hZipChord) {
        return
    }
    ; Cache function pointers.
    dll.init := DllCall("GetProcAddress", "Ptr", hZipChord, "AStr", "zc_init", "Ptr")
    dll.load_dictionary := DllCall("GetProcAddress", "Ptr", hZipChord, "AStr", "zc_load_dictionary", "Ptr")
    dll.lookup := DllCall("GetProcAddress", "Ptr", hZipChord, "AStr", "zc_lookup", "Ptr")
    dll.reverse_lookup := DllCall("GetProcAddress", "Ptr", hZipChord, "AStr", "zc_reverse_lookup", "Ptr")
    dll.register_shortcut := DllCall("GetProcAddress", "Ptr", hZipChord, "AStr", "zc_register_shortcut", "Ptr")
        
    if (!dll.init || !dll.load_dictionary || !dll.lookup || !dll.reverse_lookup || !dll.register_shortcut) {
        return
    }
    ; Initialize DLL state.
    ok := DllCall(dll.init, "Cdecl Int")
    if (ok==0) {
        VarSetCapacity(dll_buffer, dll.buf_size, 0)
        dll.available := true
    }
}

; dictPath := A_ScriptDir . "\zipchord-lib-tests\en-dvorak.chords.txt"
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

ToUtf8Ptr(str, ByRef buf) {
   bytes := StrPut(str, "UTF-8")  ; includes terminating null
   VarSetCapacity(buf, bytes, 0)
   StrPut(str, &buf, bytes, "UTF-8")
   return &buf
}
