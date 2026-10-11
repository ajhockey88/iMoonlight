; iMoonlight: Windows Text Size presets. AutoHotkey v2.
; Run this on the PC you stream from (put a shortcut in shell:startup).
; iMoonlight's Settings > Windows > Text size presses these keys:
;   Ctrl+Alt+Shift+F1 = 100%   Ctrl+Alt+Shift+F2 = 150%   Ctrl+Alt+Shift+F3 = 200%
#Requires AutoHotkey v2.0
#SingleInstance Force

Broadcast(what) {
    static HWND_BROADCAST := 0xFFFF, WM_SETTINGCHANGE := 0x1A, SMTO_ABORTIFHUNG := 2
    DllCall("SendMessageTimeoutW", "Ptr", HWND_BROADCAST, "UInt", WM_SETTINGCHANGE, "Ptr", 0
        , "Str", what, "UInt", SMTO_ABORTIFHUNG, "UInt", 2000, "Ptr*", 0)
}

SetTextSize(percent) {
    key := "HKCU\Software\Microsoft\Accessibility"
    RegWrite(percent, "REG_DWORD", key, "TextScaleFactor")
    ; Tell Windows and running apps to pick the change up without signing out.
    for what in ["TextScaleFactor", "WindowsThemeElement", "ImmersiveColorSet", "Accessibility"]
        Broadcast(what)
    ; Show what Windows now has, so a write that didn't stick is obvious.
    now := RegRead(key, "TextScaleFactor", "missing")
    ToolTip("Text size " percent "% (registry: " now ")")
    SetTimer(() => ToolTip(), -2500)
}

^!+F1:: SetTextSize(100)
^!+F2:: SetTextSize(150)
^!+F3:: SetTextSize(200)
