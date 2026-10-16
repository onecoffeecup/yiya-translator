#import "FYTranslationRequestCoordinator.h"
#import "../FYTranslationManager.h"
#import "FYRuntimeDeliveryChecks.h"

@implementation FYPreparedTranslationRequest { NSURLRequest *_request; }
// NSURLRequest copy can preserve a mutable concrete class on this macOS.
// Keep the canonical preparation private and return detached value copies.
- (NSURLRequest *)request { return [_request copy]; }
+ (instancetype)prepareText:(NSString *)text configuration:(FYTranslationConfiguration *)configuration
    systemPrompt:(NSString *)prompt defaultPrompt:(NSString *(^)(void))defaultPrompt maxTokens:(NSInteger)maxTokens
    modelOverride:(NSString *)modelOverride longText:(BOOL)longText {
    FYPreparedTranslationRequest *result = [self new];
    NSString *apiKey = [configuration.apiKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (apiKey.length == 0) {
        result->_failureReason = @"missing_configuration";
        result->_error = [NSError errorWithDomain:@"LiveCaptionTranslator" code:401 userInfo:@{NSLocalizedDescriptionKey:@"还没有配置 API Key。"}];
        return result;
    }
    NSURL *url = FYTranslationServiceURLWithError(configuration.baseURL, NULL);
    if (!url) {
        result->_failureReason = @"invalid_configuration";
        NSError *error = [NSError errorWithDomain:@"LiveCaptionTranslator" code:400
            userInfo:@{NSLocalizedDescriptionKey:@"Base URL 无效，请在“翻译服务”中填写完整的 https:// 地址。"}];
        NSError *urlError = nil;
        FYTranslationServiceURLWithError(configuration.baseURL, &urlError);
        if (urlError) { error = [NSError errorWithDomain:error.domain code:error.code
            userInfo:@{NSLocalizedDescriptionKey:urlError.localizedDescription, NSUnderlyingErrorKey:urlError}]; }
        result->_error = error; return result;
    }
    NSString *model = [modelOverride stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (model.length == 0) { model = [configuration.model stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
    if (!model.length) {
        result->_error = [NSError errorWithDomain:@"LiveCaptionTranslator" code:400
            userInfo:@{NSLocalizedDescriptionKey:@"请先在「翻译服务」填写翻译模型。"}];
        return result;
    }
    NSError *error = nil;
    NSMutableURLRequest *request = [FYTranslationManager requestWithURL:url apiKey:apiKey model:model sourceText:text
        systemPrompt:(prompt ?: defaultPrompt()) maxTokens:maxTokens disableReasoning:FYIsDeepSeekService(url.absoluteString, model)
        longText:longText error:&error];
    result->_request = [request copy]; result->_error = error;
    if (!request) { result->_failureReason = @"serialization_error"; }
    return result;
}
@end

@implementation FYTranslationRequestIdentity
- (instancetype)initWithScope:(FYTranslationRequestScope)scope generation:(NSInteger)generation revision:(NSUInteger)revision {
    if ((self = [super init])) { _scope = scope; _generation = generation; _revision = revision; }
    return self;
}
@end
@implementation FYTranslationRequestLease {
    NSInteger (^_generation)(void);
    NSUInteger (^_revision)(void);
}
- (instancetype)initWithIdentity:(FYTranslationRequestIdentity *)identity generation:(NSInteger (^)(void))generation revision:(NSUInteger (^)(void))revision {
    if ((self = [super init])) { _identity = identity; _generation = [generation copy]; _revision = [revision copy]; }
    return self;
}
- (NSInteger)currentGeneration { return _generation(); }
- (NSUInteger)currentRevision { return _revision(); }
@end
@implementation FYSystemTranslationRequestTransport
- (NSURLSessionDataTask *)taskWithRequest:(NSURLRequest *)request observer:(void (^)(NSURLResponse *, NSError *))observer
    completion:(void (^)(NSString *, NSError *))completion {
    return [FYTranslationManager taskWithRequest:request session:NSURLSession.sharedSession observer:observer completion:completion];
}
@end

@implementation FYTranslationRequestCoordinator {
    id<FYTranslationRequestTransport> _transport;
}
- (instancetype)initWithTransport:(id<FYTranslationRequestTransport>)transport {
    if ((self = [super init])) { _transport = transport; }
    return self;
}
- (void)submit:(FYPreparedTranslationRequest *)prepared owner:(FYTranslationTaskOwner *)owner lease:(FYTranslationRequestLease *)lease
    observer:(void (^)(NSURLResponse *, NSError *))observer received:(void (^)(NSString *, NSError *))received
    willResume:(void (^)(void))willResume completion:(void (^)(NSString *, NSError *))completion dropped:(void (^)(FYTranslationRequestDrop))dropped {
    __block __weak NSURLSessionDataTask *submittedTask = nil;
    void (^deliver)(NSString *, NSError *) = ^(NSString *translated, NSError *error) {
        received(translated, error);
        FYDeliverTranslationOnMain(lease.identity.generation, ^NSInteger { return lease.currentGeneration; },
            translated, error, ^(NSString *value, NSError *failure) {
                [owner finishTask:submittedTask];
                if (lease.identity.scope != FYTranslationRequestServiceTest && !FYContentRevisionIsCurrent(lease.identity.revision, lease.currentRevision)) {
                    dropped(FYTranslationRequestContentChanged); return;
                }
                completion(value, failure);
            }, ^{
                [owner finishTask:submittedTask]; dropped(FYTranslationRequestGenerationChanged);
            });
    };
    NSURLSessionDataTask *task = [_transport taskWithRequest:prepared.request observer:observer completion:deliver];
    owner.activeTask = task; submittedTask = task;
    willResume(); [task resume];
}
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
    [self cancelTasksExceptTask:nil];
}
- (void)cancelTasksExceptTask:(NSURLSessionDataTask *)retainedTask {
    NSArray *tasks = [_tasks copy];
    [_tasks removeAllObjects]; _activeTask = nil;
    for (NSURLSessionDataTask *task in tasks) {
        if (task == retainedTask) { self.activeTask = task; }
        else { [task cancel]; }
    }
}
@end

