zc_version := "2.2.0"
;@Ahk2Exe-SetVersion %A_PriorLine~U)^(.+"){1}(.+)".*$~$2%
zc_app_name := "ZipChord"
;@Ahk2Exe-SetName %A_PriorLine~U)^(.+"){1}(.+)".*$~$2%
;@Ahk2Exe-SetDescription ZipChord 2.2
;@Ahk2Exe-SetCopyright Pavel Soukenik (2021-2024)