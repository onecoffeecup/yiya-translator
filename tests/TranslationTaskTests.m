#import "FYTranslationManager.h"
static NSUInteger assertions;
static dispatch_semaphore_t heldRequestStarted;
static dispatch_semaphore_t heldRequestStopped;
static void Check(BOOL ok, NSString *message) { assertions++; if (!ok) { NSLog(@"FAIL %@",message); exit(1); } }
@interface TaskSpy : NSObject
@property(nonatomic) NSUInteger cancelCalls;
@end
@implementation TaskSpy
- (void)cancel { self.cancelCalls++; }
@end
static void RunOwnership(void) {
    FYTranslationTaskOwner *owner=[FYTranslationTaskOwner new];
    TaskSpy *old=[TaskSpy new], *current=[TaskSpy new];
    [owner cancelActiveTask];
    Check(!owner.activeTask,@"cancel empty owner is harmless");
    owner.activeTask=(NSURLSessionDataTask *)(id)old;
    owner.activeTask=(NSURLSessionDataTask *)(id)current;
    Check((id)owner.activeTask==current && old.cancelCalls==0,@"replacement does not cancel previous task");
    [owner cancelActiveTask];
    Check(current.cancelCalls==1 && !owner.activeTask,@"cancel current task and clear ownership");
    [owner cancelActiveTask];
    Check(current.cancelCalls==1,@"repeated cancellation does not cancel cleared task");
}
@interface FixtureProtocol : NSURLProtocol
@end
@implementation FixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"translation-fixture.invalid"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    if ([self.request.URL.path isEqual:@"/hold"]) { dispatch_semaphore_signal(heldRequestStarted); return; }
    if ([self.request.URL.path isEqual:@"/transport-error"]) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
        return;
    }
    NSInteger status=[self.request.URL.path isEqual:@"/http-error"]?429:200;
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[@"{\"choices\":[{\"message\":{\"content\":\" 翻译 \"}}]}" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading { if ([self.request.URL.path isEqual:@"/hold"]) { dispatch_semaphore_signal(heldRequestStopped); } }
@end
static void Run(NSURLSession *session, NSString *path, NSInteger expectedCode, BOOL observerPresent) {
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    __block BOOL observed=NO, completed=NO;
    __block NSURLResponse *rawResponse=nil;
    __block NSError *rawError=nil, *resultError=nil;
    __block NSString *result=nil;
    NSURLRequest *request=[NSURLRequest requestWithURL:[NSURL URLWithString:[@"https://translation-fixture.invalid" stringByAppendingString:path]]];
    NSURLSessionDataTask *task=[FYTranslationManager taskWithRequest:request session:session observer:observerPresent?^(NSURLResponse *response,NSError *error){ observed=YES;rawResponse=response;rawError=error; }:nil completion:^(NSString *text,NSError *error){
        Check(!observerPresent || observed,@"observer precedes completion");
        completed=YES; result=text; resultError=error; dispatch_semaphore_signal(done);
    }];
    Check(task.state==NSURLSessionTaskStateSuspended && !completed,@"returned task suspended until caller resumes");
    [task resume];
    Check(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0,@"fixture task completes within deadline");
    if (expectedCode==0) { Check([result isEqual:@"翻译"] && !resultError,@"session success decodes and trims content"); }
    else { Check(!result && resultError.code==expectedCode,@"HTTP or transport error preserved"); }
    if ([path isEqual:@"/transport-error"]) { Check(resultError==rawError && !rawResponse,@"transport error identity passes through observer and completion"); }
    else if(observerPresent) { Check([(NSHTTPURLResponse *)rawResponse statusCode]==(expectedCode?:200) && !rawError,@"observer sees raw response before content decoding"); }
}
static void RunCancellation(NSURLSession *session) {
    heldRequestStarted=dispatch_semaphore_create(0);
    heldRequestStopped=dispatch_semaphore_create(0);
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    __block NSError *observedError=nil, *completedError=nil;
    __block NSUInteger deliveries=0;
    __block NSString *result=nil;
    NSURLRequest *request=[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://translation-fixture.invalid/hold"]];
    NSURLSessionDataTask *task=[FYTranslationManager taskWithRequest:request session:session observer:^(NSURLResponse *response,NSError *error) {
        observedError=error;
    } completion:^(NSString *text,NSError *error) {
        deliveries++; result=text; completedError=error; dispatch_semaphore_signal(done);
    }];
    [task resume];
    Check(dispatch_semaphore_wait(heldRequestStarted,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0,@"cancellation fixture begins loading before cancel");
    [task cancel];
    Check(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0,@"cancelled task delivers completion");
    Check(!result && completedError.code==NSURLErrorCancelled && [completedError.domain isEqual:NSURLErrorDomain],@"cancel error is not decoded as a response");
    Check(completedError==observedError && deliveries==1,@"cancel observer runs first and preserves error identity");
    Check(dispatch_semaphore_wait(heldRequestStopped,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0,@"caller cancellation stops underlying protocol");
}
static void RunDelivery(BOOL stale) {
    __block NSInteger generation=7;
    __block BOOL finished=NO;
    __block NSUInteger completed=0, dropped=0;
    NSError *expected=[NSError errorWithDomain:@"fixture" code:17 userInfo:nil];
    FYDeliverTranslationOnMain(7, ^NSInteger {
        Check(NSThread.isMainThread,@"generation read on main thread"); return generation;
    }, @"fixture translation", expected, ^(NSString *text,NSError *error) {
        Check(NSThread.isMainThread && [text isEqual:@"fixture translation"] && error==expected,@"delivery preserves values on main thread");
        completed++; finished=YES;
    }, ^{ Check(NSThread.isMainThread,@"stale notification on main thread"); dropped++; finished=YES; });
    Check(!finished,@"delivery is asynchronous even when submitted on main thread");
    if (stale) { generation=8; }
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished && deadline.timeIntervalSinceNow>0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    }
    Check(finished && completed==(stale?0:1) && dropped==(stale?1:0),@"generation evaluated at delivery and exactly one branch runs");
}
int main(void) { @autoreleasepool {
    NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.protocolClasses=@[FixtureProtocol.class];
    NSURLSession *session=[NSURLSession sessionWithConfiguration:config];
    Run(session,@"/success",0,YES);
    Run(session,@"/http-error",429,YES);
    Run(session,@"/transport-error",NSURLErrorTimedOut,YES);
    Run(session,@"/success",0,NO);
    RunCancellation(session);
    RunOwnership();
    RunDelivery(NO);
    RunDelivery(YES);
    [session finishTasksAndInvalidate];
    NSLog(@"PASS TranslationTaskTests: %lu assertions, isolated URLProtocol, no network",(unsigned long)assertions);
} return 0; }
