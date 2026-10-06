#import <Foundation/Foundation.h>
#import "FYLearningModels.h"

NS_ASSUME_NONNULL_BEGIN

// 从 JSON 加载可核验的语法登记。等级与来源只来自本目录，不信任模型凭空生成的 URL 或等级。
@interface FYGrammarCatalog : NSObject

- (instancetype)initWithURL:(NSURL *)url;
- (BOOL)loadWithError:(NSError **)error;

@property(nonatomic, readonly) NSInteger catalogVersion;
@property(nonatomic, readonly) NSArray<FYGrammarCatalogEntry *> *allEntries;

- (nullable FYGrammarCatalogEntry *)entryForID:(NSString *)catalogID;
- (nullable FYGrammarCatalogEntry *)entryForName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
