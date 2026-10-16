#import "FYLearningCoordinator.h"
#import <objc/runtime.h>

static NSUInteger checks;
static void Check(BOOL ok, NSString *why) { checks++; if (!ok) { NSLog(@"FAIL %@",why); exit(2); } }
static void Pump(BOOL (^done)(void)) {
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && limit.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    Check(done(),@"held external boundary reaches expected state");
}
static NSError *Failure(void) { return [NSError errorWithDomain:@"SyntheticStore" code:71 userInfo:nil]; }

// Only persistence and analyzer boundaries are held. All identity, selection,
// generation, deduplication, merge, queue and example algorithms are production.
@interface HeldWorkflowStore : FYLearningStore
@property(nonatomic, strong) NSMutableArray *cacheReads;
@property(nonatomic, strong) NSMutableArray *sentenceReads;
@property(nonatomic, strong) NSMutableArray *vocabularyReads;
@property(nonatomic, strong) NSMutableArray *writes;
@property(nonatomic, strong) NSMutableArray *examples;
@property(nonatomic, strong) NSMutableArray *savedAnalyses;
@property(nonatomic, copy) void (^appendReply)(NSInteger,NSError *);
@property(nonatomic, copy) void (^writeReply)(NSError *);
@property(nonatomic, copy) NSString *preservedID;
@end
@implementation HeldWorkflowStore
- (instancetype)init { if ((self=[super initWithDatabasePath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]])) {
    _cacheReads=[NSMutableArray new]; _sentenceReads=[NSMutableArray new]; _vocabularyReads=[NSMutableArray new];
    _writes=[NSMutableArray new]; _examples=[NSMutableArray new]; _savedAnalyses=[NSMutableArray new];
} return self; }
- (void)ensureSessionWithID:(NSString *)sid displayName:(NSString *)name language:(NSString *)language completion:(void (^)(NSError *))done { done(nil); }
- (void)insertSentenceWithID:(NSString *)sid sessionID:(NSString *)session kind:(FYSentenceKind)kind originalText:(NSString *)text occurredAt:(NSDate *)date completion:(void (^)(NSError *))done { done(nil); }
- (void)preserveSentenceForHistory:(NSString *)sid completion:(void (^)(NSError *))done { self.preservedID=sid; done(nil); }
- (void)updateTranslation:(NSString *)value forSentence:(NSString *)sid version:(NSInteger)version completion:(void (^)(NSError *))done { done(nil); }
- (void)appendVersionForSentence:(NSString *)sid text:(NSString *)text translation:(NSString *)translation completion:(void (^)(NSInteger,NSError *))done { self.appendReply=done; }
- (void)fetchSentence:(NSString *)sid completion:(void (^)(FYSentenceRecord *,NSError *))done { [self.sentenceReads addObject:[done copy]]; }
- (void)fetchAnalysisForSentence:(NSString *)sid version:(NSInteger)version completion:(void (^)(FYAnalysisResult *,NSString *,NSError *))done { [self.cacheReads addObject:[done copy]]; }
- (void)saveAnalysisResult:(FYAnalysisResult *)result sentenceID:(NSString *)sid version:(NSInteger)version textHash:(NSString *)hash promptVersion:(NSInteger)prompt catalogVersion:(NSInteger)catalog modelConfig:(NSString *)model completion:(void (^)(NSError *))done { [self.savedAnalyses addObject:result]; done(nil); }
- (void)fetchVocabularyListWithCompletion:(void (^)(NSArray<FYVocabularyEntry *> *,NSError *))done { @synchronized (self) { [self.vocabularyReads addObject:[done copy]]; } }
- (void)saveVocabulary:(FYVocabularyEntry *)entry withExample:(FYVocabularyExample *)example completion:(void (^)(NSError *))done { [self.writes addObject:entry]; [self.examples addObject:example ?: NSNull.null]; self.writeReply=done; }
@end
@interface HeldWorkflowAnalyzer : FYLearningAnalyzer
@property(nonatomic, strong) NSMutableArray *replies;
@property(nonatomic) NSUInteger cancellations;
@end
@implementation HeldWorkflowAnalyzer
- (instancetype)init { if ((self=[super init])) _replies=[NSMutableArray new]; return self; }
- (void)cancelAll { self.cancellations++; }
- (void)analyzeSentence:(NSString *)text translation:(NSString *)translation completion:(void (^)(FYAnalysisResult *,NSError *))done { [self.replies addObject:[done copy]]; }
@end
static FYLearningCoordinator *Coordinator(HeldWorkflowStore *s,HeldWorkflowAnalyzer *a) {
    return [[FYLearningCoordinator alloc] initWithStore:s analyzer:a tokenizer:[FYJapaneseTokenizer new] catalog:[[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]]];
}
static FYSentenceRecord *Record(FYRequestIdentity *identity) {
    FYSentenceRecord *r=[FYSentenceRecord new]; r.sentenceID=identity.sentenceID; r.latestVersion=identity.version; r.latestText=identity.sourceText; return r;
}
static FYAnalysisResult *Result(void) { FYAnalysisResult *r=[FYAnalysisResult new]; r.grammar=@[]; r.vocabulary=@[]; r.status=FYAnalysisStatusNoResult; return r; }
static void CacheMiss(HeldWorkflowStore *s,NSUInteger index) { void (^reply)(FYAnalysisResult *,NSString *,NSError *)=s.cacheReads[index]; reply(nil,nil,nil); }

static void PinnedAndVersionedAnalysis(void) {
    HeldWorkflowStore *s=[HeldWorkflowStore new]; HeldWorkflowAnalyzer *a=[HeldWorkflowAnalyzer new]; FYLearningCoordinator *c=Coordinator(s,a);
    FYRequestIdentity *first=[c recordText:@"今日は図書館へ行こう。" kind:FYSentenceKindDialogue]; [c setTranslation:@"合成译文" forIdentity:first]; [c pinCurrent];
    __block NSError *lateError; [c analyzeCurrent:^(FYAnalysisResult *r,NSError *e) { lateError=e; }]; CacheMiss(s,0);
    FYRequestIdentity *next=[c recordText:@"明日は家で休もう。" kind:FYSentenceKindDialogue];
    Check(c.isPinned && c.hasNewerSentence && [c.currentSentenceID isEqual:first.sentenceID] && [c.latestSentenceID isEqual:next.sentenceID],@"new dialogue changes latest identity while pinned reading stays fixed");
    Check([c.currentTranslation isEqual:@"合成译文"] && [s.preservedID isEqual:first.sentenceID],@"pin keeps translation and history protection");
    __block NSError *correctionError; __block BOOL corrected=NO;
    [c correctCurrentSentenceText:@"今日は図書館に行こう。" completion:^(NSError *e) { correctionError=e; corrected=YES; }];
    Check(c.currentVersion==1 && !corrected,@"version remains unchanged until persistence completes");
    s.appendReply(2,nil); s.appendReply=nil;
    Check(corrected && !correctionError && c.currentVersion==2 && !c.currentTranslation,@"successful correction advances version and invalidates translation");
    void (^old)(FYAnalysisResult *,NSError *)=a.replies[0]; old(Result(),nil);
    Check(lateError.code==2 && s.savedAnalyses.count==0,@"late version-one analysis never writes the version-two cache");
    __block FYAnalysisResult *fresh; [c analyzeCurrent:^(FYAnalysisResult *r,NSError *e) { Check(!e,@"current analysis succeeds"); fresh=r; }]; CacheMiss(s,1);
    void (^current)(FYAnalysisResult *,NSError *)=a.replies[1]; current(Result(),nil);
    Check(fresh.version==2 && [fresh.sentenceID isEqual:first.sentenceID] && s.savedAnalyses.count==1,@"fresh result binds exact sentence and corrected version");
    [c followLatestWithCompletion:nil];
    FYRequestIdentity *third=[c recordText:@"次の合成对白です。" kind:FYSentenceKindDialogue];
    void (^follow)(FYSentenceRecord *,NSError *)=s.sentenceReads[0]; follow(Record(next),nil);
    Check(!c.isPinned && [c.currentSentenceID isEqual:third.sentenceID],@"delayed follow fetch cannot replace a newer live sentence");
    [s.cacheReads removeAllObjects]; [s.sentenceReads removeAllObjects]; [a.replies removeAllObjects]; old=nil; current=nil; follow=nil;
}
static void LateCacheAndCorrectionFailure(void) {
    HeldWorkflowStore *s=[HeldWorkflowStore new]; HeldWorkflowAnalyzer *a=[HeldWorkflowAnalyzer new]; FYLearningCoordinator *c=Coordinator(s,a);
    FYRequestIdentity *first=[c recordText:@"最初の合成句です。" kind:FYSentenceKindDialogue];
    __block NSError *stale; [c analyzeCurrent:^(FYAnalysisResult *r,NSError *e) { stale=e; }];
    FYRequestIdentity *next=[c recordText:@"別の合成句です。" kind:FYSentenceKindDialogue]; CacheMiss(s,0);
    Check(stale.code==2 && !a.replies.count,@"late cache miss does not start analysis for old selection");
    __block NSError *failure; [c correctCurrentSentenceText:@"保存失敗の句です。" completion:^(NSError *e) { failure=e; }];
    NSError *expected=Failure(); s.appendReply(0,expected); s.appendReply=nil;
    Check(failure==expected && c.currentVersion==1 && [c.currentSentenceID isEqual:next.sentenceID],@"correction error propagates unchanged and leaves identity intact");
    [c correctCurrentSentenceText:@"遅れて保存する句です。" completion:^(NSError *e) { Check(!e,@"old correction persists successfully"); }];
    [c selectSentenceID:first.sentenceID version:1 sourceText:first.sourceText translation:nil]; s.appendReply(2,nil); s.appendReply=nil;
    Check(c.currentVersion==1 && [c.currentSourceText isEqual:first.sourceText],@"completed correction cannot overwrite a later selection");
    [s.cacheReads removeAllObjects];
}
static FYVocabularyEntry *Vocabulary(NSString *surface) { FYVocabularyEntry *v=[FYVocabularyEntry new]; v.surface=surface; return v; }
static void VocabularyFIFOFailureAndLease(void) {
    HeldWorkflowStore *s=[HeldWorkflowStore new]; HeldWorkflowAnalyzer *a=[HeldWorkflowAnalyzer new];
    __weak FYLearningCoordinator *weakCoordinator; NSMutableArray *order=[NSMutableArray new];
    __block NSString *sourceID; __block NSUInteger callbacks=0;
    FYVocabularyEntry *one=Vocabulary(@"救う"), *two=Vocabulary(@"救う"), *three=Vocabulary(@"別語"); two.lemma=@"救う"; two.reading=@"すくう"; two.meaning=@"拯救"; two.completionSource=FYCompletionSourceAI;
    @autoreleasepool {
        FYLearningCoordinator *c=Coordinator(s,a); weakCoordinator=c;
        FYRequestIdentity *identity=[c recordText:@"仲間を救う。" kind:FYSentenceKindDialogue]; sourceID=identity.sentenceID; [c setTranslation:@"救助伙伴。" forIdentity:identity];
        [c bookmarkVocabulary:one selectedText:@"救う" completion:^(FYVocabularyEntry *saved,BOOL duplicate,NSError *e) { Check(saved==one && !duplicate && !e && NSThread.isMainThread,@"first save preserves entry alias and service callback thread"); [order addObject:@1]; callbacks++; }];
        [c bookmarkVocabulary:two selectedText:@"救う" completion:^(FYVocabularyEntry *saved,BOOL duplicate,NSError *e) { Check(!saved && duplicate && e.code==71,@"failed duplicate transaction returns exact error and duplicate flag"); [order addObject:@2]; callbacks++; }];
        [c bookmarkVocabulary:three selectedText:@"別語" completion:^(FYVocabularyEntry *saved,BOOL duplicate,NSError *e) { Check(saved==three && !duplicate && !e,@"queued save continues after failure"); [order addObject:@3]; callbacks++; }];
        [c recordText:@"新しい句です。" kind:FYSentenceKindDialogue]; c=nil;
    }
    Pump(^BOOL { @synchronized(s) { return s.vocabularyReads.count>=1; } });
    dispatch_sync((dispatch_queue_t)[weakCoordinator valueForKey:@"vocabularyQueue"], ^{});
    Check(s.vocabularyReads.count==1,[NSString stringWithFormat:@"queue admits exactly one held read; actual=%lu",(unsigned long)s.vocabularyReads.count]);
    Check(weakCoordinator!=nil && !s.writes.count,@"queued operation strongly leases facade and does not bypass held read");
    void (^read)(NSArray *,NSError *)=s.vocabularyReads[0]; read(@[],nil); read=nil;
    FYVocabularyExample *example=s.examples[0];
    Check([example.sentenceID isEqual:sourceID] && example.version==1 && [example.sourceTextSnapshot isEqual:@"仲間を救う。"] && [example.translationSnapshot isEqual:@"救助伙伴。"],@"example uses provenance captured before asynchronous work");
    Check(s.vocabularyReads.count==1 && s.writes.count==1,@"second save waits for first transaction completion");
    s.writeReply(nil); s.writeReply=nil; Pump(^BOOL { return s.vocabularyReads.count==2; });
    read=s.vocabularyReads[1]; read(@[one],nil); read=nil;
    Check(s.writes[1]==one && [one.reading isEqual:@"すくう"] && [one.meaning isEqual:@"拯救"] && one.completionSource==FYCompletionSourceAI,@"dedup and completion merge run on real coordinator");
    s.writeReply(Failure()); s.writeReply=nil; Pump(^BOOL { return s.vocabularyReads.count==3; });
    read=s.vocabularyReads[2]; read(@[one],nil); read=nil; s.writeReply(nil); s.writeReply=nil;
    Pump(^BOOL { return callbacks==3; }); Check([order isEqual:@[@1,@2,@3]],@"callbacks keep FIFO across success, failure and continuation");
    [s.vocabularyReads removeAllObjects];
    Pump(^BOOL { return weakCoordinator==nil; }); Check(weakCoordinator==nil,@"finished queue releases facade after external callbacks are released");
}
static void AnalysisTaskLease(void) {
    HeldWorkflowStore *s=[HeldWorkflowStore new]; HeldWorkflowAnalyzer *a=[HeldWorkflowAnalyzer new]; __weak FYLearningCoordinator *weak; __block NSUInteger completed=0;
    @autoreleasepool { FYLearningCoordinator *c=Coordinator(s,a); weak=c; [c recordText:@"合成寿命测试。" kind:FYSentenceKindDialogue];
        [c analyzeCurrent:^(FYAnalysisResult *r,NSError *e) { Check(!e && r!=nil,@"held analysis succeeds after caller releases facade"); completed++; }]; c=nil; }
    Check(weak!=nil,@"cache lookup keeps original facade task lease"); CacheMiss(s,0); [s.cacheReads removeAllObjects];
    Check(weak!=nil,@"analysis completion continues facade task lease");
    void (^reply)(FYAnalysisResult *,NSError *)=a.replies[0]; reply(Result(),nil); reply=nil; [a.replies removeAllObjects];
    Pump(^BOOL { return weak==nil; }); Check(completed==1 && weak==nil,@"completion and final callback release the leased facade");
}
static void SoleStateOwners(void) {
    HeldWorkflowStore *s=[HeldWorkflowStore new]; HeldWorkflowAnalyzer *a=[HeldWorkflowAnalyzer new]; FYLearningCoordinator *c=Coordinator(s,a);
    NSDictionary *groups=@{@"sentenceWorkflow":@[@"learningEnabled",@"japaneseMode",@"sessionID",@"lastText",@"lastKind",@"lastIdentity",@"lastDialogueKey",@"lastDialogueIdentity",@"lastDialogueExcludedSpeakerKeys",@"recordsSinceLastDialogue",@"lastItemTexts",@"lastItemIdentities",@"lastItemKind",@"isPinned",@"currentSentenceID",@"currentVersion",@"currentSourceText",@"currentTranslation",@"latestSentenceID",@"selectionGeneration"],
        @"analysisWorkflow":@[@"analysisGeneration",@"reviewAnalyzer"],@"collectionWorkflow":@[@"vocabularyQueue",@"vocabularyOperations"]};
    for (NSString *name in groups) {
        id owner=[c valueForKey:name]; Check(owner!=nil,@"workflow owner is initialized without touching persistent store");
        for (NSString *field in groups[name]) {
            NSString *ivar=[@"_" stringByAppendingString:field];
            Check(!class_getInstanceVariable(FYLearningCoordinator.class,ivar.UTF8String) && class_getInstanceVariable([owner class],ivar.UTF8String),[field stringByAppendingString:@" has exactly one actual state owner"]);
            id value=[owner valueForKey:field];
            Check([c valueForKey:field]==value || [[c valueForKey:field] isEqual:value] || (![c valueForKey:field] && !value),[field stringByAppendingString:@" cold compatibility getter reaches owner"]);
        }
    }
    id sentence=[c valueForKey:@"sentenceWorkflow"], analysis=[c valueForKey:@"analysisWorkflow"], collection=[c valueForKey:@"collectionWorkflow"];
    NSMutableString *text=[NSMutableString stringWithString:@"原copy文本"];
    [c setValue:text forKey:@"currentSourceText"]; [text appendString:@"changed"];
    Check([[sentence valueForKey:@"currentSourceText"] isEqual:@"原copy文本"],@"facade setter preserves source copy ownership");
    [sentence setValue:@"owner-current" forKey:@"currentSentenceID"];
    Check([c.currentSentenceID isEqual:@"owner-current"],@"owner writes are visible through old public getter");
    [c setValue:@9 forKey:@"analysisGeneration"]; Check([[analysis valueForKey:@"analysisGeneration"] integerValue]==9,@"analysis generation forwards to its sole owner");
    NSMutableArray *operations=[NSMutableArray new]; [c setValue:operations forKey:@"vocabularyOperations"];
    Check([collection valueForKey:@"vocabularyOperations"]==operations,@"queue operation list keeps original strong alias");
}
int main(void) { @autoreleasepool { PinnedAndVersionedAnalysis(); LateCacheAndCorrectionFailure(); VocabularyFIFOFailureAndLease(); AnalysisTaskLease(); SoleStateOwners(); NSLog(@"PASS LearningWorkflowBoundaryTests %lu checks",(unsigned long)checks); } return 0; }
