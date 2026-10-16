#import "FYLearningGrammarMatcher.h"
// Internal result bundle preserves the mutable verified list used by one optional repair.
@interface FYLearningParsedAnalysis : NSObject
@property(nonatomic, strong, readonly) FYAnalysisResult *result;
@property(nonatomic, strong, readonly) NSMutableArray<FYGrammarItem *> *verifiedGrammar;
@property(nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *rejectedItems;
@end
@interface FYLearningAnalysisParser : NSObject
- (instancetype)initWithMatcher:(FYLearningGrammarMatcher *)matcher;
- (NSData *)extractJSONDataFromContent:(NSString *)content;
- (BOOL)optionalStringsIn:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys;
- (FYLearningParsedAnalysis *)parseContent:(NSString *)content source:(NSString *)sourceText
    catalogProvider:(id<FYLearningCatalogProviding>)catalogProvider error:(NSError **)outError;
- (FYVocabularyEntry *)parseVocabularyContent:(NSString *)content surface:(NSString *)surface error:(NSError **)outError;
@end
