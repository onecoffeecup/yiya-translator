#import "FYLearningCoordinator.h"
#import "FYLearningSentenceWorkflow.h"
#import "FYLearningAnalysisWorkflow.h"
#import "FYLearningCollectionWorkflow.h"
#import "FYLearningProjection.h"

@interface FYLearningCoordinator ()
@property(nonatomic, strong) FYLearningStore *store;
@property(nonatomic, strong) FYLearningAnalyzer *analyzer;
@property(nonatomic, strong) FYLearningAnalyzer *reviewAnalyzer;
@property(nonatomic, strong) FYJapaneseTokenizer *tokenizer;
@property(nonatomic, strong) FYGrammarCatalog *catalog;
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic, copy, nullable) NSString *lastText;
@property(nonatomic) FYSentenceKind lastKind;
@property(nonatomic, strong, nullable) FYRequestIdentity *lastIdentity;
@property(nonatomic, copy, nullable) NSString *lastDialogueKey;
@property(nonatomic, strong, nullable) FYRequestIdentity *lastDialogueIdentity;
@property(nonatomic, copy, nullable) NSSet<NSString *> *lastDialogueExcludedSpeakerKeys;
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
@property(nonatomic, strong) FYLearningSentenceWorkflow *sentenceWorkflow;
@property(nonatomic, strong) FYLearningAnalysisWorkflow *analysisWorkflow;
@property(nonatomic, strong) FYLearningCollectionWorkflow *collectionWorkflow;
@end

@implementation FYLearningCoordinator
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
        _sentenceWorkflow = [FYLearningSentenceWorkflow new];
        _analysisWorkflow = [FYLearningAnalysisWorkflow new];
        _collectionWorkflow = [FYLearningCollectionWorkflow new];
    }
    return self;
}

- (BOOL)hasNewerSentence { return [self.sentenceWorkflow hasNewerSentenceWithReceiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (void)ensureSession { [self.sentenceWorkflow ensureSessionWithReceiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (FYRequestIdentity *)recordSingleText:(NSString *)rawText kind:(FYSentenceKind)kind { return [self.sentenceWorkflow recordSingleText:rawText kind:kind receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (FYRequestIdentity *)recordDialogueText:(NSString *)text excludingSpeakerLabels:(NSArray<NSString *> *)labels { return [self.sentenceWorkflow recordDialogueText:text excludingSpeakerLabels:labels receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (FYRequestIdentity *)recordText:(NSString *)text kind:(FYSentenceKind)kind { return [self.sentenceWorkflow recordText:text kind:kind receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (NSArray<FYRequestIdentity *> *)recordItems:(NSArray<NSString *> *)texts kind:(FYSentenceKind)kind { return [self.sentenceWorkflow recordItems:texts kind:kind receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (void)setTranslation:(NSString *)translation forIdentity:(FYRequestIdentity *)identity { [self.sentenceWorkflow setTranslation:translation forIdentity:identity receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (BOOL)currentMatches:(NSString *)sentenceID version:(NSInteger)version { return [self.sentenceWorkflow currentMatches:sentenceID version:version receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (void)preserveHistorySentence:(NSString *)sentenceID { [self.sentenceWorkflow preserveHistorySentence:sentenceID receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (void)pinCurrent { [self.sentenceWorkflow pinCurrentWithReceiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (void)followLatestWithCompletion:(void (^)(void))completion { [self.sentenceWorkflow followLatestWithCompletion:completion receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (void)followLatest { [self.sentenceWorkflow followLatestWithReceiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (void)selectHistorySentence:(FYSentenceRecord *)record { [self.sentenceWorkflow selectHistorySentence:record receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (void)selectSentenceID:(NSString *)sentenceID
                 version:(NSInteger)version
              sourceText:(NSString *)sourceText
             translation:(NSString *)translation { [self.sentenceWorkflow selectSentenceID:sentenceID version:version sourceText:sourceText translation:translation receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (void)correctCurrentSentenceText:(NSString *)newText completion:(void (^)(NSError *))completion { [self.sentenceWorkflow correctCurrentSentenceText:newText completion:completion receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (void)correctCurrentSentenceText:(NSString *)newText { [self.sentenceWorkflow correctCurrentSentenceText:newText receiver:(id<FYLearningSentenceWorkflowSource>)self]; }

- (BOOL)learningEnabled { return self.sentenceWorkflow.learningEnabled; }
- (void)setLearningEnabled:(BOOL)value { self.sentenceWorkflow.learningEnabled=value; }
- (BOOL)japaneseMode { return self.sentenceWorkflow.japaneseMode; }
- (void)setJapaneseMode:(BOOL)value { self.sentenceWorkflow.japaneseMode=value; }
- (NSString *)sessionID { return self.sentenceWorkflow.sessionID; }
- (void)setSessionID:(NSString *)value { self.sentenceWorkflow.sessionID=value; }
- (NSString *)lastText { return self.sentenceWorkflow.lastText; }
- (void)setLastText:(NSString *)value { self.sentenceWorkflow.lastText=value; }
- (FYSentenceKind)lastKind { return self.sentenceWorkflow.lastKind; }
- (void)setLastKind:(FYSentenceKind)value { self.sentenceWorkflow.lastKind=value; }
- (FYRequestIdentity *)lastIdentity { return self.sentenceWorkflow.lastIdentity; }
- (void)setLastIdentity:(FYRequestIdentity *)value { self.sentenceWorkflow.lastIdentity=value; }
- (NSString *)lastDialogueKey { return self.sentenceWorkflow.lastDialogueKey; }
- (void)setLastDialogueKey:(NSString *)value { self.sentenceWorkflow.lastDialogueKey=value; }
- (FYRequestIdentity *)lastDialogueIdentity { return self.sentenceWorkflow.lastDialogueIdentity; }
- (void)setLastDialogueIdentity:(FYRequestIdentity *)value { self.sentenceWorkflow.lastDialogueIdentity=value; }
- (NSSet<NSString *> *)lastDialogueExcludedSpeakerKeys { return self.sentenceWorkflow.lastDialogueExcludedSpeakerKeys; }
- (void)setLastDialogueExcludedSpeakerKeys:(NSSet<NSString *> *)value { self.sentenceWorkflow.lastDialogueExcludedSpeakerKeys=value; }
- (NSUInteger)recordsSinceLastDialogue { return self.sentenceWorkflow.recordsSinceLastDialogue; }
- (void)setRecordsSinceLastDialogue:(NSUInteger)value { self.sentenceWorkflow.recordsSinceLastDialogue=value; }
- (NSArray<NSString *> *)lastItemTexts { return self.sentenceWorkflow.lastItemTexts; }
- (void)setLastItemTexts:(NSArray<NSString *> *)value { self.sentenceWorkflow.lastItemTexts=value; }
- (NSArray<FYRequestIdentity *> *)lastItemIdentities { return self.sentenceWorkflow.lastItemIdentities; }
- (void)setLastItemIdentities:(NSArray<FYRequestIdentity *> *)value { self.sentenceWorkflow.lastItemIdentities=value; }
- (FYSentenceKind)lastItemKind { return self.sentenceWorkflow.lastItemKind; }
- (void)setLastItemKind:(FYSentenceKind)value { self.sentenceWorkflow.lastItemKind=value; }
- (BOOL)isPinned { return self.sentenceWorkflow.isPinned; }
- (void)setIsPinned:(BOOL)value { self.sentenceWorkflow.isPinned=value; }
- (NSString *)currentSentenceID { return self.sentenceWorkflow.currentSentenceID; }
- (void)setCurrentSentenceID:(NSString *)value { self.sentenceWorkflow.currentSentenceID=value; }
- (NSInteger)currentVersion { return self.sentenceWorkflow.currentVersion; }
- (void)setCurrentVersion:(NSInteger)value { self.sentenceWorkflow.currentVersion=value; }
- (NSString *)currentSourceText { return self.sentenceWorkflow.currentSourceText; }
- (void)setCurrentSourceText:(NSString *)value { self.sentenceWorkflow.currentSourceText=value; }
- (NSString *)currentTranslation { return self.sentenceWorkflow.currentTranslation; }
- (void)setCurrentTranslation:(NSString *)value { self.sentenceWorkflow.currentTranslation=value; }
- (NSString *)latestSentenceID { return self.sentenceWorkflow.latestSentenceID; }
- (void)setLatestSentenceID:(NSString *)value { self.sentenceWorkflow.latestSentenceID=value; }
- (NSInteger)selectionGeneration { return self.sentenceWorkflow.selectionGeneration; }
- (void)setSelectionGeneration:(NSInteger)value { self.sentenceWorkflow.selectionGeneration=value; }
- (void)invalidateAnalysis { [self.analysisWorkflow invalidateAnalysisWithReceiver:(id<FYLearningAnalysisWorkflowSource>)self]; }

- (void)analyzeCurrent:(void (^)(FYAnalysisResult *, NSError *))completion { [self.analysisWorkflow analyzeCurrent:completion receiver:(id<FYLearningAnalysisWorkflowSource>)self]; }

- (void)reviewCurrentAnalysis:(FYAnalysisResult *)existing
                  completion:(void (^)(FYAnalysisResult *, NSError *))completion { [self.analysisWorkflow reviewCurrentAnalysis:existing completion:completion receiver:(id<FYLearningAnalysisWorkflowSource>)self]; }

- (NSInteger)analysisGeneration { return self.analysisWorkflow.analysisGeneration; }
- (void)setAnalysisGeneration:(NSInteger)value { self.analysisWorkflow.analysisGeneration=value; }
- (FYLearningAnalyzer *)reviewAnalyzer { return self.analysisWorkflow.reviewAnalyzer; }
- (void)setReviewAnalyzer:(FYLearningAnalyzer *)value { self.analysisWorkflow.reviewAnalyzer=value; }
- (void)completeVocabulary:(NSString *)surface
                   context:(NSString *)context
                completion:(void (^)(FYVocabularyEntry *, NSError *))completion { [self.collectionWorkflow completeVocabulary:surface context:context completion:completion receiver:(id<FYLearningCollectionWorkflowSource>)self]; }

- (void)bookmarkVocabulary:(FYVocabularyEntry *)entry selectedText:(NSString *)selectedText
                completion:(void (^)(FYVocabularyEntry *, BOOL, NSError *))completion { [self.collectionWorkflow bookmarkVocabulary:entry selectedText:selectedText completion:completion receiver:(id<FYLearningCollectionWorkflowSource>)self]; }

- (void)startNextVocabularySave { [self.collectionWorkflow startNextVocabularySaveWithReceiver:(id<FYLearningCollectionWorkflowSource>)self]; }

- (FYVocabularyEntry *)findDuplicateOf:(FYVocabularyEntry *)entry in:(NSArray<FYVocabularyEntry *> *)existing { return [self.collectionWorkflow findDuplicateOf:entry in:existing receiver:(id<FYLearningCollectionWorkflowSource>)self]; }

- (BOOL)mergeCompletionInto:(FYVocabularyEntry *)existing from:(FYVocabularyEntry *)incoming { return [self.collectionWorkflow mergeCompletionInto:existing from:incoming receiver:(id<FYLearningCollectionWorkflowSource>)self]; }

- (void)attachExampleForVocabulary:(NSString *)vocabularyID
                      selectedText:(NSString *)selectedText
                        sentenceID:(NSString *)sentenceID
                           version:(NSInteger)version
                         sourceText:(NSString *)sourceText
                        translation:(NSString *)translation
                        completion:(void (^)(NSError *))completion { [self.collectionWorkflow attachExampleForVocabulary:vocabularyID selectedText:selectedText sentenceID:sentenceID version:version sourceText:sourceText translation:translation completion:completion receiver:(id<FYLearningCollectionWorkflowSource>)self]; }

- (void)bookmarkGrammar:(FYGrammarItem *)item completion:(void (^)(NSError *))completion { [self.collectionWorkflow bookmarkGrammar:item completion:completion receiver:(id<FYLearningCollectionWorkflowSource>)self]; }

- (dispatch_queue_t)vocabularyQueue { return self.collectionWorkflow.vocabularyQueue; }
- (void)setVocabularyQueue:(dispatch_queue_t)value { self.collectionWorkflow.vocabularyQueue=value; }
- (NSMutableArray *)vocabularyOperations { return self.collectionWorkflow.vocabularyOperations; }
- (void)setVocabularyOperations:(NSMutableArray *)value { self.collectionWorkflow.vocabularyOperations=value; }
+ (NSArray<FYSentenceRecord *> *)displayHistoryRecords:(NSArray<FYSentenceRecord *> *)records { return [FYLearningProjection displayHistoryRecords:records]; }

+ (NSString *)vocabularyExampleText:(NSArray<FYVocabularyExample *> *)examples requestedIndex:(NSUInteger)index { return [FYLearningProjection vocabularyExampleText:examples requestedIndex:index]; }

+ (FYSentenceRecord *)historyRecordInList:(NSArray<FYSentenceRecord *> *)records index:(NSInteger)index identifier:(NSString *)identifier { return [FYLearningProjection historyRecordInList:records index:index identifier:identifier]; }

+ (FYGrammarBookmark *)bookmarkInList:(NSArray<FYGrammarBookmark *> *)bookmarks grammarName:(NSString *)name sentenceID:(NSString *)sentenceID version:(NSInteger)version { return [FYLearningProjection bookmarkInList:bookmarks grammarName:name sentenceID:sentenceID version:version]; }

+ (FYGrammarItem *)grammarItemInList:(NSArray<FYGrammarItem *> *)items index:(NSInteger)index fallbackToFirst:(BOOL)fallback { return [FYLearningProjection grammarItemInList:items index:index fallbackToFirst:fallback]; }

+ (BOOL)analysisMatchesSentenceID:(NSString *)analysisSentenceID version:(NSInteger)analysisVersion currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion { return [FYLearningProjection analysisMatchesSentenceID:analysisSentenceID version:analysisVersion currentSentenceID:currentSentenceID currentVersion:currentVersion]; }

+ (NSArray<FYGrammarItem *> *)applicableGrammarItems:(NSArray<FYGrammarItem *> *)items text:(NSString *)text { return [FYLearningProjection applicableGrammarItems:items text:text]; }

+ (BOOL)followupBelongsToItem:(id)item requestedItem:(id)requestedItem requestGeneration:(NSInteger)requestGeneration currentGeneration:(NSInteger)currentGeneration
        sentenceID:(NSString *)sentenceID version:(NSInteger)version currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion { return [FYLearningProjection followupBelongsToItem:item requestedItem:requestedItem requestGeneration:requestGeneration currentGeneration:currentGeneration sentenceID:sentenceID version:version currentSentenceID:currentSentenceID currentVersion:currentVersion]; }

+ (BOOL)requestSentenceID:(NSString *)sentenceID version:(NSInteger)version generation:(NSInteger)generation
        matchesSentenceID:(NSString *)currentSentenceID version:(NSInteger)currentVersion generation:(NSInteger)currentGeneration { return [FYLearningProjection requestSentenceID:sentenceID version:version generation:generation matchesSentenceID:currentSentenceID version:currentVersion generation:currentGeneration]; }

+ (BOOL)selectionRange:(NSRange)range appliesToText:(NSString *)text sentenceID:(NSString *)sentenceID
              version:(NSInteger)version generation:(NSInteger)generation currentText:(NSString *)currentText
    currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion currentGeneration:(NSInteger)currentGeneration { return [FYLearningProjection selectionRange:range appliesToText:text sentenceID:sentenceID version:version generation:generation currentText:currentText currentSentenceID:currentSentenceID currentVersion:currentVersion currentGeneration:currentGeneration]; }

+ (FYVocabularyEntry *)nextReviewVocabularyInList:(NSArray<FYVocabularyEntry *> *)list index:(NSInteger)index nextIndex:(NSInteger *)nextIndex { return [FYLearningProjection nextReviewVocabularyInList:list index:index nextIndex:nextIndex]; }

+ (FYVocabularyEntry *)vocabularyInList:(NSArray<FYVocabularyEntry *> *)list identifier:(NSString *)identifier fallbackIndex:(NSInteger)index { return [FYLearningProjection vocabularyInList:list identifier:identifier fallbackIndex:index]; }

+ (BOOL)vocabularyCompletionBelongsToSelection:(NSRange)requestedRange currentRange:(NSRange)currentRange
    requestGeneration:(NSInteger)requestGeneration currentGeneration:(NSInteger)currentGeneration
    sentenceID:(NSString *)sentenceID version:(NSInteger)version currentSentenceID:(NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion {
    return NSEqualRanges(requestedRange, currentRange) &&
        [self requestSentenceID:sentenceID version:version generation:requestGeneration
            matchesSentenceID:currentSentenceID version:currentVersion generation:currentGeneration];
}

@end
