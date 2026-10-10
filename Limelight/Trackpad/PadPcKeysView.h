//
//  PadPcKeysView.h
//  iMoonlight
//
//  PC keys, ported from ThorPad: Esc, F1 to F12, Windows shortcuts, navigation keys and sticky
//  Ctrl / Alt / Shift / Win. Fills the trackpad area like the keyboard, with keys edge to edge.
//  A tapped modifier stays held until the next key, which fires with it.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PadPcKeysView;

@protocol PadPcKeysViewDelegate <NSObject>
- (void)pcKeysViewWantsLetters:(PadPcKeysView*)view;
- (void)pcKeysViewDidClose:(PadPcKeysView*)view;
@end

@interface PadPcKeysView : UIView

@property (nonatomic, weak, nullable) id<PadPcKeysViewDelegate> delegate;

/// Lets go of held modifiers and touches, ready for next time.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
