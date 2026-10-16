#import "FYLearningAnalyzer.h"
#import <objc/runtime.h>

static NSUInteger checks;
static void Check(BOOL ok, NSString *message) { checks++; if (!ok) { NSLog(@"FAIL %@", message); exit(2); } }
static void Pump(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && limit.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    Check(done(), @"mock completion reaches its boundary");
}
static NSData *Envelope(NSString *content) {
    return [NSJSONSerialization dataWithJSONObject:@{@"choices":@[@{@"message":@{@"content":content},@"finish_reason":@"stop"}]} options:0 error:NULL];
}
static NSHTTPURLResponse *Response(void) {
    return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid/v1/chat/completions"] statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
}
static FYLearningAnalyzer *Analyzer(void) {
    FYLearningAnalyzer *a=[FYLearningAnalyzer new]; a.baseURL=@"https://example.invalid/v1"; a.apiKey=@"synthetic-boundary-key"; a.model=@"fixture-model"; return a;
}
static void Drain(void) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.03]]; }

// Explicit URLSession/task boundary; resume never opens a network connection.
@interface FYHeldLearningTask : NSObject
@property(nonatomic) NSUInteger resumes;
@property(nonatomic) NSUInteger cancels;
@property(nonatomic, copy) void (^done)(NSData *, NSURLResponse *, NSError *);
- (void)resume;
- (void)cancel;
@end
@implementation FYHeldLearningTask
- (void)resume { self.resumes++; }
- (void)cancel { self.cancels++; }
@end
@interface FYHeldLearningSession : NSObject
@property(nonatomic, strong) NSMutableArray<FYHeldLearningTask *> *tasks;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))done;
@end
@implementation FYHeldLearningSession
- (instancetype)init { if ((self=[super init])) _tasks=[NSMutableArray new]; return self; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *,NSURLResponse *,NSError *))done {
    FYHeldLearningTask *task=[FYHeldLearningTask new]; task.done=done; [self.tasks addObject:task]; return (NSURLSessionDataTask *)task;
}
@end
static FYHeldLearningSession *heldSession;
static id MockSharedSession(id receiver, SEL selector) { return heldSession; }

static void DefaultTaskLifecycle(void) {
    Method method=class_getClassMethod(NSURLSession.class,@selector(sharedSession));
    IMP original=method_getImplementation(method); heldSession=[FYHeldLearningSession new];
    method_setImplementation(method,(IMP)MockSharedSession);
    @try {
        FYLearningAnalyzer *a=Analyzer(); __block NSUInteger callbacks=0;
        [a answerConversation:@[] completion:^(NSString *answer,NSError *error) { Check(!answer && error.code==499,@"cancel before registration has original cancellation error"); callbacks++; }];
        FYHeldLearningTask *unregistered=heldSession.tasks.lastObject;
        [a cancelAll]; Check(callbacks==1 && a.generation==1,@"cancel drains callback synchronously and advances generation");
        Drain(); Check(!unregistered.resumes && !unregistered.cancels && callbacks==1,@"unregistered task never resumes or completes twice");
        __block NSString *answer;
        [a answerConversation:@[] completion:^(NSString *value,NSError *error) { Check(error.code==499,@"active task cancellation reaches caller"); callbacks++; }];
        FYHeldLearningTask *old=heldSession.tasks.lastObject; Pump(^BOOL { return old.resumes==1; });
        [a cancelAll]; Check(old.cancels==1 && callbacks==2,@"registered task cancels exactly once");
        [a answerConversation:@[] completion:^(NSString *value,NSError *error) { Check(!error && NSThread.isMainThread,@"valid response delivers on main thread"); answer=value; callbacks++; }];
        FYHeldLearningTask *fresh=heldSession.tasks.lastObject; Pump(^BOOL { return fresh.resumes==1; });
        old.done(Envelope(@"late old"),Response(),nil); Drain();
        Check(callbacks==2 && [[a valueForKey:@"activeTasks"] count]==1,@"late old callback keeps the current task registered");
        fresh.done(Envelope(@"fresh answer"),Response(),nil); Pump(^BOOL { return answer!=nil; });
        fresh.done(Envelope(@"duplicate"),Response(),nil); Drain();
        Check(callbacks==3 && [answer isEqual:@"fresh answer"] && [[a valueForKey:@"pendingCompletions"] count]==0,@"response completes once and removes pending state");
        for (FYHeldLearningTask *task in heldSession.tasks) task.done=nil;
    } @finally { method_setImplementation(method,original); heldSession=nil; }
}

static void IndependentRequestsAndLease(void) {
    NSMutableArray *replies=[NSMutableArray new]; FYLearningAnalyzer *a=Analyzer(); __block NSMutableArray *answers=[NSMutableArray new];
    a.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)) { [replies addObject:[done copy]]; };
    for (NSUInteger i=0;i<2;i++) [a answerConversation:@[] completion:^(NSString *value,NSError *error) { Check(!error,@"independent simultaneous request succeeds"); [answers addObject:value]; }];
    void (^second)(NSData *,NSURLResponse *,NSError *)=replies[1], (^first)(NSData *,NSURLResponse *,NSError *)=replies[0];
    second(Envelope(@"second"),Response(),nil); first(Envelope(@"first"),Response(),nil); Pump(^BOOL { return answers.count==2; });
    Check([answers isEqual:@[@"second",@"first"]],@"simultaneous learning requests complete in response order");
    a.transport=nil; [replies removeAllObjects]; first=nil; second=nil;

    __weak FYLearningAnalyzer *weakAnalyzer; __block void (^held)(NSData *,NSURLResponse *,NSError *); __block NSUInteger callbacks=0;
    @autoreleasepool {
        FYLearningAnalyzer *pending=Analyzer(); weakAnalyzer=pending;
        pending.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)) { held=[done copy]; };
        [pending answerConversation:@[] completion:^(NSString *value,NSError *error) { Check(!error,@"held request succeeds after caller drops analyzer"); callbacks++; }];
        pending=nil;
    }
    Check(weakAnalyzer!=nil,@"transport completion preserves original analyzer lease");
    held(Envelope(@"held answer"),Response(),nil); Pump(^BOOL { return callbacks==1; });
    Check(weakAnalyzer!=nil,@"retained transport callback still owns analyzer after completion");
    held=nil; Drain(); Check(weakAnalyzer==nil,@"releasing final transport callback releases analyzer");
}

static void ReentrantCancellationAndParsing(void) {
    FYLearningAnalyzer *a=Analyzer(); NSMutableArray *replies=[NSMutableArray new]; __block NSUInteger cancellations=0; __block NSString *fresh;
    a.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)) { [replies addObject:[done copy]]; };
    [a answerConversation:@[] completion:^(NSString *value,NSError *error) {
        Check(error.code==499,@"cancellation invokes old callback"); cancellations++;
        [a answerConversation:@[] completion:^(NSString *value,NSError *error) { Check(!error,@"new request created inside cancellation survives"); fresh=value; }];
    }];
    [a cancelAll]; Check(replies.count==2 && cancellations==1,@"cancel callback can start a new request");
    void (^old)(NSData *,NSURLResponse *,NSError *)=replies[0], (^next)(NSData *,NSURLResponse *,NSError *)=replies[1];
    old(Envelope(@"stale"),Response(),nil); next(Envelope(@"reentrant"),Response(),nil); Pump(^BOOL { return fresh!=nil; });
    Check([fresh isEqual:@"reentrant"] && cancellations==1,@"old reply cannot replace the reentrant request");
    [replies removeAllObjects]; old=nil; next=nil; a.transport=nil;

    NSArray *content=@[@"{\"schema_version\":true,\"grammar\":[],\"vocabulary\":[]}",
                       @"```json\n{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}\n``` extra"];
    NSArray *codes=@[@211,@210];
    for (NSUInteger i=0;i<content.count;i++) {
        FYLearningAnalyzer *parser=Analyzer(); __block NSError *failure;
        parser.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)) { done(Envelope(content[i]),Response(),nil); };
        [parser analyzeSentence:@"合成原句。" translation:nil completion:^(FYAnalysisResult *result,NSError *error) { Check(!result,@"invalid result is never an empty success"); failure=error; }];
        Pump(^BOOL { return failure!=nil; }); Check(failure.code==[codes[i] integerValue],@"strict schema/fence validation retains error code");
    }
    FYLearningAnalyzer *missing=Analyzer(); missing.apiKey=@""; __block BOOL synchronous=NO;
    [missing answerConversation:@[] completion:^(NSString *answer,NSError *error) { synchronous=YES; Check(error.code==10001,@"missing key keeps its preflight error"); }];
    Check(synchronous && [[missing valueForKey:@"pendingCompletions"] count]==0,@"preflight failure is synchronous and creates no pending request");
}

static void IndependentInstancesAndSourceEvidence(void) {
    FYLearningAnalyzer *a=Analyzer(), *b=Analyzer();
    __block void (^replyA)(NSData *,NSURLResponse *,NSError *), (^replyB)(NSData *,NSURLResponse *,NSError *);
    __block NSUInteger cancelled=0; __block NSString *answer;
    a.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)) { replyA=[done copy]; };
    b.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)) { replyB=[done copy]; };
    [a answerConversation:@[] completion:^(NSString *value,NSError *error) { Check(error.code==499,@"first analyzer cancels independently"); cancelled++; }];
    [b answerConversation:@[] completion:^(NSString *value,NSError *error) { Check(!error,@"second analyzer is unaffected by first cancellation"); answer=value; }];
    [a cancelAll]; replyA(Envelope(@"stale"),Response(),nil); replyB(Envelope(@"independent"),Response(),nil);
    Pump(^BOOL { return answer!=nil; }); Check(cancelled==1 && b.generation==0,@"analyzer instances have separate generations and pending slots");
    a.transport=nil; b.transport=nil; replyA=nil; replyB=nil;

    FYLearningAnalyzer *source=Analyzer(); NSMutableString *text=[@"😀読ん\nだ。" mutableCopy]; __block FYAnalysisResult *result;
    source.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)) { replyA=[done copy]; };
    [source analyzeSentence:text translation:nil completion:^(FYAnalysisResult *value,NSError *error) { Check(!error,@"copied source still validates after caller mutates input"); result=value; }];
    [text setString:@"替换原句"];
    replyA(Envelope(@"{\"schema_version\":1,\"grammar\":[{\"name\":\"测试\",\"matched_text\":\"読んだ\"}],\"vocabulary\":[]}"),Response(),nil);
    Pump(^BOOL { return result!=nil; });
    Check([result.grammar.firstObject.matchedText isEqual:@"読ん\nだ"] && NSEqualRanges(result.grammar.firstObject.matchedRange,NSMakeRange(2,4)),@"parser preserves original newline and UTF-16 range after emoji");
    source.transport=nil; replyA=nil;

    FYGrammarCatalog *catalog=[[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
    Check([catalog loadWithError:NULL],@"load bundled synthetic grammar evidence");
    FYLearningAnalyzer *live=Analyzer(); result=nil;
    live.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)) { replyA=[done copy]; };
    [live analyzeSentence:@"進まざるを得ない。" translation:nil completion:^(FYAnalysisResult *value,NSError *error) { Check(!error,@"response uses current catalog"); result=value; }];
    live.catalog=catalog;
    replyA(Envelope(@"{\"schema_version\":1,\"grammar\":[{\"catalog_id\":\"zaru_wo_enai\",\"name\":\"〜ざるを得ない\",\"matched_text\":\"進まざるを得ない\"}],\"vocabulary\":[]}"),Response(),nil);
    Pump(^BOOL { return result!=nil; }); Check([result.grammar.firstObject.referenceLevel isEqual:@"N2"],@"catalog set during pending request supplies the reference level");
    live.transport=nil; replyA=nil;
}

int main(void) { @autoreleasepool {
    DefaultTaskLifecycle(); IndependentRequestsAndLease(); ReentrantCancellationAndParsing();
    IndependentInstancesAndSourceEvidence();
    NSLog(@"PASS LearningAnalyzerBoundaryTests: %lu checks; mock transport/session only, no UI/network/user data",(unsigned long)checks);
} return 0; }
