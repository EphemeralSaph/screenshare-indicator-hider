#Requires AutoHotkey v2.0
#SingleInstance Force



if (A_Args.Length > 0 && A_Args[1] = "/hide") {
    RunHider()
} else {
    RunSetup()
}

; ===================================================================
;  Helper: close any running process matching an exact exe path
; ===================================================================
; Used before overwriting or deleting the installed hider, so a
; currently-running previous install doesn't lock the file.
; Matches on the full path (via WMI's ExecutablePath), not just the
; process name, so we never accidentally close some unrelated
; program that happens to share the same filename elsewhere.
CloseRunningInstalledHider(exactPath) {
    try {
        ; Backslashes must be escaped for the WMI query string.
        escapedPath := StrReplace(exactPath, "\", "\\")
        wmi := ComObjGet("winmgmts:")
        results := wmi.ExecQuery("Select * from Win32_Process where ExecutablePath = '" . escapedPath . "'")
        ; Never terminate ourselves — e.g. user double-clicked the
        ; installed copy to reinstall/uninstall, so exactPath is us.
        myPid := ProcessExist()
        for proc in results {
            try {
                if (Integer(proc.ProcessId) != myPid) {
                    proc.Terminate()
                }
            }
        }
        ; Give Windows a brief moment to fully release the file
        ; handle after termination before we try to overwrite/delete.
        if (results.Count > 0) {
            Sleep(300)
        }
    } catch {
        ; Non-fatal — if this fails for any reason (e.g. WMI
        ; unavailable), we just proceed; the later FileCopy /
        ; DirDelete will surface its own error if still locked.
    }
}

; True if a prior install left behind its Startup shortcut and/or
; anything in the install folder.
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

; Stop every process whose ExecutablePath is a file inside installDir
; (covers renames between versions — not just the current exe name).
CloseAllRunningFromInstallDir(installDir) {
    if !DirExist(installDir) {
        return
    }
    Loop Files, installDir . "\*.*" {
        CloseRunningInstalledHider(A_LoopFileFullPath)
    }
}

; ===================================================================
;  SETUP mode
; ===================================================================
RunSetup() {
    localAppData := EnvGet("LocalAppData")
    if (localAppData = "") {
        MsgBox("Couldn't determine your LocalAppData folder (it came back empty).`n`nThis is unusual — please report this.", "Install failed", "IconX")
        ExitApp()
    }

    installDir   := localAppData . "\ScreenShareIndicatorHider"
    ; A_ScriptFullPath is this running exe's own path — compiled or
    ; not, so this line works identically in both cases. Using the
    ; live current filename here (rather than a hardcoded literal)
    ; means renaming the exe doesn't break the install.
    exeName       := A_ScriptFullPath
    SplitPath(exeName, &exeFileName)
    destPath      := installDir . "\" . exeFileName
    shortcutPath  := A_Startup . "\ScreenShareIndicatorHider.lnk"

    ; Already installed? Offer reinstall vs uninstall instead of
    ; silently overwriting (uninstall keeps the flow as simple as
    ; install: double-click the same exe again).
    if IsAlreadyInstalled(installDir, shortcutPath) {
        choice := MsgBox(
            "The screenshare indicator hider is already installed.`n`n"
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
        ; "Yes" → fall through and reinstall
    }

    if !DirExist(installDir) {
        DirCreate(installDir)
    }

    ; If a previous install of the hider is currently running, its
    ; .exe file is locked and FileCopy below would fail with a vague
    ; "Failed" error. Close any running instance of the INSTALLED
    ; copy specifically (matched by its exact path, not just name,
    ; so we never touch some unrelated program) before overwriting it.
    CloseRunningInstalledHider(destPath)

    ; Copy THIS running exe to the install location. Works whether
    ; compiled (copies the real .exe bytes) or run as source during
    ; testing (copies the .ahk file) — either way, A_ScriptFullPath
    ; points at whatever's actually running right now.
    try {
        FileCopy(A_ScriptFullPath, destPath, true)
    } catch as err {
        MsgBox("Couldn't install to " . installDir . ".`n`nError: " . err.Message . "`n`nIf this keeps happening, check Task Manager for a running '" . exeFileName . "' process and end it manually, then try again.", "Install failed", "IconX")
        ExitApp()
    }

    ; Shortcut launches the installed copy WITH the /hide argument,
    ; so it runs in hider mode automatically at every login instead
    ; of re-triggering setup.
    try {
        FileCreateShortcut(destPath, shortcutPath, installDir, "/hide")
    } catch as err {
        MsgBox("Installed, but couldn't create the Startup shortcut.`n`nError: " . err.Message, "Partial install", "IconX")
        ExitApp()
    }

    ; Launch the installed copy in hider mode right now, so it's
    ; active immediately without needing to log out and back in.
    launchedNow := false
    try {
        Run('"' . destPath . '" /hide')
        launchedNow := true
    } catch {
        ; Non-fatal — it'll still start next login via the shortcut.
    }

    if (launchedNow) {
        statusMsg := "The screenshare indicator hider is now running in the background, "
            . "and will start automatically every time you log in."
    } else {
        statusMsg := "It couldn't be started in the background right now, "
            . "but it will still start automatically every time you log in "
            . "(or after you restart)."
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

; ===================================================================
;  UNINSTALL mode
; ===================================================================
; Reverses setup: stop the running hider, remove the Startup
; shortcut, delete the install folder. Safe to run from the
; downloaded copy; if this process is itself inside the install
; folder, deletion is deferred via a short cmd so we can exit first.
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
        ; Can't delete our own directory while this process still has
        ; the exe/script open inside it — schedule a delayed rmdir.
        if (StrLower(A_ScriptDir) = StrLower(installDir)) {
            Run(
                A_ComSpec . ' /c ping 127.0.0.1 -n 2 > nul & rmdir /s /q "' . installDir . '"',
                ,
                "Hide"
            )
            ; Assume success; the delayed delete runs after we exit.
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
            . "The screenshare indicator hider has been removed and will no longer start when you log in.",
            "Screenshare Indicator Hider",
            "Iconi"
        )
    } else {
        directions := ""
        if !shortcutRemoved {
            directions .=
                "`n`nStartup shortcut`n"
                . "1. Press Win+R, type shell:startup, and press Enter.`n"
                . "2. Delete this file:`n"
                . "   " . shortcutPath
        }
        if !folderRemoved {
            directions .=
                "`n`nInstall folder`n"
                . "1. Press Win+R, paste the path below, and press Enter.`n"
                . "2. Delete the folder (or everything inside it):`n"
                . "   " . installDir
        }
        MsgBox(
            "Uninstall mostly finished, but something couldn't be removed."
            . " Please delete the leftover item(s) manually:"
            . directions,
            "Partial uninstall",
            "Icon!"
        )
    }
    ExitApp()
}

; ===================================================================
;  HIDER mode
; ===================================================================
RunHider() {
    SetTitleMatchMode(2)  ; match anywhere in the title

    ; Add more patterns here if your browser/language shows different
    ; text. Matching is substring-based (SetTitleMatchMode 2).
    global TITLE_PATTERNS := [
        "is sharing your screen",
        "is sharing a window",
        "Sharing Indicator"          ; Firefox-family wording
    ]

    ; Window classes used by each browser engine's share-indicator
    ; window. Chromium-family browsers all share one class regardless
    ; of which specific browser they are; same for Firefox-family.
    global CHROMIUM_CLASS := "Chrome_WidgetWin_1"
    global FIREFOX_CLASS  := "MozillaDialogClass"

    SetTimer(CheckForShareIndicator, 500)
}

CheckForShareIndicator() {
    global TITLE_PATTERNS, CHROMIUM_CLASS, FIREFOX_CLASS

    for pattern in TITLE_PATTERNS {
        ; hwnd = window handle: Windows' ID for a specific open window.
        ; Try matching this title pattern on a Chromium-classed window...
        hwnd := WinExist(pattern . " ahk_class " . CHROMIUM_CLASS)
        if !hwnd {
            ; ...or a Firefox-classed window.
            hwnd := WinExist(pattern . " ahk_class " . FIREFOX_CLASS)
        }

        if hwnd {
            HideFromTaskbarAndMoveOffscreen(hwnd)
        }
    }
}

HideFromTaskbarAndMoveOffscreen(hwnd) {
    exStyle := WinGetExStyle(hwnd)

    ; Only need to apply TOOLWINDOW once per window handle.
    if !(exStyle & 0x80) {
        WinSetExStyle("+0x80", hwnd)  ; add WS_EX_TOOLWINDOW

        ; Force the taskbar to re-evaluate the window by briefly
        ; hiding and reshowing it.
        WinHide(hwnd)
        WinShow(hwnd)
    }

    ; Shrink to 1x1px and park it just past the top-left of the
    ; virtual screen (the bounding box of all monitors). Using
    ; SM_XVIRTUALSCREEN / SM_YVIRTUALSCREEN keeps it off every
    ; display even when a monitor sits left or above the primary.
    ; Done every tick (not gated) in case the window snaps back.
    WinMove(SysGet(76) - 1, SysGet(77) - 1, 1, 1, hwnd)
}