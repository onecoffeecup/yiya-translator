#import "presentation/FYLiveReadingCoordinator.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface LiveLearningFact : NSObject
@property(nonatomic,copy) NSString *currentSourceText,*currentTranslation,*currentSentenceID;
@property(nonatomic) NSInteger currentVersion;
@end
@implementation LiveLearningFact @end
@interface LiveSourceFact : NSObject <FYLiveReadingSource>
@property(nonatomic,strong) FYDisplayedSentenceState *display;
@property(nonatomic,strong) LiveLearningFact *learning;
@property(nonatomic,strong) FYLiveReadingCoordinator *owner;
@property(nonatomic) NSInteger vocabSelectionGeneration;
@property(nonatomic) BOOL sourceHoverSuspended,learningAnalysisBusy;
@property(nonatomic,strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic,strong) NSString *nativeSource,*nativeGrammar,*translationText,*waitingHint,*grammarHint;
@property(nonatomic) BOOL emptyHidden,scrollHidden,hintHidden,pickHidden;
@property(nonatomic) CGFloat sourceMinimum,translationMinimum;
@property(nonatomic) NSUInteger sourceSets,grammarSets,clears,history,layouts,heights,dialogues,hostStatus,hover;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic,strong) NSString *observedSourceArgument;
@property(nonatomic) BOOL mutateDuringSet;
@end
@implementation LiveSourceFact
@dynamic displayedSentenceID,displayedSourceText,displayedTranslation,displayedVersion;
- (instancetype)init{if((self=[super init])){self.display=[FYDisplayedSentenceState new];self.learning=[LiveLearningFact new];self.owner=[FYLiveReadingCoordinator new];self.trace=[NSMutableArray new];self.nativeSource=@"";self.nativeGrammar=@"";}return self;}
- (NSString *)displayedSentenceID{return self.display.displayedSentenceID;}
- (void)setDisplayedSentenceID:(NSString *)v{self.display.displayedSentenceID=v;[self.trace addObject:@"id"];}
- (NSString *)displayedSourceText{return self.display.displayedSourceText;}
- (void)setDisplayedSourceText:(NSString *)v{self.display.displayedSourceText=v;[self.trace addObject:@"source-state"];}
- (NSString *)displayedTranslation{return self.display.displayedTranslation;}
- (void)setDisplayedTranslation:(NSString *)v{self.display.displayedTranslation=v;[self.trace addObject:@"translation-state"];}
- (NSInteger)displayedVersion{return self.display.displayedVersion;}
- (void)setDisplayedVersion:(NSInteger)v{self.display.displayedVersion=v;[self.trace addObject:@"version"];}
- (FYLearningCoordinator *)learningCoordinator{return (FYLearningCoordinator *)self.learning;}
- (NSString *)currentLiveSourceText{return self.nativeSource;}
- (NSString *)currentLiveGrammarSourceText{return self.nativeGrammar;}
- (void)setWordPickHidden:(BOOL)v{self.pickHidden=v;[self.trace addObject:@"pick-hide"];}
- (void)setLiveSourceReadingText:(NSString *)t{self.sourceSets++;self.observedSourceArgument=t;self.nativeSource=t;[self.trace addObject:@"source-native"];if(self.mutateDuringSet&&[t isKindOfClass:NSMutableString.class])[(NSMutableString *)t appendString:@" changed"];} 
- (void)setLiveGrammarSourceText:(NSString *)t{self.grammarSets++;self.nativeGrammar=t;[self.trace addObject:@"grammar-source"];}
- (void)setLiveSourceEmptyHidden:(BOOL)v{self.emptyHidden=v;}
- (void)setLiveSourceScrollHidden:(BOOL)v{self.scrollHidden=v;}
- (void)setLiveSourceHintHidden:(BOOL)v{self.hintHidden=v;}
- (void)setLiveSourceMinimumHeight:(CGFloat)v{self.sourceMinimum=v;}
- (void)setLiveTranslationMinimumHeight:(CGFloat)v{self.translationMinimum=v;}
- (void)setLiveTranslationReadingText:(NSString *)t{self.translationText=t;self.waitingHint=nil;[self.trace addObject:@"translation-native"];}
- (void)setLiveTranslationWaitingHint:(NSString *)t{self.waitingHint=t;self.translationText=nil;[self.trace addObject:@"translation-hint"];}
- (void)layoutLiveReadingWindow{self.layouts++;[self.trace addObject:@"layout"];}
- (void)updateLiveSourceReadingHeight{self.heights++;[self.trace addObject:@"height"];}
- (void)refreshLiveDialoguePresentation:(NSString *)t{self.dialogues++;[self.trace addObject:@"dialogue"];}
- (void)setLiveGrammarTranslationHint:(NSString *)t{self.grammarHint=t;[self.trace addObject:@"grammar-hint"];}
- (void)refreshHistory{self.history++;[self.trace addObject:@"history"];}
- (void)clearAnalysisDisplay{self.clears++;[self.trace addObject:@"clear"];}
- (void)liveHostRefreshLearningStatus{self.hostStatus++;[self.trace addObject:@"host-status"];}
- (void)refreshSourceHoverTips{self.hover++;[self.trace addObject:@"hover"];}
@end
int main(void){@autoreleasepool{
 Check(NSClassFromString(@"NSPanel")==Nil,@"live coordination links Foundation/CG/models only without AppKit");LiveSourceFact *s=[LiveSourceFact new];unsigned int n=0;Ivar *ivars=class_copyIvarList(FYLiveReadingCoordinator.class,&n);free(ivars);Check(n==0,@"live coordinator owns no displayed/coordinator/cache/source state");
 [s.owner refreshLearningSourceWithReceiver:s];Check(!s.clears&&!s.vocabSelectionGeneration&&!s.pickHidden&&!s.sourceSets&&!s.grammarSets,@"initial nil IDs/version and empty text keep original unchanged gates");Check(!s.emptyHidden&&s.scrollHidden&&s.hintHidden&&s.sourceMinimum==104&&s.translationMinimum==104&&[s.waitingHint isEqual:@"开始翻译后，译文会显示在这里。"]&&[s.grammarHint isEqual:@"还没有选择要分析的句子。"],@"original compact empty state/hints/minima preserved");Check([[s.trace componentsJoinedByString:@","]isEqual:@"history,id,version,source-state,translation-state,translation-hint,layout,height,dialogue,grammar-hint,host-status"]&&!s.hover,@"empty refresh retains exact state/native/layout/height/dialogue/grammar/Host order without hover");
 [s.trace removeAllObjects];s.learning.currentSentenceID=@"sentence";s.learning.currentVersion=1;s.learning.currentSourceText=@"synthetic source";s.learning.currentTranslation=@"synthetic translation";[s.owner refreshLearningSourceWithReceiver:s];Check(s.clears==1&&s.vocabSelectionGeneration==1&&s.pickHidden&&[s.displayedSentenceID isEqual:@"sentence"]&&s.displayedVersion==1&&[s.displayedSourceText isEqual:@"synthetic source"]&&[s.displayedTranslation isEqual:@"synthetic translation"],@"changed identity clears analysis/old pick before writing original displayed state");Check(s.emptyHidden&&!s.scrollHidden&&!s.hintHidden&&s.sourceMinimum==156&&s.translationMinimum==156&&[s.translationText isEqual:@"synthetic translation"]&&[s.grammarHint isEqual:@"synthetic translation"],@"nonempty source/translation keeps156 and native translation/grammar");Check([[s.trace componentsJoinedByString:@","]isEqual:@"history,clear,pick-hide,id,version,source-state,translation-state,source-native,grammar-source,translation-native,layout,height,dialogue,grammar-hint,host-status,hover"],@"changed refresh concrete sequence preserved");
 NSUInteger sourceSets=s.sourceSets,grammarSets=s.grammarSets,hover=s.hover;[s.owner refreshLearningSourceWithReceiver:s];Check(s.sourceSets==sourceSets&&s.grammarSets==grammarSets&&s.hover==hover&&s.clears==1&&s.vocabSelectionGeneration==1,@"same identity/text avoids editor rebuild,clear/generation and hover");s.sourceHoverSuspended=YES;[s.owner refreshLearningSourceWithReceiver:s];Check(s.hover==hover+1&&s.sourceSets==sourceSets,@"hover suspended refresh invokes original hover without source rewrite");s.sourceHoverSuspended=NO;s.learning.currentTranslation=nil;[s.owner refreshLearningSourceWithReceiver:s];Check([s.waitingHint isEqual:@"等待该句译文"]&&[s.grammarHint isEqual:@"暂无该句译文"]&&s.translationMinimum==156,@"source present/translation absent keeps exact waiting hints");
 s.learning.currentSourceText=@"";s.learning.currentTranslation=@"translation only";[s.owner refreshLearningSourceWithReceiver:s];Check(!s.emptyHidden&&s.scrollHidden&&s.hintHidden&&s.sourceMinimum==104&&s.translationMinimum==156&&[s.grammarHint isEqual:@"translation only"],@"translation-only state applies separate original minima");s.learning.currentVersion=2;[s.owner refreshLearningSourceWithReceiver:s];Check(s.clears==2&&s.vocabSelectionGeneration==2&&s.displayedVersion==2,@"same sentence version change clears/increments original word generation");
 FYAnalysisResult *analysis=[FYAnalysisResult new];FYGrammarItem *g1=[FYGrammarItem new];FYGrammarItem *g2=[FYGrammarItem new];g2.referenceLevel=@"N3";analysis.grammar=@[g1,g2];s.currentAnalysis=analysis;Check([[s.owner currentSentenceLevelTagWithReceiver:s]isEqual:@"N3"],@"first nonempty canonical grammar reference level returned");g1.referenceLevel=@"N2";Check([[s.owner currentSentenceLevelTagWithReceiver:s]isEqual:@"N2"],@"original first-item order preserved");s.currentAnalysis=nil;Check([s.owner currentSentenceLevelTagWithReceiver:s]==nil,@"missing analysis returns nil without fallback");
 __weak LiveSourceFact *weak;@autoreleasepool{LiveSourceFact *temporary=[LiveSourceFact new];weak=temporary;[temporary.owner refreshLearningSourceWithReceiver:temporary];}Check(!weak,@"synchronous live coordinator does not retain borrowed receiver");Check(NSClassFromString(@"NSPanel")==Nil,@"all production live coordination remains headless Foundation, no service/API/UI initialization");printf("PASS LiveReadingCoordinatorTests: %lu checks;actual refresh/level/gates/order,explicit native boundary facts,no UI\n",(unsigned long)checks);
}return 0;}
