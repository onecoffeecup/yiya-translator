#import "FYTranslationManager.h"

@implementation FYInlineTranslationCache
- (void)storeValue:(NSString *)value forKey:(NSString *)key { FYStoreInlineTranslation(self.entries,value,key); }
- (void)clear { [self.entries removeAllObjects]; }
@end

NSString *FYDisplayableTranslation(NSString *translated, NSString *sourceText,
    NSString *(^trim)(NSString *), NSString *(^normalize)(NSString *),
    BOOL (^equivalent)(NSString *, NSString *), BOOL (^looksLikeSource)(NSString *)) {
    NSString *clean=trim(translated);
    if (!clean.length) return clean;
    NSString *sourceNormalized=normalize(sourceText);
    NSMutableArray<NSString *> *keptLines=[NSMutableArray array];
    for (NSString *rawLine in [clean componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line=trim(rawLine);
        if (!line.length) continue;
        NSString *lineNormalized=normalize(line);
        BOOL isSourceEcho=sourceNormalized.length>=2 && equivalent(lineNormalized,sourceNormalized);
        BOOL sourceLanguage=looksLikeSource(line);
        BOOL labeled=[line hasPrefix:@"原文"] || [line.lowercaseString hasPrefix:@"source"];
        if (isSourceEcho || sourceLanguage || labeled) continue;
        [keptLines addObject:line];
    }
    return keptLines.count ? [keptLines componentsJoinedByString:@"\n"] : @"等待中文译文...";
}

@implementation FYTranslationRunState
- (void)reset {
    self.lastTranslatedText=@"";
    self.lastSubmittedText=@"";
    self.lastAttemptDate=nil;
}
- (BOOL)shouldThrottleText:(NSString *)text geometryChanged:(BOOL)geometryChanged interval:(NSTimeInterval)interval
    equivalent:(BOOL (^)(NSString *, NSString *))equivalent now:(NSDate *(^)(void))now {
    return !geometryChanged && equivalent(text,self.lastSubmittedText) && self.lastAttemptDate &&
        [now() timeIntervalSinceDate:self.lastAttemptDate] < interval;
}
@end

NSString *FYInlineDeliveryDropReason(NSInteger generation, NSInteger currentGeneration,
    NSUInteger inputEpoch, NSUInteger currentInputEpoch, BOOL running, NSInteger mode, NSInteger currentMode) {
    if (generation != currentGeneration) return @"generation_changed";
    if (inputEpoch != currentInputEpoch) return @"input_session_changed";
    if (running && mode != currentMode) return @"mode_changed";
    return nil;
}

void FYPartitionInlineBatch(NSArray *items, NSArray<NSNumber *> *indexes, NSArray<NSString *> *keys,
    BOOL (^isLongAtIndex)(NSUInteger), NSMutableArray *shortItems, NSMutableArray<NSNumber *> *shortIndexes,
    NSMutableArray<NSString *> *shortKeys, NSMutableArray *longItems, NSMutableArray<NSNumber *> *longIndexes,
    NSMutableArray<NSString *> *longKeys) {
    for (NSUInteger index=0; index<items.count; index++) {
        BOOL longText=isLongAtIndex(index);
        [(longText ? longItems : shortItems) addObject:items[index]];
        [(longText ? longIndexes : shortIndexes) addObject:indexes[index]];
        [(longText ? longKeys : shortKeys) addObject:keys[index]];
    }
}

void FYPlanInlineTranslations(NSUInteger count, NSDictionary<NSString *, NSString *> *cache,
    NSString *(^keyAtIndex)(NSUInteger), void (^observeHit)(NSUInteger, BOOL),
    NSMutableArray<NSString *> *translations, NSMutableArray<NSNumber *> *pendingIndexes, NSMutableArray<NSString *> *pendingKeys) {
    for (NSUInteger index=0; index<count; index++) {
        NSString *key=keyAtIndex(index), *cached=cache[key];
        if (observeHit) observeHit(index, cached.length > 0);
        if (cached.length > 0) [translations addObject:cached];
        else { [translations addObject:@""]; [pendingIndexes addObject:@(index)]; [pendingKeys addObject:key]; }
    }
}

void FYStoreInlineTranslation(NSMutableDictionary<NSString *, NSString *> *cache, NSString *value, NSString *key) {
    if (value.length == 0 || key.length == 0) return;
    if (cache.count >= 4000 && cache[key] == nil) [cache removeAllObjects];
    cache[key] = value;
}

NSErrorDomain const FYTranslationURLValidationErrorDomain = @"FYTranslationURLValidation";
static NSURL *FYInvalidServiceURL(NSError **error, FYTranslationURLValidationError code, NSString *message) {
    if (error) *error=[NSError errorWithDomain:FYTranslationURLValidationErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:message}];
    return nil;
}
NSURL *FYChatCompletionsURLWithError(NSString *baseURL, NSError **error) {
    if (error) *error=nil;
    baseURL=[baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!baseURL.length) return FYInvalidServiceURL(error,FYTranslationURLMissing,@"请填写翻译服务地址。");
    NSURLComponents *components=[NSURLComponents componentsWithString:baseURL];
    if (!components) return FYInvalidServiceURL(error,FYTranslationURLMalformed,@"翻译服务地址格式无效。");
    NSString *scheme=components.scheme.lowercaseString;
    if (!([scheme isEqual:@"https"] || [scheme isEqual:@"http"])) return FYInvalidServiceURL(error,FYTranslationURLInvalidScheme,@"翻译服务地址必须使用 http 或 https。");
    if (!components.host.length) return FYInvalidServiceURL(error,FYTranslationURLMissingHost,@"翻译服务地址缺少主机名。");
    if (components.user.length || components.password.length || components.query.length || components.fragment.length) return FYInvalidServiceURL(error,FYTranslationURLUnsupportedComponents,@"翻译服务地址不能包含用户名、密码、查询参数或片段。");
    NSString *host=components.host.lowercaseString;
    BOOL loopback=[host isEqual:@"localhost"] || [host isEqual:@"127.0.0.1"] || [host isEqual:@"::1"] || [host isEqual:@"[::1]"];
    if ([scheme isEqual:@"http"] && !loopback) return FYInvalidServiceURL(error,FYTranslationURLInsecureRemoteHTTP,@"远程 HTTP 会明文传输 API Key；请改用 HTTPS。本机服务可使用 localhost、127.0.0.1 或 [::1]。");
    while ([baseURL hasSuffix:@"/"]) baseURL=[baseURL substringToIndex:baseURL.length-1];
    if (![baseURL hasSuffix:@"/chat/completions"]) baseURL=[baseURL stringByAppendingString:@"/chat/completions"];
    NSURL *url=[NSURL URLWithString:baseURL];
    if (!url) return FYInvalidServiceURL(error,FYTranslationURLMalformed,@"翻译服务地址格式无效。");
    return url;
}
NSURL *FYChatCompletionsURL(NSString *baseURL) { return FYChatCompletionsURLWithError(baseURL,NULL); }
NSString *FYNumberedTranslationSource(NSUInteger count, NSString *(^textAtIndex)(NSUInteger)) {
    NSMutableString *result=[NSMutableString string];
    for (NSUInteger index=0; index<count; index++) [result appendFormat:@"%lu. %@\n", (unsigned long)(index+1), textAtIndex(index)];
    return result;
}

NSString *FYInlineBatchPrompt(NSString *sourceLanguage, BOOL longText) {
    NSString *source=sourceLanguage;
    return longText ? [NSString stringWithFormat:@"你是游戏界面公告翻译器。把用户发来的%@界面正文逐条翻译成简体中文。输出必须保留编号，每行格式为“1. 译文”。译文要完整、通顺，保留段落结构和完整意思，不要压缩成短语；不要解释，不要输出原文。", source] : [NSString stringWithFormat:@"你是游戏界面贴译器。把用户发来的%@界面文字逐条翻译成简体中文。输出必须保留编号，每行格式为“1. 译文”。译文要短，适合贴在原文字旁边；不要解释，不要输出原文。按钮和菜单用短语，公告正文保持完整意思。", source];
}
NSInteger FYInlineBatchMaxTokens(NSUInteger itemCount, BOOL longText) {
    NSInteger count=(NSInteger)itemCount;
    return longText ? MAX(320, count * 220) : MAX(240, count * 80);
}

BOOL FYIsDeepSeekService(NSString *baseURL, NSString *model) {
    NSString *url=[baseURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    NSString *name=[model stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    return [url containsString:@"deepseek"] || [name hasPrefix:@"deepseek-"];
}

@interface FYTranslationCache ()
@property(nonatomic, copy, readwrite) NSString *key;
@property(nonatomic, copy, readwrite) NSString *value;
@end
@implementation FYTranslationCache
- (NSString *)valueForKey:(NSString *)key { return key && [key isEqualToString:self.key] && self.value.length ? self.value : nil; }
- (void)storeValue:(NSString *)value forKey:(NSString *)key { self.key=key; self.value=value; }
- (void)clear { self.key=nil; self.value=nil; }
@end

@implementation FYTranslationTaskOwner {
    NSMutableArray<NSURLSessionDataTask *> *_tasks;
}
@synthesize activeTask = _activeTask;
- (void)setActiveTask:(NSURLSessionDataTask *)task {
    _activeTask = task;
    if (!task) { return; }
    if (!_tasks) { _tasks = [NSMutableArray new]; }
    if ([_tasks indexOfObjectIdenticalTo:task] == NSNotFound) { [_tasks addObject:task]; }
}
- (void)finishTask:(NSURLSessionDataTask *)task {
    if (!task) { return; }
    [_tasks removeObjectIdenticalTo:task];
    if (_activeTask == task) { _activeTask = _tasks.lastObject; }
}
- (void)cancelActiveTask {
    NSArray *tasks = [_tasks copy];
    [_tasks removeAllObjects]; _activeTask = nil;
    for (NSURLSessionDataTask *task in tasks) { [task cancel]; }
}
@end

void FYDeliverTranslationOnMain(NSInteger requestGeneration, NSInteger (^currentGeneration)(void),
    NSString *translated, NSError *error, void (^completion)(NSString *, NSError *), void (^dropped)(void)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (requestGeneration != currentGeneration()) { if (dropped) { dropped(); } return; }
        completion(translated, error);
    });
}

NSString *FYTranslationCacheKey(NSInteger generation, NSInteger serviceGeneration, NSString *sentenceID,
                                NSInteger version, NSString *text, NSString *prompt) {
    return sentenceID.length ? [NSString stringWithFormat:@"%ld|%ld|%@|%ld|%@|%@", (long)generation,
        (long)serviceGeneration, sentenceID, (long)version, text, prompt] : nil;
}
BOOL FYTranslationCacheCanStore(NSInteger requestGeneration, NSInteger currentGeneration,
    NSInteger requestServiceGeneration, NSInteger currentServiceGeneration, NSString *translated) {
    return requestGeneration == currentGeneration && requestServiceGeneration == currentServiceGeneration &&
        [translated stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
}

static NSString *FYTrimString(id value) {
    return [value isKindOfClass:NSString.class] ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
}
@implementation FYTranslationManager
+ (NSURLSessionDataTask *)taskWithRequest:(NSURLRequest *)request session:(NSURLSession *)session
                              observer:(void (^)(NSURLResponse *, NSError *))observer
                            completion:(void (^)(NSString *, NSError *))completion {
    return [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (observer) { observer(response, error); }
        if (error) { completion(nil, error); return; }
        NSError *decodeError = nil;
        NSString *content = [self translationFromData:data statusCode:[(NSHTTPURLResponse *)response statusCode] error:&decodeError];
        completion(content, decodeError);
    }];
}
+ (NSMutableURLRequest *)requestWithURL:(NSURL *)url apiKey:(NSString *)key model:(NSString *)model
                           sourceText:(NSString *)text systemPrompt:(NSString *)prompt
                            maxTokens:(NSInteger)maxTokens disableReasoning:(BOOL)disableReasoning
                                error:(NSError **)error {
    if (!FYChatCompletionsURLWithError(url.absoluteString, error)) { return nil; }
    NSMutableDictionary *payload = [@{@"model": model, @"messages": @[
        @{@"role": @"system", @"content": prompt}, @{@"role": @"user", @"content": FYTrimString(text)}],
        @"temperature": @0.2, @"max_tokens": @(MAX(120, maxTokens))} mutableCopy];
    if (disableReasoning) {
        payload[@"reasoning_effort"] = @"none";
        payload[@"thinking"] = @{@"type": @"disabled"};
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!body) { return nil; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    // Small realtime responses keep their current latency bound. Nonstreaming
    // batches need time to produce larger output, but remain cancellable/bounded.
    request.timeoutInterval = maxTokens <= 240 ? 15 : MIN(90, MAX(60, ceil(maxTokens / 30.0) + 15));
    request.HTTPBody = body;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", key] forHTTPHeaderField:@"Authorization"];
    return request;
}
+ (NSString *)translationFromData:(NSData *)data statusCode:(NSInteger)statusCode error:(NSError **)error {
    if (statusCode < 200 || statusCode >= 300) {
        NSString *body = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
        if (body.length > 500) { body = [[body substringToIndex:500] stringByAppendingString:@"..."]; }
        if (error) { *error = [NSError errorWithDomain:@"LiveCaptionTranslator" code:statusCode userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"翻译接口返回 %ld：%@", (long)statusCode, body]}]; }
        return nil;
    }
    NSError *decodeError = nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:&decodeError];
    if (!decoded) { if (error) { *error = decodeError; } return nil; }
    id choices = [decoded isKindOfClass:NSDictionary.class] ? decoded[@"choices"] : nil;
    id first = [choices isKindOfClass:NSArray.class] ? [choices firstObject] : nil;
    id message = [first isKindOfClass:NSDictionary.class] ? first[@"message"] : nil;
    NSString *content = [message isKindOfClass:NSDictionary.class] ? FYTrimString(message[@"content"]) : @"";
    if (content.length > 0) { return content; }
    NSString *reasoning = [message isKindOfClass:NSDictionary.class] ? FYTrimString(message[@"reasoning_content"]) : @"";
    NSString *finish = [first isKindOfClass:NSDictionary.class] ? FYTrimString(first[@"finish_reason"]) : @"";
    NSString *description = @"翻译接口没有返回译文。";
    if (reasoning.length > 0) { description = @"接口只返回了思考内容，没有返回最终译文；请使用 DeepSeek Flash，或保持 reasoning_effort=none。"; }
    else if ([finish isEqualToString:@"length"]) { description = @"接口输出被长度限制截断，没有返回译文；已提高输出额度，请再试一次。"; }
    else if (finish.length > 0) { description = [NSString stringWithFormat:@"翻译接口没有返回译文；finish_reason=%@。", finish]; }
    if (error) { *error = [NSError errorWithDomain:@"LiveCaptionTranslator" code:204 userInfo:@{NSLocalizedDescriptionKey:description}]; }
    return nil;
}
@end

NSArray<NSString *> *FYParseNumberedTranslations(NSString *text, NSUInteger count) {
    NSMutableArray<NSString *> *results = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        [results addObject:@""];
    }

    NSInteger currentIndex = -1;
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (line.length == 0) { continue; }

        NSUInteger cursor = 0;
        while (cursor < line.length && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[line characterAtIndex:cursor]]) {
            cursor++;
        }

        if (cursor > 0 && cursor < line.length) {
            NSInteger number = [[line substringToIndex:cursor] integerValue];
            if (number >= 1 && (NSUInteger)number <= count) {
                while (cursor < line.length) {
                    unichar character = [line characterAtIndex:cursor];
                    if (character == '.' || character == ')' || character == 0x3001 || character == 0xff0e || character == ':' || character == 0xff1a || [[NSCharacterSet whitespaceCharacterSet] characterIsMember:character]) {
                        cursor++;
                    } else {
                        break;
                    }
                }

                currentIndex = number - 1;
                results[currentIndex] = [[line substringFromIndex:cursor] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                continue;
            }
        }

        if (currentIndex >= 0) {
            NSString *existing = results[currentIndex];
            results[currentIndex] = existing.length > 0 ? [existing stringByAppendingFormat:@"\n%@", line] : line;
        }
    }

    BOOL hasAnyNumbered = NO;
    for (NSString *result in results) {
        if ([result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0) {
            hasAnyNumbered = YES;
            break;
        }
    }

    if (!hasAnyNumbered) { return @[]; }

    return results;
}

void FYRunInlineBatches(BOOL hasShort, BOOL hasLong, NSArray<NSString *> *translations,
    void (^launch)(BOOL longText, void (^done)(NSError *)),
    void (^completion)(NSArray<NSString *> *, NSError *)) {
    __block BOOL shortDone=!hasShort, longDone=!hasLong;
    __block NSError *shortError=nil, *longError=nil;
    void (^maybeFinish)(void)=^{
        if (!shortDone || !longDone) return;
        NSError *error=shortError ?: longError;
        completion(error ? nil : translations, error);
    };
    if (hasShort) launch(NO, ^(NSError *error){ shortError=error; shortDone=YES; maybeFinish(); });
    if (hasLong) launch(YES, ^(NSError *error){ longError=error; longDone=YES; maybeFinish(); });
    if (!hasShort && !hasLong) maybeFinish();
}

NSError *FYApplyInlineBatchResults(NSArray<NSString *> *parsed, NSUInteger count,
    NSArray<NSNumber *> *indexes, NSArray<NSString *> *keys, NSMutableArray<NSString *> *translations,
    void (^cacheValue)(NSString *, NSString *)) {
        if (parsed.count != count) {
            NSMutableArray<NSString *> *seenValues = [NSMutableArray array];
            BOOL allBlank = YES;
            for (NSUInteger index = 0; index < count; index++) {
                NSString *value = index < parsed.count ? [parsed[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
                NSNumber *targetIndex = indexes[index];
                translations[targetIndex.unsignedIntegerValue] = value;
                if (value.length == 0) { continue; }
                allBlank = NO;
                if (![seenValues containsObject:value]) { [seenValues addObject:value]; }
            }

            if (allBlank) {
                NSError *parseError = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                                          code:205
                                                      userInfo:@{NSLocalizedDescriptionKey: @"贴译结果没有按编号返回，已跳过这一轮；请重试或改用更稳定的模型（如 DeepSeek Flash）。"}];
                return parseError;
            }

            BOOL looksLikeDuplicatedParagraph = seenValues.count == 1 && count >= 3 && [seenValues[0] length] > 24;
            if (looksLikeDuplicatedParagraph) {
                NSError *parseError = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                                          code:205
                                                      userInfo:@{NSLocalizedDescriptionKey: @"贴译结果像是一整段文字被重复返回，已跳过这一轮以避免整屏贴同一句。"}];
                return parseError;
            }

            for (NSUInteger index = 0; index < count; index++) {
                NSString *value = translations[indexes[index].unsignedIntegerValue];
                if (value.length == 0) { continue; }
                cacheValue(value, keys[index]);
            }
            return nil;
        }

        for (NSUInteger index = 0; index < count; index++) {
            NSString *value = index < parsed.count ? [parsed[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
            NSNumber *targetIndex = indexes[index];
            translations[targetIndex.unsignedIntegerValue] = value;
            if (value.length == 0) { continue; }
            cacheValue(value, keys[index]);
        }
        return nil;
}
