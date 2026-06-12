
#NoEnv
#SingleInstance Force
SetBatchLines, -1

QPC()
; Adjust path as needed.
dllPath := A_ScriptDir . "\zipchord-lib.dll"

; Load DLL once and keep it loaded.
hZipChord := DllCall("LoadLibrary", "Str", dllPath, "Ptr")
if (!hZipChord) {
    MsgBox, 16, ZipChord Error, Failed to load DLL:`n%dllPath%
    ExitApp
}

; Cache function pointers.
zc_init          := DllCall("GetProcAddress", "Ptr", hZipChord, "AStr", "zc_init", "Ptr")
; zc_shutdown      := DllCall("GetProcAddress", "Ptr", hZipChord, "AStr", "zc_shutdown", "Ptr")
; zc_load_chords   := DllCall("GetProcAddress", "Ptr", hZipChord, "AStr", "zc_load_chords", "Ptr")
zc_lookup_chord  := DllCall("GetProcAddress", "Ptr", hZipChord, "AStr", "zc_lookup_chord", "Ptr")
zc_add_chord := DllCall("GetProcAddress", "Ptr", hZipChord, "AStr", "zc_add_chord", "Ptr")

count := DllCall(zc_lookup_count, "Cdecl Int")
MsgBox, Lookup count: %count%

; if (!zc_init || !zc_shutdown || !zc_load_chords || !zc_lookup_chord) {
;     MsgBox, 16, ZipChord Error, Failed to resolve one or more DLL functions.
;     ExitApp
; }

; Initialize DLL state.
ok := DllCall(zc_init, "Cdecl Int")
QPC()

if (!ok) {
    MsgBox, 16, ZipChord Error, zc_init failed.
    ExitApp
}
MsgBox, , Zipchord, Loaded ok

chord := "řžť"
expansion :="řežeť"

pChord := ToUtf8Ptr(chord, chordBuf)
pExpansion := ToUtf8Ptr(expansion, expansionBuf)

saved := DllCall(zc_add_chord, "Ptr", pChord, "Ptr", pExpansion, "Cdecl Int")

MsgBox, , , % "Save result: " . saved

bufSize := 4096
VarSetCapacity(outBuf, bufSize, 0)

pChord2 := ToUtf8Ptr("řžť", chordBuf)

QPC()
written := DllCall(zc_lookup_chord, "Ptr", pChord2, "Ptr", &outBuf, "Int", bufSize, "Cdecl Int")
QPC()

if (written > 0) {
    expansion := StrGet(&outBuf, written, "UTF-8")
    MsgBox, , ZipChord Found, % expansion    
} else {
    expansion := ""
    if (written == 0) {
        MsgBox, , ZipChord Lookup, "Not found"
    } else {
        MsgBox, , ZipChord Error, % written
    }
}
    

Return


QPC() {
	static frequency
    static start
    if (! frequency)
        DllCall("kernel32\QueryPerformanceFrequency", Int64P, frequency)
	DllCall("kernel32\QueryPerformanceCounter", Int64P, count)
    if (start) {
        MsgBox, , , % Format("`nElapsed time (ms): {:.2f}`n",  ((count / frequency) - start) * 1000)
        start := 0
    } else start := count / frequency
}

ToUtf8Ptr(str, ByRef buf) {
   bytes := StrPut(str, "UTF-8")  ; includes terminating null
   VarSetCapacity(buf, bytes, 0)
   StrPut(str, &buf, bytes, "UTF-8")
   return &buf
}

; ; Load dictionary file.
; dictPath := A_ScriptDir . "\chords.txt"

; ok := DllCall(
;     zc_load_chords,
;     "AStr", dictPath,
;     "Cdecl Int"
; )

; if (!ok) {
;     MsgBox, 16, ZipChord Error, Failed to load chord dictionary:`n%dictPath%
;     ExitApp
; }

; ; Example lookup.
; chord := "th"
; expansion := ZipChord_LookupChord(chord)

; MsgBox, Chord: %chord%`nExpansion: %expansion%

; return


; OnExit, ZipChord_Cleanup

; ZipChord_Cleanup:
;     global hZipChord, zc_shutdown

;     if (zc_shutdown) {
;         DllCall(zc_shutdown, "Cdecl")
;     }

;     if (hZipChord) {
;         DllCall("FreeLibrary", "Ptr", hZipChord)
;     }

;     ExitApp
