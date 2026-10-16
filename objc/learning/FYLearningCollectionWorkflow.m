#import "FYLearningCollectionWorkflow.h"
#import "FYLearningWorkflowUtilities.h"

@implementation FYLearningCollectionWorkflow
- (instancetype)init { if ((self=[super init])) { _vocabularyQueue=dispatch_queue_create("com.nanami.fuyi.vocabulary-saves", DISPATCH_QUEUE_SERIAL); _vocabularyOperations=[NSMutableArray array]; } return self; }

- (void)completeVocabulary:(NSString *)surface
                   context:(NSString *)context
                completion:(void (^)(FYVocabularyEntry *, NSError *))completion receiver:(id<FYLearningCollectionWorkflowSource>)receiver {
    [receiver.analyzer completeVocabulary:surface context:context completion:completion];
}

- (void)bookmarkVocabulary:(FYVocabularyEntry *)entry selectedText:(NSString *)selectedText
                completion:(void (^)(FYVocabularyEntry *, BOOL, NSError *))completion receiver:(id<FYLearningCollectionWorkflowSource>)receiver {
    if (!entry || entry.surface.length == 0) {
        if (completion) { completion(nil, NO, [NSError errorWithDomain:@"FYLearningCoordinator" code:3 userInfo:@{NSLocalizedDescriptionKey: @"词条内容为空。"}]); }
        return;
    }
    // Capture provenance before any asynchronous queue or database work.
    NSString *sentenceID = receiver.currentSentenceID;
    NSInteger version = receiver.currentVersion;
    NSString *sourceText = receiver.currentSourceText;
    NSString *translation = receiver.currentTranslation;
    void (^operation)(void (^)(void)) = ^(void (^finished)(void)) {
        [receiver.store fetchVocabularyListWithCompletion:^(NSArray<FYVocabularyEntry *> *existing, NSError *error) {
            if (error) { if (completion) { completion(nil, NO, error); } finished(); return; }
            FYVocabularyEntry *duplicate = [receiver findDuplicateOf:entry in:existing];
            FYVocabularyEntry *saved = duplicate ?: entry;
            if (duplicate) { [receiver mergeCompletionInto:duplicate from:entry]; }
            else { saved.vocabularyID = NSUUID.UUID.UUIDString; saved.bookmarkedAt = NSDate.date; }
            FYVocabularyExample *example = nil;
            if (sentenceID.length) {
                example = [FYVocabularyExample new]; example.vocabularyID = saved.vocabularyID;
                example.sentenceID = sentenceID; example.version = version;
                example.sourceTextSnapshot = sourceText; example.translationSnapshot = translation;
                example.selectedRangeText = selectedText ?: @"";
            }
            [receiver.store saveVocabulary:saved withExample:example completion:^(NSError *writeError) {
                if (completion) { completion(writeError ? nil : saved, duplicate != nil, writeError); }
                finished();
            }];
        }];
    };
    dispatch_async(receiver.vocabularyQueue, ^{
        [receiver.vocabularyOperations addObject:[operation copy]];
        if (receiver.vocabularyOperations.count == 1) { [receiver startNextVocabularySave]; }
    });
}

- (void)startNextVocabularySaveWithReceiver:(id<FYLearningCollectionWorkflowSource>)receiver {
    if (!receiver.vocabularyOperations.count) { return; }
    void (^operation)(void (^)(void)) = receiver.vocabularyOperations.firstObject;
    operation(^{
        dispatch_async(receiver.vocabularyQueue, ^{
            [receiver.vocabularyOperations removeObjectAtIndex:0];
            [receiver startNextVocabularySave];
        });
    });
}

- (FYVocabularyEntry *)findDuplicateOf:(FYVocabularyEntry *)entry in:(NSArray<FYVocabularyEntry *> *)existing receiver:(id<FYLearningCollectionWorkflowSource>)receiver {
    BOOL lemmaKnown = entry.lemma.length > 0;
    BOOL readingKnown = entry.reading.length > 0;
    for (FYVocabularyEntry *candidate in existing) {
        BOOL sameKey = NO;
        if (lemmaKnown && readingKnown && candidate.lemma.length > 0 && candidate.reading.length > 0) {
            sameKey = [candidate.lemma isEqualToString:entry.lemma] && [candidate.reading isEqualToString:entry.reading];
        } else if (!lemmaKnown || !readingKnown || candidate.lemma.length == 0 || candidate.reading.length == 0) {
            // 读音/原形未知时，用实际词形匹配
            BOOL lemmaConflict = lemmaKnown && candidate.lemma.length > 0 && ![candidate.lemma isEqualToString:entry.lemma];
            BOOL readingConflict = readingKnown && candidate.reading.length > 0 && ![candidate.reading isEqualToString:entry.reading];
            sameKey = !lemmaConflict && !readingConflict && [candidate.surface isEqualToString:entry.surface];
        }
        if (!sameKey) { continue; }
        // 同形同音但义项不同时保留为独立词条。
        if (entry.meaning.length > 0 && candidate.meaning.length > 0 && ![entry.meaning isEqualToString:candidate.meaning]) {
            continue;
        }
        return candidate;
    }
    return nil;
}

// 把 incoming 的非空字段补到 existing 的空字段上；返回是否发生了需要持久化的变化。

- (BOOL)mergeCompletionInto:(FYVocabularyEntry *)existing from:(FYVocabularyEntry *)incoming receiver:(id<FYLearningCollectionWorkflowSource>)receiver {
    BOOL changed = NO;
    if (existing.lemma.length == 0 && incoming.lemma.length > 0) { existing.lemma = incoming.lemma; changed = YES; }
    if (existing.reading.length == 0 && incoming.reading.length > 0) { existing.reading = incoming.reading; changed = YES; }
    if (existing.meaning.length == 0 && incoming.meaning.length > 0) { existing.meaning = incoming.meaning; changed = YES; }
    if (changed && existing.completionSource == FYCompletionSourceManual && incoming.completionSource == FYCompletionSourceAI) {
        existing.completionSource = FYCompletionSourceAI; changed = YES;
    }
    return changed;
}

- (void)attachExampleForVocabulary:(NSString *)vocabularyID
                      selectedText:(NSString *)selectedText
                        sentenceID:(NSString *)sentenceID
                           version:(NSInteger)version
                         sourceText:(NSString *)sourceText
                        translation:(NSString *)translation
                        completion:(void (^)(NSError *))completion receiver:(id<FYLearningCollectionWorkflowSource>)receiver {
    if (sentenceID.length == 0) {
        if (completion) { completion(nil); }
        return;
    }
    FYVocabularyExample *example = [[FYVocabularyExample alloc] init];
    example.vocabularyID = vocabularyID;
    example.sentenceID = sentenceID;
    example.version = version;
    example.sourceTextSnapshot = sourceText;
    example.translationSnapshot = translation;
    example.selectedRangeText = selectedText ?: @"";
    [receiver.store attachExample:example completion:completion];
}

- (void)bookmarkGrammar:(FYGrammarItem *)item completion:(void (^)(NSError *))completion receiver:(id<FYLearningCollectionWorkflowSource>)receiver {
    if (!item || item.name.length == 0) {
        if (completion) {
            completion([NSError errorWithDomain:@"FYLearningCoordinator" code:4
                                       userInfo:@{NSLocalizedDescriptionKey: @"语法为空。"}]);
        }
        return;
    }
    FYGrammarBookmark *bookmark = [[FYGrammarBookmark alloc] init];
    bookmark.bookmarkID = FYTextHash([NSString stringWithFormat:@"%@|%ld|%@|%@", receiver.currentSentenceID ?: @"", (long)receiver.currentVersion, item.catalogID ?: @"", item.name]);
    bookmark.catalogID = item.catalogID;
    bookmark.name = item.name;
    bookmark.sentenceID = receiver.currentSentenceID ?: @"";
    bookmark.version = receiver.currentVersion;
    bookmark.sourceTextSnapshot = receiver.currentSourceText;
    bookmark.translationSnapshot = receiver.currentTranslation;
    bookmark.bookmarkedAt = NSDate.date;
    [receiver.store fetchGrammarBookmarksWithCompletion:^(NSArray<FYGrammarBookmark *> *bookmarks, NSError *error) {
        if (error) { if (completion) { completion(error); } return; }
        for (FYGrammarBookmark *existing in bookmarks) {
            if ([existing.name isEqualToString:bookmark.name] && [existing.sentenceID isEqualToString:bookmark.sentenceID] && existing.version == bookmark.version) {
                if (completion) { completion(nil); } return;
            }
        }
        [receiver.store addGrammarBookmark:bookmark completion:completion];
    }];
}

@end
