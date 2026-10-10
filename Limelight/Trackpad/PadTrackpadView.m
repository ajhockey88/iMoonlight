//
//  PadTrackpadView.m
//  iMoonlight
//
//  A port of ThorPad's TrackpadView (Android) to UIKit.
//

#import "PadTrackpadView.h"
#import "PadOutput.h"
#import "PadSettings.h"
#import "PadHaptics.h"

typedef NS_ENUM(NSInteger, PadState) {
    PadStateIdle,        // finger down, not yet decided
    PadStateMoving,      // moving the pointer
    PadStateDragging,    // holding the left button down
    PadStateTwoFinger,   // scrolling, pinch zooming, or a two-finger tap
    PadStateDone,        // ignore the rest of this touch
    PadStateThreeFinger, // swiping with three fingers
};

static const NSTimeInterval TAP_MAX = 0.350;
/// A drag must start this soon after a tap's finger lifts...
static const NSTimeInterval DRAG_WINDOW = 0.180;
/// ...and the finger must rest this long before sliding, or it just moves the pointer.
static const NSTimeInterval DRAG_SETTLE = 0.100;
static const NSTimeInterval LONG_PRESS = 0.550;
/// How far fingers travel sideways (or three fingers up / down) to trigger a swipe, in points.
static const CGFloat SWIPE_PT = 70;
/// Movement smaller than this is not yet a slide.
static const CGFloat SLOP_PT = 4.8;
/// A touch that strays less than this and lifts quickly still counts as a tap.
static const CGFloat TAP_SLOP_PT = 12;
/// Host pixels per point of finger travel before the pointer speed setting, tuned to match
/// ThorPad's feel.
static const CGFloat POINT_TO_PIXEL = 2.5;
/// Finger travel (after scroll speed) for one wheel notch, in points.
static const CGFloat NOTCH_PT = 22;
/// High-resolution wheel units in one notch.
static const CGFloat WHEEL_DELTA = 120;
/// Fingers must spread or pinch this far, more than they move together, to start a zoom.
static const CGFloat ZOOM_START_PT = 18;
/// Change in finger spacing for each zoom step (Ctrl + one wheel notch) at zoom speed 1,
/// in points. The "Pinch zoom speed" setting divides it.
static const CGFloat ZOOM_STEP_PT = 60;

@implementation PadTrackpadView {
    NSMutableArray<UITouch*>* _touches;
    PadState _state;
    NSTimeInterval _downAt, _lastTapUpAt, _lastMoveAt;
    CGPoint _down, _last;
    CGFloat _maxStray;
    BOOL _dragArmed, _longPressed, _scrolling, _swiping, _zooming, _touching;
    NSUInteger _maxPointers;
    CGFloat _twoLastY, _twoTravel, _twoStartX, _twoStartY, _twoStartSpread;
    int _zoomSteps;
    CGFloat _threeStartX, _threeStartY;
    CGFloat _tickAcc;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _touches = [NSMutableArray array];
        _state = PadStateDone;
        _active = YES;
        self.multipleTouchEnabled = YES;
        self.backgroundColor = [UIColor blackColor];
        self.contentMode = UIViewContentModeRedraw;
        self.opaque = YES;
    }
    return self;
}

- (void)setActive:(BOOL)active {
    if (_active != active) {
        [self cancelGesture];
    }
    _active = active;
}

#pragma mark - Drawing

static NSArray<NSArray<NSString*>*>* hintColumns(void) {
    return @[
        @[@"Slide", @"move", @"Tap", @"click", @"Hold", @"right click", @"Tap, hold, slide", @"drag"],
        @[@"Up / down", @"scroll", @"Spread / pinch", @"zoom", @"Tap", @"right click", @"Swipe right", @"back (Alt+←)", @"Swipe left", @"forward (Alt+→)"],
        @[@"Swipe up", @"task view", @"Swipe down", @"show desktop", @"Swipe left / right", @"switch app"],
    ];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[UIColor blackColor] setFill];
    CGContextFillRect(ctx, self.bounds);

    // Mostly black, with a faint outline, to be kind to the OLED.
    CGRect outline = CGRectInset(self.bounds, 6, 6);
    UIBezierPath* path = [UIBezierPath bezierPathWithRoundedRect:outline cornerRadius:18];
    path.lineWidth = 1.5;
    [(_touching ? [UIColor colorWithRed:120/255.0 green:200/255.0 blue:1 alpha:90/255.0]
                : [UIColor colorWithWhite:1 alpha:40/255.0]) setStroke];
    [path stroke];

    [self drawHints];
}

/// The gesture cheat sheet along the bottom: one column per number of fingers.
- (void)drawHints {
    NSArray<NSString*>* titles = @[@"☝️ One finger", @"✌️ Two fingers", @"🤟 Three fingers"];
    NSArray<NSArray<NSString*>*>* columns = hintColumns();
    CGFloat side = 16, bottomPad = 18;
    CGFloat colW = (self.bounds.size.width - 2 * side) / 3;
    CGFloat textW = colW - 14;
    UIFont* titleFont = [UIFont boldSystemFontOfSize:11];
    UIFont* font = [UIFont systemFontOfSize:10];
    UIColor* titleColor = [UIColor colorWithRed:120/255.0 green:200/255.0 blue:1 alpha:140/255.0];
    UIColor* keyColor = [UIColor colorWithWhite:1 alpha:140/255.0];
    UIColor* valueColor = [UIColor colorWithWhite:1 alpha:97/255.0];
    NSStringDrawingOptions opts = NSStringDrawingUsesLineFragmentOrigin;

    // Lay every column out first, to line their tops up with the tallest one.
    NSMutableArray<NSArray<NSAttributedString*>*>* rows = [NSMutableArray array];
    CGFloat tallest = 0;
    for (NSUInteger c = 0; c < 3; c++) {
        NSMutableArray<NSAttributedString*>* col = [NSMutableArray array];
        CGFloat h = [titles[c] boundingRectWithSize:CGSizeMake(textW, CGFLOAT_MAX) options:opts
                                         attributes:@{NSFontAttributeName: titleFont} context:nil].size.height + 6;
        NSArray<NSString*>* hints = columns[c];
        for (NSUInteger i = 0; i < hints.count; i += 2) {
            NSMutableAttributedString* row = [[NSMutableAttributedString alloc]
                initWithString:[hints[i] stringByAppendingString:@": "]
                    attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: keyColor}];
            [row appendAttributedString:[[NSAttributedString alloc] initWithString:hints[i + 1]
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: valueColor}]];
            [col addObject:row];
            h += ceil([row boundingRectWithSize:CGSizeMake(textW, CGFLOAT_MAX) options:opts context:nil].size.height) + 3;
        }
        [rows addObject:col];
        tallest = MAX(tallest, h);
    }

    CGFloat top = self.bounds.size.height - bottomPad - tallest;
    for (NSUInteger c = 0; c < 3; c++) {
        CGFloat x0 = side + c * colW;
        if (c > 0) {
            [[UIColor colorWithWhite:1 alpha:20/255.0] setFill];
            UIRectFill(CGRectMake(x0, top, 1, tallest));
        }
        CGFloat x = x0 + 8, y = top;
        CGRect titleRect = [titles[c] boundingRectWithSize:CGSizeMake(textW, CGFLOAT_MAX) options:opts
                                                attributes:@{NSFontAttributeName: titleFont} context:nil];
        [titles[c] drawWithRect:CGRectMake(x, y, textW, titleRect.size.height) options:opts
                     attributes:@{NSFontAttributeName: titleFont, NSForegroundColorAttributeName: titleColor} context:nil];
        y += titleRect.size.height + 6;
        for (NSAttributedString* row in rows[c]) {
            CGFloat h = ceil([row boundingRectWithSize:CGSizeMake(textW, CGFLOAT_MAX) options:opts context:nil].size.height);
            [row drawWithRect:CGRectMake(x, y, textW, h) options:opts context:nil];
            y += h + 3;
        }
    }
}

#pragma mark - Gesture helpers

- (CGPoint)averageOf:(NSUInteger)count {
    CGFloat x = 0, y = 0;
    NSUInteger n = MIN(count, _touches.count);
    for (NSUInteger i = 0; i < n; i++) {
        CGPoint p = [_touches[i] locationInView:self];
        x += p.x;
        y += p.y;
    }
    return n == 0 ? CGPointZero : CGPointMake(x / n, y / n);
}

- (CGFloat)spread {
    if (_touches.count < 2) return 0;
    CGPoint a = [_touches[0] locationInView:self], b = [_touches[1] locationInView:self];
    return hypot(a.x - b.x, a.y - b.y);
}

- (void)buzz:(PadHapticAction)action {
    [PadHaptics play:action];
}

- (void)startLongPressTimer {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(longPressFired) object:nil];
    [self performSelector:@selector(longPressFired) withObject:nil afterDelay:LONG_PRESS];
}

- (void)cancelLongPressTimer {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(longPressFired) object:nil];
}

- (void)longPressFired {
    if (_state == PadStateIdle && !_dragArmed && _active) {
        [[PadOutput shared] rightClick];
        _longPressed = YES;
        _state = PadStateDone;
        [self buzz:PadHapticHold];
    }
}

- (void)endScroll {
    if (_scrolling) {
        _scrolling = NO;
        [[PadOutput shared] scrollEnd];
    }
}

- (void)endZoom {
    if (_zooming) {
        _zooming = NO;
        [[PadOutput shared] zoomEnd];
    }
}

/// Lets go of whatever the current touch was doing.
- (void)cancelGesture {
    [self cancelLongPressTimer];
    if (_state == PadStateDragging) {
        [[PadOutput shared] dragEnd];
    }
    [self endScroll];
    [self endZoom];
    _state = PadStateDone;
}

/// Clicks if the touch that just ended was a tap.
- (BOOL)maybeTap:(NSTimeInterval)held now:(NSTimeInterval)now {
    if (_state == PadStateDragging || _state == PadStateTwoFinger || _state == PadStateDone) return NO;
    if (_maxPointers != 1 || _longPressed) return NO;
    if (held >= TAP_MAX || _maxStray >= TAP_SLOP_PT) return NO;
    // A tap, even if the finger rolled a little and nudged the pointer.
    [self buzz:PadHapticClick];
    if (_active) [[PadOutput shared] click];
    _lastTapUpAt = now;
    _state = PadStateDone;
    return YES;
}

#pragma mark - Touches

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    for (UITouch* touch in touches) {
        if (_touches.count == 0) {
            [_touches addObject:touch];
            [self firstFingerDown:touch];
        } else {
            [_touches addObject:touch];
            [self anotherFingerDown];
        }
    }
}

- (void)firstFingerDown:(UITouch*)touch {
    NSTimeInterval now = touch.timestamp;
    _state = PadStateIdle;
    _touching = YES;
    [self setNeedsDisplay];
    _downAt = now;
    _lastMoveAt = now;
    _down = _last = [touch locationInView:self];
    _maxStray = 0;
    _maxPointers = 1;
    _longPressed = NO;
    _scrolling = NO;
    _swiping = NO;
    _zooming = NO;
    _dragArmed = now - _lastTapUpAt < DRAG_WINDOW;
    [self startLongPressTimer];
}

- (void)anotherFingerDown {
    NSUInteger count = _touches.count;
    _maxPointers = MAX(_maxPointers, count);
    [self cancelLongPressTimer];
    if (_state == PadStateDragging || _state == PadStateDone) return;
    if (count == 2) {
        _state = PadStateTwoFinger;
        CGPoint avg = [self averageOf:2];
        _twoLastY = avg.y;
        _twoStartX = avg.x;
        _twoStartY = avg.y;
        _twoTravel = 0;
        _twoStartSpread = [self spread];
        _zoomSteps = 0;
        _swiping = NO;
    } else if (count == 3) {
        [self endScroll];
        [self endZoom];
        _state = PadStateThreeFinger;
        CGPoint avg = [self averageOf:3];
        _threeStartX = avg.x;
        _threeStartY = avg.y;
    } else {
        // Four or more fingers: not a gesture the trackpad uses.
        [self endScroll];
        [self endZoom];
        _state = PadStateDone;
    }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if (_touches.count == 0) return;
    PadOutput* out = _active ? [PadOutput shared] : nil;

    if (_state == PadStateThreeFinger) {
        if (_touches.count < 3) return;
        CGPoint avg = [self averageOf:3];
        CGFloat dx = avg.x - _threeStartX, dy = avg.y - _threeStartY;
        if (fabs(dx) > SWIPE_PT && fabs(dx) > 1.5 * fabs(dy)) {
            [out pressKeys:@[@(PadVkAlt), @(PadVkTab)]]; // switch app
            [self buzz:PadHapticThreeFinger];
            _state = PadStateDone;
        } else if (fabs(dy) > SWIPE_PT && fabs(dy) > 1.5 * fabs(dx)) {
            // Task view, or show the desktop.
            [out pressKeys:@[@(PadVkWin), @(dy < 0 ? PadVkTab : PadVkD)]];
            [self buzz:PadHapticThreeFinger];
            _state = PadStateDone;
        }
        return;
    }

    if (_state == PadStateTwoFinger) {
        if (_touches.count < 2) return;
        CGPoint avg = [self averageOf:2];
        CGFloat dy = avg.y - _twoLastY;
        _twoLastY = avg.y;
        _twoTravel += fabs(dy);
        CGFloat sideways = avg.x - _twoStartX;
        // Pinching moves the fingers apart or together; scrolling and swiping move them as one.
        CGFloat spreadChange = [self spread] - _twoStartSpread;
        BOOL undecided = !_scrolling && !_swiping && !_zooming;
        if (undecided && fabs(spreadChange) > ZOOM_START_PT
                && fabs(spreadChange) > hypot(sideways, avg.y - _twoStartY)) {
            _zooming = YES;
        }
        if (_zooming) {
            // Spreading the fingers zooms in (bigger), pinching them together zooms out,
            // like pinching a photo on the iPhone.
            CGFloat step = ZOOM_STEP_PT / MAX(0.1f, [PadSettings zoomSpeed]);
            int steps = (int)(spreadChange / step);
            if (steps != _zoomSteps) {
                [out zoomBy:steps - _zoomSteps];
                _zoomSteps = steps;
                [self buzz:PadHapticScroll];
            }
            return;
        }
        if (undecided && fabs(spreadChange) > 0.7 * _twoTravel + SLOP_PT) {
            return; // looks like the start of a pinch: wait before scrolling
        }
        if (undecided && fabs(sideways) > SLOP_PT
                && fabs(sideways) > 1.5 * fabs(avg.y - _twoStartY)
                && fabs(spreadChange) < fabs(sideways)) {
            _swiping = YES; // a sideways swipe: back or forward, not a scroll
        }
        if (_swiping) {
            if (fabs(sideways) > SWIPE_PT) {
                // PC browsers' back and forward keys.
                [out pressKeys:@[@(PadVkAlt), @(sideways > 0 ? PadVkLeft : PadVkRight)]];
                [self buzz:PadHapticNavigate];
                _state = PadStateDone;
            }
            return;
        }
        if (!_scrolling && _twoTravel > SLOP_PT) {
            _scrolling = YES;
            _tickAcc = 0;
        }
        if (_scrolling) {
            CGFloat dir = [PadSettings invertScroll] ? -1 : 1;
            CGFloat amount = dy * [PadSettings scrollSpeed] * dir;
            // Fingers moving up scroll the content down, like a laptop trackpad.
            [out scrollBy:amount * WHEEL_DELTA / NOTCH_PT];
            // A tick for every wheel notch, like a notched scroll wheel.
            _tickAcc += amount;
            if (fabs(_tickAcc) >= NOTCH_PT) {
                _tickAcc = fmod(_tickAcc, NOTCH_PT);
                [self buzz:PadHapticScroll];
            }
        }
        return;
    }

    if (_state == PadStateDone) return;

    UITouch* touch = _touches[0];
    CGPoint p = [touch locationInView:self];
    CGFloat dx = p.x - _last.x, dy = p.y - _last.y;
    _last = p;
    _maxStray = MAX(_maxStray, hypot(p.x - _down.x, p.y - _down.y));
    NSTimeInterval now = touch.timestamp;
    NSTimeInterval dt = MAX(0.001, now - _lastMoveAt);
    _lastMoveAt = now;

    if (_state == PadStateIdle) {
        if (hypot(p.x - _down.x, p.y - _down.y) < SLOP_PT) return;
        [self cancelLongPressTimer];
        // Tap-then-drag: only when the second touch came quickly and settled first.
        // A quick tap followed by an immediate swipe just moves the pointer.
        if (_dragArmed && out != nil && now - _downAt >= DRAG_SETTLE) {
            [out dragBegin];
            [self buzz:PadHapticDragStart];
            _state = PadStateDragging;
        } else {
            _state = PadStateMoving;
        }
    }
    // Pointer acceleration: slow movements are precise, quick flicks travel far.
    CGFloat speed = hypot(dx, dy) / (dt * 1000); // points per ms
    CGFloat gain = [PadSettings sensitivity] * (1 + [PadSettings acceleration] * MIN(speed, 4)) * POINT_TO_PIXEL;
    [out moveByX:dx * gain y:dy * gain];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    for (UITouch* touch in touches) {
        if (![_touches containsObject:touch]) continue;
        if (_touches.count > 1) {
            [self fingerUp:touch];
        } else {
            [_touches removeObject:touch];
            [self lastFingerUp:touch.timestamp];
        }
    }
}

- (void)fingerUp:(UITouch*)touch {
    NSUInteger countBefore = _touches.count;
    BOOL wasFirst = _touches.firstObject == touch;
    [_touches removeObject:touch];
    if (_state == PadStateTwoFinger && countBefore == 2) {
        if (_scrolling || _zooming) {
            [self endScroll];
            [self endZoom];
            _state = PadStateDone;
        }
        // Otherwise wait for the last finger: it may be a two-finger tap.
    }
    if (wasFirst && _touches.count > 0) {
        // Keep following the finger still down without a jump.
        _last = [_touches[0] locationInView:self];
    }
}

- (void)lastFingerUp:(NSTimeInterval)now {
    [self cancelLongPressTimer];
    NSTimeInterval held = now - _downAt;
    _touching = NO;
    [self setNeedsDisplay];
    PadOutput* out = _active ? [PadOutput shared] : nil;
    if (_state == PadStateDragging) {
        [[PadOutput shared] dragEnd];
        [self buzz:PadHapticDragEnd];
    } else if (_state == PadStateTwoFinger && !_scrolling && !_swiping && !_zooming && _maxPointers == 2 && held < 0.350) {
        [out rightClick];
        [self buzz:PadHapticRightClick];
    } else if ([self maybeTap:held now:now]) {
        return;
    } else if (_state == PadStateTwoFinger) {
        [self endScroll];
        [self endZoom];
    }
    _state = PadStateDone;
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    // iOS took the touch away (a system gesture, an alert...). If it looked like a tap,
    // still click: a short tap is the touch most likely to be cancelled.
    for (UITouch* touch in touches) {
        [_touches removeObject:touch];
    }
    if (_touches.count > 0) return;
    [self cancelLongPressTimer];
    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    _touching = NO;
    [self setNeedsDisplay];
    if (_state == PadStateDragging) {
        [[PadOutput shared] dragEnd];
    }
    [self endScroll];
    [self endZoom];
    [self maybeTap:now - _downAt now:now];
    _state = PadStateDone;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gestureRecognizer {
    // Keep iOS's three-finger copy / paste / undo gestures from stealing trackpad swipes.
    return gestureRecognizer.name == nil || ![gestureRecognizer.name hasPrefix:@"kbProductivity."];
}

@end
