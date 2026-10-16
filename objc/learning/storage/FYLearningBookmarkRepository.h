#import "../FYLearningModels.h"
@class FYLearningDatabaseSession;

// Internal synchronous operations: run only on the shared database session queue.
@interface FYLearningBookmarkRepository : NSObject
- (instancetype)initWithSession:(FYLearningDatabaseSession *)session;
- (BOOL)toggleSentenceBookmark:(FYRequestIdentity *)identity error:(NSError **)outError;
- (NSArray<FYRequestIdentity *> *)fetchSentenceBookmarksWithError:(NSError **)outError;
- (NSError *)addGrammarBookmark:(FYGrammarBookmark *)bookmark;
- (NSArray<FYGrammarBookmark *> *)fetchGrammarBookmarksWithError:(NSError **)outError;
- (NSError *)deleteGrammarBookmark:(NSString *)bookmarkID;
@end
