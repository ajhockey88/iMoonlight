//
//  PadAutocorrect.m
//  iMoonlight
//

#import "PadAutocorrect.h"

static NSString* const LEARNED_KEY = @"pad.autocorrect.learned";

typedef struct { float x, y; } KeyPos;
static KeyPos keyPositions[26];

static void edits(NSString* w, float base, NSMutableDictionary<NSString*, NSNumber*>* out,
                  NSDictionary<NSString*, NSNumber*>* knownOnly);
static NSString* matchCase(NSString* typed, NSString* fix);

@implementation PadAutocorrect {
    NSDictionary<NSString*, NSNumber*>* _freq;
    NSMutableSet<NSString*>* _learned;
    NSDictionary<NSString*, NSString*>* _contractions;
}

+ (void)initialize {
    if (self == [PadAutocorrect class]) {
        NSArray<NSString*>* rows = @[@"qwertyuiop", @"asdfghjkl", @"zxcvbnm"];
        float offsets[] = {0, 0.5f, 1.5f};
        for (NSUInteger r = 0; r < rows.count; r++) {
            for (NSUInteger i = 0; i < rows[r].length; i++) {
                keyPositions[[rows[r] characterAtIndex:i] - 'a'] = (KeyPos){ i + offsets[r], r };
            }
        }
    }
}

+ (instancetype)shared {
    static PadAutocorrect* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[PadAutocorrect alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    NSArray* saved = [[NSUserDefaults standardUserDefaults] arrayForKey:LEARNED_KEY];
    _learned = [NSMutableSet setWithArray:saved ?: @[]];

    NSArray<NSString*>* pairs = @[
        @"i", @"I", @"im", @"I'm", @"ive", @"I've", @"dont", @"don't", @"doesnt", @"doesn't",
        @"didnt", @"didn't", @"cant", @"can't", @"wont", @"won't", @"isnt", @"isn't", @"arent", @"aren't",
        @"wasnt", @"wasn't", @"werent", @"weren't", @"havent", @"haven't", @"hasnt", @"hasn't",
        @"hadnt", @"hadn't", @"couldnt", @"couldn't", @"wouldnt", @"wouldn't", @"shouldnt", @"shouldn't",
        @"mustnt", @"mustn't", @"youre", @"you're", @"youve", @"you've", @"youll", @"you'll",
        @"theyre", @"they're", @"theyve", @"they've", @"theyll", @"they'll", @"weve", @"we've",
        @"thats", @"that's", @"whats", @"what's", @"wheres", @"where's", @"theres", @"there's",
        @"shes", @"she's", @"itll", @"it'll", @"aint", @"ain't",
        @"yall", @"y'all", @"alot", @"a lot", @"whos", @"who's", @"hows", @"how's",
        // "ill", "lets", "id" and "hes" are also words, so they are left alone.
    ];
    NSMutableDictionary* contractions = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < pairs.count; i += 2) contractions[pairs[i]] = pairs[i + 1];
    _contractions = contractions;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self load];
    });
    return self;
}

- (void)load {
    NSString* path = [[NSBundle mainBundle] pathForResource:@"words" ofType:@"txt"];
    NSString* text = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    if (text == nil) {
        Log(LOG_W, @"Autocorrect word list missing");
        return;
    }
    NSMutableDictionary<NSString*, NSNumber*>* freq = [NSMutableDictionary dictionaryWithCapacity:180000];
    [text enumerateLinesUsingBlock:^(NSString* line, BOOL* stop) {
        if (line.length == 0 || [line characterAtIndex:0] == '#') return;
        NSRange tab = [line rangeOfString:@"\t"];
        if (tab.location == NSNotFound || tab.location == 0) return;
        freq[[line substringToIndex:tab.location]] = @([[line substringFromIndex:tab.location + 1] intValue]);
    }];
    @synchronized (self) {
        _freq = freq;
    }
}

- (void)learn:(NSString*)word {
    NSString* w = word.lowercaseString;
    @synchronized (self) {
        if (w.length == 0 || [_learned containsObject:w]) return;
        [_learned addObject:w];
        [[NSUserDefaults standardUserDefaults] setObject:_learned.allObjects forKey:LEARNED_KEY];
    }
}

- (nullable NSString*)correct:(NSString*)word {
    if (word.length == 0) return nil;
    NSString* lw = word.lowercaseString;
    for (NSUInteger i = 0; i < lw.length; i++) {
        unichar c = [lw characterAtIndex:i];
        if ((c < 'a' || c > 'z') && c != '\'') return nil;
    }
    NSDictionary<NSString*, NSNumber*>* freq;
    @synchronized (self) {
        if ([_learned containsObject:lw]) return nil;
        freq = _freq;
    }
    NSString* contraction = _contractions[lw];
    if (contraction != nil) {
        if ([contraction isEqualToString:word]) return nil;
        return ([lw isEqualToString:@"i"] || [contraction hasPrefix:@"I"]) ? contraction : matchCase(word, contraction);
    }
    if (freq == nil || lw.length < 2 || freq[lw] != nil) return nil;

    __block NSString* bestWord = nil;
    __block float bestScore = -1e9f;
    void (^consider)(NSString*, float) = ^(NSString* candidate, float cost) {
        NSNumber* f = freq[candidate];
        if (f == nil || f.intValue < 20) return; // ignore very rare words as corrections
        // Frequency counts, but not so much that a common short word beats an obvious slip.
        float score = 0.6f * (f.intValue / 10.0f) - 3.0f * cost;
        if (score > bestScore) {
            bestScore = score;
            bestWord = candidate;
        }
    };

    NSMutableDictionary<NSString*, NSNumber*>* first = [NSMutableDictionary dictionary];
    edits(lw, 0, first, nil);
    [first enumerateKeysAndObjectsUsingBlock:^(NSString* k, NSNumber* v, BOOL* stop) { consider(k, v.floatValue); }];
    if (lw.length >= 4 && lw.length <= 14) {
        NSMutableDictionary<NSString*, NSNumber*>* second = [NSMutableDictionary dictionary];
        [first enumerateKeysAndObjectsUsingBlock:^(NSString* k, NSNumber* v, BOOL* stop) {
            if (v.floatValue <= 1.0f) edits(k, v.floatValue, second, freq);
        }];
        [second enumerateKeysAndObjectsUsingBlock:^(NSString* k, NSNumber* v, BOOL* stop) { consider(k, v.floatValue); }];
    }
    return bestWord == nil ? nil : matchCase(word, bestWord);
}

/// Records s with the cheapest cost of the slip that explains it. With a word list, keeps
/// only real words (used for second slips).
static void put(NSMutableDictionary<NSString*, NSNumber*>* out, NSString* s, float cost,
                NSDictionary<NSString*, NSNumber*>* knownOnly) {
    if (knownOnly != nil && knownOnly[s] == nil) return;
    NSNumber* old = out[s];
    if (old == nil || cost < old.floatValue) out[s] = @(cost);
}

static BOOL adjacent(unichar a, unichar b) {
    if (a < 'a' || a > 'z' || b < 'a' || b > 'z') return NO;
    KeyPos p = keyPositions[a - 'a'], q = keyPositions[b - 'a'];
    float dx = p.x - q.x, dy = p.y - q.y;
    return dx * dx + dy * dy <= 1.6f;
}

/// All one-slip variants of w.
static void edits(NSString* w, float base, NSMutableDictionary<NSString*, NSNumber*>* out,
                  NSDictionary<NSString*, NSNumber*>* knownOnly) {
    NSUInteger n = w.length;
    for (NSUInteger i = 0; i <= n; i++) {
        NSString* a = [w substringToIndex:i];
        NSString* b = [w substringFromIndex:i];
        unichar b0 = b.length > 0 ? [b characterAtIndex:0] : 0;
        unichar prev = i > 0 ? [w characterAtIndex:i - 1] : 0;
        if (b.length > 0) {
            // Typed an extra letter (doubled letters are an easy slip).
            BOOL doubled = i > 0 && prev == b0;
            put(out, [a stringByAppendingString:[b substringFromIndex:1]], base + (doubled ? 0.5f : 0.8f), knownOnly);
        }
        if (b.length > 1) {
            NSString* swapped = [NSString stringWithFormat:@"%@%C%C%@", a, [b characterAtIndex:1], b0, [b substringFromIndex:2]];
            put(out, swapped, base + 0.45f, knownOnly);
        }
        for (unichar c = 'a'; c <= 'z'; c++) {
            if (b.length > 0 && c != b0) {
                float cost = adjacent(b0, c) ? 0.5f : 1.0f;
                put(out, [NSString stringWithFormat:@"%@%C%@", a, c, [b substringFromIndex:1]], base + cost, knownOnly);
            }
            BOOL doubling = (b.length > 0 && b0 == c) || (i > 0 && prev == c);
            put(out, [NSString stringWithFormat:@"%@%C%@", a, c, b], base + (doubling ? 0.5f : 0.9f), knownOnly); // missed a letter
        }
        if (b.length > 0) put(out, [NSString stringWithFormat:@"%@'%@", a, b], base + 0.4f, knownOnly); // missed apostrophe
    }
}

static NSString* matchCase(NSString* typed, NSString* fix) {
    BOOL allUpper = typed.length > 1;
    NSCharacterSet* lower = [NSCharacterSet lowercaseLetterCharacterSet];
    for (NSUInteger i = 0; i < typed.length; i++) {
        if ([lower characterIsMember:[typed characterAtIndex:i]]) { allUpper = NO; break; }
    }
    if (allUpper) return fix.uppercaseString;
    if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:[typed characterAtIndex:0]]) {
        return [[[fix substringToIndex:1] uppercaseString] stringByAppendingString:[fix substringFromIndex:1]];
    }
    return fix;
}

@end
