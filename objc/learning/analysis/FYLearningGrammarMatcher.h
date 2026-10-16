#import "../FYLearningModels.h"
#import "../FYGrammarCatalog.h"
@protocol FYLearningCatalogProviding <NSObject>
@property(nonatomic, readonly) FYGrammarCatalog *catalog;
@end
@interface FYLearningGrammarMatcher : NSObject
- (BOOL)hasLexicalConflict:(FYGrammarItem *)item source:(NSString *)source;
- (FYGrammarCatalogEntry *)resolveCatalogEntryForItem:(FYGrammarItem *)item provider:(id<FYLearningCatalogProviding>)provider;
- (NSString *)signatureFromName:(NSString *)name;
- (NSRange)verifiedRangeForText:(NSString *)fragment occurrence:(NSInteger)occurrence inText:(NSString *)source;
- (NSRange)rangeForText:(NSString *)matchedText occurrence:(NSInteger)occurrence inText:(NSString *)text;
@end
