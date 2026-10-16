#import "presentation/FYGrammarInteractionCoordinator.h"
#import "FYGrammarInteractionTestServices.h"
#import <objc/runtime.h>
@interface GrammarCoreSource : NSObject <FYGrammarInteractionSource,GrammarFixtureController>
@property(nonatomic,strong) FYGrammarInteractionCoordinator *owner;
@property(nonatomic,strong) GrammarInteractionFacts *facts;
@end
@implementation GrammarCoreSource
@dynamic analysisRequestGeneration,followupRequestGeneration,learningAnalysisBusy,grammarAnalysisError,currentAnalysis,grammarActions,quickGrammarActions;
- (instancetype)init{if((self=[super init])){self.owner=[FYGrammarInteractionCoordinator new];self.facts=[GrammarInteractionFacts new];}return self;}
#define OWNER_VALUE(TYPE,NAME,SETTER) - (TYPE)NAME{return self.owner.NAME;}- (void)SETTER:(TYPE)value{self.owner.NAME=value;}
OWNER_VALUE(NSInteger,analysisRequestGeneration,setAnalysisRequestGeneration)
OWNER_VALUE(NSInteger,followupRequestGeneration,setFollowupRequestGeneration)
OWNER_VALUE(BOOL,learningAnalysisBusy,setLearningAnalysisBusy)
OWNER_VALUE(NSString *,grammarAnalysisError,setGrammarAnalysisError)
OWNER_VALUE(FYAnalysisResult *,currentAnalysis,setCurrentAnalysis)
OWNER_VALUE(FYGrammarActionState *,grammarActions,setGrammarActions)
OWNER_VALUE(FYGrammarActionState *,quickGrammarActions,setQuickGrammarActions)
#undef OWNER_VALUE
- (FYLearningCoordinator *)learningCoordinator{return self.facts.learning;}
- (FYLearningAnalyzer *)learningAnalyzer{return self.facts.analyzer;}
- (FYLearningAnalyzer *)quickSentenceAnalyzer{return self.facts.quickAnalyzer;}
- (FYGrammarCatalog *)grammarCatalog{return self.facts.catalog;}
- (FYAnalysisResult *)quickSentenceAnalysis{return self.facts.quickResult;}
- (NSString *)quickSentenceAnalysisSource{return self.facts.quickAnalysisSource;}
- (NSString *)quickSentenceSource{return self.facts.quickSource;}
- (NSString *)quickSentenceTranslation{return self.facts.quickTranslation;}
- (NSString *)quickSentenceID{return self.facts.quickID;}
- (NSInteger)quickSentenceVersion{return self.facts.quickVersion;}
- (NSInteger)quickSelectedGrammarIndex{return self.facts.quickIndex;}
- (BOOL)quickSentenceAnalyzing{return self.facts.quickAnalyzing;}
- (FYGrammarItem *)selectedGrammarItem{return [FYLearningCoordinator grammarItemInList:self.currentAnalysis.grammar index:0 fallbackToFirst:YES];}
- (BOOL)analysisMatchesCurrentSentence{return self.facts.applicable;}
- (FYGrammarServiceConfiguration *)grammarServiceConfiguration{return [[FYGrammarServiceConfiguration alloc]initWithBaseURL:self.facts.base model:self.facts.model apiKey:self.facts.key];}
- (void)setAnalyzeBusy:(BOOL)busy{self.learningAnalysisBusy=busy;[self.facts.trace addObject:busy?@"busyYES":@"busyNO"];}
- (void)setGrammarStatusText:(NSString *)text{self.facts.status=text;}
- (void)setGrammarStatusToErrorColor{self.facts.errorColor=YES;}
- (void)setGrammarDetailNameText:(NSString *)text{self.facts.detailName=text;}
- (void)setGrammarDetailBodyText:(NSString *)text{self.facts.detailBody=text;}
- (void)setGrammarFollowupText:(NSString *)text{self.facts.followup=text;}
- (void)setGrammarQuickAnalysisResult:(FYAnalysisResult *)result{self.facts.quickResult=result;}
- (void)applyGrammarTabSelection{}
- (void)refreshGrammarResults{self.facts.refreshed++;}
- (void)updateGrammarActionControlsForQuick:(BOOL)quick{self.facts.controls++;}
- (void)refreshQuickGrammarActionDetail{self.facts.quickDetails++;}
- (void)renderQuickSentence{self.facts.renders++;}
- (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates{self.facts.preserveCalls++;updates();}
- (void)syncCoordinatorToDisplayed{[self.facts.trace addObject:@"syncDisplayed"];}
- (void)clearAnalysisDisplay{[self.facts.trace addObject:@"clear"];}
- (void)refreshLearningStatus{[self.facts.trace addObject:@"statusRefresh"];}
- (void)selectPageAtIndex:(NSInteger)index{[self.facts.trace addObject:[NSString stringWithFormat:@"page%ld",(long)index]];}
- (void)syncLearningAnalyzerConfig{self.facts.configSync++;}
- (void)analyzeCurrentSentence:(id)sender{[self.owner analyzeCurrentSentenceWithReceiver:self];}
- (void)requestGrammarFollowupExample:(BOOL)example{[self.owner requestGrammarFollowupExample:example receiver:self];}
- (void)requestGrammarQuestion:(NSString *)question{[self.owner requestGrammarQuestion:question receiver:self];}
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick{return [self.owner grammarActionsForQuick:quick receiver:self];}
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick{return [self.owner grammarActionItemForQuick:quick receiver:self];}
- (void)testExpandQuick:(BOOL)quick{[self.owner toggleGrammarExplanationForQuick:quick receiver:self];}
- (void)testReviewQuick:(BOOL)quick{[self.owner reviewGrammarSentenceForQuick:quick receiver:self];}
@end
int main(void){@autoreleasepool{
 Check(NSClassFromString(@"NSPanel")==Nil,@"grammar interaction links Foundation/canonical models/gates only");GrammarCoreSource *s=[GrammarCoreSource new];unsigned int n=0;Ivar *v=class_copyIvarList(FYGrammarInteractionCoordinator.class,&n);free(v);Check(n==7&&!s.currentAnalysis&&!s.grammarActions&&!s.quickGrammarActions&&!s.learningAnalysisBusy,@"cold sole owner has original seven empty fields and no task/state cache initialization");RunGrammarFixture(s,s.facts);
 NSMutableString *alias=[@"alias" mutableCopy];FYGrammarServiceConfiguration *cfg=[[FYGrammarServiceConfiguration alloc]initWithBaseURL:alias model:alias apiKey:alias];[alias appendString:@"-changed"];Check(cfg.baseURL==alias&&cfg.model==alias&&cfg.apiKey==alias&&[cfg.model isEqual:@"alias-changed"],@"readonly configuration container retains original strong aliases until original analyzer copy setters");s.grammarAnalysisError=alias;[alias appendString:@"again"];Check([s.grammarAnalysisError isEqual:@"alias-changed"],@"original error copy ownership retained");
 __weak GrammarCoreSource *weak;GrammarLearningBoundary *held;@autoreleasepool{GrammarCoreSource *temporary=[GrammarCoreSource new];weak=temporary;held=temporary.facts.learning;[temporary analyzeCurrentSentence:nil];}Check(weak!=nil,@"initial held service completion retains original concrete source task lease");void(^finish)(FYAnalysisResult *,NSError *)=held.analysisReply;held.analysisReply=nil;@autoreleasepool{finish(Result(@"main",1,0),nil);finish=nil;}Check(!weak,@"completed initial callback releases concrete source without idle coordinator lease");
 __weak GrammarCoreSource *weakExpand;GrammarAnalyzerBoundary *pending;@autoreleasepool{GrammarCoreSource *temporary=[GrammarCoreSource new];weakExpand=temporary;temporary.currentAnalysis=Result(@"main",1,1);InstallActions(temporary,temporary.facts);pending=(GrammarAnalyzerBoundary *)temporary.grammarActions.analyzer;[temporary testExpandQuick:NO];}Check(weakExpand!=nil,@"expanded task retains original concrete source/state/item lease");void(^answer)(NSString *,NSError *)=pending.answerReply;pending.answerReply=nil;@autoreleasepool{answer(@"lease complete",nil);answer=nil;}Check(!weakExpand,@"expanded callback releases source after original current-state checks");
 __weak GrammarCoreSource *weakFollow;GrammarAnalyzerBoundary *followService;@autoreleasepool{GrammarCoreSource *temporary=[GrammarCoreSource new];weakFollow=temporary;temporary.currentAnalysis=Result(@"main",1,1);followService=temporary.facts.analyzer;[temporary requestGrammarQuestion:@"held question"];}Check(weakFollow!=nil,@"question task keeps original strong concrete source/item lease");answer=followService.answerReply;followService.answerReply=nil;@autoreleasepool{answer(@"done",nil);answer=nil;}Check(!weakFollow,@"question completion releases source without idle coordinator retention");
 __weak GrammarCoreSource *weakReview;GrammarLearningBoundary *reviewService;@autoreleasepool{GrammarCoreSource *temporary=[GrammarCoreSource new];weakReview=temporary;temporary.currentAnalysis=Result(@"main",1,1);InstallActions(temporary,temporary.facts);reviewService=temporary.facts.learning;[temporary testReviewQuick:NO];}Check(weakReview!=nil,@"review task retains concrete source/state/existing analysis lease");finish=reviewService.reviewReply;reviewService.reviewReply=nil;@autoreleasepool{finish(nil,[NSError errorWithDomain:@"synthetic" code:3 userInfo:nil]);finish=nil;}Check(!weakReview,@"review completion releases original source/task lease");
 Check(NSClassFromString(@"NSPanel")==Nil,@"all actual grammar orchestration stayed headless with synthetic service boundaries, no UI/API/database");printf("PASS GrammarInteractionCoordinatorTests: %lu checks; actual initial/followup/config/expand/review gates and source leases, Foundation only\n",(unsigned long)checks);
}return 0;}
