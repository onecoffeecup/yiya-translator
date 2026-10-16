#import "FYLearningStore.h"
#import "storage/FYLearningDatabaseSession.h"
#import "storage/FYLearningSentenceRepository.h"
#import "storage/FYLearningVocabularyRepository.h"
#import "storage/FYLearningAnalysisCacheRepository.h"
#import "storage/FYLearningBookmarkRepository.h"

const NSUInteger FYRecentSentenceLimit = 5;

@interface FYLearningStore ()
@property(nonatomic, strong) FYLearningDatabaseSession *session;
@property(nonatomic, strong) FYLearningSentenceRepository *sentences;
@property(nonatomic, strong) FYLearningVocabularyRepository *vocabulary;
@property(nonatomic, strong) FYLearningAnalysisCacheRepository *analyses;
@property(nonatomic, strong) FYLearningBookmarkRepository *bookmarks;
@end

@implementation FYLearningStore
- (instancetype)initWithDatabasePath:(NSString *)path {
    self = [super init];
    if (self) {
        _session = [[FYLearningDatabaseSession alloc] initWithDatabasePath:path];
        _sentences = [[FYLearningSentenceRepository alloc] initWithSession:_session];
        _vocabulary = [[FYLearningVocabularyRepository alloc] initWithSession:_session];
        _analyses = [[FYLearningAnalysisCacheRepository alloc] initWithSession:_session];
        _bookmarks = [[FYLearningBookmarkRepository alloc] initWithSession:_session];
    }
    return self;
}
- (dispatch_queue_t)completionQueue { return self.session.completionQueue; }
- (void)setCompletionQueue:(dispatch_queue_t)queue { self.session.completionQueue = queue; }
// Existing internal resilience probes use these accessors, on the store queue.
- (dispatch_queue_t)queue { return self.session.queue; }
- (sqlite3 *)db { return self.session.db; }
- (NSString *)databasePath { return self.session.databasePath; }
- (NSUInteger)historyRetentionLimit { return self.sentences.historyRetentionLimit; }
- (void)setHistoryRetentionLimit:(NSUInteger)limit { self.sentences.historyRetentionLimit = limit; }
- (void)openWithCompletion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.session ensureOpened];
        [self.session deliverError:error completion:completion];
    });
}
- (void)closeWithCompletion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.session close];
        [self.session deliverError:error completion:completion];
    });
}
- (void)configureHistoryRetentionWithLimit:(NSUInteger)limit completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.sentences configureHistoryRetentionWithLimit:limit];
        [self.session deliverError:error completion:completion];
    });
}

- (void)preserveSentenceForHistory:(NSString *)sentenceID completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.sentences preserveSentenceForHistory:sentenceID];
        [self.session deliverError:error completion:completion];
    });
}

- (void)ensureSessionWithID:(NSString *)sessionID
                displayName:(NSString *)displayName
                   language:(NSString *)language
                 completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.sentences ensureSessionWithID:sessionID displayName:displayName language:language];
        [self.session deliverError:error completion:completion];
    });
}

- (void)insertSentenceWithID:(NSString *)sentenceID
                   sessionID:(NSString *)sessionID
                        kind:(FYSentenceKind)kind
                originalText:(NSString *)originalText
                  occurredAt:(NSDate *)occurredAt
                  completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.sentences insertSentenceWithID:sentenceID sessionID:sessionID kind:kind originalText:originalText occurredAt:occurredAt];
        [self.session deliverError:error completion:completion];
    });
}

- (void)updateTranslation:(NSString *)translation
              forSentence:(NSString *)sentenceID
                  version:(NSInteger)version
               completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.sentences updateTranslation:translation forSentence:sentenceID version:version];
        [self.session deliverError:error completion:completion];
    });
}

- (void)appendVersionForSentence:(NSString *)sentenceID
                            text:(NSString *)text
                     translation:(NSString *)translation
                      completion:(void (^)(NSInteger, NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = nil;
        NSInteger capturedVersion = [self.sentences appendVersionForSentence:sentenceID text:text translation:translation error:&error];
        if (!completion) { return; }
        dispatch_async(self.session.completionQueue, ^{ completion(capturedVersion, error); });
    });
}

- (void)recordExcludedSpeakerLabels:(NSArray<NSString *> *)labels forIdentity:(FYRequestIdentity *)identity
                        completion:(void (^)(NSError *))completion {
    NSMutableSet<NSString *> *keys=[NSMutableSet new];
    for (NSString *label in labels) {
        NSString *key=FYDialogueComparisonKey(label);
        if (key.length) [keys addObject:key];
    }
    if (!keys.count || !identity.sentenceID.length || identity.version < 1) {
        [self.session deliverError:nil completion:completion]; return;
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:[keys.allObjects sortedArrayUsingSelector:@selector(compare:)] options:0 error:NULL];
    NSString *json=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *sentenceID=[identity.sentenceID copy], *source=[identity.sourceText copy];
    NSInteger version=identity.version;

    dispatch_async(self.session.queue, ^{
        NSError *error = [self.sentences recordExcludedSpeakerJSON:json sentenceID:sentenceID source:source version:version];
        [self.session deliverError:error completion:completion];
    });
}

- (void)fetchSentence:(NSString *)sentenceID
           completion:(void (^)(FYSentenceRecord *, NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = nil;
        FYSentenceRecord *record = [self.sentences fetchSentence:sentenceID error:&error];
        if (!completion) { return; }
        dispatch_async(self.session.completionQueue, ^{ completion(record, error); });
    });
}

- (void)fetchRecentSentencesWithLimit:(NSUInteger)limit
                           completion:(void (^)(NSArray<FYSentenceRecord *> *, NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = nil;
        NSArray<FYSentenceRecord *> *records = [self.sentences fetchRecentSentencesWithLimit:limit error:&error];
        if (!completion) { return; }
        dispatch_async(self.session.completionQueue, ^{ completion(records, error); });
    });
}

- (void)fetchVersionsForSentence:(NSString *)sentenceID
                      completion:(void (^)(NSArray<FYSentenceVersion *> *, NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = nil;
        NSArray<FYSentenceVersion *> *versions = [self.sentences fetchVersionsForSentence:sentenceID error:&error];
        if (!completion) { return; }
        dispatch_async(self.session.completionQueue, ^{ completion(versions, error); });
    });
}

- (void)upsertVocabulary:(FYVocabularyEntry *)entry completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.vocabulary upsertVocabulary:entry];
        [self.session deliverError:error completion:completion];
    });
}

- (void)attachExample:(FYVocabularyExample *)example completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.vocabulary attachExample:example];
        [self.session deliverError:error completion:completion];
    });
}

- (void)saveVocabulary:(FYVocabularyEntry *)entry withExample:(FYVocabularyExample *)example completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.vocabulary saveVocabulary:entry withExample:example];
        [self.session deliverError:error completion:completion];
    });
}

- (void)fetchVocabularyListWithCompletion:(void (^)(NSArray<FYVocabularyEntry *> *, NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = nil;
        NSArray<FYVocabularyEntry *> *entries = [self.vocabulary fetchVocabularyListWithError:&error];
        if (!completion) { return; }
        dispatch_async(self.session.completionQueue, ^{ completion(entries, error); });
    });
}

- (void)updateReviewStatus:(FYReviewStatus)status
             forVocabulary:(NSString *)vocabularyID
                completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.vocabulary updateReviewStatus:status forVocabulary:vocabularyID];
        [self.session deliverError:error completion:completion];
    });
}

- (void)deleteVocabulary:(NSString *)vocabularyID
              completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.vocabulary deleteVocabulary:vocabularyID];
        [self.session deliverError:error completion:completion];
    });
}

- (void)fetchExamplesForVocabulary:(NSString *)vocabularyID
                        completion:(void (^)(NSArray<FYVocabularyExample *> *, NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = nil;
        NSArray<FYVocabularyExample *> *examples = [self.vocabulary fetchExamplesForVocabulary:vocabularyID error:&error];
        if (!completion) { return; }
        dispatch_async(self.session.completionQueue, ^{ completion(examples, error); });
    });
}

- (void)saveAnalysisResult:(FYAnalysisResult *)result
                sentenceID:(NSString *)sentenceID
                   version:(NSInteger)version
                  textHash:(NSString *)textHash
              promptVersion:(NSInteger)promptVersion
             catalogVersion:(NSInteger)catalogVersion
               modelConfig:(NSString *)modelConfig
                completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.analyses saveAnalysisResult:result sentenceID:sentenceID version:version textHash:textHash promptVersion:promptVersion catalogVersion:catalogVersion modelConfig:modelConfig];
        [self.session deliverError:error completion:completion];
    });
}

- (void)fetchAnalysisForSentence:(NSString *)sentenceID
                         version:(NSInteger)version
                      completion:(void (^)(FYAnalysisResult *, NSString *, NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = nil;
        NSString *modelConfig = nil;
        FYAnalysisResult *result = [self.analyses fetchAnalysisForSentence:sentenceID version:version modelConfig:&modelConfig error:&error];
        if (!completion) { return; }
        dispatch_async(self.session.completionQueue, ^{ completion(result, modelConfig, error); });
    });
}

- (void)toggleSentenceBookmark:(FYRequestIdentity *)identity completion:(void (^)(BOOL,NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = nil;
        BOOL saved = [self.bookmarks toggleSentenceBookmark:identity error:&error];
        if (!completion) { return; }
        dispatch_async(self.session.completionQueue, ^{ completion(saved, error); });
    });
}

- (void)fetchSentenceBookmarks:(void (^)(NSArray<FYRequestIdentity *> *,NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = nil;
        NSArray<FYRequestIdentity *> *values = [self.bookmarks fetchSentenceBookmarksWithError:&error];
        if (!completion) { return; }
        dispatch_async(self.session.completionQueue, ^{ completion(values, error); });
    });
}

- (void)addGrammarBookmark:(FYGrammarBookmark *)bookmark
                completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.bookmarks addGrammarBookmark:bookmark];
        [self.session deliverError:error completion:completion];
    });
}

- (void)fetchGrammarBookmarksWithCompletion:(void (^)(NSArray<FYGrammarBookmark *> *, NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = nil;
        NSArray<FYGrammarBookmark *> *bookmarks = [self.bookmarks fetchGrammarBookmarksWithError:&error];
        if (!completion) { return; }
        dispatch_async(self.session.completionQueue, ^{ completion(bookmarks, error); });
    });
}

- (void)deleteGrammarBookmark:(NSString *)bookmarkID
                   completion:(void (^)(NSError *))completion {
    dispatch_async(self.session.queue, ^{
        NSError *error = [self.bookmarks deleteGrammarBookmark:bookmarkID];
        [self.session deliverError:error completion:completion];
    });
}

@end
