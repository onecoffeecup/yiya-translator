#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "presentation/FYQuickSentenceCoordinator.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface QuickFieldFact : NSObject
@property(nonatomic,copy) NSString *value;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) NSMutableArray *events;
- (NSString *)stringValue;
- (void)setStringValue:(NSString *)value;
@end
@implementation QuickFieldFact
- (NSString *)stringValue{[self.events addObject:self.name];return self.value;}
- (void)setStringValue:(NSString *)value{self.value=value;[self.events addObject:@"status"];}
@end
@interface QuickButtonFact : NSObject
@property(nonatomic,getter=isEnabled) BOOL enabled;
@property(nonatomic,strong) NSMutableArray *events;
@end
@implementation QuickButtonFact
@synthesize enabled=_enabled;
- (void)setEnabled:(BOOL)value{_enabled=value;[self.events addObject:value?@"enable":@"disable"];}
@end
@interface QuickAnalyzerBoundary : FYLearningAnalyzer
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) NSMutableArray *replies;
@property(nonatomic,copy) NSString *name;
@property(nonatomic) NSUInteger cancels;
@property(nonatomic,weak) NSString *requestedSource;
@property(nonatomic,weak) NSString *requestedTranslation;
@property(nonatomic,copy) void(^onCancel)(void);
@end
@implementation QuickAnalyzerBoundary
- (instancetype)init{if((self=[super init]))_replies=[NSMutableArray new];return self;}
- (void)setBaseURL:(NSString *)value{[self.events addObject:@"base-set"];[super setBaseURL:value];}
- (void)setApiKey:(NSString *)value{[self.events addObject:@"key-set"];[super setApiKey:value];}
- (void)setModel:(NSString *)value{[self.events addObject:@"model-set"];[super setModel:value];}
- (void)setCatalog:(FYGrammarCatalog *)catalog{[self.events addObject:@"catalog-set"];[super setCatalog:catalog];}
- (void)cancelAll{self.cancels++;[self.events addObject:self.name ?: @"analysis-cancel"];if(self.onCancel)self.onCancel();}
- (void)analyzeSentence:(NSString *)source translation:(NSString *)translation completion:(void(^)(FYAnalysisResult *,NSError *))completion{self.requestedSource=source;self.requestedTranslation=translation;[self.events addObject:@"analyze"];[self.replies addObject:[completion copy]];}
@end
@interface QuickStoreBoundary : NSObject
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) NSMutableArray *toggles,*fetches,*writes;
@property(nonatomic,strong) FYRequestIdentity *lastIdentity;
@property(nonatomic,strong) FYGrammarBookmark *added;
@property(nonatomic,copy) NSString *deleted;
@property(nonatomic) NSUInteger toggleCalls,fetchCalls,addCalls,deleteCalls;
- (void)toggleSentenceBookmark:(FYRequestIdentity *)identity completion:(void(^)(BOOL,NSError *))completion;
- (void)fetchGrammarBookmarksWithCompletion:(void(^)(NSArray *,NSError *))completion;
- (void)addGrammarBookmark:(FYGrammarBookmark *)bookmark completion:(void(^)(NSError *))completion;
- (void)deleteGrammarBookmark:(NSString *)bookmarkID completion:(void(^)(NSError *))completion;
@end
@implementation QuickStoreBoundary
- (instancetype)init{if((self=[super init])){_toggles=[NSMutableArray new];_fetches=[NSMutableArray new];_writes=[NSMutableArray new];}return self;}
- (void)toggleSentenceBookmark:(FYRequestIdentity *)identity completion:(void(^)(BOOL,NSError *))completion{self.toggleCalls++;self.lastIdentity=identity;[self.events addObject:@"toggle"];[self.toggles addObject:[completion copy]];}
- (void)fetchGrammarBookmarksWithCompletion:(void(^)(NSArray *,NSError *))completion{self.fetchCalls++;[self.events addObject:@"fetch"];[self.fetches addObject:[completion copy]];}
- (void)addGrammarBookmark:(FYGrammarBookmark *)bookmark completion:(void(^)(NSError *))completion{self.addCalls++;self.added=bookmark;[self.events addObject:@"add"];[self.writes addObject:[completion copy]];}
- (void)deleteGrammarBookmark:(NSString *)bookmarkID completion:(void(^)(NSError *))completion{self.deleteCalls++;self.deleted=bookmarkID;[self.events addObject:@"delete"];[self.writes addObject:[completion copy]];}
@end
@interface QuickSentenceFacts : NSObject
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) QuickStoreBoundary *store;
@property(nonatomic,strong) QuickAnalyzerBoundary *analyzer,*detailAnalyzer,*otherAnalyzer;
@property(nonatomic,strong) FYGrammarActionState *actions;
@property(nonatomic,strong) FYGrammarCatalog *catalog;
@property(nonatomic,strong) QuickFieldFact *base,*key,*model,*fallbackModel,*status;
@property(nonatomic,strong) QuickButtonFact *button;
@property(nonatomic) BOOL requested;
@property(nonatomic,strong) NSString *source,*translation,*sentenceID;
@property(nonatomic) NSInteger version,index;
@property(nonatomic,copy) NSArray *saved,*bookmarks;
@property(nonatomic) NSUInteger renders,savedRefreshes,grammarRefreshes,buttonUpdates;
@end
@implementation QuickSentenceFacts
- (instancetype)init{if((self=[super init])){_events=[NSMutableArray new];_store=[QuickStoreBoundary new];_store.events=_events;_analyzer=[QuickAnalyzerBoundary new];_analyzer.events=_events;_analyzer.name=@"analysis-cancel";_detailAnalyzer=[QuickAnalyzerBoundary new];_detailAnalyzer.events=_events;_detailAnalyzer.name=@"detail-cancel";_otherAnalyzer=[QuickAnalyzerBoundary new];_otherAnalyzer.name=@"other-cancel";_actions=[FYGrammarActionState new];_actions.analyzer=_detailAnalyzer;_catalog=[FYGrammarCatalog new];NSMutableArray *fields=[NSMutableArray new];for(NSString*n in @[@"base-get",@"key-get",@"model-get",@"fallback-model-get",@"status-get"]){QuickFieldFact*f=[QuickFieldFact new];f.name=n;f.events=_events;[fields addObject:f];}_base=fields[0];_key=fields[1];_model=fields[2];_fallbackModel=fields[3];_status=fields[4];_base.value=@"https://synthetic.invalid/v1";_key.value=@"synthetic-only-key";_model.value=@" learning-model \n";_fallbackModel.value=@" raw-fallback ";_status.value=@"unchanged";_button=[QuickButtonFact new];_button.events=_events;_button.enabled=YES;_source=@"合成原句";_translation=@"合成译文";_sentenceID=@"sentence";_version=4;_saved=@[];_bookmarks=@[];[_events removeAllObjects];}return self;}
@end
@protocol QuickSentenceDriver <NSObject>
@property(nonatomic) NSInteger quickAnalysisGeneration;
@property(nonatomic) BOOL quickSentenceAnalyzing;
@property(nonatomic,strong) FYAnalysisResult *quickSentenceAnalysis;
@property(nonatomic,copy) NSString *quickSentenceAnalysisError;
@property(nonatomic,copy) NSString *quickSentenceAnalysisSource;
@property(nonatomic,copy) NSString *quickSentenceAnalysisTranslation;
@property(nonatomic,strong) FYLearningAnalyzer *quickSentenceAnalyzer;
@property(nonatomic) BOOL sentenceBookmarkPending;
@property(nonatomic) BOOL quickGrammarBookmarkPending;
- (void)cancelQuickSentenceAnalysis;
- (void)analyzeQuickSentence:(id)sender;
- (BOOL)quickSentenceIsBookmarked;
- (void)bookmarkQuickSentence:(id)sender;
- (FYGrammarBookmark *)quickGrammarBookmark;
- (void)bookmarkQuickGrammar:(id)sender;
@end
typedef id<QuickSentenceDriver>(^QuickDriverFactory)(QuickSentenceFacts *facts);
static FYGrammarItem *Item(NSString*name){FYGrammarItem*i=[FYGrammarItem new];i.name=name;i.catalogID=@"catalog";return i;}
static FYAnalysisResult *Result(NSArray*items){FYAnalysisResult*r=[FYAnalysisResult new];r.grammar=items;return r;}
static NSError *Failure(void){return [NSError errorWithDomain:@"synthetic" code:4 userInfo:@{NSLocalizedDescriptionKey:@"合成错误"}];}
static FYGrammarBookmark *Bookmark(NSString*ID,NSInteger version,NSString*name,NSString*bookmarkID){FYGrammarBookmark*b=[FYGrammarBookmark new];b.sentenceID=ID;b.version=version;b.name=name;b.bookmarkID=bookmarkID;return b;}
static void Analyze(QuickSentenceFacts*f,FYAnalysisResult*r,NSError*e){Check(f.analyzer.replies.count>0,@"held original analysis completion exists");void(^reply)(FYAnalysisResult*,NSError*)=f.analyzer.replies.firstObject;[f.analyzer.replies removeObjectAtIndex:0];reply(r,e);}
static void Toggle(QuickSentenceFacts*f,BOOL saved,NSError*e){Check(f.store.toggles.count>0,@"held sentence toggle completion exists");void(^reply)(BOOL,NSError*)=f.store.toggles.firstObject;[f.store.toggles removeObjectAtIndex:0];reply(saved,e);}
static void Fetch(QuickSentenceFacts*f,NSArray*bookmarks,NSError*e){Check(f.store.fetches.count>0,@"held grammar fetch completion exists");void(^reply)(NSArray*,NSError*)=f.store.fetches.firstObject;[f.store.fetches removeObjectAtIndex:0];reply(bookmarks,e);}
static void Write(QuickSentenceFacts*f,NSError*e){Check(f.store.writes.count>0,@"held original grammar write completion exists");void(^reply)(NSError*)=f.store.writes.firstObject;[f.store.writes removeObjectAtIndex:0];reply(e);}
static void RunQuickSentenceFixture(id<QuickSentenceDriver>d,QuickSentenceFacts*f){
 void**app=dlsym(RTLD_DEFAULT,"NSApp");Check(!app||!*app,@"cold quick workflow initializes no UI/device/database");Check(!d.quickAnalysisGeneration&&!d.quickSentenceAnalyzing&&!d.quickSentenceAnalyzer&&!d.quickSentenceAnalysis&&!d.sentenceBookmarkPending&&!d.quickGrammarBookmarkPending,@"original nine state defaults remain empty/zero");
 [d analyzeQuickSentence:nil];Check(f.events.count==0&&!d.quickSentenceAnalyzer,@"unrequested analysis returns without lazy analyzer/config or cancel");f.requested=YES;f.source=@"";[d analyzeQuickSentence:nil];Check(f.events.count==0&&!d.quickAnalysisGeneration,@"empty requested source returns before cancellation");f.source=@"合成原句";d.quickSentenceAnalyzing=YES;[d analyzeQuickSentence:nil];Check(f.events.count==0&&!d.quickSentenceAnalyzer,@"busy analysis rejects duplicate before config/factory");d.quickSentenceAnalyzing=NO;
 d.quickSentenceAnalyzer=f.analyzer;FYGrammarItem*a=Item(@"条目甲"),*b=Item(@"条目乙");FYAnalysisResult*r=Result(@[a,b]);f.actions.expandedItem=a;[f.actions.explanations setObject:@"cached" forKey:a];[f.actions.pending addObject:a];f.actions.reviewing=YES;f.actions.reviewStatus=@"review";NSInteger before=d.quickAnalysisGeneration;NSUInteger actionGeneration=f.actions.generation;__weak id<QuickSentenceDriver> weakD=d;
 f.detailAnalyzer.onCancel=^{Check(weakD.quickAnalysisGeneration==before&&weakD.quickSentenceAnalyzing,@"detail reset happens before quick generation/busy changes");};f.analyzer.onCancel=^{Check(weakD.quickAnalysisGeneration==before+1&&!weakD.quickSentenceAnalyzing,@"quick analyzer cancel observes incremented generation and cleared busy");};d.quickSentenceAnalyzing=YES;[d cancelQuickSentenceAnalysis];f.detailAnalyzer.onCancel=nil;f.analyzer.onCancel=nil;Check(f.actions.generation==actionGeneration+1&&!f.actions.expandedItem&&!f.actions.pending.count&&!f.actions.explanations.count&&!f.actions.reviewing&&!f.actions.reviewStatus,@"cancel runs actual ActionState.reset rather than clearing a copied cache");Check([f.events isEqual:@[@"detail-cancel",@"analysis-cancel"]]&&f.otherAnalyzer.cancels==0,@"only quick detail and quick analysis scopes are cancelled in original order");
 d.quickSentenceAnalysis=r;d.quickSentenceAnalysisError=@"old error";f.index=1;[f.events removeAllObjects];[d analyzeQuickSentence:nil];Check(d.quickSentenceAnalyzing&&!d.quickSentenceAnalysis&&!d.quickSentenceAnalysisError&&f.index==0&&[d.quickSentenceAnalysisSource isEqual:f.source]&&[d.quickSentenceAnalysisTranslation isEqual:f.translation],@"analysis clears old result/error/index then snapshots source/translation before new work");Check([f.events isEqual:@[@"detail-cancel",@"analysis-cancel",@"base-get",@"base-set",@"key-get",@"key-set",@"model-get",@"model-set",@"catalog-get",@"catalog-set",@"render",@"analyze"]],@"real workflow preserves config getter/setter interleave, catalog order and busy render before request");Check(f.analyzer.requestedSource==f.source&&f.analyzer.requestedTranslation==f.translation&&[f.analyzer.model isEqual:@"learning-model"]&&f.analyzer.catalog==f.catalog,@"request uses original source/translation aliases and trimmed learning model/catalog");NSUInteger renders=f.renders;[d analyzeQuickSentence:nil];Check(f.analyzer.replies.count==1&&f.renders==renders,@"repeated analyze does not create duplicate work");Analyze(f,r,nil);Check(!d.quickSentenceAnalyzing&&d.quickSentenceAnalysis==r&&!d.quickSentenceAnalysisError&&f.renders==renders+1,@"matching completion assigns actual result and renders after releasing busy");
 f.model.value=@" \n";[f.events removeAllObjects];f.translation=nil;[d analyzeQuickSentence:nil];Check([f.analyzer.model isEqual:@" raw-fallback "]&&[f.events containsObject:@"fallback-model-get"]&&[d.quickSentenceAnalysisTranslation isEqual:@""]&&!f.analyzer.requestedTranslation,@"empty trimmed learning model falls back raw; saved translation empty differs from request nil");Analyze(f,r,Failure());Check(!d.quickSentenceAnalyzing&&!d.quickSentenceAnalysis&&[d.quickSentenceAnalysisError isEqual:@"合成错误"],@"current error rejects supplied result but preserves original cause");f.model.value=@"model";f.translation=@"合成译文";
 [d analyzeQuickSentence:nil];[d cancelQuickSentenceAnalysis];[d analyzeQuickSentence:nil];renders=f.renders;Analyze(f,r,nil);Check(d.quickSentenceAnalyzing&&!d.quickSentenceAnalysis&&f.renders==renders,@"old generation result cannot clear busy or render over newer request");Analyze(f,r,nil);Check(!d.quickSentenceAnalyzing&&d.quickSentenceAnalysis==r,@"current generation still commits after stale result");
 [d analyzeQuickSentence:nil];f.requested=NO;renders=f.renders;Analyze(f,r,nil);Check(d.quickSentenceAnalyzing&&f.renders==renders,@"closed quick panel ignores completion without releasing another operation's busy");[d cancelQuickSentenceAnalysis];f.requested=YES;[d analyzeQuickSentence:nil];f.source=@"replacement";Analyze(f,r,nil);Check(d.quickSentenceAnalyzing&&!d.quickSentenceAnalysis,@"same generation different source is stale");[d cancelQuickSentenceAnalysis];
 NSMutableString*mutableSource=[@"mutable-source" mutableCopy];f.source=mutableSource;[d analyzeQuickSentence:nil];NSString*snapshot=d.quickSentenceAnalysisSource;[mutableSource appendString:@"-changed"];f.source=[NSString stringWithString:mutableSource];Analyze(f,r,nil);Check(!d.quickSentenceAnalyzing&&d.quickSentenceAnalysis==r&&[snapshot isEqual:@"mutable-source"],@"captured request source keeps original strong alias while analysisSource property keeps original copy semantics");
 f.source=@"合成原句";f.translation=@"old translation";[d analyzeQuickSentence:nil];f.translation=@"changed translation";Analyze(f,r,nil);Check(!d.quickSentenceAnalyzing&&d.quickSentenceAnalysis==r,@"original source-only stale gate does not gain a translation/version gate");f.translation=@"合成译文";
 // Exercise the actual original lazy analyzer with missing synthetic Key: validation fails before any transport.
 d.quickSentenceAnalyzer=nil;f.key.value=nil;[d analyzeQuickSentence:nil];Check([d.quickSentenceAnalyzer isKindOfClass:FYLearningAnalyzer.class]&&!d.quickSentenceAnalyzing&&!d.quickSentenceAnalysis&&d.quickSentenceAnalysisError.length>0,@"original lazy analyzer is created and missing-key validation completes without API work");d.quickSentenceAnalyzer=f.analyzer;f.key.value=@"synthetic-only-key";
 f.saved=@[[FYRequestIdentity identityWithSentenceID:@"other" version:4 requestID:@"r" sourceText:@"x" translation:nil],[FYRequestIdentity identityWithSentenceID:@"sentence" version:3 requestID:@"r" sourceText:@"x" translation:nil]];Check(![d quickSentenceIsBookmarked],@"sentence query requires both original ID and version");f.saved=[f.saved arrayByAddingObject:[FYRequestIdentity identityWithSentenceID:@"sentence" version:4 requestID:@"r" sourceText:@"x" translation:nil]];Check([d quickSentenceIsBookmarked],@"matching saved sentence is found without new query state");
 d.sentenceBookmarkPending=YES;NSUInteger calls=f.store.toggleCalls;[d bookmarkQuickSentence:nil];Check(f.store.toggleCalls==calls,@"sentence pending gate blocks duplicate toggle");d.sentenceBookmarkPending=NO;f.sentenceID=@"";[d bookmarkQuickSentence:nil];Check(f.store.toggleCalls==calls,@"empty sentence ID sends no toggle");f.sentenceID=@"sentence";[f.events removeAllObjects];[d bookmarkQuickSentence:nil];Check(d.sentenceBookmarkPending&&!f.button.isEnabled&&[f.events isEqual:@[@"disable",@"toggle"]],@"sentence toggle sets pending and disables native action before unique store");FYRequestIdentity*i=f.store.lastIdentity;Check([i.sentenceID isEqual:@"sentence"]&&i.version==4&&[i.sourceText isEqual:f.source]&&[i.translation isEqual:f.translation]&&i.requestID.length>0,@"sentence bookmark uses actual canonical identity and fresh UUID/text snapshot");NSString*uuid=i.requestID;[d bookmarkQuickSentence:nil];Check(f.store.toggleCalls==calls+1,@"in-flight sentence bookmark remains single request");[f.events removeAllObjects];Toggle(f,YES,nil);Check(!d.sentenceBookmarkPending&&[f.status.value isEqual:@"unchanged"]&&[f.events isEqual:@[@"saved-refresh"]]&&!f.button.isEnabled,@"sentence success only clears pending and refreshes, without invented status/enable");[d bookmarkQuickSentence:nil];Check(![f.store.lastIdentity.requestID isEqual:uuid],@"next sentence bookmark operation gets a new UUID");f.sentenceID=@"other";[f.events removeAllObjects];Toggle(f,NO,Failure());Check(!d.sentenceBookmarkPending&&[f.status.value isEqual:@"句子收藏失败：合成错误"]&&[f.events isEqual:@[@"status",@"saved-refresh"]],@"original sentence error still reports after context changed, with no added stale gate");f.sentenceID=@"sentence";f.status.value=@"unchanged";
 d.quickSentenceAnalysis=Result(@[a,b]);f.index=1;FYGrammarBookmark*match=Bookmark(@"sentence",4,@"条目乙",@"first");f.bookmarks=@[Bookmark(@"sentence",3,@"条目乙",@"wrong-version"),Bookmark(@"other",4,@"条目乙",@"wrong-id"),Bookmark(@"sentence",4,@"条目甲",@"wrong-name"),match,Bookmark(@"sentence",4,@"条目乙",@"second")];Check([d quickGrammarBookmark]==match,@"grammar query uses ID/version/name and first matching existing object");f.index=2;Check(![d quickGrammarBookmark],@"out-of-range grammar selection returns nil");d.quickSentenceAnalysis=nil;f.index=0;Check(![d quickGrammarBookmark],@"empty analysis query has original zero-count guard");d.quickSentenceAnalysis=Result(@[a,b]);f.index=-1;BOOL rangeRaised=NO;@try{[d quickGrammarBookmark];}@catch(NSException*e){rangeRaised=[e.name isEqual:NSRangeException];}Check(rangeRaised,@"negative populated-array index preserves original exception contract, no refactor-only new guard");f.index=1;
 calls=f.store.fetchCalls;d.quickGrammarBookmarkPending=YES;[d bookmarkQuickGrammar:nil];d.quickGrammarBookmarkPending=NO;f.sentenceID=@"";[d bookmarkQuickGrammar:nil];f.sentenceID=@"sentence";f.index=2;[d bookmarkQuickGrammar:nil];Check(f.store.fetchCalls==calls,@"grammar pending/ID/index short circuits send no store work");f.index=1;[f.events removeAllObjects];[d bookmarkQuickGrammar:nil];Check(d.quickGrammarBookmarkPending&&[f.events isEqual:@[@"button-update",@"fetch"]],@"grammar operation marks pending and updates native action before fetch");[d bookmarkQuickGrammar:nil];Check(f.store.fetchCalls==calls+1,@"pending grammar operation blocks duplicate fetch");[f.events removeAllObjects];Fetch(f,nil,Failure());Check(!d.quickGrammarBookmarkPending&&[f.status.value isEqual:@"收藏失败：合成错误"]&&[f.events isEqual:@[@"status",@"grammar-refresh",@"button-update"]]&&!f.store.addCalls&&!f.store.deleteCalls,@"fetch error finishes in original status/refresh/update order without mutation");
 [d bookmarkQuickGrammar:nil];Fetch(f,f.bookmarks,nil);Check([f.store.deleted isEqual:@"first"]&&f.store.deleteCalls==1&&!f.store.addCalls&&d.quickGrammarBookmarkPending,@"matching grammar deletes first original record and stays pending until write completion");Write(f,nil);Check(!d.quickGrammarBookmarkPending&&[f.status.value isEqual:@"收藏已更新，可在单词学习的语法收藏中查看。"],@"delete success retains original success text and pending release");
 [d bookmarkQuickGrammar:nil];f.source=@"new UI source";f.translation=@"new UI translation";Fetch(f,@[],nil);FYGrammarBookmark*added=f.store.added;Check([added.sentenceID isEqual:@"sentence"]&&added.version==4&&[added.name isEqual:@"条目乙"]&&[added.catalogID isEqual:@"catalog"]&&[added.sourceTextSnapshot isEqual:@"合成原句"]&&[added.translationSnapshot isEqual:@"合成译文"],@"new grammar bookmark uses captured original item/identity/source/translation after UI changes");Write(f,Failure());Check([f.status.value isEqual:@"收藏失败：合成错误"]&&!d.quickGrammarBookmarkPending,@"write failure retains original reason and releases grammar pending");
 f.source=@"合成原句";f.translation=nil;[d bookmarkQuickGrammar:nil];f.sentenceID=@"replacement";f.version=9;f.status.value=@"replacement status";[f.events removeAllObjects];Fetch(f,@[],nil);Check([f.store.added.sentenceID isEqual:@"sentence"]&&f.store.added.version==4&&!f.store.added.translationSnapshot,@"changed identity still writes original captured grammar snapshot and preserves nil translation");[f.events removeAllObjects];Write(f,nil);Check(!d.quickGrammarBookmarkPending&&[f.status.value isEqual:@"replacement status"]&&[f.events isEqual:@[@"grammar-refresh",@"button-update"]],@"stale identity completion always releases pending/refreshes but suppresses status only");
 f.sentenceID=@"sentence";f.version=4;f.translation=@"合成译文";[d bookmarkQuickGrammar:nil];d.quickSentenceAnalysis=Result(@[a]);f.index=0;Fetch(f,@[],nil);Write(f,nil);Check([f.status.value isEqual:@"收藏已更新，可在单词学习的语法收藏中查看。"],@"same identity new selected item does not gain an original-absent item stale gate");Check(f.analyzer.replies.count==0&&f.store.toggles.count==0&&f.store.fetches.count==0&&f.store.writes.count==0&&f.otherAnalyzer.cancels==0,@"all held boundary operations consumed and unrelated scope untouched");app=dlsym(RTLD_DEFAULT,"NSApp");Check(!app||!*app,@"six real algorithms complete without UI/application initialization");
}
static void RunQuickSentenceLeases(QuickDriverFactory factory){
 QuickSentenceFacts*f=[QuickSentenceFacts new];f.requested=YES;__weak id weakSource;__weak NSString*weakText;
 @autoreleasepool{id<QuickSentenceDriver>d=factory(f);weakSource=d;NSMutableString*text=[@"leased-request-source" mutableCopy];weakText=text;f.source=text;d.quickSentenceAnalyzer=f.analyzer;[d analyzeQuickSentence:nil];f.source=nil;d.quickSentenceAnalysisSource=nil;}
 Check(weakSource&&weakText,@"analysis callback preserves original strong concrete source and source-text leases");@autoreleasepool{Analyze(f,nil,nil);}Check(!weakSource&&!weakText,@"analysis source/text release after held callback is removed and delivered");
 f=[QuickSentenceFacts new];@autoreleasepool{id<QuickSentenceDriver>d=factory(f);weakSource=d;[d bookmarkQuickSentence:nil];}Check(weakSource!=nil,@"sentence bookmark callback strongly leases original source");@autoreleasepool{Toggle(f,YES,nil);}Check(!weakSource,@"sentence source releases after callback refresh");
 f=[QuickSentenceFacts new];__weak FYGrammarItem*weakItem;
 @autoreleasepool{id<QuickSentenceDriver>d=factory(f);weakSource=d;FYGrammarItem*item=Item(@"leased-item");weakItem=item;NSMutableString*text=[@"leased-grammar-source" mutableCopy];weakText=text;f.source=text;d.quickSentenceAnalysis=Result(@[item]);[d bookmarkQuickGrammar:nil];d.quickSentenceAnalysis=nil;f.source=nil;}
 Check(weakSource&&weakItem&&weakText,@"grammar fetch callback preserves original source/item/strong text aliases");@autoreleasepool{Fetch(f,@[],nil);}Check(weakSource&&!weakItem,@"after fetch, write finish keeps source but releases no-longer-needed item");f.store.added=nil;@autoreleasepool{Write(f,nil);}Check(!weakSource&&!weakText,@"grammar source/text release after write finish and boundary snapshot release");
}
