#import "FYGrammarServiceConfiguration.h"
@implementation FYGrammarServiceConfiguration
- (instancetype)initWithBaseURL:(NSString *)baseURL model:(NSString *)model apiKey:(NSString *)apiKey {
    if ((self=[super init])) { _baseURL=baseURL;_model=model;_apiKey=apiKey; }return self;
}
@end
