#import "FYWordSelectionController.h"
#import "FYPresentationText.h"

@implementation FYWordSelectionController
- (void)toggleLearningPin:(id)sender source:(id<FYWordSelectionSource>)source {
    if (source.learningCoordinator.isPinned) { [source followLatestSentence:sender]; }
    else { [source pinLearningSentence:sender]; }
}

- (void)vocabularyFormChanged:(id)sender source:(id<FYWordSelectionSource>)source {
    source.vocabSelectionGeneration += 1;
    source.vocabCompletionFromAI = NO;
    [source setWordSelectionLabel:@"手动填写；原形、读音和释义均可留空。"];
}

- (void)freezeLearningSentenceForSelectionWithSource:(id<FYWordSelectionSource>)source {
    source.vocabSelectionGeneration += 1;
    source.referenceRequestGeneration += 1;
    source.referenceActiveWord = @"";
    if (source.displayedSentenceID.length == 0 || [source wordSelectionText].length == 0) { return; }
    [source syncCoordinatorToDisplayed];
    [source.learningCoordinator pinCurrent];
    [source wordHostRefreshLearningStatus];
}

- (void)selectWordAtCharacterIndex:(NSUInteger)characterIndex source:(id<FYWordSelectionSource>)source {
    NSString *text = [[source wordSelectionText] copy] ?: @"";
    NSString *sentenceID = source.displayedSentenceID;
    NSInteger version = source.displayedVersion;
    NSInteger generation = ++source.vocabSelectionGeneration;
    [source.japaneseTokenizer rangeForLocation:characterIndex inText:text completion:^(NSRange range) {
        if ([FYLearningCoordinator selectionRange:range appliesToText:text sentenceID:sentenceID version:version generation:generation
            currentText:[source wordSelectionText] currentSentenceID:source.displayedSentenceID
            currentVersion:source.displayedVersion currentGeneration:source.vocabSelectionGeneration]) {
            [source setWordSelectionRange:range];
        }
    }];
}

- (void)updateWordPickForSelectionWithSource:(id<FYWordSelectionSource>)source {
    if ([source wordSelectionTracking]) { return; }
    [source setWordLemma:@""];[source setWordReading:@""];[source setWordMeaning:@""];source.vocabCompletionFromAI=NO;
    NSString *selected = [source selectedLearningText];
    if (selected.length == 0) {
        [source setWordPickHidden:YES];
        return;
    }
    [source setWordPickHidden:NO];
    [source setWordSurfaceLabel:[NSString stringWithFormat:@"遇到的词形：%@", selected]];
}

- (void)closeWordPick:(id)sender source:(id<FYWordSelectionSource>)source {
    [source setWordPickHidden:YES];
    if ([source wordSelectionRange].length > 0) {
        [source setWordSelectionRange:NSMakeRange([source wordSelectionRange].location, 0)];
    }
}

- (void)pinLearningSentence:(id)sender source:(id<FYWordSelectionSource>)source {
    [source syncCoordinatorToDisplayed];
    [source.learningCoordinator pinCurrent];
    [source wordHostRefreshLearningStatus];
}

- (void)followLatestSentence:(id)sender source:(id<FYWordSelectionSource>)source {
    __weak id<FYWordSelectionSource> weakSelf = source;
    [source clearAnalysisDisplay];
    [source.learningCoordinator followLatestWithCompletion:^{
        [weakSelf wordHostRefreshLearningSource];
        [weakSelf wordHostRefreshLearningStatus];

    }];
}

- (NSString *)selectedLearningTextWithSource:(id<FYWordSelectionSource>)source {
    NSRange range = [source wordSelectionRange];
    if (range.location == NSNotFound || range.length == 0) { return @""; }
    NSString *text = [source wordSelectionText] ?: @"";
    if (NSMaxRange(range) > text.length) { return @""; }
    return [text substringWithRange:range];
}

- (void)bookmarkSelectedVocabulary:(id)sender source:(id<FYWordSelectionSource>)source {
    [source syncCoordinatorToDisplayed];
    NSString *selected = [source selectedLearningText];
    if (selected.length == 0) {
        [source setWordStatus:@"请先在原句上点击或拖选一个词/短语。"];
        return;
    }
    if (source.savingVocabulary) { return; }
    source.savingVocabulary = YES;
    FYVocabularyEntry *entry = [[FYVocabularyEntry alloc] init];
    entry.kind = FYVocabularyKindWord;
    entry.surface = selected;
    entry.lemma = Trim([source wordLemmaInput]);
    entry.reading = Trim([source wordReadingInput]);
    entry.meaning = Trim([source wordMeaningInput]);
    entry.completionSource = source.vocabCompletionFromAI ? FYCompletionSourceAI : FYCompletionSourceManual;
    entry.reviewStatus = FYReviewStatusNew;
    NSInteger saveGeneration = source.vocabSelectionGeneration;
    [source.learningCoordinator bookmarkVocabulary:entry selectedText:selected completion:^(FYVocabularyEntry *saved, BOOL wasDuplicate, NSError *error) {
        source.savingVocabulary = NO;
        if (saveGeneration != source.vocabSelectionGeneration) { [source refreshVocabularyList]; return; }
        if (error) { [source setWordStatus:error.localizedDescription]; return; }
        [source setWordStatus:wasDuplicate
            ? [NSString stringWithFormat:@"已有词条「%@」，已追加例句。", saved.surface]
            : [NSString stringWithFormat:@"已收藏「%@」。", saved.surface]];
        [source refreshVocabularyList];
    }];
}

- (void)completeSelectedVocabulary:(id)sender source:(id<FYWordSelectionSource>)source {
    [source syncCoordinatorToDisplayed];
    NSString *selected = [source selectedLearningText];
    if (selected.length == 0) {
        [source setWordStatus:@"请先选中一个词/短语。"];
        return;
    }
    source.vocabSelectionGeneration += 1;
    [source setWordStatus:@"正在补全读音与释义…"];
    NSString *requestedSelection = [selected copy];
    NSRange requestedRange = [source wordSelectionRange];
    NSInteger requestGeneration = source.vocabSelectionGeneration;
    NSString *requestSentenceID = source.learningCoordinator.currentSentenceID;
    NSInteger requestVersion = source.learningCoordinator.currentVersion;
    __weak id<FYWordSelectionSource> weakSelf = source;
    [source.learningCoordinator completeVocabulary:selected context:source.learningCoordinator.currentSourceText completion:^(FYVocabularyEntry *entry, NSError *error) {
        // 选区、代际或句子任一变化都视为旧请求，丢弃结果（仅比较词形无法区分同句多次出现）。
        if (![FYLearningCoordinator vocabularyCompletionBelongsToSelection:requestedRange currentRange:[weakSelf wordSelectionRange]
            requestGeneration:requestGeneration currentGeneration:weakSelf.vocabSelectionGeneration sentenceID:requestSentenceID version:requestVersion
            currentSentenceID:weakSelf.learningCoordinator.currentSentenceID currentVersion:weakSelf.learningCoordinator.currentVersion]) {
            return;
        }
        if (error) { [weakSelf setWordStatus:[NSString stringWithFormat:@"补全失败：%@", error.localizedDescription]]; return; }
        [weakSelf setWordLemma:entry.lemma ?: @""];
        [weakSelf setWordReading:entry.reading ?: @""];
        [weakSelf setWordMeaning:entry.meaning ?: @""];
        weakSelf.vocabCompletionFromAI = YES;
        [weakSelf setWordSelectionLabel:[NSString stringWithFormat:@"%@（AI 建议，可在下方修改后收藏）", requestedSelection]];
        [weakSelf setWordStatus:@"已给出 AI 建议，可修改后点「收藏所选」。"];
    }];
}

- (void)syncCoordinatorToDisplayedWithSource:(id<FYWordSelectionSource>)source {
    if (source.displayedSentenceID.length > 0 &&
        (![source.learningCoordinator.currentSentenceID isEqualToString:source.displayedSentenceID] ||
         source.learningCoordinator.currentVersion != source.displayedVersion)) {
        [source.learningCoordinator selectSentenceID:source.displayedSentenceID
                                          version:source.displayedVersion
                                       sourceText:source.displayedSourceText
                                      translation:source.displayedTranslation];
    }
}
@end
