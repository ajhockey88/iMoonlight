//
//  PadPanelView.m
//  iMoonlight
//

#import "PadPanelView.h"
#import "PadTrackpadView.h"
#import "PadKeyboardView.h"
#import "PadPcKeysView.h"
#import "PadOutput.h"
#import "PadSettings.h"
#import "PadHaptics.h"

static const CGFloat BAR_HEIGHT = 40;
static const CGFloat BAR_PAD = 6;
/// After this long without a touch the trackpad dims; the next touch only wakes it.
static const NSTimeInterval DIM_AFTER = 30;
/// With less trackpad than this left above the keyboard, the keyboard takes the whole panel.
static const CGFloat MIN_PAD_HEIGHT = 120;
/// Side by side, the keyboard's share of the width; the trackpad gets the rest.
static const CGFloat SIDE_KEYBOARD_SHARE = 0.775;
/// Side by side, the strip along the top of the trackpad where a swipe down shows the bar.
static const CGFloat GRABBER_HEIGHT = 28;
/// How far the swipe must travel to show the bar.
static const CGFloat GRABBER_SWIPE = 20;
/// Side by side, the bar hides itself again after this long.
static const NSTimeInterval BAR_SHOWN_FOR = 4;

@interface PadPanelView () <PadKeyboardViewDelegate, PadPcKeysViewDelegate>
@end

@implementation PadPanelView {
    UIStackView* _bar;
    PadTrackpadView* _pad;
    PadKeyboardView* _keyboard;
    PadPcKeysView* _pcKeys;
    UIButton* _videoButton;
    /// Side by side the bar is hidden; a swipe down on this strip shows it.
    UIView* _grabber;
    BOOL _barRevealed;
    BOOL _dimmed;
    /// The touch that wakes a dimmed panel only wakes it.
    BOOL _swallowing;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.multipleTouchEnabled = YES;

        _bar = [[UIStackView alloc] init];
        _bar.axis = UILayoutConstraintAxisHorizontal;
        _bar.distribution = UIStackViewDistributionFillEqually;
        _bar.spacing = 8;
        [_bar addArrangedSubview:[self barButton:@"⌨️ Keyboard" action:@selector(keyboardTapped)]];
        [_bar addArrangedSubview:[self barButton:@"🖥️ PC keys" action:@selector(pcKeysTapped)]];
        _videoButton = [self barButton:@"" action:@selector(videoTapped)];
        [_bar addArrangedSubview:_videoButton];
        [self updateVideoButton];
        [_bar addArrangedSubview:[self barButton:@"⚙️ Settings" action:@selector(settingsTapped)]];
        [_bar addArrangedSubview:[self barButton:@"✖️ Disconnect" action:@selector(disconnectTapped)]];
        [self addSubview:_bar];

        _pad = [[PadTrackpadView alloc] initWithFrame:CGRectZero];
        [self addSubview:_pad];

        _keyboard = [[PadKeyboardView alloc] initWithFrame:CGRectZero];
        _keyboard.delegate = self;
        _keyboard.hidden = YES;
        [self addSubview:_keyboard];

        _grabber = [[UIView alloc] init];
        _grabber.hidden = YES;
        UIView* handle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 36, 4)];
        handle.backgroundColor = [UIColor colorWithWhite:1 alpha:70 / 255.0];
        handle.layer.cornerRadius = 2;
        handle.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        handle.tag = 1;
        [_grabber addSubview:handle];
        [_grabber addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(grabberPanned:)]];
        [_grabber addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(revealBar)]];
        [self addSubview:_grabber];

        _pcKeys = [[PadPcKeysView alloc] initWithFrame:CGRectZero];
        _pcKeys.delegate = self;
        _pcKeys.hidden = YES;
        [self addSubview:_pcKeys];

        [self restartIdleTimer];
    }
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (UIButton*)barButton:(NSString*)title action:(SEL)action {
    UIButton* b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:200 / 255.0] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithRed:120 / 255.0 green:200 / 255.0 blue:1 alpha:1] forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont systemFontOfSize:13];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.6;
    b.backgroundColor = [UIColor colorWithRed:28 / 255.0 green:28 / 255.0 blue:32 / 255.0 alpha:1];
    b.layer.cornerRadius = 10;
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 4);
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat left = 0;
    BOOL keyboardCoversPad = NO;
    CGFloat padTop = BAR_PAD + BAR_HEIGHT;
    CGFloat padHeight = b.size.height - padTop;
    if (_sideBySide) {
        // Keyboard down the whole left side, the trackpad on the right, and the bar hidden
        // until a swipe down from the top of the trackpad.
        if (!_keyboard.hidden) {
            CGFloat kbWidth = round(b.size.width * SIDE_KEYBOARD_SHARE);
            _keyboard.frame = CGRectMake(_keyboardInset, 0, kbWidth - _keyboardInset, b.size.height);
            left = kbWidth + 1;
        }
        padTop = 0;
        padHeight = b.size.height;
    }
    else if (!_keyboard.hidden) {
        // The keyboard takes up as much of the screen as the iPhone's own (above the home
        // indicator), leaving the bar and the trackpad above it.
        CGFloat kbHeight = [PadKeyboardView preferredHeight];
        CGFloat bottomInset = self.safeAreaInsets.bottom;
        if (padHeight - kbHeight - bottomInset >= MIN_PAD_HEIGHT) {
            padHeight -= kbHeight + bottomInset;
            _keyboard.frame = CGRectMake(0, b.size.height - bottomInset - kbHeight, b.size.width, kbHeight);
        } else {
            _keyboard.frame = b;
            keyboardCoversPad = YES;
        }
    }
    CGFloat width = b.size.width - left;
    if (_sideBySide) {
        // When shown, the bar spans the whole top, over the keyboard's strip.
        _bar.frame = CGRectMake(_keyboardInset + BAR_PAD, BAR_PAD, b.size.width - _keyboardInset - 2 * BAR_PAD, BAR_HEIGHT);
        _bar.hidden = !_barRevealed;
        _grabber.frame = CGRectMake(left, 0, width, GRABBER_HEIGHT);
        [_grabber viewWithTag:1].center = CGPointMake(width / 2, 8);
        _grabber.hidden = _barRevealed;
        [self bringSubviewToFront:_grabber];
        [self bringSubviewToFront:_bar];
        [self bringSubviewToFront:_pcKeys];
    }
    else {
        _bar.frame = CGRectMake(left + BAR_PAD, BAR_PAD, width - 2 * BAR_PAD, BAR_HEIGHT);
        _bar.hidden = NO;
        _grabber.hidden = YES;
    }
    _pad.frame = CGRectMake(left, padTop, width, padHeight);
    _pad.showHints = !_sideBySide;
    _pad.active = _pcKeys.hidden && !keyboardCoversPad;
    _pcKeys.frame = b;
}

- (void)setKeyboardInset:(CGFloat)keyboardInset {
    if (_keyboardInset == keyboardInset) return;
    _keyboardInset = keyboardInset;
    [self setNeedsLayout];
}

- (void)setSideBySide:(BOOL)sideBySide {
    if (_sideBySide == sideBySide) return;
    _sideBySide = sideBySide;
    [self hideBar];
    [self updateVideoButton];
    [self setNeedsLayout];
}

#pragma mark - Hidden bar (side by side)

- (void)grabberPanned:(UIPanGestureRecognizer*)pan {
    if (pan.state == UIGestureRecognizerStateChanged && [pan translationInView:self].y > GRABBER_SWIPE) {
        [self revealBar];
    }
}

- (void)revealBar {
    if (!_sideBySide || _barRevealed) return;
    [PadHaptics play:PadHapticBar];
    _barRevealed = YES;
    _bar.backgroundColor = [UIColor blackColor];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    _bar.alpha = 0;
    [UIView animateWithDuration:0.15 animations:^{ self->_bar.alpha = 1; }];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideBar) object:nil];
    [self performSelector:@selector(hideBar) withObject:nil afterDelay:BAR_SHOWN_FOR];
}

- (void)hideBar {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideBar) object:nil];
    if (!_barRevealed) return;
    _barRevealed = NO;
    _bar.alpha = 1;
    [self setNeedsLayout];
}

- (void)setVideoOff:(BOOL)videoOff {
    _videoOff = videoOff;
    [self updateVideoButton];
}

- (void)updateVideoButton {
    [_videoButton setTitle:_videoOff ? @"🎥 Video on" : @"🚫 Video off" forState:UIControlStateNormal];
    _pad.note = !_videoOff ? nil : _sideBySide ? @"Video off" : @"Video is off · still connected";
    // Lit while the video is off, so it's clear why the screen is dark.
    _videoButton.backgroundColor = _videoOff
        ? [UIColor colorWithRed:36 / 255.0 green:80 / 255.0 blue:110 / 255.0 alpha:1]
        : [UIColor colorWithRed:28 / 255.0 green:28 / 255.0 blue:32 / 255.0 alpha:1];
}

#pragma mark - Bar

- (void)keyboardTapped {
    [self hideBar];
    [PadHaptics play:PadHapticBar];
    [self openKeyboard];
}

- (void)pcKeysTapped {
    [self hideBar];
    [PadHaptics play:PadHapticBar];
    [self openPcKeys];
}

- (void)videoTapped {
    [self hideBar];
    [PadHaptics play:PadHapticBar];
    [self.delegate padPanelWantsVideoToggled:self];
}

- (void)settingsTapped {
    [self hideBar];
    [PadHaptics play:PadHapticBar];
    [self.delegate padPanelWantsSettings:self];
}

- (void)disconnectTapped {
    [self hideBar];
    [PadHaptics play:PadHapticBar];
    [self.delegate padPanelWantsDisconnect:self];
}

- (void)openKeyboard {
    _pcKeys.hidden = YES;
    [_pcKeys reset];
    [_keyboard reset];
    _keyboard.hidden = NO;
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)openPcKeys {
    _keyboard.hidden = YES;
    [_pcKeys reset];
    _pcKeys.hidden = NO;
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)showTrackpad {
    _keyboard.hidden = YES;
    _pcKeys.hidden = YES;
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)resetInput {
    [_keyboard reset];
    [_pcKeys reset];
    [self showTrackpad];
    [[PadOutput shared] releaseAll];
}

- (void)keyboardViewDidClose:(PadKeyboardView*)view {
    [self showTrackpad];
}

- (void)pcKeysViewWantsLetters:(PadPcKeysView*)view {
    [self openKeyboard];
}

- (void)pcKeysViewDidClose:(PadPcKeysView*)view {
    [_pcKeys reset];
    [self showTrackpad];
}

#pragma mark - Dim when idle

- (void)restartIdleTimer {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(idleTimerFired) object:nil];
    [self performSelector:@selector(idleTimerFired) withObject:nil afterDelay:DIM_AFTER];
}

- (void)idleTimerFired {
    if ([PadSettings dimWhenIdle] && self.window != nil) {
        [self setDimmed:YES];
    }
}

- (void)setDimmed:(BOOL)dimmed {
    if (_dimmed == dimmed) return;
    _dimmed = dimmed;
    [UIView animateWithDuration:dimmed ? 0.6 : 0.15 animations:^{
        self.alpha = dimmed ? 0.25 : 1;
    }];
}

- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    if (hit == nil) return nil;
    [self restartIdleTimer];
    if (_dimmed || _swallowing) {
        // Wake up, and keep the rest of this touch away from the trackpad.
        [self setDimmed:NO];
        _swallowing = YES;
        return self;
    }
    return hit;
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self endSwallowIfDone:event];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self endSwallowIfDone:event];
}

- (void)endSwallowIfDone:(UIEvent*)event {
    for (UITouch* t in [event touchesForView:self]) {
        if (t.phase != UITouchPhaseEnded && t.phase != UITouchPhaseCancelled) return;
    }
    _swallowing = NO;
}

@end
