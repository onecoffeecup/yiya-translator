#import "FYLearningRequestBuilder.h"
#import "FYLearningAnalysisSupport.h"
#import "../../FYTranslationManager.h"

@implementation FYLearningRequestBuilder
+ (NSMutableURLRequest *)requestForConfiguration:(id<FYLearningRequestConfiguration>)configuration
    messages:(NSArray<NSDictionary *> *)messages maxTokens:(NSInteger)maxTokens
    grammarAnalysis:(BOOL)grammarAnalysis error:(NSError **)outError {
    if (configuration.apiKey.length == 0) {
        if (outError) { *outError = [NSError errorWithDomain:@"FYLearningAnalyzer" code:10001
                                        userInfo:@{NSLocalizedDescriptionKey: @"还没有配置 API Key。"}]; } return nil;
    }
    NSError *urlError = nil;
    NSURL *url = FYTranslationServiceURLWithError(configuration.baseURL, &urlError);
    if (!url) {
        if (outError) { *outError = [NSError errorWithDomain:@"FYLearningAnalyzer" code:10000
                                        userInfo:@{NSLocalizedDescriptionKey: urlError.localizedDescription ?: @"Base URL 无效。"}]; } return nil;
    }
    NSString *model = FYTrim(configuration.model);
    if (model.length == 0) {
        if (outError) { *outError = [NSError errorWithDomain:@"FYLearningAnalyzer" code:10003
            userInfo:@{NSLocalizedDescriptionKey:@"请前往「翻译服务」填写翻译模型；也可在高级选项中填写学习模型。"}]; } return nil;
    }

    // Translation and learning share the service adapter, including Claude.
    BOOL grammarJSON=grammarAnalysis && [@[@"deepseek-flash",@"deepseek-v4-pro",@"deepseek-v4-flash"] containsObject:model.lowercaseString];
    NSError *requestError=nil;
    NSMutableURLRequest *request=[FYTranslationManager requestWithURL:url apiKey:configuration.apiKey model:model
        messages:messages maxTokens:maxTokens disableReasoning:[configuration isDeepSeek] requiresJSON:grammarJSON
        timeout:30 error:&requestError];
    if (!request) {
        if (outError) { *outError = [NSError errorWithDomain:@"FYLearningAnalyzer" code:500
            userInfo:@{NSLocalizedDescriptionKey:@"构造请求失败。",NSUnderlyingErrorKey:requestError ?: [NSError errorWithDomain:@"FYLearningAnalyzer" code:500 userInfo:nil]}]; } return nil;
    }

    return request;
}
@end
