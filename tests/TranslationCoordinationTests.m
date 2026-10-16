#import "FYInlineTranslationCoordinator.h"
#import "FYTranslationRequestCoordinator.h"
#import "FYTranslationManager.h"

static NSUInteger checks;
static void Check(BOOL value, const char *message) { checks++; if (!value) { fprintf(stderr,"FAIL: %s\n",message); exit(2); } }
static void Pump(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && deadline.timeIntervalSinceNow > 0) { @autoreleasepool { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]]; } }
    Check(done(), "bounded async delivery completes");
}
@interface TestItem : NSObject
@property(copy) NSString *key;
@property BOOL longText;
@end
@implementation TestItem @end
static id Item(NSString *key, BOOL longText) { TestItem *item=[TestItem new];item.key=key;item.longText=longText;return item; }

@interface TestTask : NSObject
@property NSUInteger cancels;
@property NSUInteger resumes;
@property(copy) void (^response)(NSString *, NSError *);
- (void)cancel;
- (void)resume;
@end
@implementation TestTask
- (void)cancel { self.cancels++; }
- (void)resume { self.resumes++; }
@end
@interface BatchTransport : NSObject <FYInlineBatchTransport>
@property(strong) FYContentTranslationState *state;
@property(strong) NSMutableArray *batches;
@property(strong) NSMutableArray *outputs;
@property(strong) NSMutableArray *replies;
@property(strong) TestTask *task;
@property NSUInteger retainedRoutes;
@end
@implementation BatchTransport
- (instancetype)init { if ((self=[super init])) { _state=[FYContentTranslationState new]; _batches=[NSMutableArray new];_outputs=[NSMutableArray new];_replies=[NSMutableArray new];_task=[TestTask new]; } return self; }
- (FYContentTranslationSnapshot *)contentSnapshot { return [self.state snapshot]; }
- (void)submitBatch:(FYInlineTranslationBatch *)batch translations:(NSMutableArray<NSString *> *)translations completion:(void (^)(NSError *))completion {
    [self.batches addObject:batch];[self.outputs addObject:translations];[self.replies addObject:[completion copy]];
}
- (void)submitRetainedLongBatch:(FYInlineTranslationBatch *)batch translations:(NSMutableArray<NSString *> *)translations completion:(void (^)(NSError *))completion {
    self.retainedRoutes++;[self submitBatch:batch translations:translations completion:completion];
}
- (NSURLSessionDataTask *)activeTask { return (id)self.task; }
@end
@interface RequestTransport : NSObject <FYTranslationRequestTransport>
@property(strong) NSMutableArray<TestTask *> *tasks;
@end
@implementation RequestTransport
- (instancetype)init { if ((self=[super init])) _tasks=[NSMutableArray new];return self; }
- (NSURLSessionDataTask *)taskWithRequest:(NSURLRequest *)request observer:(void (^)(NSURLResponse *, NSError *))observer completion:(void (^)(NSString *, NSError *))completion {
    TestTask *task=[TestTask new];task.response=^(NSString *value,NSError *error){observer(nil,error);completion(value,error);};[self.tasks addObject:task];return (id)task;
}
@end
@interface LeaseState : NSObject
@property NSInteger generation;
@property NSUInteger revision;
@end
@implementation LeaseState @end
static FYTranslationRequestLease *Lease(LeaseState *state,FYTranslationRequestScope scope) {
    FYTranslationRequestIdentity *identity=[[FYTranslationRequestIdentity alloc] initWithScope:scope generation:state.generation revision:state.revision];
    return [[FYTranslationRequestLease alloc] initWithIdentity:identity generation:^NSInteger{return state.generation;} revision:^NSUInteger{return state.revision;}];
}
static FYTranslationConfiguration *Config(NSString *url,NSString *model,NSString *key) {
    return [[FYTranslationConfiguration alloc] initWithBaseURL:url model:model learningModel:@"different-learning-model" apiKey:key];
}
static FYPreparedTranslationRequest *Prepare(FYTranslationConfiguration *config,NSString *override,BOOL longText,NSString *(^prompt)(void)) {
    return [FYPreparedTranslationRequest prepareText:@"fictional input" configuration:config systemPrompt:nil defaultPrompt:prompt maxTokens:240 modelOverride:override longText:longText];
}

int main(void) { @autoreleasepool {
    FYInlineTranslationCoordinator *cache=[FYInlineTranslationCoordinator new];
    Check(cache.cache && !cache.cache.entries && !cache.pendingLongBatch && !cache.dialogueCache && cache.serial==0,"cold cache coordinator has no work, receiver, timer or transport");
    cache.cache.entries=[NSMutableDictionary dictionaryWithDictionary:@{@"cached":@"cached translation"}];
    NSArray *items=@[Item(@"cached",NO),Item(@"long-a",YES),Item(@"short",NO),Item(@"long-a",YES)];
    NSMutableArray *events=[NSMutableArray new];
    NSString *(^key)(OCRTextItem *)=^NSString *(OCRTextItem *item){TestItem *value=(id)item;[events addObject:[@"key:" stringByAppendingString:value.key]];return value.key;};
    BOOL (^isLong)(OCRTextItem *)=^BOOL(OCRTextItem *item){return ((TestItem *)(id)item).longText;};
    FYInlineTranslationPlan *plan=[FYInlineTranslationPlan planForItems:items cache:cache.cache.entries key:key isLong:isLong observer:^(NSUInteger i,BOOL hit){[events addObject:[NSString stringWithFormat:@"observe:%lu:%d",(unsigned long)i,hit]];}];
    Check([events isEqual:@[@"key:cached",@"observe:0:1",@"key:long-a",@"observe:1:0",@"key:short",@"observe:2:0",@"key:long-a",@"observe:3:0"]],"key and cache observation retain original per-item ordering");
    Check(plan.pendingCount==3 && [plan.cachedValues isEqual:@[@"cached translation",@"",@"",@""]],"plan preserves cache hits and exact output slots");
    Check([plan.shortBatch.indexes isEqual:@[@2]] && [plan.longBatch.indexes isEqual:@[@1,@3]] && plan.longBatch.items[0]==items[1],"partition keeps original indexes, repeated fields and observation identities");
    Check(![plan respondsToSelector:NSSelectorFromString(@"setCachedValues:")] && ![plan.longBatch respondsToSelector:NSSelectorFromString(@"setKeys:")],"plan and batch expose immutable interfaces");
    BatchTransport *transport=[BatchTransport new];
    __block NSUInteger complete=0;
    [cache translateItems:items key:key isLong:isLong observer:nil transport:transport completion:^(NSArray *values,NSError *error){Check(!error && values.count==4,"all routes finish before complete output delivery");complete++;}];
    Check(transport.batches.count==2 && !((FYInlineTranslationBatch *)transport.batches[0]).longText && ((FYInlineTranslationBatch *)transport.batches[1]).longText,"short and long requests remain independent and launch in original order");
    void (^shortDone)(NSError *)=transport.replies[0],(^longDone)(NSError *)=transport.replies[1];
    longDone(nil);Check(complete==0,"long completion alone cannot deliver an unfinished short plan");shortDone(nil);Check(complete==1,"both routes produce exactly one complete delivery");[transport.replies removeAllObjects];

    // A long response is aligned by key and occurrence, never old output index.
    transport=[BatchTransport new]; cache=[FYInlineTranslationCoordinator new];
    NSArray *longItems=@[Item(@"dup",YES),Item(@"dup",YES),Item(@"other",YES)];
    FYInlineTranslationBatch *first=[[FYInlineTranslationBatch alloc] initWithItems:longItems indexes:@[@0,@1,@2] keys:@[@"dup",@"dup",@"other"] longText:YES];
    NSMutableArray *oldOutput=[@[@"",@"",@""] mutableCopy],*newOutput=[@[@"",@"",@""] mutableCopy];
    __block NSUInteger oldDone=0,newDone=0;
    [cache translateRetainedLongBatch:first translations:oldOutput transport:transport completion:^(NSError *error){Check(!error,"long transport succeeds");oldDone++;}];
    FYInlineTranslationBatch *reordered=[[FYInlineTranslationBatch alloc] initWithItems:longItems indexes:@[@0,@1,@2] keys:@[@"other",@"dup",@"dup"] longText:YES];
    [cache translateRetainedLongBatch:reordered translations:newOutput transport:transport completion:^(NSError *error){Check(!error,"retained plan succeeds");newDone++;}];
    Check(transport.batches.count==1 && cache.pendingLongBatch.completions.count==2 && cache.pendingLongBatch.task==(id)transport.task,"same long key multiset retains one HTTP task and multiple current plan completions");
    NSMutableArray *values=transport.outputs[0];[values setArray:@[@"first occurrence",@"second occurrence",@"other result"]];
    void (^reply)(NSError *)=transport.replies[0];reply(nil);[transport.replies removeAllObjects];reply=nil;
    Check(oldDone==1 && newDone==1 && [newOutput isEqual:@[@"other result",@"first occurrence",@"second occurrence"]],"reordered repeated keys align by original occurrence");
    Check(!cache.pendingLongBatch,"successful long delivery clears the active batch");
    FYContentTranslationState *content=[FYContentTranslationState new];
    __block NSUInteger keyReads=0;
    BOOL (^retain)(void)=^BOOL {
        return [cache retainsLongBatchForContent:[content snapshot] newKeys:^NSArray *{keyReads++;return @[@"dup",@"dup",@"other"];}
            existingKeys:^NSArray *{keyReads++;return @[@"dup",@"dup",@"other"];}];
    };
    Check(!retain() && keyReads==0,"absence of a long transport skips source-key dependencies");
    [cache translateRetainedLongBatch:first translations:oldOutput transport:transport completion:^(NSError *error){oldDone++;}];
    [content beginText:@"synthetic" mode:FYContentModeUI]; content.items=(id)longItems;
    Check(retain() && keyReads==2,"UI content with unchanged long key multiplicity retains its active transport");
    content.mode=FYContentModeDialogue;
    Check(!retain() && keyReads==2,"dialogue mode does not read retained UI keys");
    content.mode=FYContentModeUI;
    Check(![cache retainsLongBatchForContent:[content snapshot] newKeys:^NSArray *{return @[@"dup",@"other"];}
        existingKeys:^NSArray *{return @[@"dup",@"dup",@"other"];}],"a changed occurrence count cannot retain a long batch");
    FYInlinePendingLongBatch *obsolete=cache.pendingLongBatch;[cache discardPendingLongBatch];
    Check(obsolete.completions.count==0 && !obsolete.task && !cache.pendingLongBatch,"discard releases callbacks and task before clearing batch identity");
    reply=transport.replies.lastObject;reply([NSError errorWithDomain:@"fixture" code:1 userInfo:nil]);[transport.replies removeAllObjects];reply=nil;
    Check(oldDone==1,"discarded late long error cannot notify or overwrite a new plan");
    __block NSUInteger failures=0;
    [cache translateRetainedLongBatch:first translations:oldOutput transport:transport completion:^(NSError *error){Check(error.code==9,"current long error is preserved");failures++;}];
    reply=transport.replies.lastObject;reply([NSError errorWithDomain:@"fixture" code:9 userInfo:nil]);[transport.replies removeAllObjects];reply=nil;
    Check(failures==1 && !cache.pendingLongBatch,"failed long request releases its batch identity for retry");
    NSUInteger submits=transport.batches.count;
    [cache translateRetainedLongBatch:first translations:oldOutput transport:transport completion:^(NSError *error){}];
    Check(transport.batches.count==submits+1,"failure is not a reusable pending or cached long result");
    [cache discardPendingLongBatch];[transport.replies removeAllObjects];
    NSMutableArray *out=[@[@""] mutableCopy];
    FYInlineTranslationBatch *shortPlan=[[FYInlineTranslationBatch alloc] initWithItems:(id)@[Item(@"short",NO)] indexes:@[@0] keys:@[@"short"] longText:NO];
    [cache advanceSerial];__block NSError *stale=nil;__block NSUInteger parses=0,writes=0;
    [cache applyText:@"1. fixture" error:nil batch:shortPlan translations:out submittedSerial:0 parse:^NSArray *(NSString *text,NSUInteger count){parses++;return @[@"value"];} cache:^(NSString *value,NSString *key){writes++;} completion:^(NSError *error){stale=error;}];
    Check(stale.code==NSURLErrorCancelled && parses==0 && writes==0 && [out[0] isEqual:@""],"old short serial cannot parse, cache or write the current output");

    __block NSUInteger prompts=0;
    NSString *(^prompt)(void)=^NSString *{prompts++;return @"synthetic prompt";};
    FYPreparedTranslationRequest *prepared=Prepare(Config(@"not a url",@"",@""),nil,NO,prompt);
    Check(prepared.error.code==401 && [prepared.failureReason isEqual:@"missing_configuration"] && prompts==0,"credential validation precedes URL/model/prompt and starts no work");
    prepared=Prepare(Config(@"ftp://example.invalid",@"",@"synthetic-key"),nil,NO,prompt);
    Check(prepared.error.code==400 && prepared.error.userInfo[NSUnderlyingErrorKey] && [prepared.failureReason isEqual:@"invalid_configuration"] && prompts==0,"URL error retains its underlying reason before model validation");
    prepared=Prepare(Config(@"https://example.invalid/v1",@"",@"synthetic-key"),nil,NO,prompt);
    Check(prepared.error.code==400 && !prepared.failureReason && prompts==0,"blank model keeps its original error and no extra diagnostic reason");
    prepared=Prepare(Config(@"https://example.invalid/v1",@"translation-model",@" synthetic-key "),@" override-model ",NO,prompt);
    NSDictionary *body=[NSJSONSerialization JSONObjectWithData:prepared.request.HTTPBody options:0 error:NULL];
    Check(prepared.request && !prepared.error && [body[@"model"] isEqual:@"override-model"] && prompts==1 && prepared.request.timeoutInterval==15,"valid plan preserves override, lazy prompt and normal timeout");
    NSURLRequest *escaped = prepared.request;
    if ([escaped isKindOfClass:NSMutableURLRequest.class]) { [(NSMutableURLRequest *)escaped setHTTPMethod:@"PATCH"]; }
    Check([prepared.request.HTTPMethod isEqual:@"POST"] && ![prepared respondsToSelector:NSSelectorFromString(@"setRequest:")],
          "external request mutation cannot change the immutable preparation");
    FYPreparedTranslationRequest *longPrepared=Prepare(Config(@"https://example.invalid/v1",@"translation-model",@"synthetic-key"),nil,YES,prompt);
    Check(longPrepared.request.timeoutInterval>=60 && longPrepared.request.timeoutInterval<=90,"explicit long text retains original extended wait policy");
    RequestTransport *network=[RequestTransport new];FYTranslationRequestCoordinator *requests=[[FYTranslationRequestCoordinator alloc] initWithTransport:network];
    Check(!requests.realtimeTaskOwner && network.tasks.count==0,"cold request construction starts no network or task collection");
    FYTranslationTaskOwner *owner=[FYTranslationTaskOwner new],*service=[FYTranslationTaskOwner new];requests.realtimeTaskOwner=owner;
    LeaseState *state=[LeaseState new];state.generation=4;state.revision=1;
    __block NSUInteger delivered=0,received=0,dropped=0,observed=0,started=0;
    void (^send)(FYTranslationTaskOwner *,FYTranslationRequestScope)=^(FYTranslationTaskOwner *taskOwner,FYTranslationRequestScope scope){
        [requests submit:prepared owner:taskOwner lease:Lease(state,scope) observer:^(NSURLResponse *response,NSError *error){observed++;} received:^(NSString *value,NSError *error){received++;} willResume:^{Check(taskOwner.activeTask!=nil,"task is registered before native submit observation");started++;} completion:^(NSString *value,NSError *error){Check(NSThread.isMainThread,"accepted callback stays on main");delivered++;} dropped:^(FYTranslationRequestDrop reason){dropped++;}];
    };
    send(owner,FYTranslationRequestRealtime);TestTask *old=network.tasks.lastObject;
    state.revision=2;send(owner,FYTranslationRequestRealtime);TestTask *current=network.tasks.lastObject;
    send(service,FYTranslationRequestServiceTest);TestTask *serviceTask=network.tasks.lastObject;
    Check(started==3 && old.resumes==1 && current.resumes==1 && serviceTask.resumes==1,"every scope registers and resumes exactly once");
    old.response(@"old",nil);old.response=nil;Pump(^BOOL{return dropped==1;});
    Check(owner.activeTask==(id)current && received==1 && observed==1 && delivered==0,"old content finishes its own task without releasing or delivering the newer task");
    [owner cancelActiveTask];Check(current.cancels==1 && serviceTask.cancels==0 && service.activeTask==(id)serviceTask,"realtime cancellation is isolated from service testing");
    state.revision=3;serviceTask.response(@"service",nil);serviceTask.response=nil;Pump(^BOOL{return delivered==1;});
    Check(!service.activeTask,"service reply ignores unrelated content revision and finishes its own owner");
    state.generation++;current.response(@"late",nil);current.response=nil;Pump(^BOOL{return dropped==2;});
    Check(delivered==1,"cancelled old-generation response cannot reach the application callback");
    __weak LeaseState *kept;
    FYTranslationRequestLease *lease;
    @autoreleasepool { LeaseState *temporary=[LeaseState new];kept=temporary;lease=Lease(temporary,FYTranslationRequestRealtime); }
    Check(lease.currentGeneration==0 && kept!=nil,"operation lease retains its original primitive-state receiver");lease=nil;
    Check(!kept,"releasing the completed operation lease releases the receiver");
    printf("PASS TranslationCoordinationTests: %lu checks; immutable plans, cache/batches, task scopes, stale responses and bounded leases\n",(unsigned long)checks);
} return 0; }
