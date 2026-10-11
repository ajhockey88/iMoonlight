//
//  PadAutocorrect.m
//  iMoonlight
//
//  A port of ThorPad's WordEngine and Autocorrect (app/src/main/java/com/thorpad/).
//

#import "PadAutocorrect.h"

static NSString* const LEARNED_KEY = @"pad.autocorrect.learned";
/// Letters just above the space bar: hitting one instead of space joins two words.
static NSString* const NEAR_SPACE = @"cvbnm";

typedef struct { float x, y; } KeyPos;
static KeyPos keyPositions[26];

static NSDictionary<NSString*, NSString*>* CONTRACTIONS;
/// Contractions that are also words: only fixed where the contraction is what's meant.
static NSDictionary<NSString*, NSString*>* MAYBE_CONTRACTIONS;
/// After these, "its", "ill" and "id" are the plain words ("of its", "your id").
static NSSet<NSString*>* OWNER_WORDS;
static NSSet<NSString*>* PREPOSITIONS;
/// After these, "its" and "ill" start a clause: "where it's", "now I'll".
static NSSet<NSString*>* CLAUSE_WORDS;
/// Chat shorthand that isn't in the dictionary but is typed on purpose.
static NSSet<NSString*>* SLANG;
/// Whether prev starts a clause, where "ill" means I'll and "its" means it's.
static NSSet<NSString*>* START_WORDS;
/// Words often typed for one another, fixed only when the word before makes it plain.
static NSArray<NSArray<NSString*>*>* CONFUSED;

static NSString* matchCase(NSString* typed, NSString* fix);
static NSString* _Nullable fixed(NSString* typed, NSString* fix);
static BOOL startish(NSString* _Nullable prev);
static BOOL adjacent(unichar a, unichar b);

@interface PadAutocorrectBest : NSObject
@property (nonatomic, copy) NSString* word;
@property (nonatomic) float score;
@end

@implementation PadAutocorrectBest
- (instancetype)init {
    self = [super init];
    _score = -1e9f;
    return self;
}
@end

@implementation PadAutocorrect {
    NSMutableSet<NSString*>* _learned;
    // Filled in the background, then never changed: nothing reads them before _loaded is set.
    NSDictionary<NSString*, NSNumber*>* _ids;
    /// How common each word is, as zipf x 10 (70 = once in every ten thousand words).
    uint8_t* _zipf;
    /// Word pairs, as (first id << 20 | second id), sorted, with -10 log10 P(second | first).
    uint64_t* _pairKeys;
    uint8_t* _pairScores;
    NSUInteger _pairCount;
    volatile BOOL _loaded;
    volatile BOOL _pairsLoaded;
}

+ (void)initialize {
    if (self != [PadAutocorrect class]) return;
    NSArray<NSString*>* rows = @[@"qwertyuiop", @"asdfghjkl", @"zxcvbnm"];
    float offsets[] = {0, 0.5f, 1.5f};
    for (NSUInteger r = 0; r < rows.count; r++) {
        for (NSUInteger i = 0; i < rows[r].length; i++) {
            keyPositions[[rows[r] characterAtIndex:i] - 'a'] = (KeyPos){ i + offsets[r], r };
        }
    }
    NSArray<NSString*>* pairs = @[
        @"i", @"I", @"im", @"I'm", @"ive", @"I've", @"dont", @"don't", @"doesnt", @"doesn't",
        @"didnt", @"didn't", @"cant", @"can't", @"wont", @"won't", @"isnt", @"isn't", @"arent", @"aren't",
        @"wasnt", @"wasn't", @"werent", @"weren't", @"havent", @"haven't", @"hasnt", @"hasn't",
        @"hadnt", @"hadn't", @"couldnt", @"couldn't", @"wouldnt", @"wouldn't", @"shouldnt", @"shouldn't",
        @"mustnt", @"mustn't", @"youre", @"you're", @"youve", @"you've", @"youll", @"you'll",
        @"youd", @"you'd", @"theyre", @"they're", @"theyve", @"they've", @"theyll", @"they'll",
        @"theyd", @"they'd", @"weve", @"we've", @"thats", @"that's", @"whats", @"what's",
        @"wheres", @"where's", @"theres", @"there's", @"itll", @"it'll", @"aint", @"ain't",
        @"yall", @"y'all", @"whos", @"who's", @"hows", @"how's", @"whens", @"when's", @"whys", @"why's",
        @"heres", @"here's", @"shouldve", @"should've", @"wouldve", @"would've", @"couldve", @"could've",
        @"mightve", @"might've", @"mustve", @"must've", @"neednt", @"needn't", @"dunno", @"dunno",
        @"alot", @"a lot", @"infront", @"in front", @"eachother", @"each other", @"noone", @"no one",
        @"atleast", @"at least", @"aswell", @"as well", @"incase", @"in case", @"alright", @"alright",
        @"thankyou", @"thank you", @"everytime", @"every time", @"ofcourse", @"of course",
    ];
    NSMutableDictionary* contractions = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < pairs.count; i += 2) contractions[pairs[i]] = pairs[i + 1];
    CONTRACTIONS = contractions;
    NSArray<NSString*>* maybe = @[
        @"ill", @"I'll", @"id", @"I'd", @"hes", @"he's", @"shes", @"she's", @"its", @"it's",
        @"lets", @"let's", @"well", @"we'll", @"were", @"we're", @"wed", @"we'd", @"shell", @"she'll",
        @"hed", @"he'd", @"whos", @"who's",
    ];
    NSMutableDictionary* maybeMap = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < maybe.count; i += 2) maybeMap[maybe[i]] = maybe[i + 1];
    MAYBE_CONTRACTIONS = maybeMap;
    OWNER_WORDS = [NSSet setWithArray:@[
        @"the", @"a", @"an", @"my", @"your", @"his", @"her", @"our", @"their", @"this", @"that", @"these",
        @"those", @"every", @"each", @"no", @"any", @"some", @"very", @"so", @"too", @"really", @"is",
        @"was", @"be", @"been", @"being", @"are", @"were", @"feel", @"feeling", @"felt", @"look", @"looks"]];
    PREPOSITIONS = [NSSet setWithArray:@[
        @"of", @"in", @"on", @"at", @"to", @"for", @"with", @"by", @"from", @"into", @"onto", @"about",
        @"over", @"under", @"through", @"without", @"within", @"across", @"along", @"around", @"behind",
        @"during", @"against", @"among", @"between", @"toward", @"towards", @"near", @"upon", @"via", @"per"]];
    CLAUSE_WORDS = [NSSet setWithArray:@[
        @"where", @"what", @"how", @"why", @"who", @"now", @"say", @"see", @"sure", @"know", @"knew",
        @"thought", @"think", @"bet", @"said", @"since", @"though", @"once", @"until", @"unless",
        @"while", @"whether", @"guess", @"hope", @"mean", @"means", @"like", @"cuz", @"cos",
        @"lol", @"omg", @"well", @"anyway", @"actually", @"honestly", @"plus", @"also", @"still"]];
    SLANG = [NSSet setWithArray:@[
        @"omw", @"brb", @"lol", @"lmao", @"lmfao", @"rofl", @"idk", @"idc", @"imo", @"imho", @"tbh", @"smh",
        @"btw", @"thx", @"pls", @"plz", @"ty", @"tyvm", @"np", @"gg", @"ggs", @"wp", @"afk", @"irl", @"ngl",
        @"fr", @"rn", @"wyd", @"hbu", @"ikr", @"nvm", @"ttyl", @"gtg", @"g2g", @"jk", @"bc", @"cuz", @"ya",
        @"yea", @"nah", @"gonna", @"wanna", @"gotta", @"kinda", @"sorta", @"lemme", @"gimme", @"ur", @"u",
        @"r", @"k", @"kk", @"ok", @"okk", @"hmu", @"fyi", @"asap", @"dm", @"dms", @"pc", @"gpu", @"cpu",
        @"fps", @"ui", @"wtf", @"omg", @"ofc", @"bruh", @"lmk", @"tho", @"thru", @"gn", @"gm", @"ily", @"pog"]];
    START_WORDS = [NSSet setWithArray:@[
        @"and", @"but", @"so", @"then", @"if", @"think", @"because", @"cause", @"when", @"hope", @"guess",
        @"said", @"know", @"maybe", @"yes", @"yeah", @"ok", @"okay", @"oh"]];
    CONFUSED = @[
        @[@"their", @"there"], @[@"then", @"than"], @[@"lose", @"loose"], @[@"affect", @"effect"],
        @[@"weather", @"whether"], @[@"accept", @"except"], @[@"quite", @"quiet"], @[@"advice", @"advise"],
        @[@"breath", @"breathe"], @[@"loose", @"lose"], @[@"of", @"off"], @[@"were", @"where"],
    ];
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
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self load];
    });
    return self;
}

static NSString* resourceText(NSString* name) {
    NSString* path = [[NSBundle mainBundle] pathForResource:name ofType:@"txt"];
    return path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
}

static int compareKeys(const void* a, const void* b) {
    uint64_t x = *(const uint64_t*)a, y = *(const uint64_t*)b;
    return x < y ? -1 : x > y ? 1 : 0;
}

- (void)load {
    NSString* text = resourceText(@"words");
    if (text == nil) {
        Log(LOG_W, @"Autocorrect word list missing");
        return;
    }
    NSMutableDictionary<NSString*, NSNumber*>* ids = [NSMutableDictionary dictionaryWithCapacity:180000];
    __block NSUInteger cap = 150000, n = 0;
    __block uint8_t* z = malloc(cap);
    [text enumerateLinesUsingBlock:^(NSString* line, BOOL* stop) {
        if (line.length == 0 || [line characterAtIndex:0] == '#') return;
        NSRange tab = [line rangeOfString:@"\t"];
        if (tab.location == NSNotFound || tab.location == 0) return;
        NSString* w = [line substringToIndex:tab.location];
        if (ids[w] != nil) return;
        if (n == cap) z = realloc(z, cap *= 2);
        z[n] = (uint8_t)MIN(127, MAX(0, [[line substringFromIndex:tab.location + 1] intValue]));
        ids[w] = @(n++);
    }];
    _ids = ids;
    _zipf = z;
    _loaded = YES;

    // Which words follow which only sharpens corrections: without it they still work.
    text = resourceText(@"pairs");
    if (text == nil) {
        Log(LOG_W, @"Autocorrect word pairs missing");
        return;
    }
    __block NSUInteger pcap = 250000, pn = 0;
    __block uint64_t* packed = malloc(pcap * sizeof(uint64_t));
    [text enumerateLinesUsingBlock:^(NSString* line, BOOL* stop) {
        if (line.length == 0 || [line characterAtIndex:0] == '#') return;
        NSRange sp = [line rangeOfString:@" "], tab = [line rangeOfString:@"\t"];
        if (sp.location == NSNotFound || sp.location == 0 || tab.location == NSNotFound || tab.location <= sp.location) return;
        NSNumber* a = ids[[line substringToIndex:sp.location]];
        NSNumber* b = ids[[line substringWithRange:NSMakeRange(sp.location + 1, tab.location - sp.location - 1)]];
        if (a == nil || b == nil) return;
        if (pn == pcap) packed = realloc(packed, (pcap *= 2) * sizeof(uint64_t));
        uint64_t key = (uint64_t)a.unsignedIntegerValue << 20 | b.unsignedIntegerValue;
        packed[pn++] = key << 8 | ([[line substringFromIndex:tab.location + 1] intValue] & 0xff);
    }];
    // Sort by key, keeping each score with its key.
    qsort(packed, pn, sizeof(uint64_t), compareKeys);
    uint64_t* keys = malloc(MAX(pn, 1) * sizeof(uint64_t));
    uint8_t* scores = malloc(MAX(pn, 1));
    for (NSUInteger i = 0; i < pn; i++) {
        keys[i] = packed[i] >> 8;
        scores[i] = packed[i] & 0xff;
    }
    free(packed);
    _pairKeys = keys;
    _pairScores = scores;
    _pairCount = pn;
    _pairsLoaded = YES;
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

- (nullable NSString*)correct:(NSString*)word previous:(nullable NSString*)previous {
    if (word.length == 0 || !_loaded) return nil;
    @synchronized (self) {
        if ([_learned containsObject:word.lowercaseString]) return nil;
    }
    return [self engineCorrect:word previous:previous.lowercaseString];
}

// ---- The engine -----------------------------------------------------------------------------

- (BOOL)known:(NSString*)w {
    return _ids[w] != nil;
}

/// zipf x 10, or -1 for an unknown word.
- (int)z:(NSString*)w {
    NSNumber* idx = _ids[w];
    return idx == nil ? -1 : _zipf[idx.unsignedIntegerValue];
}

/// -10 log10 P(second | first), or -1 if the pair isn't known.
- (int)pair:(nullable NSString*)first second:(NSString*)second {
    if (first == nil || !_pairsLoaded) return -1;
    NSNumber* a = _ids[first];
    NSNumber* b = _ids[second];
    if (a == nil || b == nil) return -1;
    uint64_t key = (uint64_t)a.unsignedIntegerValue << 20 | b.unsignedIntegerValue;
    uint64_t* at = bsearch(&key, _pairKeys, _pairCount, sizeof(uint64_t), compareKeys);
    return at == NULL ? -1 : _pairScores[at - _pairKeys];
}

/// How likely a word is here, in zipf units, lifted when it often follows prev.
- (float)likely:(nullable NSString*)prev word:(NSString*)w {
    float zw = [self z:w] / 10.0f;
    int p = [self pair:prev second:w];
    if (p < 0) return zw;
    // How much more likely w is after prev than anywhere, capped so context can tip a
    // close call but never invent a word out of a big slip.
    float lift = (-p / 10.0f) - (zw - 9.0f);
    return zw + 0.5f * MAX(0.0f, MIN(3.0f, lift));
}

- (nullable NSString*)engineCorrect:(NSString*)word previous:(nullable NSString*)prev {
    NSString* lw = word.lowercaseString;
    for (NSUInteger i = 0; i < lw.length; i++) {
        unichar c = [lw characterAtIndex:i];
        if ((c < 'a' || c > 'z') && c != '\'') return nil;
    }
    // A capital inside a word (iPhone, McDonald) is on purpose: leave it.
    NSCharacterSet* upper = [NSCharacterSet uppercaseLetterCharacterSet];
    NSCharacterSet* lower = [NSCharacterSet lowercaseLetterCharacterSet];
    for (NSUInteger i = 1; i < word.length; i++) {
        if ([upper characterIsMember:[word characterAtIndex:i]] && [lower characterIsMember:[word characterAtIndex:i - 1]]) return nil;
    }
    NSString* contraction = CONTRACTIONS[lw];
    if (contraction != nil) return fixed(word, contraction);
    NSString* maybe = MAYBE_CONTRACTIONS[lw];
    if (maybe != nil) return [self contractionInContext:prev word:word lower:lw maybe:maybe];
    if (lw.length < 2 || [SLANG containsObject:lw]) return nil;

    if ([self known:lw]) return [self realWordFix:prev word:word lower:lw];

    // Unknown: the best single word, or the best way to split it into words.
    PadAutocorrectBest* best = [[PadAutocorrectBest alloc] init];
    NSMutableDictionary<NSString*, NSNumber*>* first = [NSMutableDictionary dictionary];
    [self edits:lw base:0 into:first knownOnly:NO];
    [first enumerateKeysAndObjectsUsingBlock:^(NSString* k, NSNumber* v, BOOL* stop) {
        [self consider:best previous:prev candidate:k cost:v.floatValue];
    }];
    if (lw.length >= 4 && lw.length <= 20) {
        NSMutableDictionary<NSString*, NSNumber*>* second = [NSMutableDictionary dictionary];
        [first enumerateKeysAndObjectsUsingBlock:^(NSString* k, NSNumber* v, BOOL* stop) {
            if (v.floatValue <= 1.0f) [self edits:k base:v.floatValue into:second knownOnly:YES];
        }];
        [second enumerateKeysAndObjectsUsingBlock:^(NSString* k, NSNumber* v, BOOL* stop) {
            [self consider:best previous:prev candidate:k cost:v.floatValue];
        }];
    }
    PadAutocorrectBest* split = [self split:lw previous:prev];
    if (split != nil && split.score > best.score) best = split;
    if (best.word == nil) return nil;
    return fixed(word, best.word);
}

static NSString* _Nullable fixed(NSString* typed, NSString* fix) {
    if ([fix isEqualToString:typed]) return nil;
    NSString* out = [fix hasPrefix:@"I"] ? fix : matchCase(typed, fix);
    return [out isEqualToString:typed] ? nil : out;
}

static BOOL startish(NSString* _Nullable prev) {
    return prev == nil || [START_WORDS containsObject:prev];
}

/// "ill" at the start of a sentence (or after and/so/think...) is I'll; elsewhere, ill.
- (nullable NSString*)contractionInContext:(nullable NSString*)prev word:(NSString*)word lower:(NSString*)lw maybe:(NSString*)maybe {
    if ([@[@"hes", @"shes", @"hed", @"whos"] containsObject:lw]) {
        return fixed(word, maybe); // hardly ever meant as typed
    }
    if ([@[@"ill", @"id", @"its", @"lets"] containsObject:lw]) {
        // The contraction, unless the word before is one the plain word usually follows
        // ("of its", "very ill", "your id", "he lets").
        if (prev != nil && ![lw isEqualToString:@"lets"]
            && ([OWNER_WORDS containsObject:prev] || [PREPOSITIONS containsObject:prev])) return nil;
        if (startish(prev) || [CLAUSE_WORDS containsObject:prev] || ![self followsOften:prev word:lw]) {
            return fixed(word, maybe);
        }
        return nil;
    }
    // well/were/wed/shell are common words in their own right: leave them.
    return nil;
}

/// Whether w turns up after prev more often than it does anywhere.
- (BOOL)followsOften:(nullable NSString*)prev word:(NSString*)w {
    int p = [self pair:prev second:w];
    return p >= 0 && -p / 10.0f > [self z:w] / 10.0f - 9.0f;
}

/// A real word that is probably a slip for another: confused pairs, or a rare near-miss.
- (nullable NSString*)realWordFix:(nullable NSString*)prev word:(NSString*)word lower:(NSString*)lw {
    if (prev != nil) {
        for (NSArray<NSString*>* pairOf in CONFUSED) {
            if (![pairOf[0] isEqualToString:lw]) continue;
            NSString* alt = pairOf[1];
            int typed = [self pair:prev second:lw], other = [self pair:prev second:alt];
            if (other < 0 || other > 15) continue;
            // Only when the typed word is far less likely after prev (about 6x or more).
            if (typed < 0 ? other <= 8 : typed - other >= 8) return fixed(word, alt);
        }
    }
    int zt = [self z:lw];
    if (zt >= 20 || lw.length < 3) return nil;
    // A very rare word one easy slip away from a common one ("teh", "adn"): the common
    // word was meant.
    NSMutableDictionary<NSString*, NSNumber*>* first = [NSMutableDictionary dictionary];
    [self edits:lw base:0 into:first knownOnly:YES];
    __block NSString* bestWord = nil;
    __block float bestScore = -1e9f;
    [first enumerateKeysAndObjectsUsingBlock:^(NSString* k, NSNumber* v, BOOL* stop) {
        if (v.floatValue > 0.5f) return;
        float zc = [self likely:prev word:k];
        if (zc * 10 < 45 || zc * 10 - zt < 35) return;
        float s = zc - 3.0f * v.floatValue;
        if (s > bestScore) {
            bestScore = s;
            bestWord = k;
        }
    }];
    return bestWord == nil ? nil : fixed(word, bestWord);
}

- (void)consider:(PadAutocorrectBest*)best previous:(nullable NSString*)prev candidate:(NSString*)candidate cost:(float)cost {
    int zc = [self z:candidate];
    if (zc < 20) return; // ignore very rare words as corrections
    // Frequency counts, but not so much that a common short word beats an obvious slip.
    float score = 0.6f * [self likely:prev word:candidate] - 3.0f * cost;
    if (score > best.score) {
        best.score = score;
        best.word = candidate;
    }
}

/// Splits words that ran together: a missed space ("helloworld"), or a letter typed by
/// grazing the space bar ("seebyou"). Each piece must be a common word.
- (nullable PadAutocorrectBest*)split:(NSString*)w previous:(nullable NSString*)prev {
    NSInteger n = w.length;
    if (n < 4 || n > 60) return nil;
    const float join = 0.6f, graze = 0.5f;
    float best[n + 1], startScore[n + 1];
    NSInteger pieceStart[n + 1]; // for a piece ending at i: where it started
    NSInteger prevEnd[n + 1];    // for a piece starting at j: where the last piece ended
    for (NSInteger i = 0; i <= n; i++) {
        best[i] = -INFINITY;
        startScore[i] = -INFINITY;
        pieceStart[i] = 0;
        prevEnd[i] = 0;
    }
    startScore[0] = 0;
    for (NSInteger j = 0; j < n; j++) {
        // Every piece ending at j is known by now: the next piece can start right there
        // (a missed space) or one letter on (a letter typed instead of space).
        if (j > 0 && best[j] != -INFINITY) {
            float s = best[j] - join * 2;
            if (s > startScore[j]) {
                startScore[j] = s;
                prevEnd[j] = j;
            }
            // Not after a one-letter piece: "imgoing" is "I'm going", not "I going".
            unichar c = [w characterAtIndex:j];
            if (j + 1 < n && [NEAR_SPACE rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound
                && j - pieceStart[j] > 1) {
                float g = best[j] - graze * 2;
                if (g > startScore[j + 1]) {
                    startScore[j + 1] = g;
                    prevEnd[j + 1] = j;
                }
            }
        }
        if (startScore[j] == -INFINITY) continue;
        for (NSInteger i = j + 1; i <= n && i - j <= 24; i++) {
            int zp = [self pieceZ:[w substringWithRange:NSMakeRange(j, i - j)]];
            if (zp < 0) continue;
            float s = startScore[j] + (zp / 10.0f - 9.0f); // log10 of how often the word is used
            if (s > best[i]) {
                best[i] = s;
                pieceStart[i] = j;
            }
        }
    }
    if (best[n] == -INFINITY || pieceStart[n] == 0) return nil;
    // Walk back to collect the pieces.
    NSMutableString* out = [NSMutableString string];
    float minZ = 99, costs = 0, context = 0;
    NSInteger i = n, pieces = 0;
    NSString* last = nil;
    while (i > 0) {
        NSInteger j = pieceStart[i];
        NSString* piece = [w substringWithRange:NSMakeRange(j, i - j)];
        NSString* shown = CONTRACTIONS[piece] ?: piece;
        if (j == 0 && MAYBE_CONTRACTIONS[piece] != nil && startish(prev)
            && ![@[@"well", @"were", @"wed", @"shell"] containsObject:piece]) {
            shown = MAYBE_CONTRACTIONS[piece]; // "letsgo" is "let's go"
        }
        [out insertString:shown atIndex:0];
        minZ = MIN(minZ, [self pieceZ:piece] / 10.0f);
        if (last != nil && [self pair:piece second:last] >= 0) context += 0.3f;
        last = piece;
        pieces++;
        if (j == 0) break;
        NSInteger e = prevEnd[j];
        costs += e == j ? join : graze;
        [out insertString:@" " atIndex:0];
        i = e;
    }
    if (pieces < 2) return nil;
    if ([self pair:prev second:last] >= 0) context += 0.3f;
    PadAutocorrectBest* b = [[PadAutocorrectBest alloc] init];
    b.word = out;
    b.score = 0.6f * minZ - 3.0f * costs + context;
    return b;
}

/// How common a piece of a split word is (zipf x 10), or -1 if it can't be a piece.
- (int)pieceZ:(NSString*)piece {
    if (piece.length == 1 && ![piece isEqualToString:@"a"] && ![piece isEqualToString:@"i"]) return -1;
    if (CONTRACTIONS[piece] != nil && piece.length > 1) return 55; // "im going"
    int zp = [self z:piece];
    if (piece.length == 2 && zp < 45) return -1; // "re", "ow": too easy to land on by chance
    return zp < 30 ? -1 : zp;
}

/// All one-slip variants of w, each with the cheapest cost of the slip that explains it.
- (void)edits:(NSString*)w base:(float)base into:(NSMutableDictionary<NSString*, NSNumber*>*)out knownOnly:(BOOL)knownOnly {
    NSUInteger n = w.length;
    unichar src[n + 1], buf[n + 2];
    [w getCharacters:src range:NSMakeRange(0, n)];
    // Each variant is written into buf as w's first i letters, the change, then the rest.
    #define VARIANT(len, cost) [self put:out word:[NSString stringWithCharacters:buf length:(len)] cost:base + (cost) knownOnly:knownOnly]
    for (NSUInteger i = 0; i <= n; i++) {
        memcpy(buf, src, i * sizeof(unichar));
        BOOL more = i < n; // letters left after position i
        unichar b0 = more ? src[i] : 0;
        if (more) {
            // Typed an extra letter (doubled letters are an easy slip).
            BOOL doubled = i > 0 && src[i - 1] == b0;
            memcpy(buf + i, src + i + 1, (n - i - 1) * sizeof(unichar));
            VARIANT(n - 1, doubled ? 0.5f : 0.8f);
        }
        if (n - i > 1) {
            buf[i] = src[i + 1]; // swapped
            buf[i + 1] = b0;
            memcpy(buf + i + 2, src + i + 2, (n - i - 2) * sizeof(unichar));
            VARIANT(n, 0.45f);
        }
        for (unichar c = 'a'; c <= 'z'; c++) {
            if (more && c != b0) {
                buf[i] = c;
                memcpy(buf + i + 1, src + i + 1, (n - i - 1) * sizeof(unichar));
                VARIANT(n, adjacent(b0, c) ? 0.5f : 1.0f);
            }
            BOOL doubling = (more && b0 == c) || (i > 0 && src[i - 1] == c);
            buf[i] = c; // missed a letter
            memcpy(buf + i + 1, src + i, (n - i) * sizeof(unichar));
            VARIANT(n + 1, doubling ? 0.5f : 0.9f);
        }
        if (more) {
            buf[i] = '\''; // missed apostrophe
            memcpy(buf + i + 1, src + i, (n - i) * sizeof(unichar));
            VARIANT(n + 1, 0.4f);
        }
    }
    #undef VARIANT
}

- (void)put:(NSMutableDictionary<NSString*, NSNumber*>*)out word:(NSString*)s cost:(float)cost knownOnly:(BOOL)knownOnly {
    if (knownOnly && ![self known:s]) return; // second slips: keep only real words
    NSNumber* old = out[s];
    if (old == nil || cost < old.floatValue) out[s] = @(cost);
}

static BOOL adjacent(unichar a, unichar b) {
    if (a < 'a' || a > 'z' || b < 'a' || b > 'z') return NO;
    KeyPos p = keyPositions[a - 'a'], q = keyPositions[b - 'a'];
    float dx = p.x - q.x, dy = p.y - q.y;
    return dx * dx + dy * dy <= 1.6f;
}

static NSString* matchCase(NSString* typed, NSString* fix) {
    if (fix.length == 0 || typed.length == 0) return fix;
    NSCharacterSet* lower = [NSCharacterSet lowercaseLetterCharacterSet];
    BOOL allUpper = typed.length > 1;
    for (NSUInteger i = 0; i < typed.length; i++) {
        if ([lower characterIsMember:[typed characterAtIndex:i]]) { allUpper = NO; break; }
    }
    if (allUpper) return fix.uppercaseString;
    if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:[typed characterAtIndex:0]]) {
        return [[fix substringToIndex:1].uppercaseString stringByAppendingString:[fix substringFromIndex:1]];
    }
    return fix;
}

@end
