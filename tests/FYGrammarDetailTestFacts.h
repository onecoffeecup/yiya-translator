#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "learning/FYLearningCoordinator.h"
#import "learning/FYLearningViews.h"
#import "FYGrammarActionState.h"
#import "presentation/FYGrammarInteractionCoordinator.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface DetailConstraintFact : NSObject
@property(nonatomic) BOOL active;
@property(nonatomic) CGFloat constant;
@end
@implementation DetailConstraintFact @end
@interface DetailAnchorFact : NSObject
@property(nonatomic,strong) NSMutableArray<DetailConstraintFact *> *constraints;
- (id)constraintGreaterThanOrEqualToConstant:(CGFloat)value;
@end
@implementation DetailAnchorFact
- (id)constraintGreaterThanOrEqualToConstant:(CGFloat)value{DetailConstraintFact *c=[DetailConstraintFact new];c.constant=value;[self.constraints addObject:c];return c;}
@end
@interface DetailNodeFact : NSObject
@property(nonatomic,copy) NSString *stringValue,*title,*toolTip,*accessibilityHelp;
@property(nonatomic,strong) NSFont *font;
@property(nonatomic,strong) NSColor *color;
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) NSMutableArray *arrangedSubviews;
@property(nonatomic,strong) DetailAnchorFact *widthAnchor;
@property(nonatomic,strong) NSMutableAttributedString *textStorage;
@property(nonatomic) NSRange selectedRange;
@property(nonatomic) NSInteger tag,maximumNumberOfLines;
@property(nonatomic) NSControlStateValue state;
@property(nonatomic) BOOL hidden,enabled,button;
@property(nonatomic) CGFloat spacing;
- (void)addArrangedSubview:(id)view;
- (NSString *)string;
@end
@implementation DetailNodeFact
- (instancetype)init{if((self=[super init])){_stringValue=@"";_arrangedSubviews=[NSMutableArray new];_layer=[CALayer layer];_widthAnchor=[DetailAnchorFact new];_widthAnchor.constraints=[NSMutableArray new];_textStorage=[[NSMutableAttributedString alloc]initWithString:@""];}return self;}
- (BOOL)isKindOfClass:(Class)cls{if(cls==NSButton.class)return self.button;return [super isKindOfClass:cls];}
- (void)addArrangedSubview:(id)view{[self.arrangedSubviews addObject:view];}
- (NSString *)string{return self.textStorage.string;}
@end
#define DETAIL_VIEWS(X) \
 X(NSButton,grammarPageAnalyzeButton) X(NSTextField,grammarDetailNameLabel) X(NSTextField,grammarDetailLevelLabel) X(NSTextField,grammarResultsLabel) X(NSTextField,grammarDetailBodyLabel) X(NSStackView,grammarDetailFields) X(NSStackView,grammarUsageBlock) X(NSTextField,grammarExampleLabel) X(NSButton,grammarSourceLinkButton) X(NSButton,grammarDetailBookmarkButton) X(FYSelectableSourceTextView,learningSourceTextView) X(NSTextView,grammarSourceTextView) X(NSStackView,grammarOtherStack) X(NSButton,quickGrammarExpandButton) X(NSButton,grammarExpandButton) X(NSTextField,grammarExpandedLabel) X(NSButton,quickGrammarReviewButton) X(NSButton,grammarReviewButton) X(NSTextField,quickGrammarReviewStatus)
@interface DetailLearningFact : NSObject
@property(nonatomic,copy) NSString *currentSentenceID;
@property(nonatomic) NSInteger currentVersion;
@end
@implementation DetailLearningFact @end
@interface GrammarDetailFacts : NSObject
@property(nonatomic,strong) NSMutableDictionary<NSString *,DetailNodeFact *> *views;
@property(nonatomic,strong) NSMutableArray *events,*labels,*stacks;
@property(nonatomic,strong) FYAnalysisResult *currentAnalysis,*quickSentenceAnalysis;
@property(nonatomic,strong) FYGrammarActionState *mainState,*quickState;
@property(nonatomic,strong) FYGrammarInteractionCoordinator *core;
@property(nonatomic,strong) DetailLearningFact *learning;
@property(nonatomic,strong) FYGrammarBookmark *bookmark;
@property(nonatomic,copy) NSString *quickSentenceSource,*quickSentenceAnalysisSource;
@property(nonatomic) NSInteger selectedGrammarIndex,quickSelectedGrammarIndex;
@property(nonatomic) BOOL learningAnalysisBusy,quickSentenceAnalyzing;
@property(nonatomic,copy) NSArray<NSButton *> *mainStructureButtons;
#define DECLARE_DETAIL_VIEW(type,name) - (type *)name;
DETAIL_VIEWS(DECLARE_DETAIL_VIEW)
#undef DECLARE_DETAIL_VIEW
- (NSColor *)uiInk;- (NSColor *)uiAccent;- (NSColor *)uiSelected;- (NSColor *)uiSurface;
- (BOOL)analysisMatchesCurrentSentence;
- (FYGrammarItem *)selectedGrammarItem;
- (FYGrammarBookmark *)bookmarkForCurrentGrammar;
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick;
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick;
- (NSStackView *)verticalStack;
- (NSTextField *)mutedLabel:(NSString *)text;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (void)refreshSourceHoverTips;
@end
@implementation GrammarDetailFacts
- (instancetype)init{if((self=[super init])){_views=[NSMutableDictionary new];_events=[NSMutableArray new];_labels=[NSMutableArray new];_stacks=[NSMutableArray new];_core=[FYGrammarInteractionCoordinator new];_mainState=[FYGrammarActionState new];_quickState=[FYGrammarActionState new];_learning=[DetailLearningFact new];_learning.currentSentenceID=@"sentence";_learning.currentVersion=7;
#define INIT_DETAIL_VIEW(type,name) _views[@#name]=[DetailNodeFact new];
DETAIL_VIEWS(INIT_DETAIL_VIEW)
#undef INIT_DETAIL_VIEW
}return self;}
#define DEFINE_DETAIL_VIEW(type,name) - (type *)name{return (type *)self.views[@#name];}
DETAIL_VIEWS(DEFINE_DETAIL_VIEW)
#undef DEFINE_DETAIL_VIEW
- (NSColor *)uiInk{return NSColor.brownColor;}- (NSColor *)uiAccent{return NSColor.orangeColor;}- (NSColor *)uiSelected{return NSColor.greenColor;}- (NSColor *)uiSurface{return NSColor.whiteColor;}
- (BOOL)analysisMatchesCurrentSentence{return self.currentAnalysis&&[FYLearningCoordinator analysisMatchesSentenceID:self.currentAnalysis.sentenceID version:self.currentAnalysis.version currentSentenceID:self.learning.currentSentenceID currentVersion:self.learning.currentVersion];}
- (FYGrammarItem *)selectedGrammarItem{return [FYLearningCoordinator grammarItemInList:self.currentAnalysis.grammar index:self.selectedGrammarIndex fallbackToFirst:YES];}
- (FYGrammarBookmark *)bookmarkForCurrentGrammar{return self.bookmark;}
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick{[self.events addObject:quick?@"quick-state":@"main-state"];return quick?self.quickState:self.mainState;}
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick{return [self.core grammarActionItemForQuick:quick receiver:(id<FYGrammarInteractionSource>)self];}
- (NSStackView *)verticalStack{DetailNodeFact *s=[DetailNodeFact new];[self.stacks addObject:s];return (NSStackView *)s;}
- (NSTextField *)mutedLabel:(NSString *)text{DetailNodeFact *l=[DetailNodeFact new];l.stringValue=text;[self.labels addObject:l];return (NSTextField *)l;}
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color{DetailNodeFact *l=[DetailNodeFact new];l.stringValue=text;l.font=font;l.color=color;[self.labels addObject:l];return (NSTextField *)l;}
- (void)clearArrangedSubviews:(NSStackView *)stack{[self.events addObject:stack==(id)self.grammarDetailFields?@"clear-fields":@"clear-usage"];[((DetailNodeFact *)stack).arrangedSubviews removeAllObjects];}
- (void)refreshSourceHoverTips{[self.events addObject:@"hover"];}
@end
@protocol GrammarDetailDriver <NSObject>
- (void)renderGrammarDetailAtIndex:(NSInteger)index;
- (void)highlightGrammarMatches;
- (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)textView;
- (void)clearGrammarHighlight;
- (void)applyGrammarSelectionLocally;
- (void)updateGrammarActionControlsForQuick:(BOOL)quick;
@end
static FYGrammarItem *Item(NSString *name,NSRange range,NSString *text){FYGrammarItem *i=[FYGrammarItem new];i.name=name;i.matchedRange=range;i.matchedText=text;return i;}
static DetailNodeFact *V(GrammarDetailFacts *f,NSString *name){return f.views[name];}
static id Background(DetailNodeFact *t,NSUInteger i){return [t.textStorage attribute:NSBackgroundColorAttributeName atIndex:i effectiveRange:NULL];}
static void RunGrammarDetailFixture(id<GrammarDetailDriver>d,GrammarDetailFacts *f){
 Check(NSApp==nil,@"all fixtures use native strings/fonts/colors and property facts, no UI objects");NSString *text=@"😀猫は学校へ。\n猫です。";FYGrammarItem *a=Item(@"main",NSMakeRange(2,2),@"猫は"),*b=Item(@"second",NSMakeRange(9,3),@"猫です"),*wrong=Item(@"wrong",NSMakeRange(4,2),@"別文"),*outside=Item(@"out",NSMakeRange(100,2),@"外"),*missing=Item(@"missing",NSMakeRange(NSNotFound,1),@"無");FYAnalysisResult *result=[FYAnalysisResult new];result.sentenceID=@"sentence";result.version=7;result.grammar=@[a,b,wrong,outside,missing];f.currentAnalysis=result;f.selectedGrammarIndex=0;
 DetailNodeFact *source=V(f,@"learningSourceTextView"),*grammar=V(f,@"grammarSourceTextView");source.textStorage=[[NSMutableAttributedString alloc]initWithString:text attributes:@{NSForegroundColorAttributeName:NSColor.redColor,NSUnderlineStyleAttributeName:@1,NSBackgroundColorAttributeName:NSColor.blueColor}];grammar.textStorage=[source.textStorage mutableCopy];source.selectedRange=NSMakeRange(2,2);[f.events removeAllObjects];[d highlightGrammarMatches];
 Check([source.string isEqual:text]&&source.textStorage.length==text.length&&NSEqualRanges(source.selectedRange,NSMakeRange(2,2)),@"emoji/UTF16/newline/selection characters and indices remain unchanged");Check([Background(source,2)isEqual:[[f uiAccent]colorWithAlphaComponent:0.23]]&&[Background(source,9)isEqual:[f uiSelected]],@"selected item identity uses accent alpha0.23, other match uses chosen background");Check(!Background(source,0)&&!Background(source,4)&&!Background(source,8),@"old backgrounds removed globally; canonical mismatch/outside/notfound ranges rejected");Check([[source.textStorage attribute:NSForegroundColorAttributeName atIndex:2 effectiveRange:NULL]isEqual:NSColor.redColor]&&[[source.textStorage attribute:NSUnderlineStyleAttributeName atIndex:2 effectiveRange:NULL]isEqual:@1],@"foreground and unrelated native attributes preserved");Check([grammar.textStorage isEqual:source.textStorage]&&[f.events isEqual:@[@"apply-learning",@"apply-grammar",@"hover"]],@"two view facade dispatches precede hover without changing source storage identity");
 f.learning.currentVersion=8;[d applyHighlight:NSColor.greenColor toTextView:(NSTextView *)source];Check(!Background(source,2)&&!Background(source,9),@"same sentence with stale version clears backgrounds before returning");f.learning.currentVersion=7;f.learning.currentSentenceID=@"other";[d applyHighlight:NSColor.greenColor toTextView:(NSTextView *)grammar];Check(!Background(grammar,2),@"different identity cannot highlight same text");f.learning.currentSentenceID=@"sentence";[d highlightGrammarMatches];[f.events removeAllObjects];[d clearGrammarHighlight];Check(!Background(source,2)&&!Background(grammar,9)&&[f.events isEqual:@[@"apply-learning",@"apply-grammar",@"hover"]],@"clear dispatches nil highlight through both original facades then hover");
 [d applyHighlight:NSColor.greenColor toTextView:nil];Check([source.string isEqual:text],@"nil view returns before any mutation");f.currentAnalysis=nil;[source.textStorage addAttribute:NSBackgroundColorAttributeName value:NSColor.blueColor range:NSMakeRange(0,text.length)];[d applyHighlight:NSColor.greenColor toTextView:(NSTextView *)source];Check(!Background(source,2),@"no analysis still removes stale background");f.currentAnalysis=result;
 a.referenceLevel=@"N2";a.levelVerified=NO;a.meaning=@"当前释义";a.connection=@"名词接续";a.registerNote=@"口语";a.explanation=@"本句真实用法";a.levelSourceTitle=@"合成来源";a.levelSourceURL=@"https://example.invalid/grammar";V(f,@"grammarExampleLabel").stringValue=@"  合成例句  ";f.bookmark=nil;[f.events removeAllObjects];[f.labels removeAllObjects];[f.stacks removeAllObjects];[d renderGrammarDetailAtIndex:0];
 Check([V(f,@"grammarPageAnalyzeButton").title isEqual:@"重新分析"]&&[V(f,@"grammarDetailNameLabel").stringValue isEqual:@"main"]&&[V(f,@"grammarDetailLevelLabel").stringValue isEqual:@"参考 N2 · 待核实"],@"detail name/level/unverified marker exact");Check(V(f,@"grammarResultsLabel").hidden&&!V(f,@"grammarDetailBodyLabel").hidden&&[V(f,@"grammarDetailBodyLabel").stringValue isEqual:@"当前释义"],@"detail body visibility and actual meaning");
 NSArray *chips=V(f,@"grammarDetailFields").arrangedSubviews;Check(chips.count==2,@"connection and register fields keep original order");DetailNodeFact *chip=chips[0],*value=chip.arrangedSubviews[1];Check(chip.spacing==2&&[value.stringValue isEqual:@"名词接续"]&&value.maximumNumberOfLines==3&&value.font.pointSize==13&&chip.widthAnchor.constraints.count==1&&chip.widthAnchor.constraints[0].constant==104&&chip.widthAnchor.constraints[0].active,@"native detail chip spacing/actual font/three lines/104pt active minimum");Check([((DetailNodeFact *)((DetailNodeFact *)chips[1]).arrangedSubviews[1]).stringValue isEqual:@"口语"],@"register value follows connection");
 NSArray *usage=V(f,@"grammarUsageBlock").arrangedSubviews;Check(usage.count==5&&[((DetailNodeFact *)usage[0]).stringValue isEqual:@"本句用法"]&&[((DetailNodeFact *)usage[2]).stringValue isEqual:@"例句"]&&[((DetailNodeFact *)usage[3]).stringValue isEqual:@"合成例句"],@"usage then trimmed example then provenance");Check(((DetailNodeFact *)usage[1]).maximumNumberOfLines==4&&((DetailNodeFact *)usage[3]).maximumNumberOfLines==4&&((DetailNodeFact *)usage[1]).font.pointSize==13,@"actual usage/example font and four-line caps preserved");Check(!V(f,@"grammarSourceLinkButton").hidden&&[V(f,@"grammarSourceLinkButton").toolTip isEqual:a.levelSourceURL]&&!V(f,@"grammarDetailBookmarkButton").hidden&&V(f,@"grammarDetailBookmarkButton").enabled&&V(f,@"grammarDetailBookmarkButton").tag==0&&[V(f,@"grammarDetailBookmarkButton").title isEqual:@"收藏此语法"],@"source/bookmark original url/tag/title/enable semantics");Check([[f.events subarrayWithRange:NSMakeRange(0,3)]isEqual:@[@"detail",@"clear-fields",@"clear-usage"]]&&[f.events containsObject:@"controls-main"],@"detail factory clearing and original controls facade order");
 a.meaning=@"";a.connection=@"";a.registerNote=@"";a.explanation=@"";a.referenceLevel=@"";a.levelSourceURL=@"";a.levelSourceTitle=@"";V(f,@"grammarExampleLabel").stringValue=@"还没有例句。";f.bookmark=[FYGrammarBookmark new];[d renderGrammarDetailAtIndex:0];Check([V(f,@"grammarDetailLevelLabel").stringValue isEqual:@"等级待核实"]&&[V(f,@"grammarDetailBodyLabel").stringValue isEqual:@"这条语法暂无可核实的释义。"]&&V(f,@"grammarSourceLinkButton").hidden,@"empty metadata/meaning keeps original fallback and source hidden");chips=V(f,@"grammarDetailFields").arrangedSubviews;Check(chips.count==1&&[((DetailNodeFact *)((DetailNodeFact *)chips[0]).arrangedSubviews[1]).stringValue isEqual:@"待补充"]&&V(f,@"grammarUsageBlock").arrangedSubviews.count==0,@"one fallback field, sentinel example omitted and old usage cleared");Check([V(f,@"grammarDetailBookmarkButton").title isEqual:@"已收藏 · 取消收藏"],@"existing bookmark changes only original title");
 DetailNodeFact *node0=[DetailNodeFact new],*node1=[DetailNodeFact new],*other0=[DetailNodeFact new],*other1=[DetailNodeFact new],*plain=[DetailNodeFact new];node0.tag=0;node1.tag=1;other0.button=YES;other0.tag=0;other1.button=YES;other1.tag=1;plain.state=NSControlStateValueMixed;f.mainStructureButtons=(id)@[node0,node1];V(f,@"grammarOtherStack").arrangedSubviews=[@[other0,plain,other1]mutableCopy];f.selectedGrammarIndex=1;[f.events removeAllObjects];[d applyGrammarSelectionLocally];Check(CGColorEqualToColor(node1.layer.backgroundColor,f.uiSelected.CGColor)&&CGColorEqualToColor(node0.layer.backgroundColor,FYAdventureColor(@"paper").CGColor),@"selection colors existing structure buttons without rebuilding them");Check(other0.state==NSControlStateValueOff&&other1.state==NSControlStateValueOn&&plain.state==NSControlStateValueMixed&&CGColorEqualToColor(other0.layer.backgroundColor,f.uiSurface.CGColor),@"other rows update button state/color and ignore nonbuttons");Check([f.events.firstObject isEqual:@"detail"]&&[f.events.lastObject isEqual:@"hover"]&&[V(f,@"grammarDetailNameLabel").stringValue isEqual:@"second"],@"local selected detail before highlighting/hover");
 f.selectedGrammarIndex=100;[f.events removeAllObjects];[d applyGrammarSelectionLocally];Check(![f.events containsObject:@"detail"]&&[f.events containsObject:@"hover"],@"out-of-range local selection skips detail but preserves highlight refresh");f.selectedGrammarIndex=0;f.mainState.expandedItem=a;[f.mainState.pending addObject:a];[d updateGrammarActionControlsForQuick:NO];Check([V(f,@"grammarExpandButton").title isEqual:@"正在展开…"]&&!V(f,@"grammarExpandButton").enabled&&!V(f,@"grammarExpandedLabel").hidden,@"pending main item disables expand with busy title");[f.mainState.pending removeObject:a];[f.mainState.explanations setObject:@"  原样解释  " forKey:a];[d updateGrammarActionControlsForQuick:NO];Check([V(f,@"grammarExpandButton").title isEqual:@"收起解释"]&&[V(f,@"grammarExpandedLabel").stringValue isEqual:@"  原样解释  "],@"expanded cached body remains untrimmed");f.mainState.expandedItem=nil;[f.mainState.errors setObject:@"合成错误" forKey:a];[d updateGrammarActionControlsForQuick:NO];Check([V(f,@"grammarExpandButton").title isEqual:@"重试解释"]&&V(f,@"grammarExpandedLabel").hidden,@"main error retry title and collapsed body");
 f.mainState.reviewing=YES;[d updateGrammarActionControlsForQuick:NO];Check(!V(f,@"grammarReviewButton").enabled&&[V(f,@"grammarReviewButton").title isEqual:@"正在复核…"],@"reviewing original title and disabled action");f.mainState.reviewing=NO;f.learningAnalysisBusy=YES;[d updateGrammarActionControlsForQuick:NO];Check(!V(f,@"grammarReviewButton").enabled,@"initial analysis busy disables main review");f.learningAnalysisBusy=NO;f.learning.currentVersion=8;[d updateGrammarActionControlsForQuick:NO];Check(V(f,@"grammarReviewButton").hidden&&V(f,@"grammarExpandButton").hidden&&V(f,@"grammarExpandedLabel").hidden&&[V(f,@"grammarExpandedLabel").stringValue isEqual:@""],@"stale analysis hides actions and clears expanded text");f.learning.currentVersion=7;
 f.quickSentenceAnalysis=result;f.quickSentenceSource=@"quick text";f.quickSentenceAnalysisSource=@"quick text";f.quickSelectedGrammarIndex=0;f.quickState.reviewStatus=@"复核说明";NSString *held=V(f,@"grammarExpandedLabel").stringValue;[d updateGrammarActionControlsForQuick:YES];Check(!V(f,@"quickGrammarReviewButton").hidden&&V(f,@"quickGrammarReviewButton").enabled&&!V(f,@"quickGrammarReviewStatus").hidden&&[V(f,@"quickGrammarReviewStatus").stringValue isEqual:@"复核说明"]&&[V(f,@"grammarExpandedLabel").stringValue isEqual:held],@"quick independent result/state/status leaves main detail untouched");f.quickSentenceAnalyzing=YES;f.quickState.reviewStatus=@"";[d updateGrammarActionControlsForQuick:YES];Check(!V(f,@"quickGrammarReviewButton").enabled&&V(f,@"quickGrammarReviewStatus").hidden,@"quick analysis busy and empty status visibility");f.quickSentenceSource=@"changed";[d updateGrammarActionControlsForQuick:YES];Check(V(f,@"quickGrammarReviewButton").hidden&&V(f,@"quickGrammarExpandButton").hidden,@"quick source mismatch suppresses old actions");Check(NSApp==nil,@"all six native algorithms executed with no app/window/control/database/API");
}
