//
//  PadOutput.m
//  iMoonlight
//

#import "PadOutput.h"
#import "KeyboardSupport.h"

#include <Limelight.h>

/// Clicks hold the button about this long, like a real mouse, so games that check
/// the button once per frame still see them.
static const int64_t CLICK_HOLD_MS = 90;
/// How long each typed key stays down.
static const useconds_t KEY_HOLD_US = 25 * 1000;

@implementation PadOutput {
    float _moveRemainderX, _moveRemainderY;
    float _scrollRemainder;
    BOOL _dragging;
    BOOL _zooming;
    // Keys are sent in order on their own queue, so typing never blocks the UI
    // and a correction's backspaces always land before its new letters.
    dispatch_queue_t _keyQueue;
}

+ (instancetype)shared {
    static PadOutput* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[PadOutput alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    _keyQueue = dispatch_queue_create("imoonlight.pad.keys", DISPATCH_QUEUE_SERIAL);
    return self;
}

#pragma mark - Mouse

- (void)moveByX:(float)dx y:(float)dy {
    _moveRemainderX += dx;
    _moveRemainderY += dy;
    short sx = (short)MAX(-32000, MIN(32000, _moveRemainderX));
    short sy = (short)MAX(-32000, MIN(32000, _moveRemainderY));
    if (sx == 0 && sy == 0) {
        return;
    }
    _moveRemainderX -= sx;
    _moveRemainderY -= sy;
    LiSendMouseMoveEvent(sx, sy);
}

- (void)clickButton:(int)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, button);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, CLICK_HOLD_MS * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, button);
    });
}

- (void)click {
    [self clickButton:BUTTON_LEFT];
}

- (void)rightClick {
    [self clickButton:BUTTON_RIGHT];
}

- (void)dragBegin {
    _dragging = YES;
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
}

- (void)dragEnd {
    if (_dragging) {
        _dragging = NO;
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    }
}

- (void)scrollBy:(float)amount {
    _scrollRemainder += amount;
    short units = (short)MAX(-32000, MIN(32000, _scrollRemainder));
    if (units != 0) {
        _scrollRemainder -= units;
        LiSendHighResScrollEvent(units);
    }
}

- (void)scrollEnd {
    _scrollRemainder = 0;
}

// Zoom goes through the key queue so Ctrl is always down before the wheel turns.
- (void)zoomBy:(int)notches {
    if (notches == 0) return;
    BOOL first = !_zooming;
    _zooming = YES;
    dispatch_async(_keyQueue, ^{
        if (first) {
            LiSendKeyboardEvent(PadVkCtrl, KEY_ACTION_DOWN, MODIFIER_CTRL);
            usleep(KEY_HOLD_US);
        }
        LiSendHighResScrollEvent((short)MAX(-200, MIN(200, notches)) * 120);
    });
}

- (void)zoomEnd {
    if (!_zooming) return;
    _zooming = NO;
    dispatch_async(_keyQueue, ^{
        usleep(KEY_HOLD_US);
        LiSendKeyboardEvent(PadVkCtrl, KEY_ACTION_UP, 0);
    });
}

- (void)releaseAll {
    [self dragEnd];
    [self zoomEnd];
    _moveRemainderX = _moveRemainderY = 0;
    _scrollRemainder = 0;
}

#pragma mark - Keyboard

static char modifierFlagFor(int code) {
    switch (code) {
        case PadVkShift: return MODIFIER_SHIFT;
        case PadVkCtrl: return MODIFIER_CTRL;
        case PadVkAlt: return MODIFIER_ALT;
        case PadVkWin: return MODIFIER_META;
        default: return 0;
    }
}

- (void)pressKeys:(NSArray<NSNumber*>*)codes {
    NSArray<NSNumber*>* keys = [codes copy];
    dispatch_async(_keyQueue, ^{
        char modifiers = 0;
        for (NSNumber* key in keys) {
            modifiers |= modifierFlagFor(key.intValue);
            LiSendKeyboardEvent(key.shortValue, KEY_ACTION_DOWN, modifiers);
        }
        usleep(KEY_HOLD_US);
        for (NSNumber* key in [keys reverseObjectEnumerator]) {
            LiSendKeyboardEvent(key.shortValue, KEY_ACTION_UP, modifiers);
            modifiers &= ~modifierFlagFor(key.intValue);
        }
    });
}

- (void)setWindowsTextSize:(int)percent {
    int f = percent >= 200 ? PadVkF3 : percent >= 150 ? PadVkF2 : PadVkF1;
    [self pressKeys:@[@(PadVkCtrl), @(PadVkAlt), @(PadVkShift), @(f)]];
}

- (void)typeText:(NSString*)text {
    NSString* copy = [text copy];
    dispatch_async(_keyQueue, ^{
        for (NSUInteger i = 0; i < copy.length; i++) {
            unichar c = [copy characterAtIndex:i];
            struct KeyEvent event = [KeyboardSupport translateKeyEvent:c withModifierFlags:0];
            if (event.keycode == 0) {
                // Not on a US keyboard: send it as text instead.
                NSString* one = [copy substringWithRange:[copy rangeOfComposedCharacterSequenceAtIndex:i]];
                const char* utf8 = one.UTF8String;
                LiSendUtf8TextEvent(utf8, (unsigned int)strlen(utf8));
                i += one.length - 1;
                continue;
            }
            if (event.modifier != 0) {
                LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_DOWN, event.modifier);
            }
            LiSendKeyboardEvent2(event.keycode, KEY_ACTION_DOWN, event.modifier, SS_KBE_FLAG_NON_NORMALIZED);
            usleep(KEY_HOLD_US);
            LiSendKeyboardEvent2(event.keycode, KEY_ACTION_UP, event.modifier, SS_KBE_FLAG_NON_NORMALIZED);
            if (event.modifier != 0) {
                LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_UP, 0);
            }
        }
    });
}

- (void)special:(PadSpecialKey)key {
    switch (key) {
        case PadSpecialEnter: [self pressKeys:@[@(PadVkEnter)]]; break;
        case PadSpecialBackspace: [self pressKeys:@[@(PadVkBackspace)]]; break;
        case PadSpecialTab: [self pressKeys:@[@(PadVkTab)]]; break;
        case PadSpecialEscape: [self pressKeys:@[@(PadVkEscape)]]; break;
        case PadSpecialLeft: [self pressKeys:@[@(PadVkLeft)]]; break;
        case PadSpecialRight: [self pressKeys:@[@(PadVkRight)]]; break;
        case PadSpecialUp: [self pressKeys:@[@(PadVkUp)]]; break;
        case PadSpecialDown: [self pressKeys:@[@(PadVkDown)]]; break;
        case PadSpecialClearAll:
            // Select all, then delete the selection.
            [self pressKeys:@[@(PadVkCtrl), @(PadVkA)]];
            [self pressKeys:@[@(PadVkBackspace)]];
            break;
    }
}

@end
