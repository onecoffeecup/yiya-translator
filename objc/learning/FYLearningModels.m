#import "FYLearningModels.h"

NSString *FYDialogueComparisonKey(NSString *text) {
    NSMutableString *key = [NSMutableString string];
    NSCharacterSet *spacing = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSCharacterSet *dashes = [NSCharacterSet characterSetWithCharactersInString:@"-－‐‑‒–—ー"];
    NSCharacterSet *periods = [NSCharacterSet characterSetWithCharactersInString:@".．。"];
    for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        // Compact each line before scanning its prefix: Vision also inserts
        // spaces between the dots. Keep newlines until every prefix is handled.
        NSString *line = [[rawLine componentsSeparatedByCharactersInSet:spacing] componentsJoinedByString:@""];
        // A leading run of middle dots / ellipsis / bullets is decoration that
        // OCR returns with a variable count (・×11 vs …••••), so it must not
        // split one dialogue into several identities. Opening quotes/brackets
        // remain in the key, but do not hide a Japanese line's leading dots.
        NSCharacterSet *leadingNoise = [NSCharacterSet characterSetWithCharactersInString:@"・･…⋯‥•。．._＿"];
        NSCharacterSet *openers = [NSCharacterSet characterSetWithCharactersInString:@"「『（(【［[〈《“‘\""];
        NSMutableString *opening = [NSMutableString new];
        NSUInteger noise = 0;
        while (noise < line.length) {
            unichar c = [line characterAtIndex:noise];
            if ([openers characterIsMember:c]) { [opening appendFormat:@"%C", c]; }
            else if (![leadingNoise characterIsMember:c]) { break; }
            noise++;
        }
        unichar firstAfterNoise = noise < line.length ? [line characterAtIndex:noise] : 0;
        BOOL quotedJapanese = (firstAfterNoise >= 0x3041 && firstAfterNoise <= 0x30FF) ||
            (firstAfterNoise >= 0x3400 && firstAfterNoise <= 0x9FFF) ||
            (firstAfterNoise >= 0xFF66 && firstAfterNoise <= 0xFF9D);
        // Do not turn a bracketed decimal (.5) or non-Japanese notation into
        // another value. The unquoted prefix retains the existing policy.
        if (noise > opening.length && (!opening.length || quotedJapanese)) {
            line = [opening stringByAppendingString:[line substringFromIndex:noise]];
        }
        NSUInteger prefix = 0;
        while (prefix < line.length && ([dashes characterIsMember:[line characterAtIndex:prefix]] ||
                                       [spacing characterIsMember:[line characterAtIndex:prefix]])) { prefix++; }
        if (prefix > 0 && prefix < line.length) {
            unichar first = [line characterAtIndex:prefix];
            // At the beginning of a Japanese line, OCR can confuse a dialogue
            // dash with ー. Internal long vowels and negative numbers stay intact.
            if ((first >= 0x3041 && first <= 0x30FA) || (first >= 0x3400 && first <= 0x9FFF)) {
                line = [line substringFromIndex:prefix];
            }
        }
        // Vision can alternate … (U+2026), ⋯ (U+22EF) and dot-run lengths.
        // Also accept internal pauses and callers that already supply flattened
        // text, where a middle body line's ending becomes an internal run.
        // Preserve single internal separators, decimals and non-Japanese
        // notation; only the comparison key changes, never the source snapshot.
        NSCharacterSet *ellipsis = [NSCharacterSet characterSetWithCharactersInString:@"・･…⋯‥•"];
        NSCharacterSet *symbols = [NSCharacterSet characterSetWithCharactersInString:@"…⋯‥"];
        NSMutableString *folded = [NSMutableString string];
        for (NSUInteger start = 0; start < line.length;) {
            unichar c = [line characterAtIndex:start];
            if (![ellipsis characterIsMember:c] && ![periods characterIsMember:c]) {
                [folded appendFormat:@"%C", c]; start++; continue;
            }
            NSUInteger end = start;
            BOOL hasSymbol = NO, hasEllipsisGlyph = NO;
            while (end < line.length) {
                unichar dot = [line characterAtIndex:end];
                if (![ellipsis characterIsMember:dot] && ![periods characterIsMember:dot]) { break; }
                hasSymbol |= [symbols characterIsMember:dot];
                hasEllipsisGlyph |= [ellipsis characterIsMember:dot];
                end++;
            }
            unichar previous = start > 0 ? [line characterAtIndex:start - 1] : 0;
            BOOL japanese = (previous >= 0x3041 && previous <= 0x30FF) || (previous >= 0x3400 && previous <= 0x9FFF);
            BOOL isEllipsis = hasSymbol || end - start >= 2 || (end == line.length && hasEllipsisGlyph);
            [folded appendString:japanese && isEllipsis ? @"…" : [line substringWithRange:NSMakeRange(start, end - start)]];
            start = end;
        }
        line = folded;
        NSUInteger end = line.length;
        while (end > 0 && [periods characterIsMember:[line characterAtIndex:end - 1]]) { end--; }
        if (end > 0 && end < line.length) {
            unichar last = [line characterAtIndex:end - 1];
            // Ignore unstable sentence-final periods only after Japanese text;
            // retain decimal numbers, question marks and exclamation marks.
            if ((last >= 0x3041 && last <= 0x30FF) || (last >= 0x3400 && last <= 0x9FFF)) {
                line = [line substringToIndex:end];
            }
        }
        [key appendString:line];
    }
    return key;
}

static NSArray<NSString *> *FYDialogueKeyLines(NSString *text) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *key = FYDialogueComparisonKey(raw);
        if (key.length) { [result addObject:key]; }
    }
    return result;
}

BOOL FYDialogueIsIncompleteFrame(NSString *candidate, NSString *complete) {
    NSArray<NSString *> *shortLines = FYDialogueKeyLines(candidate), *fullLines = FYDialogueKeyLines(complete);
    // A control bar can cut off the only body line, or the last line of a box.
    // Accept only a long exact prefix ending at an unfinished connective. A
    // general substring/fuzzy match would swallow new short replies, negation
    // and question endings. Inspect raw punctuation before comparison removes it.
    if (shortLines.count > 0 && shortLines.count == fullLines.count) {
        NSString *raw = [candidate stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *shortTail = shortLines.lastObject, *fullTail = fullLines.lastObject;
        NSCharacterSet *terminals = [NSCharacterSet characterSetWithCharactersInString:@"。.!！?？…‥・･\"」』）)"];
        BOOL aligned = raw.length && ![terminals characterIsMember:[raw characterAtIndex:raw.length - 1]];
        for (NSUInteger i = 0; i + 1 < shortLines.count; i++) {
            aligned &= [shortLines[i] isEqualToString:fullLines[i]];
        }
        BOOL unfinished = NO;
        // の/が/けど/から can themselves finish a natural spoken utterance;
        // do not use those endings as evidence of a missing continuation.
        for (NSString *ending in @[@"は", @"を", @"に", @"で", @"へ", @"と", @"も", @"ので", @"、", @","]) {
            if ([shortTail hasSuffix:ending]) { unfinished = YES; break; }
        }
        if (aligned && unfinished && shortTail.length >= 7 && fullTail.length >= shortTail.length + 5 &&
            shortTail.length * 5 <= fullTail.length * 4 && [fullTail hasPrefix:shortTail]) { return YES; }
    }
    // Require the same speaker and at least two aligned body lines. A fuzzy
    // whole-sentence similarity would also merge real questions and negations.
    if (shortLines.count < 3 || shortLines.count != fullLines.count ||
        ![shortLines[0] isEqualToString:fullLines[0]]) { return NO; }
    NSCharacterSet *endNoise = [NSCharacterSet characterSetWithCharactersInString:@".．。…_＿"];
    BOOL unfinishedContinuation = NO, anchoredInteriorClip = NO;
    NSUInteger shortenedLines = 0, missingCharacters = 0;
    for (NSUInteger i = 1; i < shortLines.count; i++) {
        NSString *shortLine = [shortLines[i] stringByTrimmingCharactersInSet:endNoise];
        NSString *fullLine = fullLines[i];
        if ([shortLine isEqualToString:fullLine]) { continue; }
        if (shortLine.length < 4 || fullLine.length <= shortLine.length) { return NO; }
        BOOL prefix = [fullLine hasPrefix:shortLine];
        // The final visible glyph can be misread at a clipped edge (それなり
        // vs それなら、...). Allow one such glyph only with a long missing tail.
        BOOL clippedLastGlyph = fullLine.length >= shortLine.length + 4 &&
            [fullLine hasPrefix:[shortLine substringToIndex:shortLine.length - 1]];
        if (!prefix && !clippedLastGlyph) { return NO; }
        // A single interior line can lose most of its tail while two later
        // lines remain intact (e.g. じゃあi vs じゃあさ、なんか相談あったら).
        // Require a substantial omission and two exact trailing anchors;
        // ordinary word substitutions and short suffix changes stay distinct.
        if (i + 2 < shortLines.count && shortLine.length * 2 <= fullLine.length &&
            fullLine.length - shortLine.length >= 6) {
            NSUInteger anchorCharacters=0;BOOL trailingMatches=YES;
            for(NSUInteger j=i+1;j<shortLines.count;j++) {
                if(![shortLines[j] isEqualToString:fullLines[j]]){trailingMatches=NO;break;}
                anchorCharacters += [fullLines[j] length];
            }
            if(trailingMatches && anchorCharacters>=12){anchoredInteriorClip=YES;}
        }
        shortenedLines++;
        missingCharacters += fullLine.length - shortLine.length;
        // A comma-ended continuation is positive evidence of truncation;
        // punctuation-only changes (e.g. statement -> question) are not.
        if (prefix && ([shortLine hasSuffix:@"、"] || [shortLine hasSuffix:@","])) {
            unfinishedContinuation = YES;
        }
    }
    return unfinishedContinuation || (shortenedLines == 1 && anchoredInteriorClip) || (shortenedLines >= 2 && missingCharacters >= 4);
}

BOOL FYDialogueIsSpeakerAnchoredFragment(NSString *candidate, NSString *complete) {
    NSArray<NSString *> *shortLines = FYDialogueKeyLines(candidate), *fullLines = FYDialogueKeyLines(complete);
    if (shortLines.count < 3 || shortLines.count >= fullLines.count ||
        ![shortLines[0] isEqualToString:fullLines[0]]) { return NO; }
    NSString *speaker = shortLines[0];
    NSCharacterSet *sentenceMarks = [NSCharacterSet characterSetWithCharactersInString:@"、,。.!！?？:：…"];
    if (speaker.length > 16 || [speaker rangeOfCharacterFromSet:sentenceMarks].location != NSNotFound) { return NO; }
    NSUInteger dropped = fullLines.count - shortLines.count;
    if (dropped > 2) { return NO; }
    // A separate name box may survive while the first body line disappears.
    // Keep the already complete frame only with two exact body anchors and a
    // substantial shared tail; a name plus a generic "ね？" is insufficient.
    NSUInteger anchorCharacters = 0;
    for (NSUInteger i = 1; i < shortLines.count; i++) {
        if (![shortLines[i] isEqualToString:fullLines[i + dropped]]) { return NO; }
        anchorCharacters += [shortLines[i] length];
    }
    return anchorCharacters >= 12;
}

BOOL FYDialogueIsFragmentOfDialogue(NSString *candidate, NSString *complete) {
    if (FYDialogueIsSpeakerAnchoredFragment(candidate, complete)) { return YES; }
    NSArray<NSString *> *shortLines = FYDialogueKeyLines(candidate), *fullLines = FYDialogueKeyLines(complete);
    if (shortLines.count == 0 || shortLines.count >= fullLines.count) { return NO; }
    NSUInteger dropped = fullLines.count - shortLines.count;
    // Two or more missing content lines stop looking like OCR clipping of the
    // same box; keep those as genuine separate occurrences.
    if (shortLines.count > 1 && dropped > 2) { return NO; }
    for (NSUInteger start = 0; start + shortLines.count <= fullLines.count; start++) {
        BOOL matches = YES;
        for (NSUInteger i = 0; i < shortLines.count; i++) {
            if (![shortLines[i] isEqualToString:fullLines[start + i]]) { matches = NO; break; }
        }
        if (!matches) { continue; }
        BOOL atHead = start == 0;
        BOOL atTail = start + shortLines.count == fullLines.count;
        // A clipped read keeps the head or the tail of the box. A different
        // utterance that merely shares middle lines must stay separate.
        if (!atHead && !atTail) { continue; }
        // A lone line is only accepted as the tail (the last visible line of a
        // box whose upper part was covered); a lone first line is ambiguous.
        if (shortLines.count == 1 && !atTail) { continue; }
        return YES;
    }
    return NO;
}

BOOL FYDialogueTextsAreEquivalent(NSString *first, NSString *second) {
    if (first.length == 0 || second.length == 0) { return NO; }
    if ([FYDialogueComparisonKey(first) isEqualToString:FYDialogueComparisonKey(second)]) { return YES; }
    // The relation must be symmetric: either frame may be the degraded one.
    return FYDialogueIsIncompleteFrame(first, second) || FYDialogueIsIncompleteFrame(second, first) ||
           FYDialogueIsFragmentOfDialogue(first, second) || FYDialogueIsFragmentOfDialogue(second, first);
}

@implementation FYRequestIdentity

+ (instancetype)identityWithSentenceID:(NSString *)sentenceID
                               version:(NSInteger)version
                             requestID:(NSString *)requestID
                            sourceText:(NSString *)sourceText
                           translation:(NSString *)translation {
    FYRequestIdentity *identity = [[FYRequestIdentity alloc] init];
    identity.sentenceID = sentenceID ?: @"";
    identity.version = version;
    identity.requestID = requestID ?: @"";
    identity.sourceText = sourceText ?: @"";
    identity.translation = translation;
    return identity;
}

@end

@implementation FYSentenceRecord
@end

@implementation FYSentenceVersion
@end

@implementation FYVocabularyEntry
@end

@implementation FYVocabularyExample
@end

@implementation FYGrammarItem
- (instancetype)init {
    self = [super init];
    if (self) {
        _matchedRange = NSMakeRange(NSNotFound, 0);
    }
    return self;
}
@end

@implementation FYAnalysisResult
- (instancetype)init {
    self = [super init];
    if (self) {
        _grammar = @[];
        _structureParts = @[];
        _vocabulary = @[];
        _schemaVersion = 1;
        _status = FYAnalysisStatusNone;
        _sentenceID = @"";
        _version = 0;
    }
    return self;
}
@end

@implementation FYGrammarBookmark
@end

@implementation FYGrammarCatalogEntry
- (instancetype)init {
    self = [super init];
    if (self) {
        _aliases = @[];
        _contentSourceIDs = @[];
        _referenceSources = @[];
        _contentOrigin = @"project_original";
        _levelReviewStatus = @"pending";
    }
    return self;
}
@end
