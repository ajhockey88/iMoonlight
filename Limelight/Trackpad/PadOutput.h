//
//  PadOutput.h
//  iMoonlight
//
//  Sends trackpad gestures and keyboard keys to the PC as mouse and keyboard input,
//  through moonlight-common-c.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Windows virtual-key codes, which is what Moonlight hosts expect.
enum {
    PadVkBackspace = 0x08,
    PadVkTab = 0x09,
    PadVkEnter = 0x0D,
    PadVkEscape = 0x1B,
    PadVkSpace = 0x20,
    PadVkPageUp = 0x21,
    PadVkPageDown = 0x22,
    PadVkEnd = 0x23,
    PadVkHome = 0x24,
    PadVkLeft = 0x25,
    PadVkUp = 0x26,
    PadVkRight = 0x27,
    PadVkDown = 0x28,
    PadVkPrintScreen = 0x2C,
    PadVkDelete = 0x2E,
    PadVkA = 0x41,
    PadVkD = 0x44,
    PadVkWin = 0x5B,
    PadVkF1 = 0x70,
    PadVkF2 = 0x71,
    PadVkF3 = 0x72,
    PadVkF4 = 0x73,
    PadVkF13 = 0x7C,
    PadVkF14 = 0x7D,
    PadVkF15 = 0x7E,
    PadVkShift = 0xA0,
    PadVkCtrl = 0xA2,
    PadVkAlt = 0xA4,
};

/// Keys on the on-screen keyboard that aren't characters.
typedef NS_ENUM(NSInteger, PadSpecialKey) {
    PadSpecialEnter,
    PadSpecialBackspace,
    PadSpecialTab,
    PadSpecialEscape,
    PadSpecialLeft,
    PadSpecialRight,
    PadSpecialUp,
    PadSpecialDown,
    /// Deletes all the text in the selected text box (Ctrl+A, then Backspace).
    PadSpecialClearAll,
};

@interface PadOutput : NSObject

+ (instancetype)shared;

/// Relative pointer movement, in host pixels. Fractions carry over to the next call.
- (void)moveByX:(float)dx y:(float)dy;
- (void)click;
- (void)rightClick;
- (void)dragBegin;
- (void)dragEnd;
/// High-resolution wheel units (120 = one notch). Positive scrolls up.
- (void)scrollBy:(float)amount;
- (void)scrollEnd;
/// Pinch zoom: holds Ctrl and turns the wheel, which zooms text in browsers and most apps.
/// Positive notches zoom in (bigger). Ctrl stays down until zoomEnd.
- (void)zoomBy:(int)notches;
- (void)zoomEnd;

/// Presses these keys together (modifiers first), then lets go in reverse order.
- (void)pressKeys:(NSArray<NSNumber*>*)codes;
- (void)typeText:(NSString*)text;
- (void)special:(PadSpecialKey)key;

/// Asks the PC to switch its Windows display scale to 100, 150 or 200 percent, by pressing
/// F13 / F14 / F15 (no modifiers), which Tools/TextSize.ahk on the PC listens for.
- (void)setWindowsTextSize:(int)percent;

/// Lets go of anything still held, e.g. when the stream ends mid-drag.
- (void)releaseAll;

@end

NS_ASSUME_NONNULL_END
