#import "FYLearningCoordinator.h"

static NSString *FYTrim(NSString *value) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *FYTextHash(NSString *text) {
    // FNV-1a 64-bit，用于缓存键，不用于安全。
    uint64_t hash = 1469598103934665603ULL;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        hash ^= (uint64_t)c;
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)hash];
}

@interface FYLearningCoordinator ()
@property(nonatomic, strong) FYLearningStore *store;
@property(nonatomic, strong) FYLearningAnalyzer *analyzer;
@property(nonatomic, strong) FYJapaneseTokenizer *tokenizer;
@property(nonatomic, strong) FYGrammarCatalog *catalog;
@property(nonatomic, copy) NSString *sessionID;

@property(nonatomic, copy, nullable) NSString *lastText;
@property(nonatomic) FYSentenceKind lastKind;
@property(nonatomic, strong, nullable) FYRequestIdentity *lastIdentity;
@property(nonatomic, copy, nullable) NSString *lastDialogueKey;
@property(nonatomic, strong, nullable) FYRequestIdentity *lastDialogueIdentity;
@property(nonatomic) NSUInteger recordsSinceLastDialogue;
@property(nonatomic, copy) NSArray<NSString *> *lastItemTexts;
@property(nonatomic, copy) NSArray<FYRequestIdentity *> *lastItemIdentities;
@property(nonatomic) FYSentenceKind lastItemKind;

@property(nonatomic) BOOL isPinned;
@property(nonatomic, copy, nullable) NSString *currentSentenceID;
@property(nonatomic) NSInteger currentVersion;
@property(nonatomic, copy) NSString *currentSourceText;
@property(nonatomic, copy, nullable) NSString *currentTranslation;
@property(nonatomic, copy, nullable) NSString *latestSentenceID;
@property(nonatomic) NSInteger analysisGeneration;
@property(nonatomic) NSInteger selectionGeneration;
@property(nonatomic, strong) dispatch_queue_t vocabularyQueue;
@property(nonatomic, strong) NSMutableArray *vocabularyOperations;
@end

@implementation FYLearningCoordinator
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
                        if (FYDialogueTextsAreEquivalent(member.latestText, record.latestText)) { same = YES; break; }
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
                BOOL degraded = NO;
                for (FYSentenceRecord *other in group) {
                    if (other == candidate) { continue; }
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
+ (BOOL)vocabularyCompletionBelongsToSelection:(NSRange)requestedRange currentRange:(NSRange)currentRange
    requestGeneration:(NSInteger)requestGeneration currentGeneration:(NSInteger)currentGeneration
    sentenceID:(NSString *)sentenceID version:(NSInteger)version currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion {
    return NSEqualRanges(requestedRange, currentRange) &&
        [self requestSentenceID:sentenceID version:version generation:requestGeneration
            matchesSentenceID:currentSentenceID version:currentVersion generation:currentGeneration];
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

- (instancetype)initWithStore:(FYLearningStore *)store
                     analyzer:(FYLearningAnalyzer *)analyzer
                    tokenizer:(FYJapaneseTokenizer *)tokenizer
                      catalog:(FYGrammarCatalog *)catalog {
    self = [super init];
    if (self) {
        _store = store;
        _analyzer = analyzer;
        _tokenizer = tokenizer;
        _catalog = catalog;
        _learningEnabled = YES;
        _japaneseMode = YES;
        _currentSourceText = @"";
        _lastItemTexts = @[];
        _lastItemIdentities = @[];
        _vocabularyQueue = dispatch_queue_create("com.nanami.fuyi.vocabulary-saves", DISPATCH_QUEUE_SERIAL);
        _vocabularyOperations = [NSMutableArray array];
    }
    return self;
}

- (BOOL)hasNewerSentence {
    if (!self.latestSentenceID || !self.currentSentenceID) { return NO; }
    return ![self.latestSentenceID isEqualToString:self.currentSentenceID];
}

- (void)ensureSession {
    if (!self.sessionID) {
        self.sessionID = NSUUID.UUID.UUIDString;
    }
    [self.store ensureSessionWithID:self.sessionID displayName:@"" language:self.japaneseMode ? @"日文" : @"英文" completion:^(NSError *e) { if (e && self.persistenceErrorHandler) { self.persistenceErrorHandler(e); } }];
}

- (FYRequestIdentity *)recordSingleText:(NSString *)rawText kind:(FYSentenceKind)kind {
    NSString *text = FYTrim(rawText);
    if (text.length == 0) {
        return [FYRequestIdentity identityWithSentenceID:@"" version:0 requestID:@"" sourceText:@"" translation:nil];
    }
    [self ensureSession];
    NSString *dialogueKey = kind == FYSentenceKindDialogue ? FYDialogueComparisonKey(text) : nil;
    if (kind == FYSentenceKindDialogue && dialogueKey.length > 0 &&
        self.lastDialogueIdentity && ([self.lastDialogueKey isEqualToString:dialogueKey] ||
        FYDialogueIsIncompleteFrame(text, self.lastDialogueIdentity.sourceText) ||
        FYDialogueIsFragmentOfDialogue(text, self.lastDialogueIdentity.sourceText))) {
        return self.lastDialogueIdentity;
    }
    if (kind != FYSentenceKindDialogue && [self.lastText isEqualToString:text] && self.lastKind == kind && self.lastIdentity) {
        return self.lastIdentity;
    }
    NSString *sentenceID = NSUUID.UUID.UUIDString;
    FYRequestIdentity *identity = [FYRequestIdentity identityWithSentenceID:sentenceID
                                                                    version:1
                                                                  requestID:NSUUID.UUID.UUIDString
                                                                 sourceText:text
                                                                translation:nil];
    [self.store insertSentenceWithID:sentenceID sessionID:self.sessionID kind:kind originalText:text occurredAt:NSDate.date completion:^(NSError *e) { if (e && self.persistenceErrorHandler) { self.persistenceErrorHandler(e); } }];
    self.lastText = text;
    self.lastKind = kind;
    self.lastIdentity = identity;
    if (kind == FYSentenceKindDialogue) {
        self.lastDialogueKey = dialogueKey;
        self.lastDialogueIdentity = identity;
        self.recordsSinceLastDialogue = 0;
    } else if (kind != FYSentenceKindOption) {
        // Options belong to the same dialogue frame; a UI/snapshot starts a
        // different context and must not suppress a later genuine recurrence.
        self.lastDialogueKey = nil;
        self.lastDialogueIdentity = nil;
    } else if (++self.recordsSinceLastDialogue >= FYRecentSentenceLimit) {
        // Enough new options can evict an unpinned dialogue from history.
        // Never reuse an identity whose sentence may have been pruned.
        self.lastDialogueKey = nil;
        self.lastDialogueIdentity = nil;
    }
    self.lastItemTexts = @[];
    self.lastItemIdentities = @[];
    return identity;
}

- (FYRequestIdentity *)recordText:(NSString *)text kind:(FYSentenceKind)kind {
    if (!self.learningEnabled || !self.japaneseMode) { return nil; }
    FYRequestIdentity *identity = [self recordSingleText:text kind:kind];
    if (identity.sentenceID.length == 0) { return nil; }
    self.latestSentenceID = identity.sentenceID;
    if (!self.isPinned && ![self.currentSentenceID isEqualToString:identity.sentenceID]) {
        self.selectionGeneration += 1;
        self.currentSentenceID = identity.sentenceID;
        self.currentVersion = identity.version;
        self.currentSourceText = identity.sourceText;
        self.currentTranslation = identity.translation;
        [self invalidateAnalysis];
    }
    return identity;
}

- (NSArray<FYRequestIdentity *> *)recordItems:(NSArray<NSString *> *)texts kind:(FYSentenceKind)kind {
    if (!self.learningEnabled || !self.japaneseMode || texts.count == 0) { return @[]; }
    if (self.lastItemKind == kind && [texts isEqualToArray:self.lastItemTexts] && self.lastItemIdentities.count == texts.count) {
        return self.lastItemIdentities;
    }
    NSMutableArray<FYRequestIdentity *> *identities = [NSMutableArray arrayWithCapacity:texts.count];
    for (NSString *text in texts) {
        FYRequestIdentity *identity = [self recordSingleText:text kind:kind];
        [identities addObject:identity];
        if (identity.sentenceID.length > 0) {
            self.latestSentenceID = identity.sentenceID;
            if (!self.isPinned && ![self.currentSentenceID isEqualToString:identity.sentenceID]) {
                self.selectionGeneration += 1;
                self.currentSentenceID = identity.sentenceID;
                self.currentVersion = identity.version;
                self.currentSourceText = identity.sourceText;
                self.currentTranslation = identity.translation;
            }
        }
    }
    self.lastItemTexts = [texts copy];
    self.lastItemIdentities = [identities copy];
    self.lastItemKind = kind;
    if (!self.isPinned && self.currentSentenceID.length > 0) {
        [self invalidateAnalysis];
    }
    return identities;
}

- (void)setTranslation:(NSString *)translation forIdentity:(FYRequestIdentity *)identity {
    if (!identity || identity.sentenceID.length == 0) { return; }
    NSString *value = translation ?: @"";
    [self.store updateTranslation:value forSentence:identity.sentenceID version:identity.version completion:^(NSError *e) { if (e && self.persistenceErrorHandler) { self.persistenceErrorHandler(e); } }];
    if ([self.currentSentenceID isEqualToString:identity.sentenceID] && self.currentVersion == identity.version) {
        self.currentTranslation = value;
    }
}

- (void)invalidateAnalysis {
    self.analysisGeneration += 1;
    [self.analyzer cancelAll];
}

- (BOOL)currentMatches:(NSString *)sentenceID version:(NSInteger)version {
    return [self.currentSentenceID isEqualToString:sentenceID] && self.currentVersion == version;
}

- (void)preserveHistorySentence:(NSString *)sentenceID {
    [self.store preserveSentenceForHistory:sentenceID completion:^(NSError *error) {
        if (error && self.persistenceErrorHandler) { self.persistenceErrorHandler(error); }
    }];
}

- (void)pinCurrent {
    if (self.currentSentenceID.length == 0 || self.currentSourceText.length == 0) { return; }
    self.selectionGeneration += 1;
    self.isPinned = YES;
    [self preserveHistorySentence:self.currentSentenceID];
}

- (void)followLatestWithCompletion:(void (^)(void))completion {
    NSInteger generation = ++self.selectionGeneration;
    NSString *targetID = self.latestSentenceID;
    self.isPinned = NO;
    [self preserveHistorySentence:nil];
    [self invalidateAnalysis];
    if (targetID.length > 0) {
        [self.store fetchSentence:targetID completion:^(FYSentenceRecord *record, NSError *error) {
            // 旧跟随回调不得覆盖后来（期间）的选择（历史/固定/新跟随）。
            if (generation == self.selectionGeneration && !self.isPinned && [targetID isEqualToString:self.latestSentenceID] && record) {
                NSString *translation = [self currentMatches:record.sentenceID version:record.latestVersion] ? (self.currentTranslation ?: record.latestTranslation) : record.latestTranslation;
                self.currentSentenceID = record.sentenceID;
                self.currentVersion = record.latestVersion;
                self.currentSourceText = record.latestText;
                self.currentTranslation = translation;
            }
            if (completion) { completion(); }
        }];
    } else if (completion) {
        completion();
    }
}

- (void)followLatest {
    [self followLatestWithCompletion:nil];
}

- (void)selectHistorySentence:(FYSentenceRecord *)record {
    if (!record) { return; }
    self.selectionGeneration += 1;
    self.isPinned = YES;
    [self invalidateAnalysis];
    self.currentSentenceID = record.sentenceID;
    [self preserveHistorySentence:record.sentenceID];
    self.currentVersion = record.latestVersion;
    self.currentSourceText = record.latestText;
    self.currentTranslation = record.latestTranslation;
}

- (void)selectSentenceID:(NSString *)sentenceID
                 version:(NSInteger)version
              sourceText:(NSString *)sourceText
             translation:(NSString *)translation {
    if (sentenceID.length == 0) { return; }
    self.selectionGeneration += 1;
    self.isPinned = YES;
    [self invalidateAnalysis];
    self.currentSentenceID = sentenceID;
    [self preserveHistorySentence:sentenceID];
    self.currentVersion = version;
    self.currentSourceText = sourceText;
    self.currentTranslation = translation;
}

- (void)correctCurrentSentenceText:(NSString *)newText completion:(void (^)(NSError *))completion {
    NSString *text = FYTrim(newText);
    NSString *sentenceID = self.currentSentenceID;
    NSInteger correctedVersion = self.currentVersion;
    if (sentenceID.length == 0 || text.length == 0) {
        if (completion) { completion([NSError errorWithDomain:@"FYLearningCoordinator" code:5 userInfo:@{NSLocalizedDescriptionKey: @"没有可修正的句子。"}]); }
        return;
    }
    if ([text isEqualToString:self.currentSourceText]) {
        if (completion) { completion(nil); }
        return;
    }
    [self.store appendVersionForSentence:sentenceID text:text translation:nil completion:^(NSInteger version, NSError *error) {
        if (error) {
            if (completion) { completion(error); }
            return;
        }
        if (version <= 0) {
            if (completion) { completion([NSError errorWithDomain:@"FYLearningCoordinator" code:6 userInfo:@{NSLocalizedDescriptionKey: @"保存修正失败。"}]); }
            return;
        }
        // 数据库写入已完成，但只在当前选择仍是修正前那一句时才更新界面状态，避免串到后来的句子上。
        if ([self.currentSentenceID isEqualToString:sentenceID] && self.currentVersion == correctedVersion) {
            self.currentVersion = version;
            self.currentSourceText = text;
            self.currentTranslation = nil;
            [self invalidateAnalysis];
        }
        if (completion) { completion(nil); }
    }];
}

- (void)correctCurrentSentenceText:(NSString *)newText {
    [self correctCurrentSentenceText:newText completion:nil];
}

- (void)analyzeCurrent:(void (^)(FYAnalysisResult *, NSError *))completion {
    NSString *sentenceID = self.currentSentenceID;
    NSInteger version = self.currentVersion;
    NSString *text = self.currentSourceText;
    NSString *translation = self.currentTranslation;
    if (sentenceID.length == 0 || text.length == 0) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"FYLearningCoordinator" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"当前没有可分析的句子。"}]);
        }
        return;
    }
    NSInteger generation = ++self.analysisGeneration;
    NSString *hash = FYTextHash(text);
    NSInteger promptVersion = 3; // Invalidate caches without verified whole-sentence structure.
    NSInteger catalogVersion = self.catalog.catalogVersion;
    NSString *modelConfig = [NSString stringWithFormat:@"%@|%@|%ld|%ld",
                             self.analyzer.baseURL ?: @"", self.analyzer.model ?: @"",
                             (long)promptVersion, (long)catalogVersion];

    [self.store fetchAnalysisForSentence:sentenceID version:version completion:^(FYAnalysisResult *cached, NSString *model, NSError *error) {
        if (generation != self.analysisGeneration || ![self currentMatches:sentenceID version:version]) {
            completion(nil, [NSError errorWithDomain:@"FYLearningCoordinator" code:2 userInfo:@{NSLocalizedDescriptionKey: @"分析已被取消或句子已切换。"}]); return;
        }
        if (error) { completion(nil, error); return; }
        BOOL cacheHit = cached && (cached.status == FYAnalysisStatusSuccess || cached.status == FYAnalysisStatusNoResult) &&
                        [model isEqualToString:modelConfig];
        if (cacheHit) {
            if (generation != self.analysisGeneration || ![self currentMatches:sentenceID version:version]) {
                completion(nil, [NSError errorWithDomain:@"FYLearningCoordinator" code:2
                                                userInfo:@{NSLocalizedDescriptionKey: @"分析已被取消或句子已切换。"}]);
                return;
            }
            cached.sentenceID = sentenceID;
            cached.version = version;
            completion(cached, nil);
            return;
        }
        [self.analyzer analyzeSentence:text translation:translation completion:^(FYAnalysisResult *result, NSError *analyzeError) {
            if (generation != self.analysisGeneration || ![self currentMatches:sentenceID version:version]) {
                completion(nil, [NSError errorWithDomain:@"FYLearningCoordinator" code:2
                                                userInfo:@{NSLocalizedDescriptionKey: @"分析已被取消或句子已切换。"}]);
                return;
            }
            if (analyzeError) {
                completion(nil, analyzeError);
                return;
            }
            result.sentenceID = sentenceID;
            result.version = version;
            [self.store saveAnalysisResult:result sentenceID:sentenceID version:version textHash:hash
                             promptVersion:promptVersion catalogVersion:catalogVersion modelConfig:modelConfig completion:^(NSError *e) { if (e && self.persistenceErrorHandler) { self.persistenceErrorHandler(e); } }];
            completion(result, nil);
        }];
    }];
}

- (void)completeVocabulary:(NSString *)surface
                   context:(NSString *)context
                completion:(void (^)(FYVocabularyEntry *, NSError *))completion {
    [self.analyzer completeVocabulary:surface context:context completion:completion];
}

- (void)bookmarkVocabulary:(FYVocabularyEntry *)entry selectedText:(NSString *)selectedText
                completion:(void (^)(FYVocabularyEntry *, BOOL, NSError *))completion {
    if (!entry || entry.surface.length == 0) {
        if (completion) { completion(nil, NO, [NSError errorWithDomain:@"FYLearningCoordinator" code:3 userInfo:@{NSLocalizedDescriptionKey: @"词条内容为空。"}]); }
        return;
    }
    // Capture provenance before any asynchronous queue or database work.
    NSString *sentenceID = self.currentSentenceID;
    NSInteger version = self.currentVersion;
    NSString *sourceText = self.currentSourceText;
    NSString *translation = self.currentTranslation;
    void (^operation)(void (^)(void)) = ^(void (^finished)(void)) {
        [self.store fetchVocabularyListWithCompletion:^(NSArray<FYVocabularyEntry *> *existing, NSError *error) {
            if (error) { if (completion) { completion(nil, NO, error); } finished(); return; }
            FYVocabularyEntry *duplicate = [self findDuplicateOf:entry in:existing];
            FYVocabularyEntry *saved = duplicate ?: entry;
            if (duplicate) { [self mergeCompletionInto:duplicate from:entry]; }
            else { saved.vocabularyID = NSUUID.UUID.UUIDString; saved.bookmarkedAt = NSDate.date; }
            FYVocabularyExample *example = nil;
            if (sentenceID.length) {
                example = [FYVocabularyExample new]; example.vocabularyID = saved.vocabularyID;
                example.sentenceID = sentenceID; example.version = version;
                example.sourceTextSnapshot = sourceText; example.translationSnapshot = translation;
                example.selectedRangeText = selectedText ?: @"";
            }
            [self.store saveVocabulary:saved withExample:example completion:^(NSError *writeError) {
                if (completion) { completion(writeError ? nil : saved, duplicate != nil, writeError); }
                finished();
            }];
        }];
    };
    dispatch_async(self.vocabularyQueue, ^{
        [self.vocabularyOperations addObject:[operation copy]];
        if (self.vocabularyOperations.count == 1) { [self startNextVocabularySave]; }
    });
}

- (void)startNextVocabularySave {
    if (!self.vocabularyOperations.count) { return; }
    void (^operation)(void (^)(void)) = self.vocabularyOperations.firstObject;
    operation(^{
        dispatch_async(self.vocabularyQueue, ^{
            [self.vocabularyOperations removeObjectAtIndex:0];
            [self startNextVocabularySave];
        });
    });
}

- (FYVocabularyEntry *)findDuplicateOf:(FYVocabularyEntry *)entry in:(NSArray<FYVocabularyEntry *> *)existing {
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
- (BOOL)mergeCompletionInto:(FYVocabularyEntry *)existing from:(FYVocabularyEntry *)incoming {
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
                        completion:(void (^)(NSError *))completion {
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
    [self.store attachExample:example completion:completion];
}

- (void)bookmarkGrammar:(FYGrammarItem *)item completion:(void (^)(NSError *))completion {
    if (!item || item.name.length == 0) {
        if (completion) {
            completion([NSError errorWithDomain:@"FYLearningCoordinator" code:4
                                       userInfo:@{NSLocalizedDescriptionKey: @"语法为空。"}]);
        }
        return;
    }
    FYGrammarBookmark *bookmark = [[FYGrammarBookmark alloc] init];
    bookmark.bookmarkID = FYTextHash([NSString stringWithFormat:@"%@|%ld|%@|%@", self.currentSentenceID ?: @"", (long)self.currentVersion, item.catalogID ?: @"", item.name]);
    bookmark.catalogID = item.catalogID;
    bookmark.name = item.name;
    bookmark.sentenceID = self.currentSentenceID ?: @"";
    bookmark.version = self.currentVersion;
    bookmark.sourceTextSnapshot = self.currentSourceText;
    bookmark.translationSnapshot = self.currentTranslation;
    bookmark.bookmarkedAt = NSDate.date;
    [self.store fetchGrammarBookmarksWithCompletion:^(NSArray<FYGrammarBookmark *> *bookmarks, NSError *error) {
        if (error) { if (completion) { completion(error); } return; }
        for (FYGrammarBookmark *existing in bookmarks) {
            if ([existing.name isEqualToString:bookmark.name] && [existing.sentenceID isEqualToString:bookmark.sentenceID] && existing.version == bookmark.version) {
                if (completion) { completion(nil); } return;
            }
        }
        [self.store addGrammarBookmark:bookmark completion:completion];
    }];
}

@end
