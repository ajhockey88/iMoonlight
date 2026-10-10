//
//  PadHaptics.m
//  iMoonlight
//

#import "PadHaptics.h"
#import "PadSettings.h"

#import <UIKit/UIKit.h>

static NSString* const ACTION_NAMES[] = {
    @"Click", @"Right click", @"Drag start", @"Drag end", @"Press and hold",
    @"Scroll wheel notch", @"Keyboard key", @"Clear all", @"Top bar buttons",
    @"Back / forward swipe", @"Three-finger swipe"
};
static NSString* const ACTION_KEYS[] = {
    @"click", @"right_click", @"drag_start", @"drag_end", @"hold", @"scroll", @"key",
    @"clear_all", @"bar", @"navigate", @"three_finger"
};
static NSString* const FEEL_NAMES[] = { @"Off", @"Tick", @"Click", @"Heavy", @"Double", @"Buzz" };

static const PadHapticFeel DEFAULT_FEEL[] = {
    PadFeelClick, PadFeelDouble, PadFeelHeavy, PadFeelTick, PadFeelHeavy, PadFeelTick,
    PadFeelClick, PadFeelHeavy, PadFeelClick, PadFeelClick, PadFeelHeavy
};
static const NSInteger DEFAULT_STRENGTH[] = { 60, 60, 80, 50, 80, 35, 45, 100, 50, 70, 70 };

@implementation PadHaptics

static UIImpactFeedbackGenerator* tickGenerator;
static UIImpactFeedbackGenerator* clickGenerator;
static UIImpactFeedbackGenerator* heavyGenerator;

+ (void)initialize {
    if (self == [PadHaptics class]) {
        tickGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
        clickGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        heavyGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [tickGenerator prepare];
        [clickGenerator prepare];
        [heavyGenerator prepare];
    }
}

+ (NSString*)nameForAction:(PadHapticAction)action { return ACTION_NAMES[action]; }
+ (NSString*)nameForFeel:(PadHapticFeel)feel { return FEEL_NAMES[feel]; }

+ (NSString*)feelKey:(PadHapticAction)action {
    return [@"pad.haptic.feel." stringByAppendingString:ACTION_KEYS[action]];
}

+ (NSString*)strengthKey:(PadHapticAction)action {
    return [@"pad.haptic.strength." stringByAppendingString:ACTION_KEYS[action]];
}

+ (PadHapticFeel)feelForAction:(PadHapticAction)action {
    NSInteger feel = [PadSettings integerForKey:[self feelKey:action] fallback:DEFAULT_FEEL[action]];
    return (feel >= 0 && feel < PadFeelCount) ? (PadHapticFeel)feel : DEFAULT_FEEL[action];
}

+ (void)setFeel:(PadHapticFeel)feel forAction:(PadHapticAction)action {
    [PadSettings setInteger:feel forKey:[self feelKey:action]];
}

+ (NSInteger)strengthForAction:(PadHapticAction)action {
    return [PadSettings integerForKey:[self strengthKey:action] fallback:DEFAULT_STRENGTH[action]];
}

+ (void)setStrength:(NSInteger)strength forAction:(PadHapticAction)action {
    [PadSettings setInteger:MAX(0, MIN(100, strength)) forKey:[self strengthKey:action]];
}

+ (void)play:(PadHapticAction)action {
    [self playFeel:[self feelForAction:action] strength:[self strengthForAction:action]];
}

+ (void)playFeel:(PadHapticFeel)feel strength:(NSInteger)strength {
    if (feel == PadFeelOff || strength <= 0) {
        return;
    }
    // Map 0-100 onto the Taptic Engine's intensity range, keeping weak settings perceptible.
    CGFloat intensity = 0.15 + 0.85 * MIN(strength, 100) / 100.0;
    switch (feel) {
        case PadFeelTick:
            [tickGenerator impactOccurredWithIntensity:intensity * 0.7];
            [tickGenerator prepare];
            break;
        case PadFeelClick:
            [clickGenerator impactOccurredWithIntensity:intensity];
            [clickGenerator prepare];
            break;
        case PadFeelHeavy:
            [heavyGenerator impactOccurredWithIntensity:intensity];
            [heavyGenerator prepare];
            break;
        case PadFeelDouble:
            [clickGenerator impactOccurredWithIntensity:intensity];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                [clickGenerator impactOccurredWithIntensity:intensity];
                [clickGenerator prepare];
            });
            break;
        case PadFeelBuzz:
            for (int i = 0; i < 4; i++) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, i * 25 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    [heavyGenerator impactOccurredWithIntensity:intensity];
                    [heavyGenerator prepare];
                });
            }
            break;
        default:
            break;
    }
}

@end
