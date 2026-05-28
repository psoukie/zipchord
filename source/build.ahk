#include version.ahk

ahk_exe := A_ProgramFiles . "\AutoHotkey\Compiler\Ahk2Exe.exe"
build_dir := A_ScriptDir . "\..\build"
zipchord_exe := "..\build\zipchord.exe"
uninstall_exe := "..\build\uninstall.exe"
installer_exe := "..\build\zipchord-install.exe"
result_file := "..\build\result.txt"

FileDelete, build_dir . "\zipchord.exe"
FileDelete, build_dir . "\uninstall.exe"
FileDelete, build_dir . "\zipchord-install.exe"

FileDelete, build_dir . "\result.txt"

RunWait %ComSpec% /c ""%ahk_exe%" /in zipchord.ahk /out %zipchord_exe% /icon zipchord.ico > %result_file%"
RunWait %ComSpec% /c ""%ahk_exe%" /in uninstall.ahk /out %uninstall_exe% /icon shell32_271.ico >> %result_file%"
RunWait %ComSpec% /c ""%ahk_exe%" /in installer.ahk /out %installer_exe% /icon zipchord.ico >> %result_file%"

FileDelete, build_dir . "\zipchord-exe-" . zc_version . ".zip"
FileDelete, build_dir . "\zipchord-install-" . zc_version . ".zip"
Zip(zipchord_exe, "..\build\zipchord-exe-" . zc_version . ".zip")
Zip(installer_exe, "..\build\zipchord-install-" . zc_version . ".zip")

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
    file := A_ScriptDir . "\" . file
    sZip := A_ScriptDir . "\" . sZip
    If Not FileExist(sZip)
        CreateZipFile(sZip)
    psh := ComObjCreate( "Shell.Application" )
    pzip := psh.Namespace( sZip )
    pzip.CopyHere( file, 4|16 )
}

CreateZipFile(sZip) {
	Header1 := "PK" . Chr(5) . Chr(6)
	VarSetCapacity(Header2, 18, 0)
	file := FileOpen(sZip,"w")
	file.Write(Header1)
	file.RawWrite(Header2,18)
	file.close()
}