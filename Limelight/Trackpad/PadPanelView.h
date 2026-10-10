//
//  PadPanelView.h
//  iMoonlight
//
//  The half of the screen that isn't the stream in portrait: a slim bar of buttons
//  (Keyboard, PC keys, Video off, Settings, Disconnect) over the trackpad. The keyboard takes
//  the iPhone keyboard's height along the bottom, with the trackpad still usable above it;
//  PC keys cover the whole panel. Side by side (sideways with video off), the keyboard fills
//  the left side, top to bottom, and the bar and trackpad sit on the right.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PadPanelView;

@protocol PadPanelViewDelegate <NSObject>
- (void)padPanelWantsSettings:(PadPanelView*)panel;
- (void)padPanelWantsDisconnect:(PadPanelView*)panel;
- (void)padPanelWantsVideoToggled:(PadPanelView*)panel;
@end

@interface PadPanelView : UIView

@property (nonatomic, weak, nullable) id<PadPanelViewDelegate> delegate;
/// Shows the Video button as "Video on" while the video is off.
@property (nonatomic) BOOL videoOff;
/// Keyboard on the left at full height, bar and trackpad on the right.
@property (nonatomic) BOOL sideBySide;
/// Side by side, how far the keyboard stays in from the left edge (to clear the camera).
@property (nonatomic) CGFloat keyboardInset;

- (void)openKeyboard;
/// Closes the keyboard or PC keys and lets go of anything held.
- (void)resetInput;

@end

NS_ASSUME_NONNULL_END
