//
//  PadSettings.m
//  iMoonlight
//

#import "PadSettings.h"

NSString* const PadKeySensitivity = @"pad.sensitivity";
NSString* const PadKeyAcceleration = @"pad.acceleration";
NSString* const PadKeyScrollSpeed = @"pad.scrollSpeed";
NSString* const PadKeyInvertScroll = @"pad.invertScroll";
NSString* const PadKeyZoomSpeed = @"pad.zoomSpeed";
NSString* const PadKeySwapScreens = @"pad.swapScreens";
NSString* const PadKeyDimWhenIdle = @"pad.dimWhenIdle";
NSString* const PadKeyAutocorrect = @"pad.autocorrect";
NSString* const PadKeyTypeOnRelease = @"pad.typeOnRelease";
NSString* const PadKeyAutoCapitalize = @"pad.autoCapitalize";
NSString* const PadKeyDoubleSpacePeriod = @"pad.doubleSpacePeriod";

NSString* const PadKeyShowHints = @"pad.showHints";

NSString* const PadSettingsChangedNotification = @"PadSettingsChangedNotification";

@implementation PadSettings

+ (void)initialize {
    if (self == [PadSettings class]) {
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
            PadKeySensitivity: @1.8f,
            PadKeyAcceleration: @0.6f,
            PadKeyScrollSpeed: @2.0f,
            PadKeyInvertScroll: @NO,
            PadKeyZoomSpeed: @1.0f,
            PadKeySwapScreens: @NO,
            PadKeyDimWhenIdle: @YES,
            PadKeyAutocorrect: @YES,
            PadKeyTypeOnRelease: @NO,
            PadKeyAutoCapitalize: @YES,
            PadKeyDoubleSpacePeriod: @YES,
            PadKeyShowHints: @NO,
        }];
    }
}

+ (float)sensitivity { return [self floatForKey:PadKeySensitivity]; }
+ (float)acceleration { return [self floatForKey:PadKeyAcceleration]; }
+ (float)scrollSpeed { return [self floatForKey:PadKeyScrollSpeed]; }
+ (float)zoomSpeed { return [self floatForKey:PadKeyZoomSpeed]; }
+ (BOOL)invertScroll { return [self boolForKey:PadKeyInvertScroll]; }
+ (BOOL)swapScreens { return [self boolForKey:PadKeySwapScreens]; }
+ (BOOL)dimWhenIdle { return [self boolForKey:PadKeyDimWhenIdle]; }
+ (BOOL)autocorrect { return [self boolForKey:PadKeyAutocorrect]; }
+ (BOOL)typeOnRelease { return [self boolForKey:PadKeyTypeOnRelease]; }
+ (BOOL)autoCapitalize { return [self boolForKey:PadKeyAutoCapitalize]; }
+ (BOOL)doubleSpacePeriod { return [self boolForKey:PadKeyDoubleSpacePeriod]; }

+ (BOOL)showHints { return [self boolForKey:PadKeyShowHints]; }

+ (float)floatForKey:(NSString*)key {
    return [[NSUserDefaults standardUserDefaults] floatForKey:key];
}

+ (void)setFloat:(float)value forKey:(NSString*)key {
    [[NSUserDefaults standardUserDefaults] setFloat:value forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:PadSettingsChangedNotification object:nil];
}

+ (BOOL)boolForKey:(NSString*)key {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

+ (void)setBool:(BOOL)value forKey:(NSString*)key {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:PadSettingsChangedNotification object:nil];
}

+ (NSInteger)integerForKey:(NSString*)key fallback:(NSInteger)fallback {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return value != nil ? [value integerValue] : fallback;
}

+ (void)setInteger:(NSInteger)value forKey:(NSString*)key {
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:PadSettingsChangedNotification object:nil];
}

@end
