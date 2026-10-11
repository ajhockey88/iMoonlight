; iMoonlight: Windows Text Size presets. AutoHotkey v2.
; Run this on the PC you stream from (put a shortcut in shell:startup).
; iMoonlight's Settings > Windows > Text size presses these keys:
;   Ctrl+Alt+Shift+F1 = 100%   Ctrl+Alt+Shift+F2 = 150%   Ctrl+Alt+Shift+F3 = 200%
#Requires AutoHotkey v2.0
#SingleInstance Force

Broadcast(what, spi := 0) {
    static HWND_BROADCAST := 0xFFFF, WM_SETTINGCHANGE := 0x1A, SMTO_ABORTIFHUNG := 2
    DllCall("SendMessageTimeoutW", "Ptr", HWND_BROADCAST, "UInt", WM_SETTINGCHANGE, "Ptr", spi
        , "Str", what, "UInt", SMTO_ABORTIFHUNG, "UInt", 2000, "Ptr*", 0)
}

SetTextSize(percent) {
    key := "HKCU\Software\Microsoft\Accessibility"
    RegWrite(percent, "REG_DWORD", key, "TextScaleFactor")
    ; Tell Windows and running apps to pick the change up without signing out. Besides the
    ; named notices, send the ones Windows' own Display settings send (wParam = the SPI code):
    ; non-client metrics, icon metrics and work area, which make Explorer redraw the taskbar.
    for what in ["TextScaleFactor", "WindowsThemeElement", "ImmersiveColorSet", "Accessibility"]
        Broadcast(what)
    for spi in [0x2A, 0x2E, 0x2F]  ; SPI_SETNONCLIENTMETRICS, SPI_SETICONMETRICS, SPI_SETWORKAREA
        Broadcast("", spi)
    ; Also poke the taskbar directly.
    static WM_SETTINGCHANGE := 0x1A
    try PostMessage(WM_SETTINGCHANGE, 0x2A, 0, , "ahk_class Shell_TrayWnd")
    ; Show what Windows now has, so a write that didn't stick is obvious.
    now := RegRead(key, "TextScaleFactor", "missing")
    ToolTip("Text size " percent "% (registry: " now ")")
    SetTimer(() => ToolTip(), -2500)
}

^!+F1:: SetTextSize(100)
^!+F2:: SetTextSize(150)
^!+F3:: SetTextSize(200)
