//
//  PadTrackpadView.h
//  iMoonlight
//
//  The touch surface, with the same gestures as ThorPad's PC mode:
//  one finger moves the pointer, a tap clicks, tap-then-slide drags, a press and hold or
//  a two-finger tap right-clicks, two fingers up or down scroll, spreading or pinching two
//  fingers zooms (Ctrl + wheel), two fingers sideways go
//  back / forward, and three-finger swipes switch apps, show task view or the desktop.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PadTrackpadView : UIView

/// Where gestures go; NO while the keyboard or PC keys cover the trackpad.
/// A quiet line of text in the middle of the trackpad, e.g. while the video is off.
@property (nonatomic, copy, nullable) NSString* note;
/// The gesture cheat sheet along the bottom. Off by default (a setting).
@property (nonatomic) BOOL showHints;
@property (nonatomic) BOOL active;
/// The keyboard's hand button is held: a finger on the trackpad counts as two, so one finger
/// scrolls, and a sideways swipe goes back / forward.
@property (nonatomic) BOOL handHeld;

@end

NS_ASSUME_NONNULL_END
