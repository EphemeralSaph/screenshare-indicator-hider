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
; Used before overwriting the installed hider, so a currently-running
; previous install doesn't lock the file and cause FileCopy to fail.
; Matches on the full path (via WMI's ExecutablePath), not just the
; process name, so we never accidentally close some unrelated
; program that happens to share the same filename elsewhere.
CloseRunningInstalledHider(exactPath) {
    try {
        ; Backslashes must be escaped for the WMI query string.
        escapedPath := StrReplace(exactPath, "\", "\\")
        wmi := ComObjGet("winmgmts:")
        results := wmi.ExecQuery("Select * from Win32_Process where ExecutablePath = '" . escapedPath . "'")
        for proc in results {
            try {
                proc.Terminate()
            }
        }
        ; Give Windows a brief moment to fully release the file
        ; handle after termination before we try to overwrite it.
        if (results.Count > 0) {
            Sleep(300)
        }
    } catch {
        ; Non-fatal — if this fails for any reason (e.g. WMI
        ; unavailable), we just proceed to the FileCopy attempt as
        ; before, which will surface its own error if still locked.
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
    startupDir    := A_Startup
    shortcutPath  := startupDir . "\ScreenShareIndicatorHider.lnk"

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

    ; Shrink to 1x1px and move fully off-screen. Done every tick
    ; (not gated) in case the window snaps back to center.
    WinMove(-2000, -2000, 1, 1, hwnd)
}