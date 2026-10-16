#import "FYReferenceWorkflowTestFacts.h"
@interface ReferenceWorkflowFixture : NSObject <FYReferenceQuerySource,FYSourceHoverSource,ReferenceWorkflowDriver>
@property(nonatomic,strong) ReferenceFacts*facts;
@property(nonatomic,strong) ReferenceResourceBoundary*resourceBoundary;
@property(nonatomic,strong) id referenceStack;
@property(nonatomic,strong) FYReferenceQueryCoordinator*queryCoordinator;
@property(nonatomic,strong) FYSourceHoverCoordinator*hoverCoordinator;
@end
@implementation ReferenceWorkflowFixture
- (instancetype)init{if((self=[super init])){_queryCoordinator=[FYReferenceQueryCoordinator new];_hoverCoordinator=[FYSourceHoverCoordinator new];_referenceStack=[NSObject new];}return self;}
- (NSInteger)referenceRequestGeneration{return self.queryCoordinator.referenceRequestGeneration;}
- (void)setReferenceRequestGeneration:(NSInteger)value{self.queryCoordinator.referenceRequestGeneration=value;}
- (NSString *)referenceActiveWord{return self.queryCoordinator.referenceActiveWord;}
- (void)setReferenceActiveWord:(NSString *)value{self.queryCoordinator.referenceActiveWord=value;}
- (NSArray<NSDictionary *> *)referenceRecords{return self.queryCoordinator.referenceRecords;}
- (void)setReferenceRecords:(NSArray<NSDictionary *> *)value{self.queryCoordinator.referenceRecords=value;}
- (FYReferenceDictionary *)referenceDictionary{return self.queryCoordinator.referenceDictionary;}
- (void)setReferenceDictionary:(FYReferenceDictionary *)value{self.queryCoordinator.referenceDictionary=value;}
- (NSUInteger)sourceHoverGeneration{return self.hoverCoordinator.sourceHoverGeneration;}
- (void)setSourceHoverGeneration:(NSUInteger)value{self.hoverCoordinator.sourceHoverGeneration=value;}
- (NSUInteger)quickSourceHoverGeneration{return self.hoverCoordinator.quickSourceHoverGeneration;}
- (void)setQuickSourceHoverGeneration:(NSUInteger)value{self.hoverCoordinator.quickSourceHoverGeneration=value;}
- (NSCache<NSString *,NSString *> *)sourceHoverCache{return self.hoverCoordinator.sourceHoverCache;}
- (void)setSourceHoverCache:(NSCache<NSString *,NSString *> *)value{self.hoverCoordinator.sourceHoverCache=value;}
- (BOOL)sourceHoverSuspended{return self.hoverCoordinator.sourceHoverSuspended;}
- (void)setSourceHoverSuspended:(BOOL)value{self.hoverCoordinator.sourceHoverSuspended=value;}
- (FYJapaneseTokenizer*)japaneseTokenizer{return self.facts.tokenizer;}
- (void)setJapaneseTokenizer:(FYJapaneseTokenizer*)value{self.facts.tokenizer=value;}
- (FYAnalysisResult*)currentAnalysis{return self.facts.analysis;}
- (FYAnalysisResult*)quickSentenceAnalysis{return self.facts.quickAnalysis;}
- (NSString*)quickSentenceAnalysisSource{return self.facts.quickAnalysisSource;}
- (NSString*)quickSentenceSource{return self.facts.quickSource;}
- (NSString*)quickSentenceID{return self.facts.quickID;}
- (NSInteger)quickSentenceVersion{return self.facts.version;}
- (BOOL)quickSentenceRequested{return self.facts.requested;}
- (BOOL)analysisMatchesCurrentSentence{return self.facts.matches;}
- (NSString*)mainHoverText{return self.facts.main.string;}
- (BOOL)mainHoverEditable{return self.facts.main.editable;}
- (NSArray*)mainHoverViews{return@[self.facts.main ?: (id)NSNull.null,self.facts.grammar ?: (id)NSNull.null];}
- (id<NSObject>)quickHoverView{return self.facts.quick;}
- (NSString*)hoverTextForView:(id<NSObject>)view{return[(ReferenceTextFact*)view string];}
- (BOOL)hoverEditableForView:(id<NSObject>)view{return[(ReferenceTextFact*)view editable];}
- (id)verticalStack{return[NSObject new];}
- (BOOL)hasReferenceStack{return self.referenceStack!=nil;}
- (FYReferenceDictionary*)makeReferenceDictionary{return[[FYReferenceDictionary alloc]initWithURL:[self.resourceBoundary referenceResourceURL:@"reference.sqlite"]];}
- (void)setReferenceSearchText:(NSString*)text{self.facts.search.stringValue=text;}
- (void)clearReferenceRows{self.facts.clears++;}
- (void)showReferenceLoadingWord:(NSString*)word{[self.facts.events addObject:@"loading"];}
- (void)showReferenceEmptyWord:(NSString*)word error:(NSError*)error{self.facts.emptyResults++;self.facts.lastEmptyWord=word;self.facts.lastError=error.localizedDescription;}
- (void)renderReferenceRecords:(NSArray*)records{self.facts.renderedRecords=records;self.facts.entryChanges++;}
- (void)clearSourceHoverAttributes:(NSArray*)views{[self.facts.events addObject:@"clear-hover"];}
- (void)lookupReferenceWord:(NSString *)word reading:(NSString *)reading { [self.queryCoordinator lookupWord:word reading:reading receiver:self]; }
- (void)applyAnalysisHoverTips:(FYAnalysisResult *)analysis source:(NSString *)source views:(NSArray *)views { [self.hoverCoordinator applyAnalysis:analysis source:source views:views receiver:self]; }
- (void)populateSourceHoverTips:(NSString *)source views:(NSArray *)views analysis:(FYAnalysisResult *)analysis fallback:(NSString *)fallback isCurrent:(BOOL (^)(void))isCurrent { [self.hoverCoordinator populateSource:source views:views analysis:analysis fallback:fallback isCurrent:isCurrent receiver:self]; }
- (void)refreshSourceHoverTips { [self.hoverCoordinator refreshMainWithReceiver:self]; }
- (void)refreshQuickSentenceHoverTips { [self.hoverCoordinator refreshQuickWithReceiver:self]; }
- (void)setSourceHoverTip:(NSString*)tip range:(NSRange)range source:(NSString*)source views:(NSArray*)views{[self.facts.tips addObject:@{@"tip":tip,@"range":[NSValue valueWithRange:range],@"source":source,@"views":views}];}
@end
static id<ReferenceWorkflowDriver> Source(ReferenceFacts*f){activeFacts=f;ReferenceWorkflowFixture*s=[ReferenceWorkflowFixture new];s.facts=f;s.resourceBoundary=[ReferenceResourceBoundary new];s.resourceBoundary.facts=f;return s;}
static BOOL(^heldCurrent)(void);
@interface ReferenceCurrentCaptureFixture : ReferenceWorkflowFixture
@end
@implementation ReferenceCurrentCaptureFixture
- (void)populateSourceHoverTips:(NSString*)source views:(NSArray*)views analysis:(FYAnalysisResult*)analysis fallback:(NSString*)fallback isCurrent:(BOOL(^)(void))isCurrent{heldCurrent=[isCurrent copy];}
@end
static void RunWeakCurrentClosure(void){ReferenceFacts*f=[ReferenceFacts new];__weak id weak;__weak ReferenceTextFact*view;@autoreleasepool{ReferenceCurrentCaptureFixture*s=[ReferenceCurrentCaptureFixture new];s.facts=f;weak=s;view=f.quick;[s refreshQuickSentenceHoverTips];f.quick=nil;}Check(!weak&&view&&heldCurrent&&!heldCurrent(),@"actual quick currentness closure retains view but keeps only a weak receiver");@autoreleasepool{heldCurrent=nil;}Check(!view,@"releasing held currentness closure releases original view lease");}
int main(void){@autoreleasepool{unsigned n=0;Ivar*v=class_copyIvarList(FYReferenceQueryCoordinator.class,&n);free(v);Check(n==4,@"query owns exactly original generation/two copy snapshots/shared dictionary");v=class_copyIvarList(FYSourceHoverCoordinator.class,&n);free(v);Check(n==4,@"hover owns two independent generations/cache/suspension only");InstallServices();ReferenceFacts*f=[ReferenceFacts new];RunReferenceWorkflow(Source(f),f);RunReferenceLeases(^id<ReferenceWorkflowDriver>(ReferenceFacts*f){return Source(f);});RunWeakCurrentClosure();RestoreServices();activeFacts=nil;printf("PASS ReferenceWorkflowTests: %lu checks\n",(unsigned long)checks);}return 0;}
