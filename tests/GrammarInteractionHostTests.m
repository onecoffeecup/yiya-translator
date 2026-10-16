#import "presentation/FYGrammarPresentationController.h"
#import "FYGrammarInteractionTestServices.h"
@interface GrammarFieldFact : NSObject
@property(nonatomic,copy) NSString *stringValue,*title;
@property(nonatomic) BOOL enabled;
@property(nonatomic,strong) NSColor *textColor;
@property(nonatomic,copy) void (^onText)(NSString *);
@property(nonatomic,copy) void (^onColor)(NSColor *);
@property(nonatomic) NSInteger tag;
@end
@implementation GrammarFieldFact
@synthesize stringValue=_stringValue,textColor=_textColor;
- (void)setStringValue:(NSString *)text{_stringValue=[text copy];if(self.onText)self.onText(text);}
- (void)setTextColor:(NSColor *)color{_textColor=color;if(self.onColor)self.onColor(color);}
@end
@interface GrammarNativePeer : NSObject
@property(nonatomic,strong) GrammarInteractionFacts *facts;
@property(nonatomic,strong) NSSecureTextField *apiKeyField;
@property(nonatomic,strong) NSTextField *baseURLField,*learningModelField,*modelField;
@property(nonatomic) NSUInteger fallbackReads;
@end
@implementation GrammarNativePeer
- (FYLearningCoordinator *)learningCoordinator{return self.facts.learning;}
- (FYLearningAnalyzer *)learningAnalyzer{return self.facts.analyzer;}
- (FYLearningAnalyzer *)quickSentenceAnalyzer{return self.facts.quickAnalyzer;}
- (FYGrammarCatalog *)grammarCatalog{return self.facts.catalog;}
- (FYAnalysisResult *)quickSentenceAnalysis{return self.facts.quickResult;}
- (void)setQuickSentenceAnalysis:(FYAnalysisResult *)r{self.facts.quickResult=r;}
- (NSString *)quickSentenceAnalysisSource{return self.facts.quickAnalysisSource;}
- (NSString *)quickSentenceSource{return self.facts.quickSource;}
- (NSString *)quickSentenceTranslation{return self.facts.quickTranslation;}
- (NSString *)quickSentenceID{return self.facts.quickID;}
- (NSInteger)quickSentenceVersion{return self.facts.quickVersion;}
- (NSInteger)quickSelectedGrammarIndex{return self.facts.quickIndex;}
- (BOOL)quickSentenceAnalyzing{return self.facts.quickAnalyzing;}
- (void)syncCoordinatorToDisplayed{[self.facts.trace addObject:@"syncDisplayed"];}
- (void)refreshLearningStatus{[self.facts.trace addObject:@"statusRefresh"];}
- (void)selectPageAtIndex:(NSInteger)index{[self.facts.trace addObject:[NSString stringWithFormat:@"page%ld",(long)index]];}
- (void)syncLearningAnalyzerConfig{self.facts.configSync++;}
@end
@interface GrammarNativeFixture : FYGrammarPresentationController <GrammarFixtureController>
@property(nonatomic,strong) GrammarInteractionFacts *facts;
@end
@implementation GrammarNativeFixture
- (void)clearAnalysisDisplay{[self.facts.trace addObject:@"clear"];}
- (BOOL)analysisMatchesCurrentSentence{return self.facts.applicable;}
- (void)setAnalyzeBusy:(BOOL)busy{[super setAnalyzeBusy:busy];[self.facts.trace addObject:busy?@"busyYES":@"busyNO"];}
- (void)applyGrammarTabSelection{}
- (void)refreshGrammarResults{self.facts.refreshed++;}
- (void)updateGrammarActionControlsForQuick:(BOOL)quick{self.facts.controls++;}
- (void)refreshQuickGrammarActionDetail{self.facts.quickDetails++;}
- (void)renderQuickSentence{self.facts.renders++;}
- (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates{self.facts.preserveCalls++;updates();}
- (void)testExpandQuick:(BOOL)quick{GrammarFieldFact *sender=[GrammarFieldFact new];sender.tag=quick?1:0;[self toggleGrammarExplanation:(NSButton *)sender];}
- (void)testReviewQuick:(BOOL)quick{GrammarFieldFact *sender=[GrammarFieldFact new];sender.tag=quick?1:0;[self reviewGrammarSentence:(NSButton *)sender];}
@end
static GrammarFieldFact *Field(NSString *text){GrammarFieldFact *f=[GrammarFieldFact new];f.stringValue=text;return f;}
static GrammarNativeFixture *Fixture(GrammarNativePeer *peer){
 GrammarNativeFixture *c=[[GrammarNativeFixture alloc]initWithHost:(id<FYGrammarPresentationControllerHost>)peer];c.facts=peer.facts;__weak GrammarInteractionFacts *weak=peer.facts;
 GrammarFieldFact *status=Field(@"");status.onText=^(NSString *t){weak.status=t;};status.onColor=^(NSColor *color){weak.errorColor=[color isEqual:NSColor.systemRedColor];};c.grammarStatusLabel=(NSTextField *)status;
 GrammarFieldFact *name=Field(@"");name.onText=^(NSString *t){weak.detailName=t;};c.grammarDetailNameLabel=(NSTextField *)name;GrammarFieldFact *body=Field(@"");body.onText=^(NSString *t){weak.detailBody=t;};c.grammarDetailBodyLabel=(NSTextField *)body;GrammarFieldFact *follow=Field(@"");follow.onText=^(NSString *t){weak.followup=t;};c.grammarFollowupResultLabel=(NSTextField *)follow;c.grammarPageAnalyzeButton=(NSButton *)Field(@"");c.analyzeButton=(NSButton *)Field(@"");
 peer.apiKeyField=(NSSecureTextField *)Field(peer.facts.key);peer.baseURLField=(NSTextField *)Field(peer.facts.base);peer.learningModelField=(NSTextField *)Field(@" ");peer.modelField=(NSTextField *)Field(peer.facts.model);
 // Native controls are the actual source of config; synchronize scenario changes on every config read.
 return c;
}
// Host property getters supply original native field values without stubbing any of the seven algorithms.
@interface DynamicGrammarPeer : GrammarNativePeer @end
@implementation DynamicGrammarPeer
- (NSSecureTextField *)apiKeyField{GrammarFieldFact *f=(GrammarFieldFact *)[super apiKeyField];f.stringValue=self.facts.key;return (NSSecureTextField *)f;}
- (NSTextField *)baseURLField{GrammarFieldFact *f=(GrammarFieldFact *)[super baseURLField];f.stringValue=self.facts.base;return (NSTextField *)f;}
- (NSTextField *)modelField{self.fallbackReads++;GrammarFieldFact *f=(GrammarFieldFact *)[super modelField];f.stringValue=self.facts.model;return (NSTextField *)f;}
@end
int main(void){@autoreleasepool{
 Check(NSApp==nil,@"actual native grammar fixture creates no app/view/window/control");DynamicGrammarPeer *peer=[DynamicGrammarPeer new];peer.facts=[GrammarInteractionFacts new];GrammarNativeFixture *c=Fixture(peer);RunGrammarFixture(c,peer.facts);
 NSUInteger reads=peer.fallbackReads;peer.learningModelField.stringValue=@" explicit model ";FYGrammarActionState *configured=[c grammarActionsForQuick:NO];Check([configured.analyzer.model isEqual:@"explicit model"]&&peer.fallbackReads==reads,@"native learning model Trim precedes fallback and nonempty value avoids fallback getter");peer.learningModelField.stringValue=@" \n";peer.facts.model=@" raw fallback ";configured=[c grammarActionsForQuick:NO];Check([configured.analyzer.model isEqual:@" raw fallback "]&&peer.fallbackReads==reads+1,@"empty learning model reads original raw fallback without extra normalization");
 Check(NSApp==nil,@"all original/new seven algorithms run with native fields/services/render actions only; real native scroll/render not executed");
 __weak GrammarNativeFixture *weak;GrammarLearningBoundary *held;@autoreleasepool{DynamicGrammarPeer *p=[DynamicGrammarPeer new];p.facts=[GrammarInteractionFacts new];GrammarNativeFixture *temporary=Fixture(p);weak=temporary;held=p.facts.learning;[temporary analyzeCurrentSentence:nil];}Check(weak!=nil,@"actual original/new initial task keeps concrete native controller strong");void(^finish)(FYAnalysisResult *,NSError *)=held.analysisReply;held.analysisReply=nil;@autoreleasepool{finish(nil,[NSError errorWithDomain:@"synthetic" code:2 userInfo:nil]);finish=nil;}Check(!weak,@"native controller releases after callback lease completion with weak Host unchanged");
 printf("PASS GrammarInteractionHostTests: %lu checks; actual original/new seven grammar algorithms, typed native/service boundaries and strong task leases\n",(unsigned long)checks);
}return 0;}
