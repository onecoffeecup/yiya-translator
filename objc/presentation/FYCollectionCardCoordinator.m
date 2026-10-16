#import "FYCollectionCardCoordinator.h"

@implementation FYCollectionCardCoordinator
- (FYVocabularyEntry *)wordWithReceiver:(id<FYCollectionCardSource>)receiver identifier:(NSString *(^)(void))identifier tag:(NSInteger(^)(void))tag {
    return [FYLearningCoordinator vocabularyInList:receiver.reviewList identifier:identifier() fallbackIndex:tag()];
}

- (void)nextExampleWithReceiver:(id<FYCollectionCardSource>)receiver identifier:(NSString *(^)(void))identifier {
    if (!receiver.wordExampleIndices) { receiver.wordExampleIndices = [NSMutableDictionary dictionary]; }
    receiver.wordExampleIndices[identifier()] = @([receiver.wordExampleIndices[identifier()] unsignedIntegerValue] + 1);
    [receiver rebuildWordCards];
}

- (void)toggleDetailsWithReceiver:(id<FYCollectionCardSource>)receiver word:(FYVocabularyEntry *(^)(void))word update:(void(^)(BOOL))update {
    FYVocabularyEntry *entry=word();if(!entry){return;}
    if(!receiver.expandedWordCards){receiver.expandedWordCards=[NSMutableSet new];}
    BOOL expanded=[receiver.expandedWordCards containsObject:entry.vocabularyID];
    expanded?[receiver.expandedWordCards removeObject:entry.vocabularyID]:[receiver.expandedWordCards addObject:entry.vocabularyID];
    update(expanded);
}

- (void)toggleMeaningWithReceiver:(id<FYCollectionCardSource>)receiver word:(FYVocabularyEntry *(^)(void))word update:(void(^)(FYVocabularyEntry *,BOOL))update {
    FYVocabularyEntry *entry = word();
    if (!entry) { return; }
    BOOL currentlyRevealed=receiver.revealedMeanings[entry.vocabularyID]==nil || [receiver.revealedMeanings[entry.vocabularyID] boolValue];
    BOOL revealed = !currentlyRevealed;
    receiver.revealedMeanings[entry.vocabularyID] = @(revealed);
    update(entry,revealed);
}

- (void)toggleMasteredWithReceiver:(id<FYCollectionCardSource>)receiver word:(FYVocabularyEntry *(^)(void))word {
    FYVocabularyEntry *entry = word();
    if (!entry) { return; }
    FYReviewStatus status = entry.reviewStatus == FYReviewStatusKnown ? FYReviewStatusLearning : FYReviewStatusKnown;
    [receiver.learningStore updateReviewStatus:status forVocabulary:entry.vocabularyID completion:^(NSError *e) {
        if (e) { [receiver setReviewPromptText:[NSString stringWithFormat:@"操作失败：%@", e.localizedDescription]]; return; }
        [receiver refreshVocabularyList];
    }];
}

- (void)removeWordWithReceiver:(id<FYCollectionCardSource>)receiver word:(FYVocabularyEntry *(^)(void))word {
    FYVocabularyEntry *entry = word();
    if (!entry) { return; }
    [receiver.learningStore deleteVocabulary:entry.vocabularyID completion:^(NSError *e) {
        if (e) { [receiver setReviewPromptText:[NSString stringWithFormat:@"操作失败：%@", e.localizedDescription]]; return; }
        [receiver refreshVocabularyList];
    }];
}

@end
