//
//  PadKeyboardView.h
//  iMoonlight
//
//  A keyboard the size of the iPhone's own, ported from ThorPad. It sits along the bottom of
//  the panel with the trackpad still usable above it. Touches between keys go to the nearest
//  key, so there are no dead spots. A key types the moment a finger
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
@end

@interface PadKeyboardView : UIView

@property (nonatomic, weak, nullable) id<PadKeyboardViewDelegate> delegate;

/// The suggestion strip plus four rows of iPhone-size keys.
+ (CGFloat)preferredHeight;

/// Clears the preview and returns to letters, ready for the next time it opens.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
