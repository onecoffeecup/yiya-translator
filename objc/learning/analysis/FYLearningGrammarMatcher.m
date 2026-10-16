#import "FYLearningGrammarMatcher.h"
#import "FYLearningAnalysisSupport.h"
#import <NaturalLanguage/NaturalLanguage.h>

@implementation FYLearningGrammarMatcher
- (BOOL)hasLexicalConflict:(FYGrammarItem *)item source:(NSString *)source {
    NSString *name = [self signatureFromName:item.name];
    NSString *marker = [@[@"たい", @"なら"] containsObject:name] ? name : nil;
    if (!marker) { return NO; }
    NSString *compact = [[source componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
    NSString *span = [[item.matchedText componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
    // Convert the already verified UTF-16 range to the whitespace-free input.
    NSString *prefix = [[[[source substringToIndex:item.matchedRange.location] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""] copy];
    NSRange compactRange = NSMakeRange(prefix.length, span.length);
    NLTokenizer *tokenizer = [[NLTokenizer alloc] initWithUnit:NLTokenUnitWord];
    tokenizer.string = compact; [tokenizer setLanguage:NLLanguageJapanese];
    NSMutableArray<NSValue *> *tokens = [NSMutableArray new];
    [tokenizer enumerateTokensInRange:NSMakeRange(0, compact.length) usingBlock:^(NSRange range, NLTokenizerAttributes attributes, BOOL *stop) {
        [tokens addObject:[NSValue valueWithRange:range]];
    }];
    BOOL found = NO;
    NSUInteger cursor = compactRange.location;
    while (cursor < NSMaxRange(compactRange)) {
        NSRange match = [compact rangeOfString:marker options:0 range:NSMakeRange(cursor, NSMaxRange(compactRange)-cursor)];
        if (match.location == NSNotFound) { break; }
        found = YES; BOOL embedded = NO;
        for (NSValue *value in tokens) {
            NSRange word = value.rangeValue;
            if (word.location < match.location && NSMaxRange(word) >= NSMaxRange(match)) { embedded = YES; break; }
        }
        if (!embedded) { return NO; }
        cursor = NSMaxRange(match);
    }
    return found;
}

- (FYGrammarCatalogEntry *)resolveCatalogEntryForItem:(FYGrammarItem *)item provider:(id<FYLearningCatalogProviding>)provider {
    if (!provider.catalog) { return nil; }
    // 提供了 catalog_id 时只按 ID 定位；未知 ID 不得回退按名称授级/带来源。
    // 只有未提供 ID 时才允许按名称定位。
    FYGrammarCatalogEntry *entry = nil;
    if (item.catalogID.length > 0) {
        entry = [provider.catalog entryForID:item.catalogID];
    } else if (item.name.length > 0) {
        entry = [provider.catalog entryForName:item.name];
    }
    if (entry) {
        // catalog_id 必须与名称对应；名字对不上就不信任等级与来源。
        BOOL nameMatches = [entry.name isEqualToString:item.name] || [entry.aliases containsObject:item.name];
        if (item.catalogID.length > 0 && !nameMatches) { return nil; }
        // 命中片段必须真的在原文里，且要与该语法的一个签名形式一致，否则不授予等级。
        if (item.matchedRange.location == NSNotFound) { return nil; }
        if (![self entry:entry matchesSignature:item.matchedText]) { return nil; }
    }
    return entry;
}

- (BOOL)entry:(FYGrammarCatalogEntry *)entry matchesSignature:(NSString *)matchedText {
    NSString *compact = [[matchedText componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
    NSMutableArray<NSString *> *signatures = [NSMutableArray array];
    NSString *core = [self signatureFromName:entry.name];
    if (core.length > 0) { [signatures addObject:core]; }
    [signatures addObjectsFromArray:entry.aliases];
    [signatures addObjectsFromArray:entry.signatureForms ?: @[]];
    for (NSString *signature in signatures) {
        NSString *s = [self signatureFromName:signature];
        if (s.length == 0) { continue; }
        if ([compact containsString:s]) { return YES; }
    }
    return NO;
}

- (NSString *)signatureFromName:(NSString *)name {
    NSString *s = [name stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"〜～"]];
    NSRange paren = [s rangeOfString:@"（"];
    if (paren.location != NSNotFound) { s = [s substringToIndex:paren.location]; }
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSRange)verifiedRangeForText:(NSString *)fragment occurrence:(NSInteger)occurrence inText:(NSString *)source {
    NSRange exact = [self rangeForText:fragment occurrence:occurrence inText:source];
    if (exact.location != NSNotFound) { return exact; }
    NSMutableString *compact = [NSMutableString string];
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray array];
    NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSUInteger i=0;i<source.length;i++) {
        unichar c=[source characterAtIndex:i];
        if (![space characterIsMember:c]) { [compact appendString:[source substringWithRange:NSMakeRange(i,1)]];[offsets addObject:@(i)]; }
    }
    NSString *needle = [[fragment componentsSeparatedByCharactersInSet:space] componentsJoinedByString:@""];
    if (!needle.length) { return NSMakeRange(NSNotFound,0); }
    NSRange found = [self rangeForText:needle occurrence:occurrence inText:compact];
    if (found.location == NSNotFound) {
        // An unambiguous real span needs no model-supplied ordinal. Multiple spans stay strict.
        NSRange first = [self rangeForText:needle occurrence:0 inText:compact];
        NSRange second = [self rangeForText:needle occurrence:1 inText:compact];
        if (first.location == NSNotFound || second.location != NSNotFound) { return NSMakeRange(NSNotFound,0); }
        found = first;
    }
    NSUInteger start = offsets[found.location].unsignedIntegerValue;
    NSUInteger end = offsets[NSMaxRange(found)-1].unsignedIntegerValue + 1;
    return NSMakeRange(start,end-start);
}

- (NSRange)rangeForText:(NSString *)matchedText occurrence:(NSInteger)occurrence inText:(NSString *)text {
    if (matchedText.length == 0 || text.length == 0 || occurrence < 0) {
        return NSMakeRange(NSNotFound, 0);
    }
    NSInteger target = occurrence;
    NSRange searchRange = NSMakeRange(0, text.length);
    while (searchRange.location < text.length) {
        NSRange found = [text rangeOfString:matchedText options:0 range:searchRange];
        if (found.location == NSNotFound) { break; }
        if (target == 0) { return found; }
        target -= 1;
        searchRange = NSMakeRange(NSMaxRange(found), text.length - NSMaxRange(found));
    }
    return NSMakeRange(NSNotFound, 0);
}

@end
