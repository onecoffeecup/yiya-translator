#import "FYLearningSentenceWorkflow.h"
#import "FYLearningWorkflowUtilities.h"
static NSString *FYDialogueBodyExcludingLabels(NSString *source, NSSet<NSString *> *keys) {
    NSArray<NSString *> *lines=[source componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSUInteger removed=0;
    // Each confirmed label can explain one prefix row, not a repeated name
    // spoken as the first body line (e.g. 青木 / 青木 / そう呼んでください。).
    NSMutableSet<NSString *> *remaining=[keys mutableCopy];
    while (removed<lines.count) {
        NSString *key=FYDialogueComparisonKey(lines[removed]);
        if (![remaining containsObject:key]) { break; }
        [remaining removeObject:key];removed++;
    }
    return removed && removed<lines.count
        ? [[lines subarrayWithRange:NSMakeRange(removed,lines.count-removed)] componentsJoinedByString:@"\n"] : nil;
}


@implementation FYLearningSentenceWorkflow
- (instancetype)init { if ((self=[super init])) { _learningEnabled=YES; _japaneseMode=YES; _currentSourceText=@""; _lastItemTexts=@[]; _lastItemIdentities=@[]; } return self; }

- (BOOL)hasNewerSentenceWithReceiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    if (!receiver.latestSentenceID || !receiver.currentSentenceID) { return NO; }
    return ![receiver.latestSentenceID isEqualToString:receiver.currentSentenceID];
}

- (void)ensureSessionWithReceiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    if (!receiver.sessionID) {
        receiver.sessionID = NSUUID.UUID.UUIDString;
    }
    [receiver.store ensureSessionWithID:receiver.sessionID displayName:@"" language:receiver.japaneseMode ? @"日文" : @"英文" completion:^(NSError *e) { if (e && receiver.persistenceErrorHandler) { receiver.persistenceErrorHandler(e); } }];
}

- (FYRequestIdentity *)recordSingleText:(NSString *)rawText kind:(FYSentenceKind)kind receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    NSString *text = FYTrim(rawText);
    if (text.length == 0) {
        return [FYRequestIdentity identityWithSentenceID:@"" version:0 requestID:@"" sourceText:@"" translation:nil];
    }
    [receiver ensureSession];
    NSString *dialogueKey = kind == FYSentenceKindDialogue ? FYDialogueComparisonKey(text) : nil;
    if (kind == FYSentenceKindDialogue && dialogueKey.length > 0 &&
        receiver.lastDialogueIdentity && ([receiver.lastDialogueKey isEqualToString:dialogueKey] ||
        FYDialogueIsIncompleteFrame(text, receiver.lastDialogueIdentity.sourceText) ||
        FYDialogueIsFragmentOfDialogue(text, receiver.lastDialogueIdentity.sourceText))) {
        return receiver.lastDialogueIdentity;
    }
    if (kind != FYSentenceKindDialogue && [receiver.lastText isEqualToString:text] && receiver.lastKind == kind && receiver.lastIdentity) {
        return receiver.lastIdentity;
    }
    NSString *sentenceID = NSUUID.UUID.UUIDString;
    FYRequestIdentity *identity = [FYRequestIdentity identityWithSentenceID:sentenceID
                                                                    version:1
                                                                  requestID:NSUUID.UUID.UUIDString
                                                                 sourceText:text
                                                                translation:nil];
    [receiver.store insertSentenceWithID:sentenceID sessionID:receiver.sessionID kind:kind originalText:text occurredAt:NSDate.date completion:^(NSError *e) { if (e && receiver.persistenceErrorHandler) { receiver.persistenceErrorHandler(e); } }];
    receiver.lastText = text;
    receiver.lastKind = kind;
    receiver.lastIdentity = identity;
    if (kind == FYSentenceKindDialogue) {
        receiver.lastDialogueKey = dialogueKey;
        receiver.lastDialogueIdentity = identity;
        receiver.lastDialogueExcludedSpeakerKeys = nil;
        receiver.recordsSinceLastDialogue = 0;
    } else if (kind != FYSentenceKindOption) {
        // Options belong to the same dialogue frame; a UI/snapshot starts a
        // different context and must not suppress a later genuine recurrence.
        receiver.lastDialogueKey = nil;
        receiver.lastDialogueIdentity = nil;
    } else if (++receiver.recordsSinceLastDialogue >= FYRecentSentenceLimit) {
        // Enough new options can evict an unpinned dialogue from history.
        // Never reuse an identity whose sentence may have been pruned.
        receiver.lastDialogueKey = nil;
        receiver.lastDialogueIdentity = nil;
    }
    receiver.lastItemTexts = @[];
    receiver.lastItemIdentities = @[];
    return identity;
}

- (FYRequestIdentity *)recordDialogueText:(NSString *)text excludingSpeakerLabels:(NSArray<NSString *> *)labels receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    FYRequestIdentity *previous=receiver.lastDialogueIdentity;
    NSSet<NSString *> *previousKeys=receiver.lastDialogueExcludedSpeakerKeys;
    // A transient pixel miss must not reintroduce a label already confirmed
    // for this unchanged body. A new spoken body does not inherit this rule.
    NSString *incomingBody=previous ? FYDialogueBodyExcludingLabels(text,previousKeys) : nil;
    if (incomingBody && [FYDialogueComparisonKey(incomingBody) isEqualToString:FYDialogueComparisonKey(previous.sourceText)]) {
        text=incomingBody;
    }
    NSMutableSet<NSString *> *excludedKeys=[NSMutableSet new];
    for (NSString *label in labels) {
        NSString *key=FYDialogueComparisonKey(label);
        if (key.length) [excludedKeys addObject:key];
    }
    if (receiver.learningEnabled && receiver.japaneseMode && labels.count && receiver.lastDialogueIdentity) {
        NSString *oldBody=FYDialogueBodyExcludingLabels(receiver.lastDialogueIdentity.sourceText,excludedKeys);
        if (oldBody) {
            if ([FYDialogueComparisonKey(oldBody) isEqualToString:FYDialogueComparisonKey(text)]) {
                // Removing a confirmed label is a correction, not a clipped
                // frame. Start a clean identity without rewriting old history.
                receiver.lastDialogueIdentity=nil;
                receiver.lastDialogueKey=nil;
            }
        }
    }
    FYRequestIdentity *identity=[receiver recordText:text kind:FYSentenceKindDialogue];
    if (identity) {
        if (identity==previous && previousKeys.count) [excludedKeys unionSet:previousKeys];
        receiver.lastDialogueExcludedSpeakerKeys=excludedKeys;
        if (excludedKeys.count &&
            [FYDialogueComparisonKey(identity.sourceText) isEqualToString:FYDialogueComparisonKey(text)] &&
            (identity != previous || ![excludedKeys isEqualToSet:previousKeys])) {
            [receiver.store recordExcludedSpeakerLabels:excludedKeys.allObjects forIdentity:identity completion:^(NSError *error) {
                if (error && receiver.persistenceErrorHandler) receiver.persistenceErrorHandler(error);
            }];
        }
    }
    return identity;
}

- (FYRequestIdentity *)recordText:(NSString *)text kind:(FYSentenceKind)kind receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    if (!receiver.learningEnabled || !receiver.japaneseMode) { return nil; }
    FYRequestIdentity *identity = [receiver recordSingleText:text kind:kind];
    if (identity.sentenceID.length == 0) { return nil; }
    receiver.latestSentenceID = identity.sentenceID;
    if (!receiver.isPinned && ![receiver.currentSentenceID isEqualToString:identity.sentenceID]) {
        receiver.selectionGeneration += 1;
        receiver.currentSentenceID = identity.sentenceID;
        receiver.currentVersion = identity.version;
        receiver.currentSourceText = identity.sourceText;
        receiver.currentTranslation = identity.translation;
        [receiver invalidateAnalysis];
    }
    return identity;
}

- (NSArray<FYRequestIdentity *> *)recordItems:(NSArray<NSString *> *)texts kind:(FYSentenceKind)kind receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    if (!receiver.learningEnabled || !receiver.japaneseMode || texts.count == 0) { return @[]; }
    if (receiver.lastItemKind == kind && [texts isEqualToArray:receiver.lastItemTexts] && receiver.lastItemIdentities.count == texts.count) {
        return receiver.lastItemIdentities;
    }
    NSMutableArray<FYRequestIdentity *> *identities = [NSMutableArray arrayWithCapacity:texts.count];
    for (NSString *text in texts) {
        FYRequestIdentity *identity = [receiver recordSingleText:text kind:kind];
        [identities addObject:identity];
        if (identity.sentenceID.length > 0) {
            receiver.latestSentenceID = identity.sentenceID;
            if (!receiver.isPinned && ![receiver.currentSentenceID isEqualToString:identity.sentenceID]) {
                receiver.selectionGeneration += 1;
                receiver.currentSentenceID = identity.sentenceID;
                receiver.currentVersion = identity.version;
                receiver.currentSourceText = identity.sourceText;
                receiver.currentTranslation = identity.translation;
            }
        }
    }
    receiver.lastItemTexts = [texts copy];
    receiver.lastItemIdentities = [identities copy];
    receiver.lastItemKind = kind;
    if (!receiver.isPinned && receiver.currentSentenceID.length > 0) {
        [receiver invalidateAnalysis];
    }
    return identities;
}

- (void)setTranslation:(NSString *)translation forIdentity:(FYRequestIdentity *)identity receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    if (!identity || identity.sentenceID.length == 0) { return; }
    NSString *value = translation ?: @"";
    [receiver.store updateTranslation:value forSentence:identity.sentenceID version:identity.version completion:^(NSError *e) { if (e && receiver.persistenceErrorHandler) { receiver.persistenceErrorHandler(e); } }];
    if ([receiver.currentSentenceID isEqualToString:identity.sentenceID] && receiver.currentVersion == identity.version) {
        receiver.currentTranslation = value;
    }
}

- (BOOL)currentMatches:(NSString *)sentenceID version:(NSInteger)version receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    return [receiver.currentSentenceID isEqualToString:sentenceID] && receiver.currentVersion == version;
}

- (void)preserveHistorySentence:(NSString *)sentenceID receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    [receiver.store preserveSentenceForHistory:sentenceID completion:^(NSError *error) {
        if (error && receiver.persistenceErrorHandler) { receiver.persistenceErrorHandler(error); }
    }];
}

- (void)pinCurrentWithReceiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    if (receiver.currentSentenceID.length == 0 || receiver.currentSourceText.length == 0) { return; }
    receiver.selectionGeneration += 1;
    receiver.isPinned = YES;
    [receiver preserveHistorySentence:receiver.currentSentenceID];
}

- (void)followLatestWithCompletion:(void (^)(void))completion receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    NSInteger generation = ++receiver.selectionGeneration;
    NSString *targetID = receiver.latestSentenceID;
    receiver.isPinned = NO;
    [receiver preserveHistorySentence:nil];
    [receiver invalidateAnalysis];
    if (targetID.length > 0) {
        [receiver.store fetchSentence:targetID completion:^(FYSentenceRecord *record, NSError *error) {
            // 旧跟随回调不得覆盖后来（期间）的选择（历史/固定/新跟随）。
            if (generation == receiver.selectionGeneration && !receiver.isPinned && [targetID isEqualToString:receiver.latestSentenceID] && record) {
                NSString *translation = [receiver currentMatches:record.sentenceID version:record.latestVersion] ? (receiver.currentTranslation ?: record.latestTranslation) : record.latestTranslation;
                receiver.currentSentenceID = record.sentenceID;
                receiver.currentVersion = record.latestVersion;
                receiver.currentSourceText = record.latestText;
                receiver.currentTranslation = translation;
            }
            if (completion) { completion(); }
        }];
    } else if (completion) {
        completion();
    }
}

- (void)followLatestWithReceiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    [receiver followLatestWithCompletion:nil];
}

- (void)selectHistorySentence:(FYSentenceRecord *)record receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    if (!record) { return; }
    receiver.selectionGeneration += 1;
    receiver.isPinned = YES;
    [receiver invalidateAnalysis];
    receiver.currentSentenceID = record.sentenceID;
    [receiver preserveHistorySentence:record.sentenceID];
    receiver.currentVersion = record.latestVersion;
    receiver.currentSourceText = record.latestText;
    receiver.currentTranslation = record.latestTranslation;
}

- (void)selectSentenceID:(NSString *)sentenceID
                 version:(NSInteger)version
              sourceText:(NSString *)sourceText
             translation:(NSString *)translation receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    if (sentenceID.length == 0) { return; }
    receiver.selectionGeneration += 1;
    receiver.isPinned = YES;
    [receiver invalidateAnalysis];
    receiver.currentSentenceID = sentenceID;
    [receiver preserveHistorySentence:sentenceID];
    receiver.currentVersion = version;
    receiver.currentSourceText = sourceText;
    receiver.currentTranslation = translation;
}

- (void)correctCurrentSentenceText:(NSString *)newText completion:(void (^)(NSError *))completion receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    NSString *text = FYTrim(newText);
    NSString *sentenceID = receiver.currentSentenceID;
    NSInteger correctedVersion = receiver.currentVersion;
    if (sentenceID.length == 0 || text.length == 0) {
        if (completion) { completion([NSError errorWithDomain:@"FYLearningCoordinator" code:5 userInfo:@{NSLocalizedDescriptionKey: @"没有可修正的句子。"}]); }
        return;
    }
    if ([text isEqualToString:receiver.currentSourceText]) {
        if (completion) { completion(nil); }
        return;
    }
    [receiver.store appendVersionForSentence:sentenceID text:text translation:nil completion:^(NSInteger version, NSError *error) {
        if (error) {
            if (completion) { completion(error); }
            return;
        }
        if (version <= 0) {
            if (completion) { completion([NSError errorWithDomain:@"FYLearningCoordinator" code:6 userInfo:@{NSLocalizedDescriptionKey: @"保存修正失败。"}]); }
            return;
        }
        // 数据库写入已完成，但只在当前选择仍是修正前那一句时才更新界面状态，避免串到后来的句子上。
        if ([receiver.currentSentenceID isEqualToString:sentenceID] && receiver.currentVersion == correctedVersion) {
            receiver.currentVersion = version;
            receiver.currentSourceText = text;
            receiver.currentTranslation = nil;
            [receiver invalidateAnalysis];
        }
        if (completion) { completion(nil); }
    }];
}

- (void)correctCurrentSentenceText:(NSString *)newText receiver:(id<FYLearningSentenceWorkflowSource>)receiver {
    [receiver correctCurrentSentenceText:newText completion:nil];
}

@end
