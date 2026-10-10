//
//  PadAutocorrect.h
//  iMoonlight
//
//  iPhone-style autocorrect for the on-screen keyboard, ported from ThorPad: when a word is
//  finished, an unknown word is swapped for the most likely intended word. Likelihood weighs
//  how common a word is (words.txt) against how big a slip it would take to type it wrong,
//  with neighbouring keys counting as small slips. Words run together by a missed space bar
//  (or a c, v, b, n or m hit instead of it) are split back apart. Words the user insists on are
//  remembered and never corrected again. The word before counts too: a correction that
//  commonly follows it wins a close call.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PadAutocorrect : NSObject

/// Shared instance; the word list loads in the background the first time.
+ (instancetype)shared;

/// Remembers a word so it is never corrected.
- (void)learn:(NSString*)word;

/// The correction for a finished word, or nil to leave it as typed. Safe to call off the main thread.
- (nullable NSString*)correct:(NSString*)word;
/// The same, using the word typed before it (or nil) to settle close calls.
- (nullable NSString*)correct:(NSString*)word previous:(nullable NSString*)previous;

@end

NS_ASSUME_NONNULL_END
