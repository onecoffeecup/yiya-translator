#import <Foundation/Foundation.h>
#import "FYLearningModels.h"
#import "FYLearningStore.h"
#import "FYLearningAnalyzer.h"
#import "FYJapaneseTokenizer.h"
#import "FYGrammarCatalog.h"

NS_ASSUME_NONNULL_BEGIN

// 学习模块的编排层：固定/跟随状态、来源 ID 绑定、连续画面去重、异步结果归属。
@interface FYLearningCoordinator : NSObject
+ (NSArray<FYSentenceRecord *> *)displayHistoryRecords:(NSArray<FYSentenceRecord *> *)records;
+ (NSString *)vocabularyExampleText:(NSArray<FYVocabularyExample *> *)examples requestedIndex:(NSUInteger)index;
+ (nullable FYSentenceRecord *)historyRecordInList:(NSArray<FYSentenceRecord *> *)records index:(NSInteger)index identifier:(nullable NSString *)identifier;
+ (nullable FYGrammarBookmark *)bookmarkInList:(NSArray<FYGrammarBookmark *> *)bookmarks
    grammarName:(nullable NSString *)name sentenceID:(nullable NSString *)sentenceID version:(NSInteger)version;
+ (nullable FYGrammarItem *)grammarItemInList:(nullable NSArray<FYGrammarItem *> *)items index:(NSInteger)index fallbackToFirst:(BOOL)fallback;
+ (BOOL)analysisMatchesSentenceID:(nullable NSString *)analysisSentenceID version:(NSInteger)analysisVersion
    currentSentenceID:(nullable NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion;
+ (NSArray<FYGrammarItem *> *)applicableGrammarItems:(NSArray<FYGrammarItem *> *)items text:(NSString *)text;
+ (BOOL)vocabularyCompletionBelongsToSelection:(NSRange)requestedRange currentRange:(NSRange)currentRange
    requestGeneration:(NSInteger)requestGeneration currentGeneration:(NSInteger)currentGeneration
    sentenceID:(nullable NSString *)sentenceID version:(NSInteger)version currentSentenceID:(nullable NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion;
+ (BOOL)followupBelongsToItem:(id)item requestedItem:(id)requestedItem requestGeneration:(NSInteger)requestGeneration currentGeneration:(NSInteger)currentGeneration
        sentenceID:(nullable NSString *)sentenceID version:(NSInteger)version currentSentenceID:(nullable NSString *)currentSentenceID currentVersion:(NSInteger)currentVersion;
+ (BOOL)requestSentenceID:(nullable NSString *)sentenceID version:(NSInteger)version generation:(NSInteger)generation
        matchesSentenceID:(nullable NSString *)currentSentenceID version:(NSInteger)currentVersion generation:(NSInteger)currentGeneration;
+ (BOOL)selectionRange:(NSRange)range appliesToText:(NSString *)text
           sentenceID:(nullable NSString *)sentenceID version:(NSInteger)version generation:(NSInteger)generation
          currentText:(NSString *)currentText currentSentenceID:(nullable NSString *)currentSentenceID
       currentVersion:(NSInteger)currentVersion currentGeneration:(NSInteger)currentGeneration;
+ (nullable FYVocabularyEntry *)nextReviewVocabularyInList:(NSArray<FYVocabularyEntry *> *)list
                                                  index:(NSInteger)index nextIndex:(NSInteger *)nextIndex;
// Stable ID takes precedence; a stale ID must not fall back to a different index.
+ (nullable FYVocabularyEntry *)vocabularyInList:(NSArray<FYVocabularyEntry *> *)list
                                    identifier:(nullable NSString *)identifier fallbackIndex:(NSInteger)index;

- (instancetype)initWithStore:(FYLearningStore *)store
                     analyzer:(FYLearningAnalyzer *)analyzer
                    tokenizer:(FYJapaneseTokenizer *)tokenizer
                      catalog:(FYGrammarCatalog *)catalog;

@property(nonatomic, copy, nullable) void (^persistenceErrorHandler)(NSError *error);
@property(nonatomic) BOOL learningEnabled;   // 用户是否开启学习记录
@property(nonatomic) BOOL japaneseMode;      // 当前识别语言是否为日语

- (void)ensureSession;

// 记录一条原句（对白/快照），返回不可变身份供回填。连续相同画面复用已有记录。
- (FYRequestIdentity *)recordText:(NSString *)text kind:(FYSentenceKind)kind;

// 逐条记录（贴译/选项），返回与输入一一对应的身份数组。
- (NSArray<FYRequestIdentity *> *)recordItems:(NSArray<NSString *> *)texts kind:(FYSentenceKind)kind;

// 回填译文：只更新匹配的版本，旧版本不会覆盖新版本。
- (void)setTranslation:(NSString *)translation forIdentity:(FYRequestIdentity *)identity;

// 当前学习句状态（固定/跟随）。
@property(nonatomic, readonly) BOOL isPinned;
@property(nonatomic, readonly, nullable) NSString *currentSentenceID;
@property(nonatomic, readonly) NSInteger currentVersion;
@property(nonatomic, readonly) NSString *currentSourceText;
@property(nonatomic, readonly, nullable) NSString *currentTranslation;
@property(nonatomic, readonly, nullable) NSString *latestSentenceID;
@property(nonatomic, readonly) BOOL hasNewerSentence;
- (void)pinCurrent;
- (void)followLatest;   // 兼容旧调用（无 completion）
- (void)followLatestWithCompletion:(nullable void (^)(void))completion;
- (void)selectHistorySentence:(FYSentenceRecord *)record;
- (void)selectSentenceID:(NSString *)sentenceID
                 version:(NSInteger)version
              sourceText:(NSString *)sourceText
             translation:(nullable NSString *)translation;

// 修正当前句原文：追加新版本，旧译文/旧分析不再对应新文本（待更新）。
- (void)correctCurrentSentenceText:(NSString *)newText;   // 兼容旧调用（无 completion）
- (void)correctCurrentSentenceText:(NSString *)newText completion:(nullable void (^)(NSError *_Nullable error))completion;

// 分析当前句（带缓存与版本核对）。onRequestStarted 在主线程调用，供 UI 置忙。
- (void)analyzeCurrent:(void (^)(FYAnalysisResult *_Nullable result, NSError *_Nullable error))completion;

// 词条补全与收藏。
- (void)completeVocabulary:(NSString *)surface
                   context:(NSString *)context
                completion:(void (^)(FYVocabularyEntry *_Nullable entry, NSError *_Nullable error))completion;

- (void)bookmarkVocabulary:(FYVocabularyEntry *)entry
              selectedText:(NSString *)selectedText
                completion:(void (^)(FYVocabularyEntry *_Nullable saved, BOOL wasDuplicate, NSError *_Nullable error))completion;

// 语法收藏。
- (void)bookmarkGrammar:(FYGrammarItem *)item completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
