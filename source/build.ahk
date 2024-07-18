#include version.ahk

ahk_exe := A_ProgramFiles . "\AutoHotkey\Compiler\Ahk2Exe.exe"

FileDelete, A_ScriptDir . "\" . "zipchord.exe"
FileDelete, A_ScriptDir . "\" . "uninstall.exe"
FileDelete, A_ScriptDir . "\" . "zipchord-install.exe"

RunWait %ComSpec% /c ""%ahk_exe%" /in zipchord.ahk /icon zipchord.ico > result.txt"
RunWait %ComSpec% /c ""%ahk_exe%" /in uninstall.ahk /icon shell32_271.ico >> result.txt"
RunWait %ComSpec% /c ""%ahk_exe%" /in installer.ahk /out zipchord-install.exe /icon zipchord.ico >> result.txt"

FileDelete, "zipchord-exe-" . zc_version . ".zip"
FileDelete, "zipchord-install-" . zc_version . ".zip"
Zip("zipchord.exe", "zipchord-exe-" . zc_version . ".zip")
Zip("zipchord-install.exe", "zipchord-install-" . zc_version . ".zip")

FileRead, result, result.txt
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