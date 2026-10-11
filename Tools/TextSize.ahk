; iMoonlight: Windows Text Size presets. AutoHotkey v2.
; Run this on the PC you stream from (put a shortcut in shell:startup).
; iMoonlight's Settings > Windows > Text size presses these keys:
;   Ctrl+Alt+Shift+F1 = 100%   Ctrl+Alt+Shift+F2 = 150%   Ctrl+Alt+Shift+F3 = 200%
#Requires AutoHotkey v2.0
#SingleInstance Force

SetTextSize(percent) {
    RegWrite(percent, "REG_DWORD", "HKCU\Software\Microsoft\Accessibility", "TextScaleFactor")
    ; Tell running apps and Settings to pick the change up without signing out.
    static HWND_BROADCAST := 0xFFFF, WM_SETTINGCHANGE := 0x1A, SMTO_ABORTIFHUNG := 2
    DllCall("SendMessageTimeoutW", "Ptr", HWND_BROADCAST, "UInt", WM_SETTINGCHANGE, "Ptr", 0
        , "Str", "WindowsThemeElement", "UInt", SMTO_ABORTIFHUNG, "UInt", 2000, "Ptr*", 0)
    ToolTip("Text size " percent "%")
    SetTimer(() => ToolTip(), -1500)
}

^!+F1:: SetTextSize(100)
^!+F2:: SetTextSize(150)
^!+F3:: SetTextSize(200)
