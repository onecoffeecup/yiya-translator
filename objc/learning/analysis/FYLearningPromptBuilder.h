#import "FYLearningGrammarMatcher.h"
@interface FYLearningPromptBuilder : NSObject
- (instancetype)initWithMatcher:(FYLearningGrammarMatcher *)matcher;
- (NSArray<NSDictionary *> *)grammarReadingCuesForText:(NSString *)text catalog:(FYGrammarCatalog *)catalog;
- (NSArray<NSDictionary *> *)analysisMessagesForSource:(NSString *)sourceText translation:(NSString *)translation
    readingCues:(NSArray<NSDictionary *> *)readingCues repairItems:(NSArray<NSDictionary *> *)repairItems
    reviewResult:(FYAnalysisResult *)reviewResult;
@end
