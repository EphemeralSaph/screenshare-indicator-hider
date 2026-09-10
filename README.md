# Screenshare Indicator Hider

Hides the "**X is sharing your screen/window**" or "**You are sharing X**" popup that Chromium- and Firefox-based browsers show during a screenshare, **without stopping the screenshare**. Also hides it from your taskbar and Alt-Tab switcher.

## Installation

1. Download `screenshare-indicator-hider.exe` from this repo's [Releases](../../releases) page.
2. Double-click it.
3. Uncheck "Always ask before opening this file".
4. Click "Run".

Running the downloaded `.exe` again later (e.g. after updating it) shows a prompt: **Yes** reinstalls/updates, **No** uninstalls, **Cancel** leaves things as-is.

## Uninstalling

1. Double-click `screenshare-indicator-hider.exe` again (same file you used to install).
2. Click **No** when asked whether to reinstall or uninstall.

---



## The Problem

Whenever a website shares your screen (Google Meet, Zoom's web client, Discord, Teams' web client, anything using the browser's `getDisplayMedia()` API), your browser opens a small, separate window to confirm what's being shared and give you a "Stop sharing" control. This is a real Windows top-level window, not just a UI overlay — so it:

- Shows up as its **own icon in the taskbar**, forcing you to pick between it and your actual browser window every time you click your browser's taskbar icon.
- Shows up as its **own entry in Alt-Tab**, cluttering your switcher.
- Can't just be **closed** — closing it stops the screenshare, since it doubles as the share's control window.
- [Firefox-based browsers only] Can't be **minimized** without it snapping to a fixed corner instead of disappearing.

This is intentional behavior (it exists so no website can silently hide the fact that it's capturing your screen), but it's still an annoyance with no built-in setting to fix it in Brave, Chrome, Firefox, or any other Chromium/Firefox-based browser.

## The Solution

This tool watches for that indicator window and, the moment it appears:

1. Applies the `WS_EX_TOOLWINDOW` extended window style to it, which tells Windows to exclude it from the taskbar and Alt-Tab. (A brief hide/show cycle is needed right after, since Windows' taskbar manager only re-checks a window's style when it re-appears, not continuously.)
2. Shrinks it to a 1×1 pixel and moves it to off-screen coordinates (`-2000, -2000`) — a position with no physical monitor to render on, so it's fully invisible without ever hiding, minimizing, or closing the window (any of which might either fail to remove it from view, or break the screenshare entirely).

The indicator window is still fully open and functional the whole time — it's just untouchable and invisible. If you ever need to actually stop the screenshare, use the in-page "Stop presenting" button that Meet/Zoom/etc. show inside the tab itself, rather than this window.

## Compatibility

Works with any website, in:

- **Chromium-based browsers**: Chrome, Edge, Brave, Vivaldi, Opera, etc.
- **Firefox-based browsers**: Firefox, Zen, LibreWolf, Waterfox, etc.



## Known Limitations



### Windows Only

There are currently no plans to make a Mac-/Linux-compatible version. Feel free to fork this if it would be of any help in making your own.

### English Only

Title matching uses the English text Chromium/Firefox show in the indicator's title (e.g. "is sharing your screen"). If your Windows or browser display language isn't English, the title text will differ and this won't catch it as-is.

**To fix this for your language:** open `screenshare-indicator-hider.ahk`, find the `TITLE_PATTERNS` list, add the equivalent phrase(s) your browser shows, then rebuild (see below). You can find the exact title using [AutoHotkey's Window Spy](https://www.autohotkey.com/docs/v2/Program.htm#Window_Spy) tool (included with any AutoHotkey install) — hover it over the indicator window while sharing your screen, and it'll show you the exact title, class, and exe to match on.

Pull requests adding other languages' title patterns are welcome.

### No Tab Sharing Support

The tab-sharing indicator is built into Chromium-based browsers instead of being a top-level window, and tab sharing isn't even an option for Firefox-based browsers. The tab sharing indicator could likely be fairly easily handled with a Tampermonkey userscript or similar, but I have no plans to make this myself as I don't use tab sharing.

## Advanced Installation



### Run `screenshare-indicator-hider.ahk` From Source

Requires [AutoHotkey v2](https://www.autohotkey.com/) installed.

1. Double-click `screenshare-indicator-hider.ahk` to run it in setup mode (same behavior as the compiled `.exe`).



### Build `screenshare-indicator-hider.exe` From Source

Requires [AutoHotkey v2](https://www.autohotkey.com/) installed.

1. Install Ahk2Exe by navigating to the AutoHotkey Dash and selecting Compile, which will prompt installation.
2. Select Compile again and set **Base File** to the `AutoHotkey64.exe` option and then click **Save**. You can now close both AutoHotkey windows.
3. Right-click `screenshare-indicator-hider.ahk` → **Compile Script**. This produces `screenshare-indicator-hider.exe` in the same folder — that single file is everything end users need.

