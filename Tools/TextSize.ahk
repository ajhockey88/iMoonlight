; iMoonlight: Windows display scale presets. AutoHotkey v2.
; Run this on the PC you stream from (put a shortcut in shell:startup).
; iMoonlight's Settings > Windows > Display scale presses these keys:
;   Ctrl+Alt+1 = 100%   Ctrl+Alt+2 = 150%   Ctrl+Alt+3 = 200%
; It sets the same "Scale" as Settings > System > Display, on every active display, and
; Windows applies it live. (The real Text size slider can't be applied from a script.)
#Requires AutoHotkey v2.0
#SingleInstance Force

SCALES := [100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500]

; Returns a short report: how many displays changed, and for each its allowed range,
; the step asked for, and the step Windows reports afterwards (steps are relative to the
; display's recommended scale; 0 = recommended).
SetDisplayScale(percent) {
    target := 0
    for i, s in SCALES
        if (s = percent)
            target := i
    DllCall("GetDisplayConfigBufferSizes", "UInt", 2, "UInt*", &np := 0, "UInt*", &nm := 0)  ; active paths only
    paths := Buffer(72 * np, 0)
    modes := Buffer(64 * nm, 0)
    if DllCall("QueryDisplayConfig", "UInt", 2, "UInt*", &np, "Ptr", paths, "UInt*", &nm, "Ptr", modes, "Ptr", 0)
        return 0
    changed := 0
    report := ""
    Loop np {
        base := (A_Index - 1) * 72
        luid := NumGet(paths, base, "Int64")
        id := NumGet(paths, base + 8, "UInt")
        ; Ask what this display can do: scales are counted relative to its recommended one.
        get := Buffer(32, 0)
        NumPut("Int", -3, "UInt", 32, "Int64", luid, "UInt", id, get)
        if DllCall("DisplayConfigGetDeviceInfo", "Ptr", get)
            continue
        minRel := NumGet(get, 20, "Int")
        maxRel := NumGet(get, 28, "Int")
        recommended := 1 - minRel  ; minRel is minus the recommended scale's distance from 100%
        rel := Max(minRel, Min(maxRel, target - recommended))
        set := Buffer(24, 0)
        NumPut("Int", -4, "UInt", 24, "Int64", luid, "UInt", id, "Int", rel, set)
        err := DllCall("DisplayConfigSetDeviceInfo", "Ptr", set)
        if !err
            changed++
        DllCall("DisplayConfigGetDeviceInfo", "Ptr", get)
        report .= "`n#" A_Index ": range " minRel ".." maxRel ", asked " rel ", now " NumGet(get, 24, "Int") ", result " err
    }
    return changed " changed" report
}

Apply(percent) {
    ToolTip("Display scale " percent "%: " SetDisplayScale(percent))
    SetTimer(() => ToolTip(), -6000)
}

^!1:: Apply(100)
^!2:: Apply(150)
^!3:: Apply(200)
