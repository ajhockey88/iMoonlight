//
//  PadPanelView.h
//  iMoonlight
//
//  The half of the screen that isn't the stream in portrait: a slim bar of buttons
//  (Keyboard, PC keys, Settings, Disconnect) over the trackpad. The keyboard is iPhone-size
//  along the bottom, with the trackpad still usable above it; PC keys cover the whole panel.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PadPanelView;

@protocol PadPanelViewDelegate <NSObject>
- (void)padPanelWantsSettings:(PadPanelView*)panel;
- (void)padPanelWantsDisconnect:(PadPanelView*)panel;
@end

@interface PadPanelView : UIView

@property (nonatomic, weak, nullable) id<PadPanelViewDelegate> delegate;

- (void)openKeyboard;
/// Closes the keyboard or PC keys and lets go of anything held.
- (void)resetInput;

@end

NS_ASSUME_NONNULL_END
