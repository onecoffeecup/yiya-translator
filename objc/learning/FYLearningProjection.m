#import "FYLearningProjection.h"
static BOOL FYHistoryHasExcludedLabelPrefix(FYSentenceRecord *legacy, FYSentenceRecord *confirmed) {
    if (legacy.kind != FYSentenceKindDialogue || confirmed.kind != FYSentenceKindDialogue ||
        !confirmed.excludedSpeakerLabels.count) return NO;
    NSRange newline=[legacy.latestText rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet];
    if (newline.location == NSNotFound) return NO;
    NSString *prefix=FYDialogueComparisonKey([legacy.latestText substringToIndex:newline.location]);
    NSString *body=[legacy.latestText substringFromIndex:NSMaxRange(newline)];
    return [confirmed.excludedSpeakerLabels containsObject:prefix] &&
        [FYDialogueComparisonKey(body) isEqualToString:FYDialogueComparisonKey(confirmed.latestText)];
}


@implementation FYLearningProjection
+ (NSArray<FYSentenceRecord *> *)displayHistoryRecords:(NSArray<FYSentenceRecord *> *)records {
        NSMutableArray<FYSentenceRecord *> *unique = [NSMutableArray array];
        // Group equivalent reads of one dialogue (variable leading dot runs,
        // a missed speaker box, a clipped last line) plus duplicates already
        // saved by older versions or across app restarts. Collections, stable
        // IDs and source snapshots stay untouched; this never rewrites the store.
        NSMutableArray<NSMutableArray<FYSentenceRecord *> *> *groups = [NSMutableArray array];
        for (FYSentenceRecord *record in records) {
            NSMutableArray<NSMutableArray<FYSentenceRecord *> *> *matches = [NSMutableArray array];
            for (NSMutableArray<FYSentenceRecord *> *group in groups) {
                if (group.firstObject.kind != record.kind) { continue; }
                BOOL same = NO;
                if (record.kind != FYSentenceKindDialogue) {
                    // Options, UI text and snapshots only collapse on identical text.
                    same = record.latestText.length > 0 && [group.firstObject.latestText isEqualToString:record.latestText];
                } else {
                    for (FYSentenceRecord *member in group) {
                        if (FYDialogueTextsAreEquivalent(member.latestText, record.latestText) ||
                            FYHistoryHasExcludedLabelPrefix(member,record) || FYHistoryHasExcludedLabelPrefix(record,member)) { same = YES; break; }
                    }
                }
                if (same) { [matches addObject:group]; }
            }
            if (matches.count == 0) {
                [groups addObject:[NSMutableArray arrayWithObject:record]];
                continue;
            }
            // A record can be equivalent to two groups (the relation is not
            // transitive); join them instead of picking one arbitrarily.
            NSMutableArray<FYSentenceRecord *> *target = matches.firstObject;
            [target addObject:record];
            for (NSUInteger i = 1; i < matches.count; i++) {
                NSMutableArray<FYSentenceRecord *> *extra = matches[i];
                if (extra == target) { continue; }
                [target addObjectsFromArray:extra];
                [groups removeObjectIdenticalTo:extra];
            }
            [target sortUsingComparator:^NSComparisonResult(FYSentenceRecord *a, FYSentenceRecord *b) {
                return [b.occurredAt compare:a.occurredAt];
            }];
        }
        for (NSMutableArray<FYSentenceRecord *> *group in groups) {
            if (group.count == 1) { [unique addObject:group.firstObject]; continue; }
            // Show the newest record that is not a degraded read of another
            // member, so a complete dialogue wins over a clipped frame even
            // when the clipped frame arrived later. `group` is newest-first.
            FYSentenceRecord *representative = nil;
            for (FYSentenceRecord *candidate in group) {
                // Prefer the stored body-only identity over an obsolete label-prefixed
                // snapshot, including a later pixel miss. Exact body + typed plate
                // evidence is required; a name-like first line alone proves nothing.
                BOOL obsoleteLabel=NO;
                for (FYSentenceRecord *other in group) {
                    if (other != candidate && FYHistoryHasExcludedLabelPrefix(candidate,other)) { obsoleteLabel=YES; break; }
                }
                if (obsoleteLabel) continue;
                BOOL degraded = NO;
                for (FYSentenceRecord *other in group) {
                    if (other == candidate) { continue; }
                    if (FYHistoryHasExcludedLabelPrefix(other,candidate)) continue;
                    if (FYDialogueIsIncompleteFrame(candidate.latestText, other.latestText) ||
                        FYDialogueIsFragmentOfDialogue(candidate.latestText, other.latestText)) { degraded = YES; break; }
                }
                if (!degraded) { representative = candidate; break; }
            }
            [unique addObject:representative ?: group.firstObject];
        }
    return unique;
}

+ (NSString *)vocabularyExampleText:(NSArray<FYVocabularyExample *> *)examples requestedIndex:(NSUInteger)index {
    if (!examples.count) return @"没有关联例句。";
    index %= examples.count;
    FYVocabularyExample *example=examples[index];
    NSString *translation=example.translationSnapshot.length > 0 ? [NSString stringWithFormat:@"\n译文：%@",example.translationSnapshot] : @"";
    return [NSString stringWithFormat:@"来源例句 %lu / %lu\n%@%@",(unsigned long)index+1,(unsigned long)examples.count,example.sourceTextSnapshot,translation];
}

+ (FYSentenceRecord *)historyRecordInList:(NSArray<FYSentenceRecord *> *)records index:(NSInteger)index identifier:(NSString *)identifier {
    if (index < 0 || index >= (NSInteger)records.count) return nil;
    FYSentenceRecord *record=records[index];
    if (identifier.length && ![record.sentenceID isEqualToString:identifier]) {
        for (FYSentenceRecord *candidate in records) if ([candidate.sentenceID isEqualToString:identifier]) return candidate;
        return nil;
    }
    return record;
}

+ (FYGrammarBookmark *)bookmarkInList:(NSArray<FYGrammarBookmark *> *)bookmarks grammarName:(NSString *)name sentenceID:(NSString *)sentenceID version:(NSInteger)version {
    for (FYGrammarBookmark *bookmark in bookmarks) {
        if ([bookmark.name isEqualToString:name] && [bookmark.sentenceID isEqualToString:sentenceID] && bookmark.version == version) return bookmark;
    }
    return nil;
}

+ (FYGrammarItem *)grammarItemInList:(NSArray<FYGrammarItem *> *)items index:(NSInteger)index fallbackToFirst:(BOOL)fallback {
    if (!items.count) return nil;
    if (index < 0 || index >= (NSInteger)items.count) { if (!fallback) return nil; index=0; }
    return items[index];
}

+ (BOOL)analysisMatchesSentenceID:(NSString *)analysisSentenceID version:(NSInteger)analysisVersion currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion {
    return [analysisSentenceID isEqualToString:currentSentenceID] && analysisVersion == currentVersion;
}

+ (NSArray<FYGrammarItem *> *)applicableGrammarItems:(NSArray<FYGrammarItem *> *)items text:(NSString *)text {
    NSMutableArray *result=[NSMutableArray new];
    for (FYGrammarItem *item in items) {
        NSRange range=item.matchedRange;
        if (range.location != NSNotFound && range.length <= text.length && range.location <= text.length-range.length &&
            [[text substringWithRange:range] isEqualToString:item.matchedText]) [result addObject:item];
    }
    return result;
}

+ (BOOL)followupBelongsToItem:(id)item requestedItem:(id)requestedItem requestGeneration:(NSInteger)requestGeneration currentGeneration:(NSInteger)currentGeneration
        sentenceID:(NSString *)sentenceID version:(NSInteger)version currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion {
    return requestGeneration == currentGeneration && requestedItem == item &&
        [sentenceID isEqualToString:currentSentenceID] && version == currentVersion;
}

+ (BOOL)requestSentenceID:(NSString *)sentenceID version:(NSInteger)version generation:(NSInteger)generation
        matchesSentenceID:(NSString *)currentSentenceID version:(NSInteger)currentVersion generation:(NSInteger)currentGeneration {
    return generation == currentGeneration && [sentenceID isEqualToString:currentSentenceID] && version == currentVersion;
}

+ (BOOL)selectionRange:(NSRange)range appliesToText:(NSString *)text sentenceID:(NSString *)sentenceID
              version:(NSInteger)version generation:(NSInteger)generation currentText:(NSString *)currentText
    currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion currentGeneration:(NSInteger)currentGeneration {
    return generation == currentGeneration && [sentenceID isEqualToString:currentSentenceID] &&
        version == currentVersion && [text isEqualToString:currentText] &&
        range.location != NSNotFound && range.length <= text.length && range.location <= text.length - range.length;
}

+ (FYVocabularyEntry *)nextReviewVocabularyInList:(NSArray<FYVocabularyEntry *> *)list index:(NSInteger)index nextIndex:(NSInteger *)nextIndex {
    if (list.count == 0) { if (nextIndex) { *nextIndex = 0; } return nil; }
    NSInteger safe = index >= 0 && index < (NSInteger)list.count ? index : 0;
    if (nextIndex) { *nextIndex = safe + 1; }
    return list[safe];
}

+ (FYVocabularyEntry *)vocabularyInList:(NSArray<FYVocabularyEntry *> *)list identifier:(NSString *)identifier fallbackIndex:(NSInteger)index {
    if (identifier.length) {
        for (FYVocabularyEntry *entry in list) { if ([entry.vocabularyID isEqualToString:identifier]) { return entry; } }
        return nil;
    }
    return index >= 0 && index < (NSInteger)list.count ? list[index] : nil;
}

@end
