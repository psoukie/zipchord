#include version.ahk

ahk_exe := A_ProgramFiles . "\AutoHotkey\Compiler\Ahk2Exe.exe"
odin_exe := "odin"
build_dir := FullPath(A_ScriptDir . "\..\build")
zipchord_exe := build_dir . "\zipchord.exe"
zipchord_dll := build_dir . "\zipchord-lib.dll"
uninstall_exe := build_dir . "\uninstall.exe"
installer_exe := build_dir . "\zipchord-install.exe"
result_file := build_dir . "\result.txt"
odin_version_file := A_ScriptDir . "\zipchord-lib\version.odin"

if ( ! InStr(FileExist(build_dir), "D"))
    FileCreateDir, % build_dir

build_artifacts := ["zipchord.exe", "zipchord-lib.dll", "uninstall.exe", "zipchord-install.exe", "result.txt"
                  , "zipchord-exe-*.zip", "zipchord-install-*.zip"]
For _, artifact in build_artifacts {
    FileDelete, % build_dir . "\\" . artifact
}

WriteOdinVersionFile(odin_version_file, zc_version)

RunWait %ComSpec% /c ""%ahk_exe%" /in zipchord.ahk /out "%zipchord_exe%" /icon zipchord.ico > "%result_file%""
RunWait %ComSpec% /c "call ..\odin-env.bat && %odin_exe% build zipchord-lib -build-mode:dll -out:..\build\zipchord-lib.dll >> ..\build\result.txt 2>&1", %A_ScriptDir%
if !FileExist(zipchord_dll) {
    FileAppend, `r`nERROR: zipchord-lib.dll was not created at %zipchord_dll%.`r`n, % result_file
    FileRead, result, % result_file
    MsgBox, % result
    ExitApp
}
RunWait %ComSpec% /c ""%ahk_exe%" /in uninstall.ahk /out "%uninstall_exe%" /icon shell32_271.ico >> "%result_file%""
RunWait %ComSpec% /c ""%ahk_exe%" /in installer.ahk /out "%installer_exe%" /icon zipchord.ico >> "%result_file%""

Zip(zipchord_exe, build_dir . "\zipchord-exe-" . zc_version . ".zip")
Zip(installer_exe, build_dir . "\zipchord-install-" . zc_version . ".zip")

FileRead, result, % result_file
MsgBox, % result

; Zip code uses an adapted portion of code by Shajul (https://www.autohotkey.com/board/topic/60706-native-zip-and-unzip-xpvista7-ahk-l/)
/*
Zip/Unzip file(s)/folder(s)/wildcard pattern files
Requires: Autohotkey_L, Windows > XP
URL: http://www.autohotkey.com/forum/viewtopic.php?t=65401
Credits: Sean for original idea
*/

Zip(file,sZip) {
    If Not FileExist(sZip)
        CreateZipFile(sZip)
    psh := ComObjCreate( "Shell.Application" )
    pzip := psh.Namespace( sZip )
    pzip.CopyHere( file, 4|16 )

    previous_size := -1
    stable_count := 0
    Loop {
        Sleep, 200
        FileGetSize, current_size, % sZip
        if (current_size > 22 && current_size == previous_size) {
            stable_count += 1
            if (stable_count >= 3) {
                break
            }
        } else {
            stable_count := 0
        }
        previous_size := current_size
    }
}

CreateZipFile(sZip) {
	Header1 := "PK" . Chr(5) . Chr(6)
	VarSetCapacity(Header2, 18, 0)
	file := FileOpen(sZip,"w")
	file.Write(Header1)
	file.RawWrite(Header2,18)
	file.close()
}

FullPath(path) {
    length := DllCall("GetFullPathName", "Str", path, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
    VarSetCapacity(full_path, length * (A_IsUnicode ? 2 : 1))
    DllCall("GetFullPathName", "Str", path, "UInt", length, "Str", full_path, "Ptr", 0, "UInt")
    return full_path
}

WriteOdinVersionFile(filename, version) {
    odin_version =
    (
package zipchord_library

ZC_VERSION :: "%version%"
    )
    FileDelete, % filename
    FileAppend, % odin_version, % filename, UTF-8-RAW
}
