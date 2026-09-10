#Requires AutoHotkey v2.0
#SingleInstance Force

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

; Stop hider, remove shortcut and install folder. If
; this process is inside installDir, defer rmdir via
; cmd so we can exit first.
RunUninstall(installDir, shortcutPath) {
    CloseAllRunningFromInstallDir(installDir)

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
            . "The screenshare indicator hider has "
            . "been removed and will no longer start "
            . "when you log in.",
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
    SetTitleMatchMode(2)  ; substring match

    ; Add patterns for other browser/language titles.
    global TITLE_PATTERNS := [
        "is sharing your screen",
        "is sharing a window",
        "Sharing Indicator"  ; Firefox-family
    ]
    global CHROMIUM_CLASS := "Chrome_WidgetWin_1"
    global FIREFOX_CLASS := "MozillaDialogClass"

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

; Chromium: minimize. Firefox: shrink + move off-screen
; (minimize leaves a corner duplicate).
HideShareIndicator(hwnd, isChromium) {
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
        ; 1x1 just past virtual-screen top-left.
        WinMove(
            SysGet(76) - 1, SysGet(77) - 1, 1, 1, hwnd
        )
    }
}