#import "FYLearningResponseDecoder.h"
#import "FYLearningAnalysisSupport.h"
#import "../../FYTranslationManager.h"

@implementation FYLearningResponseDecoder
+ (void)decodeData:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error
    requestURL:(NSURL *)requestURL completion:(void (^)(NSString *, NSError *))completion {
    if (error) {
        completion(nil, [NSError errorWithDomain:@"FYLearningAnalyzer" code:10002
                                        userInfo:@{NSLocalizedDescriptionKey: @"网络连接失败，请检查网络后重试。", NSUnderlyingErrorKey: error}]);
        return;
    }
    if (![response isKindOfClass:NSHTTPURLResponse.class]) {
        completion(nil, [NSError errorWithDomain:@"FYLearningAnalyzer" code:202
                                        userInfo:@{NSLocalizedDescriptionKey: @"接口响应格式错误。"}]);
        return;
    }
    NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
    if (statusCode < 200 || statusCode >= 300) {
        completion(nil, [NSError errorWithDomain:@"FYLearningAnalyzer" code:statusCode
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"学习接口返回 HTTP %ld。", (long)statusCode]}]);
        return;
    }

    NSDictionary *decoded = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![decoded isKindOfClass:NSDictionary.class]) {
        completion(nil, [NSError errorWithDomain:@"FYLearningAnalyzer" code:203
                                        userInfo:@{NSLocalizedDescriptionKey: @"接口没有返回合法 JSON。"}]);
        return;
    }
    if (FYUsesAnthropicMessagesAPI(requestURL)) {
        if ([decoded[@"stop_reason"] isEqual:@"refusal"]) {
            completion(nil,[NSError errorWithDomain:@"FYLearningAnalyzer" code:204
                userInfo:@{NSLocalizedDescriptionKey:@"学习模型拒绝分析这段内容。"}]);
            return;
        }
        if ([decoded[@"stop_reason"] isEqual:@"max_tokens"]) {
            completion(nil,[NSError errorWithDomain:@"FYLearningAnalyzer" code:204
                userInfo:@{NSLocalizedDescriptionKey:@"接口输出被截断，没有返回完整结果。"}]);
            return;
        }
        NSError *contentError=nil;
        NSString *content=[FYTranslationManager translationFromData:data statusCode:statusCode error:&contentError];
        if (!content.length) {
            completion(nil,[NSError errorWithDomain:@"FYLearningAnalyzer" code:204
                userInfo:@{NSLocalizedDescriptionKey:@"学习接口没有返回最终内容。"}]);
        } else completion(content,nil);
        return;
    }
    NSArray *choices = decoded[@"choices"];
    NSDictionary *firstChoice = ([choices isKindOfClass:NSArray.class] && choices.count > 0 && [choices[0] isKindOfClass:NSDictionary.class])
        ? choices[0] : nil;
    NSDictionary *message = [firstChoice[@"message"] isKindOfClass:NSDictionary.class] ? firstChoice[@"message"] : nil;
    if (!firstChoice || !message) {
        completion(nil, [NSError errorWithDomain:@"FYLearningAnalyzer" code:203
                                        userInfo:@{NSLocalizedDescriptionKey: @"接口响应缺少 choices/message。"}]);
        return;
    }
    NSString *finishReason = FYTrim(FYStringOrEmpty(firstChoice[@"finish_reason"]));
    NSString *content = FYTrim(FYStringOrEmpty(message[@"content"]));
    if ([finishReason isEqualToString:@"length"]) {
        completion(nil, [NSError errorWithDomain:@"FYLearningAnalyzer" code:204
                                        userInfo:@{NSLocalizedDescriptionKey: @"接口输出被截断，没有返回完整结果。"}]);
        return;
    }
    if (content.length == 0) {
        NSString *reasoningContent = FYTrim(FYStringOrEmpty(message[@"reasoning_content"]));
        NSString *description = @"学习接口没有返回内容。";
        if (reasoningContent.length > 0) {
            description = @"接口只返回了思考内容，没有返回最终结果；请重试。";
        } else if (finishReason.length > 0) {
            description = [NSString stringWithFormat:@"接口没有返回结果；finish_reason=%@。", finishReason];
        }
        completion(nil, [NSError errorWithDomain:@"FYLearningAnalyzer" code:204
                                        userInfo:@{NSLocalizedDescriptionKey: description}]);
        return;
    }
    completion(content, nil);
}
@end
