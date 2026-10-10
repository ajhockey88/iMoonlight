//
//  PadHaptics.h
//  iMoonlight
//
//  A buzz for every trackpad and keyboard action, each with its own feel and strength
//  (Settings > Haptics), like ThorPad.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PadHapticAction) {
    PadHapticClick,
    PadHapticRightClick,
    PadHapticDragStart,
    PadHapticDragEnd,
    PadHapticHold,
    PadHapticScroll,
    PadHapticKey,
    PadHapticClearAll,
    PadHapticBar,
    PadHapticNavigate,
    PadHapticThreeFinger,
    PadHapticActionCount
};

typedef NS_ENUM(NSInteger, PadHapticFeel) {
    PadFeelOff,
    PadFeelTick,
    PadFeelClick,
    PadFeelHeavy,
    PadFeelDouble,
    PadFeelBuzz,
    PadFeelCount
};

@interface PadHaptics : NSObject

+ (NSString*)nameForAction:(PadHapticAction)action;
+ (NSString*)nameForFeel:(PadHapticFeel)feel;

+ (PadHapticFeel)feelForAction:(PadHapticAction)action;
+ (void)setFeel:(PadHapticFeel)feel forAction:(PadHapticAction)action;
/// 0 to 100.
+ (NSInteger)strengthForAction:(PadHapticAction)action;
+ (void)setStrength:(NSInteger)strength forAction:(PadHapticAction)action;

/// Buzzes for an action, with the feel and strength set up for it.
+ (void)play:(PadHapticAction)action;
/// Buzzes with a given feel and strength, e.g. to preview a setting.
+ (void)playFeel:(PadHapticFeel)feel strength:(NSInteger)strength;

@end

NS_ASSUME_NONNULL_END
