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
static NSString* splitRunTogether(NSString* w, NSDictionary<NSString*, NSNumber*>* freq,
                                  NSDictionary<NSString*, NSString*>* contractions);

/// Words that commonly come next, most likely first: the context that settles close
/// autocorrect calls. Written for this keyboard from common English usage.
static NSString* const NEXT_WORDS =
    @"i\tam will have think don't can was just love know want need\n"
    @"i'm\tgoing not so sure just in on at here\n"
    @"you\tare can have know want for to need will guys\n"
    @"we\tare can have will need should were\n"
    @"they\tare were have will can don't\n"
    @"he\tis was said has will\n"
    @"she\tis was said has will\n"
    @"it\tis was will would\n"
    @"it's\tnot a the just going\n"
    @"that\tis was the it you\n"
    @"this\tis was one time week\n"
    @"what\tis are do the time you\n"
    @"how\tare is do much many about\n"
    @"where\tis are do did\n"
    @"when\tyou i the is we\n"
    @"why\tis do are not did\n"
    @"who\tis are was\n"
    @"can\tyou i we be\n"
    @"could\tyou be have not\n"
    @"would\tyou be have like\n"
    @"should\tbe i we have\n"
    @"will\tbe you have\n"
    @"do\tyou not it this\n"
    @"don't\tknow have want think\n"
    @"did\tyou not it\n"
    @"is\tit the a not that\n"
    @"are\tyou we they the\n"
    @"was\ta the it not\n"
    @"have\ta to you been the\n"
    @"has\tbeen a to\n"
    @"had\ta to been\n"
    @"be\ta the able there\n"
    @"been\ta the working\n"
    @"to\tthe be do get go see make\n"
    @"of\tthe a my this it\n"
    @"in\tthe a my this\n"
    @"on\tthe a my it\n"
    @"at\tthe a home work\n"
    @"for\tthe a you me\n"
    @"with\tthe a you me\n"
    @"from\tthe a my\n"
    @"about\tthe it that\n"
    @"and\tthe i it then\n"
    @"but\ti it the\n"
    @"or\tnot the\n"
    @"so\ti much it\n"
    @"if\tyou i it\n"
    @"thank\tyou\n"
    @"thanks\tfor\n"
    @"see\tyou it the\n"
    @"let\tme us\n"
    @"let's\tgo do see\n"
    @"going\tto\n"
    @"want\tto\n"
    @"need\tto\n"
    @"good\tmorning night luck job\n"
    @"how's\tit\n"
    @"what's\tup the\n"
    @"a\tlot few little good new\n"
    @"the\tsame best first\n"
    @"my\tname own\n"
    @"your\town name\n"
    @"just\ta the\n"
    @"not\tsure a the\n"
    @"no\tproblem worries\n"
    @"right\tnow\n"
    @"talk\tto\n"
    @"look\tat\n"
    @"looking\tforward for at\n"
    @"sounds\tgood\n";

@implementation PadAutocorrect {
    NSDictionary<NSString*, NSNumber*>* _freq;
    NSDictionary<NSString*, NSArray<NSString*>*>* _next;
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

    NSMutableDictionary* next = [NSMutableDictionary dictionary];
    for (NSString* line in [NEXT_WORDS componentsSeparatedByString:@"\n"]) {
        NSArray<NSString*>* parts = [line componentsSeparatedByString:@"\t"];
        if (parts.count != 2) continue;
        NSMutableArray* words = [NSMutableArray array];
        for (NSString* w in [parts[1] componentsSeparatedByString:@" "]) {
            if (w.length > 0) [words addObject:w];
        }
        if (words.count > 0) next[parts[0]] = words;
    }
    _next = next;

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
    return [self correct:word previous:nil];
}

- (BOOL)word:(NSString*)w follows:(nullable NSString*)previous {
    return previous != nil && [_next[previous.lowercaseString] containsObject:w];
}

- (nullable NSString*)correct:(NSString*)word previous:(nullable NSString*)previous {
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
    __block float bestCost = 0;
    void (^consider)(NSString*, float) = ^(NSString* candidate, float cost) {
        NSNumber* f = freq[candidate];
        if (f == nil || f.intValue < 20) return; // ignore very rare words as corrections
        // Frequency counts, but not so much that a common short word beats an obvious slip.
        float score = 0.6f * (f.intValue / 10.0f) - 3.0f * cost;
        // Context: a word that commonly follows the one before settles a close call.
        if ([self word:candidate follows:previous]) score += 2.0f;
        if (score > bestScore) {
            bestScore = score;
            bestWord = candidate;
            bestCost = cost;
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
    // Words run together by a missed space beat anything but an easy one-slip fix.
    NSString* split = lw.length >= 4 ? splitRunTogether(lw, freq, _contractions) : nil;
    if (split != nil && (bestWord == nil || bestCost > 0.5f)) {
        return matchCase(word, split);
    }
    return bestWord == nil ? nil : matchCase(word, bestWord);
}

/// Can stand alone as one of the words in a split: common enough that a split is safe.
static BOOL splitPiece(NSString* piece, NSDictionary<NSString*, NSNumber*>* freq,
                       NSDictionary<NSString*, NSString*>* contractions, int* f) {
    NSUInteger n = piece.length;
    if (n > 1 && contractions[piece] != nil) {
        *f = 60; // "im", "dont"...: typed without the apostrophe, as usual
        return YES;
    }
    if (n == 1 && ![piece isEqualToString:@"a"] && ![piece isEqualToString:@"i"]) return NO;
    NSNumber* v = freq[piece];
    if (v == nil) return NO;
    *f = v.intValue;
    return *f >= (n <= 2 ? 55 : 40);
}

/// "helloworld" or "hellobworld" (a key next to the space bar hit instead of it) as
/// "hello world": the fewest common words w can be cut into (the most common on a tie), or nil.
static NSString* splitRunTogether(NSString* w, NSDictionary<NSString*, NSNumber*>* freq,
                                  NSDictionary<NSString*, NSString*>* contractions) {
    NSUInteger n = w.length;
    if (n > 40) return nil;
    const int MAX_PIECES = 4;
    const float NONE = -1e9f;
    // best[i][k]: best score for w[0..i) cut into k pieces, ending at a piece boundary.
    float best[41][MAX_PIECES + 1];
    NSInteger from[41][MAX_PIECES + 1];
    for (NSUInteger i = 0; i <= n; i++) for (int k = 0; k <= MAX_PIECES; k++) best[i][k] = NONE;
    best[0][0] = 0;
    NSCharacterSet* nearSpace = [NSCharacterSet characterSetWithCharactersInString:@"cvbnm"];
    for (NSUInteger i = 0; i < n; i++) {
        for (int k = 0; k < MAX_PIECES; k++) {
            if (best[i][k] == NONE) continue;
            // The next piece starts right here (missed space), or one letter later when that
            // letter sits next to the space bar (hit instead of it).
            for (int skip = 0; skip <= 1; skip++) {
                if (skip == 1 && (k == 0 || ![nearSpace characterIsMember:[w characterAtIndex:i]])) continue;
                NSUInteger start = i + skip;
                for (NSUInteger end = start + 1; end <= n; end++) {
                    int f;
                    if (!splitPiece([w substringWithRange:NSMakeRange(start, end - start)], freq, contractions, &f)) continue;
                    float score = best[i][k] + f - 20 * skip;
                    if (score > best[end][k + 1]) {
                        best[end][k + 1] = score;
                        from[end][k + 1] = (NSInteger)(i * 2 + skip);
                    }
                }
            }
        }
    }
    // Fewest pieces wins: "hellonworld" is one slip from "hello world", two from "hell on world".
    int bestK = 0;
    for (int k = 2; k <= MAX_PIECES && bestK == 0; k++) {
        if (best[n][k] != NONE) bestK = k;
    }
    if (bestK == 0) return nil;
    NSMutableArray<NSString*>* pieces = [NSMutableArray array];
    NSUInteger end = n;
    for (int k = bestK; k > 0; k--) {
        NSInteger back = from[end][k];
        NSUInteger i = (NSUInteger)(back / 2), start = i + (NSUInteger)(back % 2);
        NSString* piece = [w substringWithRange:NSMakeRange(start, end - start)];
        if ([piece isEqualToString:@"i"]) piece = @"I";
        else if (contractions[piece] != nil) piece = contractions[piece];
        [pieces insertObject:piece atIndex:0];
        end = i;
    }
    return [pieces componentsJoinedByString:@" "];
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
