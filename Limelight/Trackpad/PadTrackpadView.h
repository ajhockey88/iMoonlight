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
@property (nonatomic) BOOL active;

@end

NS_ASSUME_NONNULL_END
