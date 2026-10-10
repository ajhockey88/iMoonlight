//
//  PadSettings.h
//  iMoonlight
//
//  Settings for the portrait trackpad, keyboard and haptics, ported from ThorPad's Prefs.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* const PadKeySensitivity;
extern NSString* const PadKeyAcceleration;
extern NSString* const PadKeyScrollSpeed;
extern NSString* const PadKeyInvertScroll;
extern NSString* const PadKeyZoomSpeed;
extern NSString* const PadKeySwapScreens;
extern NSString* const PadKeyDimWhenIdle;
extern NSString* const PadKeyAutocorrect;
extern NSString* const PadKeyTypeOnRelease;
extern NSString* const PadKeyAutoCapitalize;
extern NSString* const PadKeyDoubleSpacePeriod;

/// Posted when any trackpad setting changes.
extern NSString* const PadSettingsChangedNotification;

@interface PadSettings : NSObject

/// Pointer movement per point of finger travel at slow speed.
+ (float)sensitivity;
/// How much faster the pointer gets when the finger moves fast. 0 = linear.
+ (float)acceleration;
/// Scroll distance per point of two-finger movement.
+ (float)scrollSpeed;
/// How much a pinch zooms: zoom steps per 60 pt change in finger spacing.
+ (float)zoomSpeed;
/// NO = natural (content follows fingers), YES = classic scroll wheel direction.
+ (BOOL)invertScroll;
/// Trackpad on top, stream underneath.
+ (BOOL)swapScreens;
/// Dim the trackpad after 30 seconds without a touch.
+ (BOOL)dimWhenIdle;
/// Keyboard: fix misspelled words when a word is finished.
+ (BOOL)autocorrect;
/// Keyboard: type when the finger lifts instead of when it lands.
+ (BOOL)typeOnRelease;
/// Keyboard: capital letter at the start of a sentence.
+ (BOOL)autoCapitalize;
/// Keyboard: two spaces type ". ".
+ (BOOL)doubleSpacePeriod;

+ (float)floatForKey:(NSString*)key;
+ (void)setFloat:(float)value forKey:(NSString*)key;
+ (BOOL)boolForKey:(NSString*)key;
+ (void)setBool:(BOOL)value forKey:(NSString*)key;
+ (NSInteger)integerForKey:(NSString*)key fallback:(NSInteger)fallback;
+ (void)setInteger:(NSInteger)value forKey:(NSString*)key;

@end

NS_ASSUME_NONNULL_END
