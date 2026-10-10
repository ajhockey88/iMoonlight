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

@interface PadPanelView () <PadKeyboardViewDelegate, PadPcKeysViewDelegate>
@end

@implementation PadPanelView {
    UIStackView* _bar;
    PadTrackpadView* _pad;
    PadKeyboardView* _keyboard;
    PadPcKeysView* _pcKeys;
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
        [_bar addArrangedSubview:[self barButton:@"⚙️ Settings" action:@selector(settingsTapped)]];
        [_bar addArrangedSubview:[self barButton:@"✖️ Disconnect" action:@selector(disconnectTapped)]];
        [self addSubview:_bar];

        _pad = [[PadTrackpadView alloc] initWithFrame:CGRectZero];
        [self addSubview:_pad];

        _keyboard = [[PadKeyboardView alloc] initWithFrame:CGRectZero];
        _keyboard.delegate = self;
        _keyboard.hidden = YES;
        [self addSubview:_keyboard];

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
    _bar.frame = CGRectMake(BAR_PAD, BAR_PAD, b.size.width - 2 * BAR_PAD, BAR_HEIGHT);
    CGFloat padTop = BAR_PAD + BAR_HEIGHT;
    CGFloat padHeight = b.size.height - padTop;
    // The keyboard is iPhone-size along the bottom (above the home indicator), leaving the
    // bar and the trackpad above it.
    CGFloat kbHeight = [PadKeyboardView preferredHeight] + self.safeAreaInsets.bottom;
    if (!_keyboard.hidden) {
        if (padHeight - kbHeight >= MIN_PAD_HEIGHT) {
            padHeight -= kbHeight;
            _keyboard.frame = CGRectMake(0, b.size.height - kbHeight, b.size.width, kbHeight);
        } else {
            _keyboard.frame = b;
        }
    }
    _pad.frame = CGRectMake(0, padTop, b.size.width, padHeight);
    _pad.active = _pcKeys.hidden && (_keyboard.hidden || _keyboard.frame.origin.y > 0);
    _pcKeys.frame = b;
}

#pragma mark - Bar

- (void)keyboardTapped {
    [PadHaptics play:PadHapticBar];
    [self openKeyboard];
}

- (void)pcKeysTapped {
    [PadHaptics play:PadHapticBar];
    [self openPcKeys];
}

- (void)settingsTapped {
    [PadHaptics play:PadHapticBar];
    [self.delegate padPanelWantsSettings:self];
}

- (void)disconnectTapped {
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
