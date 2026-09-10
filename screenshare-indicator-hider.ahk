#Requires AutoHotkey v2.0
#SingleInstance Force



; Add patterns for other browser/language titles.
global TITLE_PATTERNS := [
    "is sharing your screen",
    "is sharing a window",
    "Sharing Indicator"  ; Firefox-family
]
global CHROMIUM_CLASS := "Chrome_WidgetWin_1"
global FIREFOX_CLASS := "MozillaDialogClass"
global GEOMETRY_FILE_NAME := "firefox-geometry.ini"

if (A_Args.Length > 0 && A_Args[1] = "/hide") {
    RunHider()
} else {
    RunSetup()
}

; Close process at exactPath via WMI (path match, not
; name). Skips our PID so reinstall from install dir
; does not kill this process. Sleeps briefly after
; terminate so the file unlocks before overwrite/delete.
CloseRunningInstalledHider(exactPath) {
    try {
        ; Escape backslashes for the WMI query string.
        escapedPath := StrReplace(exactPath, "\", "\\")
        wmi := ComObjGet("winmgmts:")
        query := "Select * from Win32_Process where "
            . "ExecutablePath = '" . escapedPath . "'"
        results := wmi.ExecQuery(query)
        myPid := ProcessExist()
        for proc in results {
            try {
                if (Integer(proc.ProcessId) != myPid) {
                    proc.Terminate()
                }
            }
        }
        if (results.Count > 0) {
            Sleep(300)
        }
    } catch {
        ; Non-fatal; FileCopy/DirDelete will error if
        ; the file is still locked.
    }
}

; True if Startup shortcut or install-folder files exist.
IsAlreadyInstalled(installDir, shortcutPath) {
    if FileExist(shortcutPath) {
        return true
    }
    if !DirExist(installDir) {
        return false
    }
    Loop Files, installDir . "\*.*" {
        return true
    }
    return false
}

; Stop processes whose ExecutablePath is under installDir
; (covers renames between versions).
CloseAllRunningFromInstallDir(installDir) {
    if !DirExist(installDir) {
        return
    }
    Loop Files, installDir . "\*.*" {
        CloseRunningInstalledHider(A_LoopFileFullPath)
    }
}

FirefoxGeometryPath(installDir) {
    global GEOMETRY_FILE_NAME
    return installDir . "\" . GEOMETRY_FILE_NAME
}

; Persist original Firefox indicator bounds before the
; 1x1 off-screen move so uninstall can restore exactly.
SaveFirefoxGeometry(installDir, hwnd, x, y, w, h) {
    if !DirExist(installDir) {
        return
    }
    try {
        IniWrite(
            x . "," . y . "," . w . "," . h,
            FirefoxGeometryPath(installDir),
            "Geometry",
            String(Integer(hwnd))
        )
    } catch {
        ; Non-fatal — hide still works without restore.
    }
}

; Returns [x, y, w, h] or false if missing/invalid.
LoadFirefoxGeometry(installDir, hwnd) {
    path := FirefoxGeometryPath(installDir)
    if !FileExist(path) {
        return false
    }
    try {
        val := IniRead(
            path, "Geometry", String(Integer(hwnd)), ""
        )
    } catch {
        return false
    }
    if (val = "" || val = "ERROR") {
        return false
    }
    parts := StrSplit(val, ",")
    if (parts.Length != 4) {
        return false
    }
    try {
        return [
            Integer(parts[1]),
            Integer(parts[2]),
            Integer(parts[3]),
            Integer(parts[4])
        ]
    } catch {
        return false
    }
}

; Undo hide mutations on any live indicator windows.
; Call after stopping the hider so the timer cannot
; re-hide during restore.
RestoreShareIndicators(installDir) {
    global TITLE_PATTERNS, CHROMIUM_CLASS, FIREFOX_CLASS

    SetTitleMatchMode(2)
    for pattern in TITLE_PATTERNS {
        for hwnd in WinGetList(
            pattern . " ahk_class " . CHROMIUM_CLASS
        ) {
            RestoreShareIndicator(installDir, hwnd, true)
        }
        for hwnd in WinGetList(
            pattern . " ahk_class " . FIREFOX_CLASS
        ) {
            RestoreShareIndicator(installDir, hwnd, false)
        }
    }
}

RestoreShareIndicator(installDir, hwnd, isChromium) {
    try {
        if !WinExist("ahk_id " . hwnd) {
            return
        }
        exStyle := WinGetExStyle(hwnd)
        if (exStyle & 0x80) {
            WinSetExStyle("-0x80", hwnd)
            WinHide(hwnd)
            WinShow(hwnd)
        }
        if isChromium {
            if (WinGetMinMax(hwnd) = -1) {
                WinRestore(hwnd)
            }
        } else {
            ; Unminimize first — WinMove alone does not.
            if (WinGetMinMax(hwnd) = -1) {
                WinRestore(hwnd)
            }
            geo := LoadFirefoxGeometry(installDir, hwnd)
            if geo {
                WinMove(geo[1], geo[2], geo[3], geo[4], hwnd)
            }
        }
    } catch {
        ; Window may have closed mid-restore.
    }
}

RunSetup() {
    localAppData := EnvGet("LocalAppData")
    if (localAppData = "") {
        MsgBox(
            "Couldn't determine your LocalAppData "
            . "folder (it came back empty).`n`n"
            . "This is unusual — please report this.",
            "Install failed",
            "IconX"
        )
        ExitApp()
    }

    installDir := localAppData
        . "\ScreenShareIndicatorHider"
    ; Live filename so renaming the exe still works.
    SplitPath(A_ScriptFullPath, &exeFileName)
    destPath := installDir . "\" . exeFileName
    shortcutPath := A_Startup
        . "\ScreenShareIndicatorHider.lnk"

    if IsAlreadyInstalled(installDir, shortcutPath) {
        choice := MsgBox(
            "The screenshare indicator hider is "
            . "already installed.`n`n"
            . "Yes — Reinstall / update`n"
            . "No — Uninstall completely`n"
            . "Cancel — Leave everything as-is",
            "Screenshare Indicator Hider",
            "YesNoCancel Icon?"
        )
        if (choice = "Cancel") {
            ExitApp()
        }
        if (choice = "No") {
            RunUninstall(installDir, shortcutPath)
            return
        }
    }

    if !DirExist(installDir) {
        DirCreate(installDir)
    }

    ; Unlock installed copy before overwrite.
    CloseRunningInstalledHider(destPath)

    try {
        FileCopy(A_ScriptFullPath, destPath, true)
    } catch as err {
        MsgBox(
            "Couldn't install to " . installDir
            . ".`n`nError: " . err.Message
            . "`n`nIf this keeps happening, check Task "
            . "Manager for a running '" . exeFileName
            . "' process and end it manually, then "
            . "try again.",
            "Install failed",
            "IconX"
        )
        ExitApp()
    }

    ; /hide so login starts hider mode, not setup.
    try {
        FileCreateShortcut(
            destPath, shortcutPath, installDir, "/hide"
        )
    } catch as err {
        MsgBox(
            "Installed, but couldn't create the "
            . "Startup shortcut.`n`nError: "
            . err.Message,
            "Partial install",
            "IconX"
        )
        ExitApp()
    }

    launchedNow := false
    try {
        Run('"' . destPath . '" /hide')
        launchedNow := true
    } catch {
        ; Non-fatal — Startup shortcut still works.
    }

    if (launchedNow) {
        statusMsg := "The screenshare indicator hider "
            . "is now running in the background, and "
            . "will start automatically every time you "
            . "log in."
    } else {
        statusMsg := "It couldn't be started in the "
            . "background right now, but it will still "
            . "start automatically every time you log "
            . "in (or after you restart)."
    }

    MsgBox(
        "Installed!`n`n"
        . statusMsg . "`n`n"
        . "Installed to:`n" . destPath,
        "Screenshare Indicator Hider",
        "Iconi"
    )
    ExitApp()
}

; Stop hider, restore any hidden indicators, remove
; shortcut and install folder. If this process is
; inside installDir, defer rmdir via cmd so we can
; exit first.
RunUninstall(installDir, shortcutPath) {
    CloseAllRunningFromInstallDir(installDir)
    RestoreShareIndicators(installDir)

    shortcutRemoved := true
    if FileExist(shortcutPath) {
        try {
            FileDelete(shortcutPath)
        } catch {
            shortcutRemoved := false
        }
    }

    folderRemoved := true
    if DirExist(installDir) {
        if (StrLower(A_ScriptDir) = StrLower(installDir)) {
            Run(
                A_ComSpec . ' /c ping 127.0.0.1 -n 2 '
                . '> nul & rmdir /s /q "'
                . installDir . '"',
                ,
                "Hide"
            )
        } else {
            try {
                DirDelete(installDir, true)
            } catch {
                folderRemoved := false
            }
        }
    }

    if (shortcutRemoved && folderRemoved) {
        MsgBox(
            "Uninstalled!`n`n"
            . "Any hidden screenshare indicator "
            . "windows have been restored. The hider "
            . "has been removed and will no longer "
            . "start when you log in.",
            "Screenshare Indicator Hider",
            "Iconi"
        )
    } else {
        directions := ""
        if !shortcutRemoved {
            directions .=
                "`n`nStartup shortcut`n"
                . "1. Press Win+R, type shell:startup, "
                . "and press Enter.`n"
                . "2. Delete this file:`n"
                . "   " . shortcutPath
        }
        if !folderRemoved {
            directions .=
                "`n`nInstall folder`n"
                . "1. Press Win+R, paste the path "
                . "below, and press Enter.`n"
                . "2. Delete the folder (or everything "
                . "inside it):`n"
                . "   " . installDir
        }
        MsgBox(
            "Uninstall mostly finished, but something "
            . "couldn't be removed. Please delete the "
            . "leftover item(s) manually:"
            . directions,
            "Partial uninstall",
            "Icon!"
        )
    }
    ExitApp()
}

RunHider() {
    localAppData := EnvGet("LocalAppData")
    global INSTALL_DIR := ""
    if (localAppData != "") {
        INSTALL_DIR := localAppData
            . "\ScreenShareIndicatorHider"
    }

    SetTitleMatchMode(2)
    SetTimer(CheckForShareIndicator, 500)
}

CheckForShareIndicator() {
    global TITLE_PATTERNS, CHROMIUM_CLASS, FIREFOX_CLASS

    for pattern in TITLE_PATTERNS {
        hwnd := WinExist(
            pattern . " ahk_class " . CHROMIUM_CLASS
        )
        if hwnd {
            HideShareIndicator(hwnd, true)
            continue
        }
        hwnd := WinExist(
            pattern . " ahk_class " . FIREFOX_CLASS
        )
        if hwnd {
            HideShareIndicator(hwnd, false)
        }
    }
}

; Chromium: minimize. Firefox: restore if needed, then
; shrink + move off-screen (minimize leaves a visible bar).
HideShareIndicator(hwnd, isChromium) {
    global INSTALL_DIR

    exStyle := WinGetExStyle(hwnd)

    ; WS_EX_TOOLWINDOW once; hide/show refreshes taskbar.
    if !(exStyle & 0x80) {
        WinSetExStyle("+0x80", hwnd)
        WinHide(hwnd)
        WinShow(hwnd)
    }

    if isChromium {
        ; Re-apply if the window is restored.
        if (WinGetMinMax(hwnd) != -1) {
            WinMinimize(hwnd)
        }
    } else {
        ; WinMove on a minimized window only nudges the
        ; iconic placement (e.g. to -1,-1) and leaves a
        ; visible title-bar remnant — restore first.
        if (WinGetMinMax(hwnd) = -1) {
            WinRestore(hwnd)
        }
        WinGetPos(&x, &y, &w, &h, hwnd)
        ; Save original bounds only — not our 1x1 park.
        if (INSTALL_DIR != "" && (w > 1 || h > 1)) {
            SaveFirefoxGeometry(INSTALL_DIR, hwnd, x, y, w, h)
        }
        ; 1x1 just past virtual-screen top-left.
        WinMove(
            SysGet(76) - 1, SysGet(77) - 1, 1, 1, hwnd
        )
    }
}