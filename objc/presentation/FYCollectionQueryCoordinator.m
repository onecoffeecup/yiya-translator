#import "FYCollectionQueryCoordinator.h"

@implementation FYCollectionQueryCoordinator
- (void)openHistoryWithReceiver:(id<FYCollectionQuerySource>)receiver tag:(NSInteger(^)(void))tag identifier:(NSString *(^)(void))identifier {
    FYSentenceRecord *record = [FYLearningCoordinator historyRecordInList:receiver.historyRecords index:tag() identifier:identifier()];
    if (!record) { return; }
    [receiver.learningCoordinator selectHistorySentence:record];
    [receiver refreshLearningSource];
    [receiver refreshLearningStatus];
    [receiver clearAnalysisDisplay];
    [receiver selectPageAtIndex:0];
    [receiver analyzeCurrentSentence:nil];
}

- (void)refreshHistoryWithReceiver:(id<FYCollectionQuerySource>)receiver {
    [receiver.learningStore fetchRecentSentencesWithLimit:FYRecentSentenceLimit completion:^(NSArray<FYSentenceRecord *> *records, NSError *error) {
        [receiver clearHistoryRows];
        if (error) { [receiver appendHistoryMessage:[NSString stringWithFormat:@"历史加载失败：%@", error.localizedDescription]]; return; }
        receiver.historyRecords = [FYLearningCoordinator displayHistoryRecords:records];
        if (receiver.historyRecords.count == 0) { [receiver appendHistoryMessage:@"暂无最近台词，翻译成功后会显示在这里。"]; return; }
        [receiver renderHistoryRows];
    }];
}

- (void)refreshGrammarWithReceiver:(id<FYCollectionQuerySource>)receiver {
    [receiver refreshSavedSentences];
    [receiver.learningStore fetchGrammarBookmarksWithCompletion:^(NSArray<FYGrammarBookmark *> *bookmarks, NSError *error) {
        if (error) { [receiver setGrammarBookmarkListText:[NSString stringWithFormat:@"语法收藏加载失败：%@", error.localizedDescription]]; return; }
        receiver.grammarBookmarks = bookmarks ?: @[];
        [receiver updateLearningCollectionSummary];
        [receiver updateQuickGrammarBookmark];
        [receiver clearSavedGrammarRows];
        [receiver setGrammarBookmarkListText:bookmarks.count ? @"" : @"暂无收藏。在实时翻译或查句弹窗中收藏语法。"];
        [receiver setGrammarBookmarkListHidden:bookmarks.count > 0];
        [receiver renderSavedGrammarRows];
        if ([receiver analysisMatchesCurrentSentence] && receiver.currentAnalysis.grammar.count) {
            [receiver setMainGrammarBookmarkTitle:[receiver bookmarkForCurrentGrammar] ? @"已收藏 · 取消收藏" : @"收藏此语法"];
        }
    }];
}

- (void)deleteGrammarWithReceiver:(id<FYCollectionQuerySource>)receiver identifier:(NSString *(^)(void))identifier {
    NSString *bookmarkID = identifier();
    if (!bookmarkID.length) { return; }
    [receiver.learningStore deleteGrammarBookmark:bookmarkID completion:^(NSError *error) {
        if (error) { [receiver setGrammarBookmarkListHidden:NO]; [receiver setGrammarBookmarkListText:[NSString stringWithFormat:@"取消收藏失败：%@", error.localizedDescription]]; return; }
        [receiver refreshGrammarBookmarks:nil];
    }];
}

- (void)refreshExampleChoicesWithReceiver:(id<FYCollectionQuerySource>)receiver {
    [receiver clearVocabularyExampleChoices];
    receiver.vocabularyExamplesList = receiver.reviewList ?: @[];
    if (receiver.vocabularyExamplesList.count == 0) {
        [receiver addVocabularyExampleChoice:@"暂无词条"];
        return;
    }
    for (FYVocabularyEntry *entry in receiver.vocabularyExamplesList) {
        [receiver addVocabularyExampleChoice:entry.surface];
    }
}

- (void)showExamplesWithReceiver:(id<FYCollectionQuerySource>)receiver {
    NSInteger index = [receiver selectedVocabularyExampleIndex];
    if (index < 0 || index >= (NSInteger)receiver.vocabularyExamplesList.count) { return; }
    NSString *vocabularyID = receiver.vocabularyExamplesList[index].vocabularyID;
    [receiver.learningStore fetchExamplesForVocabulary:vocabularyID completion:^(NSArray<FYVocabularyExample *> *examples, NSError *error) {
        if (error) {
            [receiver setVocabularyExamplesText:[NSString stringWithFormat:@"读取例句失败：%@", error.localizedDescription]];
            return;
        }
        if (examples.count == 0) {
            [receiver setVocabularyExamplesText:@"该词条暂无例句。"];
            return;
        }
        NSMutableString *text = [NSMutableString string];
        for (FYVocabularyExample *example in examples) {
            NSString *translation = example.translationSnapshot.length > 0 ? [NSString stringWithFormat:@"\n译文：%@", example.translationSnapshot] : @"";
            [text appendFormat:@"• %@%@\n", example.sourceTextSnapshot, translation];
        }
        [receiver setVocabularyExamplesText:text];
    }];
}

- (void)refreshSentencesWithReceiver:(id<FYCollectionQuerySource>)receiver {
    [receiver.learningStore fetchSentenceBookmarks:^(NSArray<FYRequestIdentity *> *identities,NSError *error){
        if(error){return;}
        receiver.savedSentences=identities;[receiver updateLearningCollectionSummary];[receiver clearSavedSentenceRows];
        [receiver renderSavedSentenceRows:identities];
        [receiver setQuickSentenceBookmarkTitle:[receiver quickSentenceIsBookmarked]?@"已收藏 · 取消":@"收藏这一句"];
        [receiver setQuickSentenceBookmarkEnabled:!receiver.sentenceBookmarkPending && receiver.quickSentenceID.length>0];
    }];
}

- (FYRequestIdentity *)sentenceWithReceiver:(id<FYCollectionQuerySource>)receiver identifier:(NSString *(^)(void))identifier {
    for(FYRequestIdentity *identity in receiver.savedSentences){if([identifier() isEqualToString:[NSString stringWithFormat:@"%@:%ld",identity.sentenceID,(long)identity.version]]){return identity;}}return nil;
}

- (void)openSentenceWithReceiver:(id<FYCollectionQuerySource>)receiver identity:(FYRequestIdentity *(^)(void))identityProvider {
    FYRequestIdentity *identity=identityProvider();if(!identity){return;}
    [receiver.learningCoordinator selectSentenceID:identity.sentenceID version:identity.version sourceText:identity.sourceText translation:identity.translation];
    [receiver refreshLearningSource];[receiver refreshLearningStatus];[receiver selectPageAtIndex:0];[receiver analyzeCurrentSentence:nil];
}

- (void)removeSentenceWithReceiver:(id<FYCollectionQuerySource>)receiver identity:(FYRequestIdentity *(^)(void))identityProvider disable:(void(^)(void))disable {
    FYRequestIdentity *identity=identityProvider();if(!identity || receiver.sentenceBookmarkPending){return;}
    receiver.sentenceBookmarkPending=YES;disable();
    [receiver.learningStore toggleSentenceBookmark:identity completion:^(BOOL saved,NSError *error){receiver.sentenceBookmarkPending=NO;if(error){[receiver setVocabularyStatusText:error.localizedDescription];}[receiver refreshSavedSentences];}];
}

- (void)loadCardExamplesForWord:(NSString *)vocabularyID generation:(NSInteger)generation receiver:(id<FYCollectionQuerySource>)receiver text:(void(^)(NSString *))text hidden:(void(^)(BOOL))hidden {
    [receiver.learningStore fetchExamplesForVocabulary:vocabularyID completion:^(NSArray<FYVocabularyExample *> *examples, NSError *e) {
            if (generation != receiver.wordCardsGeneration) { return; }
            if (e) { text([NSString stringWithFormat:@"例句加载失败：%@", e.localizedDescription]); return; }
            if (examples.count == 0) { text(@"没有关联例句。"); return; }
            hidden(examples.count < 2);
            text([FYLearningCoordinator vocabularyExampleText:examples requestedIndex:[receiver.wordExampleIndices[vocabularyID] unsignedIntegerValue]]);
    }];
}

@end
