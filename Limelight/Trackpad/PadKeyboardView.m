//
//  PadKeyboardView.m
//  iMoonlight
//
//  A port of ThorPad's KeyboardView (Android) to UIKit.
//

#import "PadKeyboardView.h"
#import "PadOutput.h"
#import "PadSettings.h"
#import "PadHaptics.h"
#import "PadAutocorrect.h"

typedef NS_ENUM(NSInteger, PadKeyType) {
    PadKeyChar, PadKeyShift, PadKeyBackspace, PadKeyEnter, PadKeySpace, PadKeyPage, PadKeySpecial, PadKeyClose
};
typedef NS_ENUM(NSInteger, PadKeyStyle) { PadKeyStyleKey, PadKeyStyleMod, PadKeyStyleEnter };
enum { PageLetters = 0, PageSymbols = 1, PageMore = 2 };

static const NSTimeInterval REPEAT_DELAY = 0.400, REPEAT_EVERY = 0.055;
static const NSTimeInterval CAPS_LOCK_DOUBLE_TAP = 0.350;
static const NSTimeInterval FLASH = 0.090;
static const CGFloat STRIP_HEIGHT = 44;
/// Two taps of space this close together type ". ".
static const NSTimeInterval DOUBLE_SPACE = 0.8;

static UIColor* rgb(int r, int g, int b) {
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1];
}

@interface PadKey : NSObject
@property (nonatomic, copy) NSString* label;
@property (nonatomic) PadKeyType type;
@property (nonatomic) unichar ch;
/// Page number or PadSpecialKey.
@property (nonatomic) NSInteger value;
@property (nonatomic) CGFloat weight;
@property (nonatomic) PadKeyStyle style;
@property (nonatomic) CGRect rect;
@end

@implementation PadKey
+ (instancetype)label:(NSString*)label type:(PadKeyType)type ch:(unichar)ch value:(NSInteger)value
               weight:(CGFloat)weight style:(PadKeyStyle)style {
    PadKey* k = [[PadKey alloc] init];
    k.label = label;
    k.type = type;
    k.ch = ch;
    k.value = value;
    k.weight = weight;
    k.style = style;
    return k;
}
@end

static NSArray<PadKey*>* chars(NSString* s) {
    NSMutableArray* out = [NSMutableArray array];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        [out addObject:[PadKey label:[NSString stringWithCharacters:&c length:1] type:PadKeyChar ch:c value:0 weight:1 style:PadKeyStyleKey]];
    }
    return out;
}

static NSArray<PadKey*>* mod(NSString* label, PadKeyType type, NSInteger value) {
    return @[[PadKey label:label type:type ch:0 value:value weight:1.45 style:PadKeyStyleMod]];
}

static NSArray<PadKey*>* special(NSString* label, PadSpecialKey key) {
    return @[[PadKey label:label type:PadKeySpecial ch:0 value:key weight:1 style:PadKeyStyleMod]];
}

static NSArray<PadKey*>* join(NSArray<NSArray<PadKey*>*>* parts) {
    NSMutableArray* out = [NSMutableArray array];
    for (NSArray* p in parts) [out addObjectsFromArray:p];
    return out;
}

static NSArray<PadKey*>* bottomRow(NSString* pageLabel, NSInteger target) {
    return join(@[mod(pageLabel, PadKeyPage, target),
                  chars(@","),
                  @[[PadKey label:@"space" type:PadKeySpace ch:' ' value:0 weight:4 style:PadKeyStyleKey]],
                  chars(@"."),
                  @[[PadKey label:@"⏎ Enter" type:PadKeyEnter ch:0 value:PadSpecialEnter weight:1.6 style:PadKeyStyleEnter]]]);
}

@implementation PadKeyboardView {
    NSArray<NSArray<NSArray<PadKey*>*>*>* _pages;
    PadKey* _closeKey;
    CGRect _stripRect, _pillRect;
    NSMapTable<UITouch*, id>* _down; // touch -> PadKey or NSNull
    NSMutableString* _typed;
    NSInteger _page;
    NSInteger _shift; // 0 off, 1 next letter only, 2 caps lock
    NSTimeInterval _lastShiftTap;
    CGFloat _rowHeight;
    PadKey* _repeating;
    PadKey* _flash;
    BOOL _typeOnRelease;
    BOOL _autoCapitalize;
    BOOL _doubleSpacePeriod;
    /// Shift was turned on for a new sentence, not by the user.
    BOOL _autoShifted;
    NSTimeInterval _lastSpaceAt;

    // Autocorrect: the suggestion for the word being typed is worked out in the background
    // and shown in the strip; tapping the strip keeps the word as typed.
    PadAutocorrect* _autocorrect;
    dispatch_queue_t _acQueue;
    NSUInteger _acGeneration;
    NSString* _suggestion;
    NSString* _suggestionFor;
    // The last correction made, so an immediate backspace can undo it.
    NSString* _fixOriginal;
    NSString* _fixApplied;
    NSString* _fixBoundary;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.multipleTouchEnabled = YES;
        self.backgroundColor = [UIColor blackColor];
        self.contentMode = UIViewContentModeRedraw;
        _down = [NSMapTable strongToStrongObjectsMapTable];
        _typed = [NSMutableString string];
        _acQueue = dispatch_queue_create("imoonlight.pad.autocorrect", DISPATCH_QUEUE_SERIAL);
        _closeKey = [PadKey label:@"✕ Close" type:PadKeyClose ch:0 value:0 weight:0 style:PadKeyStyleKey];
        _pages = @[
            @[chars(@"qwertyuiop"),
              chars(@"asdfghjkl"),
              join(@[mod(@"⇧", PadKeyShift, 0), chars(@"zxcvbnm"), mod(@"⌫", PadKeyBackspace, PadSpecialBackspace)]),
              bottomRow(@"?123", PageSymbols)],
            @[chars(@"1234567890"),
              chars(@"@#$%&-+()"),
              join(@[mod(@"=\\<", PadKeyPage, PageMore), chars(@"*\"':;!?"), mod(@"⌫", PadKeyBackspace, PadSpecialBackspace)]),
              bottomRow(@"ABC", PageLetters)],
            @[chars(@"~`|\\{}[]<>"),
              join(@[special(@"Esc", PadSpecialEscape), special(@"Tab", PadSpecialTab), chars(@"=_^/"),
                     special(@"←", PadSpecialLeft), special(@"↑", PadSpecialUp), special(@"→", PadSpecialRight)]),
              join(@[mod(@"?123", PadKeyPage, PageSymbols), chars(@"'\":;!?"), special(@"↓", PadSpecialDown),
                     mod(@"⌫", PadKeyBackspace, PadSpecialBackspace)]),
              bottomRow(@"ABC", PageLetters)],
        ];
        [self applySettings];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applySettings)
                                                     name:PadSettingsChangedNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)applySettings {
    _typeOnRelease = [PadSettings typeOnRelease];
    _autoCapitalize = [PadSettings autoCapitalize];
    _doubleSpacePeriod = [PadSettings doubleSpacePeriod];
    PadAutocorrect* ac = [PadSettings autocorrect] ? [PadAutocorrect shared] : nil;
    if (ac != _autocorrect) {
        _autocorrect = ac;
        [self clearSuggestion];
    }
}

- (void)reset {
    [_typed setString:@""];
    [self clearSuggestion];
    _fixOriginal = nil;
    _page = PageLetters;
    _shift = 0;
    _autoShifted = NO;
    [self updateAutoShift];
    [self cancelTouches];
    [self setNeedsDisplay];
}

#pragma mark - Layout

+ (CGFloat)preferredHeight {
    return 260; // the iPhone keyboard's height without its emoji / dictation row
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat closeW = MAX(88, w * 260 / 1240);
    _stripRect = CGRectMake(0, 0, w - closeW, STRIP_HEIGHT);
    _closeKey.rect = CGRectMake(w - closeW, 0, closeW, STRIP_HEIGHT);
    _rowHeight = (h - STRIP_HEIGHT) / 4;
    for (NSArray<NSArray<PadKey*>*>* rows in _pages) {
        for (NSUInteger r = 0; r < rows.count; r++) {
            CGFloat total = 0;
            for (PadKey* k in rows[r]) total += k.weight;
            CGFloat x = 0, top = STRIP_HEIGHT + r * _rowHeight;
            for (PadKey* k in rows[r]) {
                CGFloat kw = w * k.weight / total;
                k.rect = CGRectMake(x, top, kw, _rowHeight);
                x += kw;
            }
        }
    }
    [self setNeedsDisplay];
}

#pragma mark - Drawing

- (void)drawRect:(CGRect)rect {
    [[UIColor blackColor] setFill];
    UIRectFill(self.bounds);
    CGFloat hair = 1;
    [rgb(0x11, 0x13, 0x17) setFill];
    UIRectFill(CGRectMake(_stripRect.origin.x, _stripRect.origin.y, _stripRect.size.width - hair, _stripRect.size.height - hair));
    [self drawPreview];
    [self drawKey:_closeKey hair:hair];
    for (NSArray<PadKey*>* row in _pages[_page]) {
        for (PadKey* k in row) [self drawKey:k hair:hair];
    }
}

- (BOOL)isDown:(PadKey*)k {
    if (k == _flash) return YES;
    for (UITouch* t in _down) {
        if ([_down objectForKey:t] == k) return YES;
    }
    return NO;
}

static void drawCentered(NSString* text, CGRect r, UIFont* font, UIColor* color) {
    NSDictionary* attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: color};
    CGSize size = [text sizeWithAttributes:attrs];
    [text drawAtPoint:CGPointMake(CGRectGetMidX(r) - size.width / 2, CGRectGetMidY(r) - size.height / 2) withAttributes:attrs];
}

- (void)drawKey:(PadKey*)k hair:(CGFloat)hair {
    UIColor* bg;
    UIColor* fg;
    CGFloat size;
    BOOL bold = NO;
    BOOL clearAll = k.type == PadKeySpace && _repeating != nil;
    // Font sizes follow the key height, within limits that read well on a phone.
    CGFloat rh = MIN(_rowHeight, 110);
    if (k.type == PadKeyClose) {
        bg = rgb(0x4a, 0x22, 0x28);
        fg = rgb(0xff, 0xb3, 0xba);
        size = STRIP_HEIGHT * 0.38;
        bold = YES;
    } else if (k.style == PadKeyStyleEnter) {
        bg = rgb(0x1f, 0x4d, 0x6b);
        fg = rgb(0xbf, 0xe6, 0xff);
        size = rh * 0.17;
    } else if (k.style == PadKeyStyleMod) {
        bg = (k.type == PadKeyShift && _shift == 2) ? rgb(0x24, 0x50, 0x6e) : rgb(0x2c, 0x30, 0x39);
        fg = (k.type == PadKeyShift && _shift > 0) ? [UIColor whiteColor] : rgb(0xcf, 0xd6, 0xe2);
        size = k.label.length > 2 ? rh * 0.17 : rh * 0.24;
        bold = k.type == PadKeyShift && _shift > 0;
    } else if (clearAll) {
        // While backspace is held, the space bar becomes "Clear all".
        bg = rgb(0x3a, 0x1f, 0x23);
        fg = rgb(0xff, 0x9a, 0x9a);
        size = rh * 0.17;
        bold = YES;
    } else if (k.type == PadKeySpace) {
        bg = rgb(0x24, 0x26, 0x2d);
        fg = rgb(0x8a, 0x90, 0x9b);
        size = rh * 0.14;
    } else {
        bg = rgb(0x24, 0x26, 0x2d);
        fg = [UIColor whiteColor];
        size = rh * 0.29;
    }
    if ([self isDown:k]) {
        bg = rgb(0x78, 0xc8, 0xff);
        fg = [UIColor blackColor];
    }
    [bg setFill];
    UIRectFill(CGRectMake(k.rect.origin.x, k.rect.origin.y, k.rect.size.width - hair, k.rect.size.height - hair));
    NSString* label = clearAll ? @"Clear all" : k.label;
    if (k.type == PadKeyChar && _shift > 0 && _page == PageLetters) label = label.uppercaseString;
    UIFont* font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    drawCentered(label, k.rect, font, fg);
}

- (void)drawPreview {
    CGFloat h = _stripRect.size.height;
    CGFloat x = h * 0.3;
    CGFloat cy = CGRectGetMidY(_stripRect);

    UIFont* hintFont = [UIFont systemFontOfSize:h * 0.28];
    NSString* hint = @"Typing to PC";
    NSDictionary* hintAttrs = @{NSFontAttributeName: hintFont, NSForegroundColorAttributeName: rgb(0x6e, 0x73, 0x7d)};
    CGSize hs = [hint sizeWithAttributes:hintAttrs];
    [hint drawAtPoint:CGPointMake(x, cy - hs.height / 2) withAttributes:hintAttrs];
    x += hs.width + h * 0.22;

    CGFloat right = CGRectGetMaxX(_stripRect) - h * 0.3;
    _pillRect = CGRectZero;
    if (_suggestion != nil) {
        // "→ fix ✕" pill: autocorrect will use this at the next space; tap to keep yours.
        NSDictionary* pillAttrs = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:h * 0.36],
                                    NSForegroundColorAttributeName: rgb(0x78, 0xc8, 0xff)};
        NSString* pill = [NSString stringWithFormat:@"→ %@  ✕", _suggestion];
        CGSize ps = [pill sizeWithAttributes:pillAttrs];
        CGFloat pw = ps.width + h * 0.5;
        _pillRect = CGRectMake(CGRectGetMaxX(_stripRect) - h * 0.12 - pw, h * 0.14, pw, h * 0.72);
        [rgb(0x2c, 0x30, 0x39) setFill];
        [[UIBezierPath bezierPathWithRoundedRect:_pillRect cornerRadius:h * 0.2] fill];
        [pill drawAtPoint:CGPointMake(_pillRect.origin.x + h * 0.25, cy - ps.height / 2) withAttributes:pillAttrs];
        right = _pillRect.origin.x - h * 0.2;
    }

    NSDictionary* textAttrs = @{NSFontAttributeName: [UIFont systemFontOfSize:h * 0.46],
                                NSForegroundColorAttributeName: rgb(0xe8, 0xe8, 0xe8)};
    CGFloat room = MAX(0, right - x);
    NSString* shown = [[_typed stringByReplacingOccurrencesOfString:@"\n" withString:@"↵"]
                       stringByReplacingOccurrencesOfString:@"\t" withString:@"⇥"];
    // Keep as much of the end as fits.
    while (shown.length > 0 && [shown sizeWithAttributes:textAttrs].width > room) {
        shown = [shown substringFromIndex:MIN(shown.length, (NSUInteger)4)];
    }
    CGSize ts = [shown sizeWithAttributes:textAttrs];
    CGFloat lineH = [textAttrs[NSFontAttributeName] lineHeight];
    [shown drawAtPoint:CGPointMake(x, cy - lineH / 2) withAttributes:textAttrs];
    CGFloat caretX = x + ts.width + 2;
    [rgb(0x78, 0xc8, 0xff) setFill];
    UIRectFill(CGRectMake(caretX, cy - h * 0.26, 2, h * 0.52));
}

#pragma mark - Touch

- (PadKey*)keyAt:(CGPoint)p {
    if (CGRectContainsPoint(_closeKey.rect, p)) return _closeKey;
    if (p.y < CGRectGetMaxY(_closeKey.rect)) return nil; // the preview strip isn't a key
    PadKey* best = nil;
    CGFloat bestD = CGFLOAT_MAX;
    for (NSArray<PadKey*>* row in _pages[_page]) {
        for (PadKey* k in row) {
            if (CGRectContainsPoint(k.rect, p)) return k;
            // Edges: snap to the nearest key so the very border still counts.
            CGFloat dx = MAX(MAX(CGRectGetMinX(k.rect) - p.x, 0), p.x - CGRectGetMaxX(k.rect));
            CGFloat dy = MAX(MAX(CGRectGetMinY(k.rect) - p.y, 0), p.y - CGRectGetMaxY(k.rect));
            CGFloat d = dx * dx + dy * dy;
            if (d < bestD) {
                bestD = d;
                best = k;
            }
        }
    }
    return best;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    for (UITouch* touch in touches) {
        CGPoint p = [touch locationInView:self];
        PadKey* k = [self keyAt:p];
        [_down setObject:(k ?: [NSNull null]) forKey:touch];
        if (k == nil && _suggestion != nil && p.y < CGRectGetMaxY(_stripRect)) {
            [self rejectSuggestion];
            [PadHaptics play:PadHapticKey];
        }
        if (_repeating != nil && k != nil && k.type == PadKeySpace) {
            // While backspace is held the space bar reads "Clear all": tapping it
            // wipes the text, and the held backspace stops repeating.
            [_down setObject:[NSNull null] forKey:touch];
            [self clearAll];
            continue;
        }
        if (k != nil) {
            [PadHaptics play:PadHapticKey];
            [self flashKey:k];
            if (k.type == PadKeyBackspace) {
                // Delete right away, then keep deleting while held.
                [self fire:k];
                _repeating = k;
                [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(repeatKey) object:nil];
                [self performSelector:@selector(repeatKey) withObject:nil afterDelay:REPEAT_DELAY];
            } else if (!_typeOnRelease && k.type != PadKeyClose) {
                [self fire:k];
            }
        }
    }
    [self setNeedsDisplay];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if (!_typeOnRelease) return; // already typed
    for (UITouch* touch in touches) {
        id was = [_down objectForKey:touch];
        if (was == nil) continue;
        if ([was isKindOfClass:[PadKey class]] && ((PadKey*)was).type == PadKeyBackspace) continue;
        PadKey* now = [self keyAt:[touch locationInView:self]];
        if (now != was) {
            [_down setObject:(now ?: [NSNull null]) forKey:touch];
            [self setNeedsDisplay];
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    for (UITouch* touch in touches) {
        id value = [_down objectForKey:touch];
        [_down removeObjectForKey:touch];
        if (![value isKindOfClass:[PadKey class]]) continue;
        PadKey* k = value;
        if (k.type == PadKeyBackspace) {
            if (_repeating == k) {
                _repeating = nil;
                [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(repeatKey) object:nil];
            }
        } else if (_typeOnRelease || k.type == PadKeyClose) {
            [self fire:k];
        }
    }
    [self setNeedsDisplay];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self cancelTouches];
    [self setNeedsDisplay];
}

- (void)repeatKey {
    if (_repeating == nil) return;
    [self fire:_repeating];
    [self performSelector:@selector(repeatKey) withObject:nil afterDelay:REPEAT_EVERY];
}

#pragma mark - Autocorrect

static BOOL isBoundary(unichar c) {
    return c == ' ' || c == '.' || c == ',' || c == '!' || c == '?' || c == ';' || c == ':';
}

static BOOL isWordChar(unichar c) {
    return [[NSCharacterSet letterCharacterSet] characterIsMember:c] || c == '\'';
}

/// The word just before the cursor, as far as the keyboard has seen it typed.
- (NSString*)currentWord {
    NSUInteger i = _typed.length;
    while (i > 0 && isWordChar([_typed characterAtIndex:i - 1])) i--;
    NSString* w = [_typed substringFromIndex:i];
    while ([w hasPrefix:@"'"]) w = [w substringFromIndex:1];
    return w;
}

/// The word before the current one, across spaces only (so not across a sentence end).
- (NSString*)previousWord {
    NSUInteger i = _typed.length;
    while (i > 0 && isWordChar([_typed characterAtIndex:i - 1])) i--;
    NSUInteger end = i;
    while (end > 0 && [_typed characterAtIndex:end - 1] == ' ') end--;
    if (end == i || end == 0 || !isWordChar([_typed characterAtIndex:end - 1])) return nil;
    NSUInteger start = end;
    while (start > 0 && isWordChar([_typed characterAtIndex:start - 1])) start--;
    return [_typed substringWithRange:NSMakeRange(start, end - start)];
}

/// At the start of a sentence: nothing typed yet, or after a new line or ". ", "! ", "? ".
- (BOOL)atSentenceStart {
    NSUInteger n = _typed.length;
    if (n == 0 || [_typed characterAtIndex:n - 1] == '\n') return YES;
    if ([_typed characterAtIndex:n - 1] != ' ') return NO;
    NSUInteger i = n;
    while (i > 0 && [_typed characterAtIndex:i - 1] == ' ') i--;
    if (i == 0) return YES;
    unichar c = [_typed characterAtIndex:i - 1];
    return c == '.' || c == '!' || c == '?';
}

/// Shift on for one letter at the start of a sentence, and off again if that no longer holds.
- (void)updateAutoShift {
    if (_shift == 2) {
        _autoShifted = NO;
        return;
    }
    BOOL want = _autoCapitalize && _page == PageLetters && [self atSentenceStart];
    if (want && _shift == 0) {
        _shift = 1;
        _autoShifted = YES;
    } else if (!want && _autoShifted && _shift == 1) {
        _shift = 0;
        _autoShifted = NO;
    } else if (_shift == 0) {
        _autoShifted = NO;
    }
}

- (void)typeText:(NSString*)s {
    [_typed appendString:s];
    if (_typed.length > 200) [_typed deleteCharactersInRange:NSMakeRange(0, _typed.length - 200)];
    [[PadOutput shared] typeText:s];
}

- (void)deleteChars:(NSUInteger)n {
    for (NSUInteger i = 0; i < n; i++) {
        if (_typed.length > 0) [_typed deleteCharactersInRange:NSMakeRange(_typed.length - 1, 1)];
        [[PadOutput shared] special:PadSpecialBackspace];
    }
}

/// At the end of a word, swaps it for its correction. boundary is nil for Enter.
- (void)autocorrectWord:(NSString*)boundary {
    NSString* word = [self currentWord];
    NSString* fix = nil;
    if (_autocorrect != nil && word.length > 0) {
        fix = [word isEqualToString:_suggestionFor] ? _suggestion : [_autocorrect correct:word previous:[self previousWord]];
    }
    [self clearSuggestion];
    if (fix == nil || [fix isEqualToString:word]) return;
    [self deleteChars:word.length];
    [self typeText:fix];
    if (boundary != nil) {
        _fixOriginal = word;
        _fixApplied = fix;
        _fixBoundary = boundary;
    }
}

/// Backspace right after a correction puts back what was typed, and learns it.
- (BOOL)undoCorrection {
    NSString* tail = [_fixApplied stringByAppendingString:_fixBoundary];
    NSString* original = _fixOriginal;
    _fixOriginal = nil;
    if (_typed.length < tail.length || ![_typed hasSuffix:tail]) return NO;
    [self deleteChars:tail.length];
    [self typeText:original];
    [_autocorrect learn:original];
    [self clearSuggestion];
    return YES;
}

- (void)rejectSuggestion {
    if (_suggestionFor != nil) [_autocorrect learn:_suggestionFor];
    [self clearSuggestion];
}

- (void)clearSuggestion {
    _suggestion = nil;
    _suggestionFor = nil;
    _acGeneration++;
    [self setNeedsDisplay];
}

/// Works out, off the main thread, what the word being typed would be corrected to.
- (void)updateSuggestion {
    NSString* word = [self currentWord];
    if (_autocorrect == nil || word.length == 0) {
        [self clearSuggestion];
        return;
    }
    if (_suggestion != nil && ![word isEqualToString:_suggestionFor]) {
        _suggestion = nil;
        _suggestionFor = nil;
        [self setNeedsDisplay];
    }
    PadAutocorrect* ac = _autocorrect;
    NSString* previous = [self previousWord];
    NSUInteger generation = ++_acGeneration;
    __weak PadKeyboardView* weakSelf = self;
    dispatch_async(_acQueue, ^{
        PadKeyboardView* check = weakSelf;
        if (check == nil || check->_acGeneration != generation) return; // superseded already
        NSString* fix = [ac correct:word previous:previous];
        dispatch_async(dispatch_get_main_queue(), ^{
            PadKeyboardView* strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf->_acGeneration != generation) return;
            if (![word isEqualToString:[strongSelf currentWord]]) return;
            strongSelf->_suggestionFor = word;
            strongSelf->_suggestion = (fix != nil && ![fix isEqualToString:word]) ? fix : nil;
            [strongSelf setNeedsDisplay];
        });
    });
}

#pragma mark - Keys

/// Lights a key briefly so even the quickest tap visibly registers.
- (void)flashKey:(PadKey*)k {
    _flash = k;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(endFlash) object:nil];
    [self performSelector:@selector(endFlash) withObject:nil afterDelay:FLASH];
}

- (void)endFlash {
    _flash = nil;
    [self setNeedsDisplay];
}

- (void)clearAll {
    [self flashKey:_repeating];
    _repeating = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(repeatKey) object:nil];
    [_typed setString:@""];
    _fixOriginal = nil;
    [self clearSuggestion];
    [[PadOutput shared] special:PadSpecialClearAll];
    [PadHaptics play:PadHapticClearAll];
}

- (void)cancelTouches {
    [_down removeAllObjects];
    _repeating = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(repeatKey) object:nil];
}

- (void)fire:(PadKey*)k {
    BOOL undoable = _fixOriginal != nil;
    if (k.type != PadKeyBackspace) _fixOriginal = nil; // only an immediate backspace undoes a fix
    switch (k.type) {
        case PadKeyClose:
            [self cancelTouches];
            [self.delegate keyboardViewDidClose:self];
            return;
        case PadKeyPage:
            _page = k.value;
            _shift = 0;
            [self cancelTouches];
            break;
        case PadKeyShift: {
            NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
            if (_shift == 0) _shift = 1;
            else if (_shift == 1 && now - _lastShiftTap < CAPS_LOCK_DOUBLE_TAP) _shift = 2;
            else _shift = 0;
            _lastShiftTap = now;
            _autoShifted = NO;
            [self setNeedsDisplay];
            return; // the user's choice: no auto-capitalization until the next key
        }
        case PadKeyBackspace:
            if (undoable && [self undoCorrection]) break;
            _fixOriginal = nil;
            if (_typed.length > 0) [_typed deleteCharactersInRange:NSMakeRange(_typed.length - 1, 1)];
            [[PadOutput shared] special:PadSpecialBackspace];
            [self updateSuggestion];
            break;
        case PadKeyEnter:
            [self autocorrectWord:nil];
            [_typed setString:@""];
            _fixOriginal = nil;
            [[PadOutput shared] special:PadSpecialEnter];
            break;
        case PadKeySpecial:
            if (k.value == PadSpecialTab) [_typed appendString:@"\t"];
            [[PadOutput shared] special:(PadSpecialKey)k.value];
            break;
        case PadKeySpace:
        case PadKeyChar: {
            if (k.type == PadKeySpace && [self doubleSpaceToPeriod]) break;
            unichar c = k.ch;
            if (_page == PageLetters && _shift > 0 && c >= 'a' && c <= 'z') c -= 'a' - 'A';
            NSString* s = [NSString stringWithCharacters:&c length:1];
            if (isBoundary(c)) [self autocorrectWord:s];
            [self typeText:s];
            if (_shift == 1 && k.type == PadKeyChar) _shift = 0;
            if (k.type == PadKeySpace) _lastSpaceAt = [NSProcessInfo processInfo].systemUptime;
            [self updateSuggestion];
            break;
        }
    }
    [self updateAutoShift];
    [self setNeedsDisplay];
}

/// A second quick space after a word turns the first into ". ", like the iPhone.
- (BOOL)doubleSpaceToPeriod {
    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    NSUInteger n = _typed.length;
    if (!_doubleSpacePeriod || now - _lastSpaceAt > DOUBLE_SPACE || n < 2) return NO;
    if ([_typed characterAtIndex:n - 1] != ' ') return NO;
    unichar before = [_typed characterAtIndex:n - 2];
    if (![[NSCharacterSet alphanumericCharacterSet] characterIsMember:before]) return NO;
    _lastSpaceAt = 0; // a third space is just a space
    _fixOriginal = nil;
    [self deleteChars:1];
    [self typeText:@". "];
    [self updateSuggestion];
    return YES;
}

@end
