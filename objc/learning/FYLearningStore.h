#import <Foundation/Foundation.h>
#import "FYLearningModels.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSUInteger FYRecentSentenceLimit;

// SQLite 读写都在内部串行队列执行；所有 completion 默认回主线程（测试可指定队列）。
@interface FYLearningStore : NSObject

- (instancetype)initWithDatabasePath:(NSString *)path;
- (void)openWithCompletion:(void (^)(NSError *_Nullable error))completion;
- (void)closeWithCompletion:(void (^)(NSError *_Nullable error))completion;
- (dispatch_queue_t)completionQueue; // 默认主队列，测试可覆盖
- (void)setCompletionQueue:(dispatch_queue_t)queue;

// 0 disables pruning (used by isolated stores); the app retains the latest five.
- (void)configureHistoryRetentionWithLimit:(NSUInteger)limit
                               completion:(void (^)(NSError *_Nullable error))completion;
// Keep a pinned sentence usable until the user follows the latest sentence again.
- (void)preserveSentenceForHistory:(nullable NSString *)sentenceID
                      completion:(void (^)(NSError *_Nullable error))completion;

// 会话
- (void)ensureSessionWithID:(NSString *)sessionID
                displayName:(NSString *)displayName
                   language:(NSString *)language
                 completion:(void (^)(NSError *_Nullable error))completion;

// 句子：创建时同时写第一条版本（version=1）。翻译回填用 updateTranslation。
- (void)insertSentenceWithID:(NSString *)sentenceID
                   sessionID:(NSString *)sessionID
                        kind:(FYSentenceKind)kind
                originalText:(NSString *)originalText
                  occurredAt:(NSDate *)occurredAt
                  completion:(void (^)(NSError *_Nullable error))completion;

- (void)updateTranslation:(NSString *)translation
              forSentence:(NSString *)sentenceID
                  version:(NSInteger)version
               completion:(void (^)(NSError *_Nullable error))completion;

// 追加新版本（OCR 修正后）；返回写入的版本号。
- (void)appendVersionForSentence:(NSString *)sentenceID
                            text:(NSString *)text
                     translation:(nullable NSString *)translation
                      completion:(void (^)(NSInteger version, NSError *_Nullable error))completion;

- (void)fetchSentence:(NSString *)sentenceID
           completion:(void (^)(FYSentenceRecord *_Nullable record, NSError *_Nullable error))completion;

- (void)fetchRecentSentencesWithLimit:(NSUInteger)limit
                           completion:(void (^)(NSArray<FYSentenceRecord *> *records, NSError *_Nullable error))completion;

- (void)fetchVersionsForSentence:(NSString *)sentenceID
                      completion:(void (^)(NSArray<FYSentenceVersion *> *versions, NSError *_Nullable error))completion;

// Commit the vocabulary entry and its source example together; neither survives a failed write.
- (void)saveVocabulary:(FYVocabularyEntry *)entry withExample:(nullable FYVocabularyExample *)example
             completion:(void (^)(NSError *_Nullable error))completion;

// 词条：保存/更新。重复收藏由 coordinator 判定，store 只负责写入。
- (void)upsertVocabulary:(FYVocabularyEntry *)entry
              completion:(void (^)(NSError *_Nullable error))completion;

- (void)attachExample:(FYVocabularyExample *)example
           completion:(void (^)(NSError *_Nullable error))completion;

- (void)fetchVocabularyListWithCompletion:(void (^)(NSArray<FYVocabularyEntry *> *entries, NSError *_Nullable error))completion;

- (void)updateReviewStatus:(FYReviewStatus)status
             forVocabulary:(NSString *)vocabularyID
                completion:(void (^)(NSError *_Nullable error))completion;

- (void)deleteVocabulary:(NSString *)vocabularyID
              completion:(void (^)(NSError *_Nullable error))completion;

- (void)fetchExamplesForVocabulary:(NSString *)vocabularyID
                        completion:(void (^)(NSArray<FYVocabularyExample *> *examples, NSError *_Nullable error))completion;

// 分析结果缓存
- (void)saveAnalysisResult:(FYAnalysisResult *)result
                sentenceID:(NSString *)sentenceID
                   version:(NSInteger)version
                  textHash:(NSString *)textHash
              promptVersion:(NSInteger)promptVersion
             catalogVersion:(NSInteger)catalogVersion
               modelConfig:(NSString *)modelConfig
                completion:(void (^)(NSError *_Nullable error))completion;

- (void)fetchAnalysisForSentence:(NSString *)sentenceID
                         version:(NSInteger)version
                      completion:(void (^)(FYAnalysisResult *_Nullable result, NSString *_Nullable modelConfig, NSError *_Nullable error))completion;

- (void)toggleSentenceBookmark:(FYRequestIdentity *)identity completion:(void (^)(BOOL saved, NSError *_Nullable error))completion;
- (void)fetchSentenceBookmarks:(void (^)(NSArray<FYRequestIdentity *> *identities, NSError *_Nullable error))completion;

// 语法收藏
- (void)addGrammarBookmark:(FYGrammarBookmark *)bookmark
                completion:(void (^)(NSError *_Nullable error))completion;

- (void)fetchGrammarBookmarksWithCompletion:(void (^)(NSArray<FYGrammarBookmark *> *bookmarks, NSError *_Nullable error))completion;

- (void)deleteGrammarBookmark:(NSString *)bookmarkID
                   completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
