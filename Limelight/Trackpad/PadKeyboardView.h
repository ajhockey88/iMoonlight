//
//  PadKeyboardView.h
//  iMoonlight
//
//  A keyboard that fills the trackpad area, ported from ThorPad. Keys touch edge to edge with
//  only a hairline between them, so the whole area is target. A key types the moment a finger
//  lands on it (or, with "type when the finger lifts", when it lifts), every finger is tracked
//  on its own, and each press flashes and buzzes. Backspace repeats while held, and while it is
//  held the space bar turns into a red "Clear all" key. Autocorrect fixes a word when it's
//  finished, and backspace right after a fix undoes it.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PadKeyboardView;

@protocol PadKeyboardViewDelegate <NSObject>
- (void)keyboardViewDidClose:(PadKeyboardView*)view;
@optional
/// The hand button was pressed or let go.
- (void)keyboardView:(PadKeyboardView*)view handHeld:(BOOL)held;
@end

@interface PadKeyboardView : UIView

@property (nonatomic, weak, nullable) id<PadKeyboardViewDelegate> delegate;

/// Shows the hand button in the preview strip. While it is held, one finger on the trackpad
/// acts as two. Off sideways, where the trackpad is not above the keyboard.
@property (nonatomic) BOOL handEnabled;

/// How tall the keyboard is in portrait: about the height of the iPhone's own keyboard.
+ (CGFloat)preferredHeight;

/// Clears the preview and returns to letters, ready for the next time it opens.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
