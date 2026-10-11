//
//  PadAutocorrect.h
//  iMoonlight
//
//  iPhone-style autocorrect for the on-screen keyboard, the same engine as ThorPad's: when a
//  word is finished, it is swapped for the most likely intended text. Likelihood weighs how
//  common a word is (words.txt), how well it follows the word before it (pairs.txt), and how
//  big a slip it would take to type it wrong, with neighbouring keys counting as small slips.
//  It also splits words that ran together, adds apostrophes, and fixes commonly confused words
//  when the word before makes the mistake plain. Words the user insists on are remembered and
//  never corrected again.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PadAutocorrect : NSObject

/// Shared instance; the word lists load in the background the first time.
+ (instancetype)shared;

/// Remembers a word so it is never corrected.
- (void)learn:(NSString*)word;

/// The correction for a finished word, or nil to leave it as typed. Safe to call off the main thread.
- (nullable NSString*)correct:(NSString*)word;
/// The same, using the word typed before it in the same sentence (or nil at the start of one).
- (nullable NSString*)correct:(NSString*)word previous:(nullable NSString*)previous;

@end

NS_ASSUME_NONNULL_END
