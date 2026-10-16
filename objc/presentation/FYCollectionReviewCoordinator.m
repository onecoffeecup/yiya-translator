#import "FYCollectionReviewCoordinator.h"

@implementation FYCollectionReviewCoordinator
- (void)refreshVocabularyWithReceiver:(id<FYCollectionReviewSource>)receiver {
    [receiver.learningStore fetchVocabularyListWithCompletion:^(NSArray<FYVocabularyEntry *> *entries, NSError *error) {
        if (error) {
            [receiver setVocabularyEmptyHidden:NO];
            [receiver setVocabularyListHidden:NO];
            [receiver setVocabularyListText:[NSString stringWithFormat:@"加载收藏失败：%@", error.localizedDescription]];
            return;
        }
        [receiver setVocabularyEmptyHidden:entries.count > 0];
        receiver.reviewList = entries ?: @[];
        [receiver updateLearningCollectionSummary];
        if (receiver.reviewingEntry) {
            FYVocabularyEntry *current = nil;
            for (FYVocabularyEntry *entry in receiver.reviewList) { if ([entry.vocabularyID isEqualToString:receiver.reviewingEntry.vocabularyID]) { current = entry; break; } }
            receiver.reviewingEntry = current;
            if (!current) {
                [receiver setReviewWordHidden:YES]; [receiver setReviewMeaningHidden:YES];
                [receiver setReviewWordText:@""]; [receiver setReviewMeaningText:@""];
                [receiver setReviewPromptText:@"这个词已取消收藏，请点「下一个词」。"];
            }
        }
        if (receiver.reviewIndex >= receiver.reviewList.count) { receiver.reviewIndex = 0; }
        [receiver rebuildWordCards];
        if (entries.count == 0) {
            [receiver setVocabularyListText:@"还没有收藏的词语。\n回到实时翻译页，点击或拖选日文原句中的词语即可收藏。"];
            [receiver setVocabularyListHidden:NO];
            receiver.reviewIndex = 0;
            receiver.reviewingEntry = nil;
            [receiver setReviewWordText:@""];
            [receiver setReviewMeaningText:@""];
        } else {
            [receiver setVocabularyListText:@""];
            [receiver setVocabularyListHidden:YES];
        }
        [receiver refreshGrammarBookmarks:nil];
    }];
}

- (void)nextWordWithReceiver:(id<FYCollectionReviewSource>)receiver {
    if (!receiver.reviewList) {
        // 首次尚未加载完成：先触发加载，等数据返回后再点一次。
        [receiver setReviewPromptText:@"正在加载收藏…"];
        [receiver refreshVocabularyList];
        return;
    }
    if (receiver.reviewList.count == 0) {
        [receiver setReviewPromptText:@"没有可复习的词条"];
        return;
    }
    NSInteger nextIndex = receiver.reviewIndex;
    receiver.reviewingEntry = [FYLearningCoordinator nextReviewVocabularyInList:receiver.reviewList index:receiver.reviewIndex nextIndex:&nextIndex];
    receiver.reviewIndex = nextIndex;
    [receiver setReviewWordHidden:NO];
    [receiver setReviewMeaningHidden:YES];
    [receiver setReviewWordText:receiver.reviewingEntry.surface];
    [receiver setReviewMeaningText:@""];
    [receiver setReviewPromptText:@"先回忆含义，再点「揭晓释义」。"];
}

- (void)revealMeaningWithReceiver:(id<FYCollectionReviewSource>)receiver {
    if (!receiver.reviewingEntry) { [receiver setReviewPromptText:@"请先点「下一个词」。"]; return; }
    [receiver setReviewMeaningHidden:NO];
    NSString *reading = receiver.reviewingEntry.reading.length > 0 ? [NSString stringWithFormat:@"（%@）", receiver.reviewingEntry.reading] : @"";
    [receiver setReviewMeaningText:[NSString stringWithFormat:@"%@ %@", reading, receiver.reviewingEntry.meaning ?: @"（暂无释义）"]];
}

- (void)markKnownWithReceiver:(id<FYCollectionReviewSource>)receiver {
    [receiver setReviewStatus:FYReviewStatusKnown];
}

- (void)markLearningWithReceiver:(id<FYCollectionReviewSource>)receiver {
    [receiver setReviewStatus:FYReviewStatusLearning];
}

- (void)setStatus:(FYReviewStatus)status receiver:(id<FYCollectionReviewSource>)receiver {
    if (!receiver.reviewingEntry) { [receiver setReviewPromptText:@"请先点「下一个词」。"]; return; }
    [receiver.learningStore updateReviewStatus:status forVocabulary:receiver.reviewingEntry.vocabularyID completion:^(NSError *e) {
        if (e) { [receiver setReviewPromptText:[NSString stringWithFormat:@"标记失败：%@", e.localizedDescription]]; return; }
        [receiver refreshVocabularyList];
        [receiver setReviewPromptText:status == FYReviewStatusKnown ? @"已标记「记住了」" : @"已标记「还不熟」"];
    }];
}

- (void)removeWordWithReceiver:(id<FYCollectionReviewSource>)receiver {
    if (!receiver.reviewingEntry) { [receiver setReviewPromptText:@"请先点「下一个词」。"]; return; }
    NSString *vocabularyID = receiver.reviewingEntry.vocabularyID;
    __weak typeof(receiver) weakSelf = receiver;
    [receiver.learningStore deleteVocabulary:vocabularyID completion:^(NSError *error) {
        if (error) {
            [weakSelf setReviewPromptText:[NSString stringWithFormat:@"取消收藏失败：%@", error.localizedDescription]];
            return;
        }
        [weakSelf setReviewWordText:@""];
        [weakSelf setReviewMeaningText:@""];
        weakSelf.reviewingEntry = nil;
        [weakSelf refreshVocabularyList];
    }];
}

@end
