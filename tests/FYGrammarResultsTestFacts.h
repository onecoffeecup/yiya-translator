#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import "learning/FYLearningCoordinator.h"
#import "learning/FYLearningViews.h"
#import "presentation/FYGrammarInteractionCoordinator.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface ResultsConstraintFact : NSObject @property(nonatomic) BOOL active;@end
@implementation ResultsConstraintFact @end
@interface ResultsAnchorFact : NSObject
@property(nonatomic,strong) id lastTarget;
@property(nonatomic,strong) ResultsConstraintFact *lastConstraint;
- (id)constraintEqualToAnchor:(id)anchor;
@end
@implementation ResultsAnchorFact
- (id)constraintEqualToAnchor:(id)anchor{self.lastTarget=anchor;self.lastConstraint=[ResultsConstraintFact new];return self.lastConstraint;}
@end
@interface ResultsCellFact : NSObject @property(nonatomic) BOOL truncatesLastVisibleLine;@end
@implementation ResultsCellFact @end
@interface ResultsViewFact : NSObject
@property(nonatomic,copy) NSString *title,*stringValue,*toolTip,*name;
@property(nonatomic,strong) NSFont *font;
@property(nonatomic,strong) NSColor *textColor,*contentTintColor;
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) ResultsAnchorFact *widthAnchor;
@property(nonatomic,strong) ResultsCellFact *cell;
@property(nonatomic,strong) NSMutableArray *arrangedSubviews;
@property(nonatomic) BOOL hidden,enabled,bordered,wantsLayer;
@property(nonatomic) NSInteger tag;
@property(nonatomic) NSControlStateValue state;
@property(nonatomic) NSBezelStyle bezelStyle;
@property(nonatomic) NSTextAlignment alignment;
@property(nonatomic) NSLineBreakMode lineBreakMode;
@property(nonatomic,copy) void (^onText)(NSString *text);
- (BOOL)isHidden;
- (void)addArrangedSubview:(id)view;
@end
@implementation ResultsViewFact
@synthesize stringValue=_stringValue;
- (instancetype)init{if((self=[super init])){_title=@"";_stringValue=@"";_layer=[CALayer layer];_widthAnchor=[ResultsAnchorFact new];_cell=[ResultsCellFact new];_arrangedSubviews=[NSMutableArray new];}return self;}
- (BOOL)isHidden{return self.hidden;}
- (void)addArrangedSubview:(id)view{[self.arrangedSubviews addObject:view];}
- (void)setStringValue:(NSString *)value{_stringValue=[value copy];if(self.onText)self.onText(value);}
@end
@interface ResultsLearningFact : NSObject
@property(nonatomic,copy) NSString *currentSentenceID,*currentSourceText;
@property(nonatomic) NSInteger currentVersion;
@end
@implementation ResultsLearningFact @end
@interface ResultsCoreFact : FYGrammarInteractionCoordinator
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,copy) void (^onCurrentWrite)(FYAnalysisResult *value);
@property(nonatomic,copy) void (^onErrorClear)(void);
@end
@implementation ResultsCoreFact
- (void)setAnalysisRequestGeneration:(NSInteger)value{[super setAnalysisRequestGeneration:value];[self.events addObject:@"analysis-gen"];}
- (void)setFollowupRequestGeneration:(NSInteger)value{[super setFollowupRequestGeneration:value];[self.events addObject:@"followup-gen"];}
- (void)setCurrentAnalysis:(FYAnalysisResult *)value{[super setCurrentAnalysis:value];[self.events addObject:value?@"current-set":@"current-nil"];if(self.onCurrentWrite)self.onCurrentWrite(value);}
- (void)setGrammarAnalysisError:(NSString *)value{[super setGrammarAnalysisError:value];[self.events addObject:value?@"error-set":@"error-nil"];if(!value&&self.onErrorClear)self.onErrorClear();}
- (void)setLearningAnalysisBusy:(BOOL)value{[super setLearningAnalysisBusy:value];[self.events addObject:value?@"busy-yes":@"busy-no"];}
@end
@interface ResultsCancelFact : FYLearningAnalyzer
@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic) NSUInteger cancels;
@end
@implementation ResultsCancelFact
- (void)cancelAll{self.cancels++;[self.events addObject:self.name];}
@end
@interface GrammarResultsFacts : NSObject
@property(nonatomic,strong) ResultsCoreFact *core;
@property(nonatomic,strong) ResultsLearningFact *learning;
@property(nonatomic,strong) NSMutableDictionary<NSString *,id> *views;
@property(nonatomic,strong) NSMutableArray *events,*factoryTitles,*rows;
@property(nonatomic,copy) NSString *levelTag;
@property(nonatomic,strong) ResultsViewFact *structure;
@property(nonatomic) NSInteger selectedGrammarIndex,selectedGrammarTab,lastDetail;
@property(nonatomic) CGFloat offset,lastOffset;
@property(nonatomic) NSUInteger controls,clears,highlights,details,tabCalls,busyCalls;
@property(nonatomic,copy) void (^onControls)(void);
@property(nonatomic,copy) void (^onStructure)(FYAnalysisResult *result);
@property(nonatomic,copy) void (^onFactory)(void);
@end
@protocol GrammarResultsDriver <NSObject>
- (void)setAnalyzeBusy:(BOOL)busy;
- (void)refreshGrammarResults;
- (void)clearAnalysisDisplay;
- (void)applyGrammarTabSelection;
- (void)toggleGrammarFollowup:(id)sender;
@end
static ResultsViewFact *RV(GrammarResultsFacts *f,NSString *name){return f.views[name];}
static FYAnalysisResult *Result(NSArray *items){FYAnalysisResult *r=[FYAnalysisResult new];r.sentenceID=@"sentence";r.version=4;r.grammar=items;r.sentenceNote=@"合成整句说明";return r;}
static FYGrammarItem *Grammar(NSString *name){FYGrammarItem *i=[FYGrammarItem new];i.name=name;return i;}
static NSUInteger Occurrences(NSArray *list,NSString *name){return [[list filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id obj,NSDictionary *bindings){return [obj isEqual:name];}]]count];}
static void RunGrammarResultsFixture(id<GrammarResultsDriver>d,GrammarResultsFacts *f){
 Check(NSApp==nil,@"native results fixtures create no app/view/control/window");FYGrammarItem *a=Grammar(@"条目甲"),*b=Grammar(@"条目乙");a.referenceLevel=@"N2";a.levelVerified=NO;b.referenceLevel=@"";FYAnalysisResult *r=Result(@[a,b]);f.core.currentAnalysis=r;f.selectedGrammarIndex=1;f.selectedGrammarTab=1;[f.events removeAllObjects];[d setAnalyzeBusy:YES];Check(f.core.learningAnalysisBusy&&[RV(f,@"grammarPageAnalyzeButton").title isEqual:@"分析中…"]&&!RV(f,@"analyzeButton").enabled&&!RV(f,@"grammarPageAnalyzeButton").enabled&&[RV(f,@"grammarStatusLabel").stringValue isEqual:@"正在分析…"],@"busy first updates original state and analyze controls/status");Check([f.events.firstObject isEqual:@"busy-call"]&&[f.events[1]isEqual:@"busy-yes"]&&[f.events[2]isEqual:@"tab"]&&[f.events[3]isEqual:@"controls"],@"busy retains original facade→state→tab→controls dynamic sequence");[d setAnalyzeBusy:NO];Check(!f.core.learningAnalysisBusy&&[RV(f,@"grammarPageAnalyzeButton").title isEqual:@"重新分析"]&&RV(f,@"analyzeButton").enabled,@"idle existing result uses reanalyze title");
 NSArray *tabs=f.views[@"grammarTabButtons"],*lines=f.views[@"grammarTabUnderlines"];Check([((ResultsViewFact *)tabs[0]).title isEqual:@"整句理解"]&&[((ResultsViewFact *)tabs[1]).title isEqual:@"语法点"]&&[((ResultsViewFact *)tabs[2]).title isEqual:@"例句"]&&((ResultsViewFact *)tabs[1]).font.pointSize==13,@"tabs keep exact labels and actual13pt fonts");Check(CGColorEqualToColor(((ResultsViewFact *)lines[1]).layer.backgroundColor,FYAdventureColor(@"leaf").CGColor)&&CGColorEqualToColor(((ResultsViewFact *)lines[0]).layer.backgroundColor,NSColor.clearColor.CGColor),@"selected underline uses original leaf color; missing third underline safe");
 for(NSInteger index=0;index<3;index++){f.selectedGrammarTab=index;[d applyGrammarTabSelection];Check(RV(f,@"sentenceInsightStack").hidden==(index!=0)&&RV(f,@"grammarPointsPane").hidden==(index!=1)&&RV(f,@"grammarExamplesPane").hidden==(index!=2)&&!RV(f,@"grammarEmptyPane").hidden==NO,@"each result tab shows only its original pane");}
 f.core.currentAnalysis=Result(@[]);f.selectedGrammarTab=1;[d applyGrammarTabSelection];Check(!RV(f,@"grammarEmptyPane").hidden&&RV(f,@"grammarPointsPane").hidden&&[RV(f,@"grammarEmptyTitle").stringValue isEqual:@"这句没有识别到语法点"]&&[RV(f,@"grammarEmptyAnalyzeButton").title isEqual:@"重新分析"],@"empty grammar has exact empty-tab copy and reanalyze action");f.core.grammarAnalysisError=@"合成错误";[d applyGrammarTabSelection];Check([RV(f,@"grammarEmptyTitle").stringValue isEqual:@"这次分析没有完成"]&&[RV(f,@"grammarEmptyHint").stringValue isEqual:@"合成错误\n请检查原句或翻译服务后重试。"]&&[RV(f,@"grammarEmptyAnalyzeButton").title isEqual:@"重试分析"],@"error takes priority over empty grammar");f.learning.currentSentenceID=@"";[d applyGrammarTabSelection];Check([RV(f,@"grammarEmptyTitle").stringValue isEqual:@"等待一句原文"]&&!RV(f,@"grammarEmptyAnalyzeButton").enabled,@"missing sentence takes priority over error and disables analysis");[d setAnalyzeBusy:YES];Check([RV(f,@"grammarEmptyTitle").stringValue isEqual:@"正在分析这句话"]&&[RV(f,@"grammarEmptyAnalyzeButton").title isEqual:@"分析中…"],@"busy takes priority over missing sentence/error");f.learning.currentSentenceID=@"sentence";f.core.grammarAnalysisError=nil;f.core.currentAnalysis=nil;[d setAnalyzeBusy:NO];Check([RV(f,@"grammarPageAnalyzeButton").title isEqual:@"分析此句"]&&RV(f,@"grammarTabRow").hidden&&RV(f,@"grammarStatusLabel").hidden&&!RV(f,@"grammarEmptyPane").hidden&&RV(f,@"grammarEmptyAnalyzeButton").enabled,@"no result retains native compact empty hierarchy and enabled configured sentence");
 f.views[@"grammarFollowupDisclosure"]=nil;[d toggleGrammarFollowup:nil];Check(!f.views[@"grammarFollowupDisclosure"],@"absent followup stays absent");ResultsViewFact *disclosure=[ResultsViewFact new];disclosure.hidden=YES;f.views[@"grammarFollowupDisclosure"]=disclosure;[d toggleGrammarFollowup:nil];Check(!disclosure.hidden&&[RV(f,@"grammarFollowupToggle").title isEqual:@"收起追问"]&&RV(f,@"grammarFollowupToggle").state==NSControlStateValueOn,@"followup opens from actual hidden getter");[d toggleGrammarFollowup:nil];Check(disclosure.hidden&&[RV(f,@"grammarFollowupToggle").title isEqual:@"追问"]&&RV(f,@"grammarFollowupToggle").state==NSControlStateValueOff,@"followup closes with original title/state");id toggle=f.views[@"grammarFollowupToggle"];f.views[@"grammarFollowupToggle"]=nil;[d toggleGrammarFollowup:nil];Check(!disclosure.hidden,@"missing toggle does not prevent disclosure update");f.views[@"grammarFollowupToggle"]=toggle;
 f.core.currentAnalysis=r;f.selectedGrammarTab=1;f.selectedGrammarIndex=99;f.levelTag=@"N3";f.structure=[ResultsViewFact new];f.offset=82;f.core.grammarAnalysisError=@"old";RV(f,@"grammarFollowupResultLabel").stringValue=@"old answer";NSInteger gen=f.core.followupRequestGeneration;[f.events removeAllObjects];[f.factoryTitles removeAllObjects];[f.rows removeAllObjects];[d refreshGrammarResults];Check(!f.core.grammarAnalysisError&&f.core.followupRequestGeneration==gen+1&&f.selectedGrammarIndex==0,@"refresh invalidates followup once, clears error and clamps invalid index");Check(!RV(f,@"grammarStructureCard").hidden&&!RV(f,@"grammarDetailFields").hidden&&[RV(f,@"sentenceInsightLabel").stringValue isEqual:r.sentenceNote]&&[RV(f,@"liveLevelTag").stringValue isEqual:@"N3"]&&!RV(f,@"liveLevelTag").hidden,@"refresh applies real result note/level and visibility");Check(RV(f,@"sentenceStructureStack").arrangedSubviews.count==1&&RV(f,@"sentenceStructureStack").arrangedSubviews[0]==f.structure&&f.lastOffset==82,@"refresh reuses structure-factory output and restores current horizontal offset last");Check([f.factoryTitles isEqual:@[@"条目甲",@"条目乙"]]&&f.rows.count==2&&[RV(f,@"grammarFollowupResultLabel").stringValue isEqual:@""]&&[RV(f,@"grammarStatusLabel").stringValue isEqual:@"识别到 2 条语法"],@"rows preserve source order/titles, followup clear and exact count");ResultsViewFact *row=f.rows[0];Check(row.tag==0&&row.state==NSControlStateValueOn&&[row.toolTip isEqual:@"参考 N2 · 待核实"]&&row.font.pointSize==14&&!row.bordered&&row.layer.cornerRadius==5&&row.alignment==NSTextAlignmentLeft&&row.lineBreakMode==NSLineBreakByTruncatingTail&&row.cell.truncatesLastVisibleLine,@"native row tag/state/tooltip/actualfont/style/truncation preserved");Check(row.widthAnchor.lastTarget==RV(f,@"grammarOtherStack").widthAnchor&&row.widthAnchor.lastConstraint.active,@"row equal-width constraint uses actual destination anchor");Check([f.events.firstObject isEqual:@"error-nil"]&&[f.events[1]isEqual:@"controls"]&&[f.events.lastObject isEqual:@"restore"]&&[f.events indexOfObject:@"detail"]<[f.events indexOfObject:@"highlight"]&&[f.events indexOfObject:@"highlight"]<[f.events indexOfObject:@"tab"],@"refresh error/control/detail/highlight/tab/restore sequence and overrides preserved");for(ResultsViewFact *c in f.views[@"grammarFollowupControls"])Check(c.enabled,@"matching nonempty result enables each followup control");
 f.selectedGrammarIndex=1;f.structure=nil;f.levelTag=@"";[d refreshGrammarResults];Check(f.selectedGrammarIndex==1&&[RV(f,@"liveLevelTag").stringValue isEqual:@""]&&RV(f,@"liveLevelTag").hidden&&[((ResultsViewFact *)RV(f,@"sentenceStructureStack").arrangedSubviews[0]).stringValue isEqual:@"本次解析没有整句结构图，可重新分析获取。"],@"valid index survives and missing structure uses original fallback with hidden level");f.learning.currentVersion=5;[d refreshGrammarResults];for(ResultsViewFact *c in f.views[@"grammarFollowupControls"])Check(!c.enabled,@"stale version disables followup without silently changing result");f.learning.currentVersion=4;
 f.core.currentAnalysis=Result(@[]);[f.events removeAllObjects];CGFloat held=f.lastOffset;[d refreshGrammarResults];Check([RV(f,@"grammarStatusLabel").stringValue isEqual:@"没有识别到语法"]&&[RV(f,@"grammarDetailNameLabel").stringValue isEqual:@"没有识别结果"]&&RV(f,@"grammarDetailBookmarkButton").hidden&&RV(f,@"grammarSourceLinkButton").hidden&&[f.events containsObject:@"clear-highlight"]&&![f.events containsObject:@"restore"]&&f.lastOffset==held,@"zero-item branch uses exact empty copy, clear highlight and early return before scroll restore");f.core.currentAnalysis=nil;[d refreshGrammarResults];Check([RV(f,@"grammarStatusLabel").stringValue isEqual:@"尚未分析"]&&[RV(f,@"grammarDetailNameLabel").stringValue isEqual:@"尚未分析"]&&[RV(f,@"grammarDetailBodyLabel").stringValue isEqual:@"请在实时翻译页选中一句并点「分析此句」。"]&&RV(f,@"sentenceStructureStack").arrangedSubviews.count==0,@"nil result clears structure and keeps exact native initial body");
 __weak FYAnalysisResult *retired;__weak GrammarResultsFacts *weakFacts=f;__block BOOL heldAtErrorClear=NO;@autoreleasepool{FYAnalysisResult *temporary=Result(@[a]);retired=temporary;f.core.currentAnalysis=temporary;temporary=nil;f.onStructure=^(FYAnalysisResult *value){Check(value!=nil&&value==retired,@"refresh structure factory receives the captured original result after reentrant replacement");};f.core.onErrorClear=^{weakFacts.core.currentAnalysis=nil;heldAtErrorClear=retired!=nil;};[d refreshGrammarResults];f.core.onErrorClear=nil;f.onStructure=nil;}Check(heldAtErrorClear&&!retired,@"refresh strong local result survives reentrant core replacement then releases");
 FYGrammarActionState *main=f.core.grammarActions,*quick=f.core.quickGrammarActions;ResultsCancelFact *mainCancel=(ResultsCancelFact *)main.analyzer,*quickCancel=(ResultsCancelFact *)quick.analyzer;main.expandedItem=a;[main.pending addObject:a];[main.explanations setObject:@"old" forKey:a];main.reviewing=YES;main.reviewStatus=@"old";quick.expandedItem=b;[quick.explanations setObject:@"quick" forKey:b];quick.reviewing=YES;NSInteger mainGeneration=main.generation,quickGeneration=quick.generation;f.core.currentAnalysis=r;f.core.grammarAnalysisError=@"old";f.core.learningAnalysisBusy=YES;f.core.analysisRequestGeneration=12;f.core.followupRequestGeneration=21;f.selectedGrammarIndex=1;[f.events removeAllObjects];[d clearAnalysisDisplay];
 Check(mainCancel.cancels==1&&quickCancel.cancels==0&&main.generation==mainGeneration+1&&main.pending.count==0&&main.explanations.count==0&&!main.expandedItem&&!main.reviewing&&!main.reviewStatus,@"clear resets/cancels original main state only");Check(quick.generation==quickGeneration&&quick.expandedItem==b&&quick.reviewing&&[[quick.explanations objectForKey:b]isEqual:@"quick"],@"clear preserves independent quick state/cache/tasks");Check(f.core.analysisRequestGeneration==13&&f.core.followupRequestGeneration==22&&!f.core.currentAnalysis&&!f.core.grammarAnalysisError&&!f.core.learningAnalysisBusy&&f.selectedGrammarIndex==0,@"clear generations/current/error/busy/index remain original unique owners");Check(Occurrences(f.events,@"current-nil")==2&&[f.events.firstObject isEqual:@"cancel-main"]&&[f.events indexOfObject:@"analysis-gen"]<[f.events indexOfObject:@"followup-gen"]&&[f.events indexOfObject:@"busy-call"]<[f.events indexOfObject:@"clear-fields"]&&[f.events.lastObject isEqual:@"clear-highlight"],@"clear keeps two nil writes and reset/generation/busy-tab/field/highlight order");Check(RV(f,@"grammarExpandButton").hidden&&RV(f,@"grammarExpandedLabel").hidden&&RV(f,@"grammarReviewButton").hidden&&[RV(f,@"grammarStatusLabel").stringValue isEqual:@"尚未分析"]&&[RV(f,@"sentenceInsightLabel").stringValue isEqual:@""]&&RV(f,@"sentenceInsightStack").hidden&&RV(f,@"grammarDetailBookmarkButton").hidden,@"clear preserves original native hide/reset presentation");for(ResultsViewFact *c in f.views[@"grammarFollowupControls"])Check(!c.enabled,@"clear disables each followup control");
 __block BOOL injected=NO,sawFreshAtControls=NO;FYAnalysisResult *fresh=Result(@[b]);f.core.onCurrentWrite=^(FYAnalysisResult *value){if(!value&&!injected){injected=YES;weakFacts.core.currentAnalysis=fresh;}};f.onControls=^{if(injected&&weakFacts.core.currentAnalysis==fresh)sawFreshAtControls=YES;};[d clearAnalysisDisplay];f.core.onCurrentWrite=nil;f.onControls=nil;Check(injected&&sawFreshAtControls&&!f.core.currentAnalysis,@"clear preserves current replacement during first nil, Tab reentry sees fresh result, second nil still clears it");Check(NSApp==nil,@"all five native algorithms run without window, controls, real database/credentials/API");
}

@interface GrammarResultsFacts (NativeFacts)
- (NSButton *)analyzeButton;
- (NSTextField *)grammarDetailBodyLabel;
- (NSButton *)grammarDetailBookmarkButton;
- (NSStackView *)grammarDetailFields;
- (NSTextField *)grammarDetailLevelLabel;
- (NSTextField *)grammarDetailNameLabel;
- (NSButton *)grammarEmptyAnalyzeButton;
- (NSTextField *)grammarEmptyHint;
- (NSView *)grammarEmptyPane;
- (NSTextField *)grammarEmptyTitle;
- (NSView *)grammarExamplesPane;
- (NSButton *)grammarExpandButton;
- (NSTextField *)grammarExpandedLabel;
- (NSArray<NSControl *> *)grammarFollowupControls;
- (NSView *)grammarFollowupDisclosure;
- (NSTextField *)grammarFollowupResultLabel;
- (NSButton *)grammarFollowupToggle;
- (NSTextField *)grammarOtherEmptyLabel;
- (NSStackView *)grammarOtherStack;
- (NSButton *)grammarPageAnalyzeButton;
- (NSView *)grammarPointsPane;
- (NSTextField *)grammarReferenceNote;
- (NSTextField *)grammarResultsLabel;
- (NSButton *)grammarReviewButton;
- (NSButton *)grammarSourceLinkButton;
- (NSTextField *)grammarStatusLabel;
- (NSView *)grammarStructureCard;
- (NSArray<NSButton *> *)grammarTabButtons;
- (NSView *)grammarTabRow;
- (NSArray<NSView *> *)grammarTabUnderlines;
- (NSTextField *)liveLevelTag;
- (NSTextField *)sentenceInsightLabel;
- (NSStackView *)sentenceInsightStack;
- (NSStackView *)sentenceStructureStack;
- (FYAnalysisResult *)currentAnalysis;
- (void)setCurrentAnalysis:(FYAnalysisResult *)value;
- (FYGrammarActionState *)grammarActions;
- (NSString *)grammarAnalysisError;
- (void)setGrammarAnalysisError:(NSString *)value;
- (NSInteger)analysisRequestGeneration;
- (void)setAnalysisRequestGeneration:(NSInteger)value;
- (NSInteger)followupRequestGeneration;
- (void)setFollowupRequestGeneration:(NSInteger)value;
- (BOOL)learningAnalysisBusy;
- (void)setLearningAnalysisBusy:(BOOL)value;
- (NSInteger)selectedGrammarIndex;
- (void)setSelectedGrammarIndex:(NSInteger)value;
- (NSInteger)selectedGrammarTab;
- (FYLearningCoordinator *)learningCoordinator;
- (NSColor *)uiInk;- (NSColor *)uiMuted;- (NSColor *)uiSelected;- (NSColor *)uiSurface;
- (void)updateGrammarActionControlsForQuick:(BOOL)quick;
- (NSString *)currentSentenceLevelTag;
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick;
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)result source:(NSString *)source quick:(BOOL)quick;
- (NSTextField *)mutedLabel:(NSString *)text;
- (BOOL)analysisMatchesCurrentSentence;
- (void)clearGrammarHighlight;
- (void)highlightGrammarMatches;
- (void)renderGrammarDetailAtIndex:(NSInteger)index;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
@end
@implementation GrammarResultsFacts
- (instancetype)init{if((self=[super init])){_events=[NSMutableArray new];_views=[NSMutableDictionary new];_factoryTitles=[NSMutableArray new];_rows=[NSMutableArray new];_core=[ResultsCoreFact new];_core.events=_events;_core.grammarActions=[FYGrammarActionState new];_core.quickGrammarActions=[FYGrammarActionState new];ResultsCancelFact *a=[ResultsCancelFact new];a.events=_events;a.name=@"cancel-main";ResultsCancelFact *b=[ResultsCancelFact new];b.events=_events;b.name=@"cancel-quick";_core.grammarActions.analyzer=a;_core.quickGrammarActions.analyzer=b;_learning=[ResultsLearningFact new];_learning.currentSentenceID=@"sentence";_learning.currentSourceText=@"合成原文";_learning.currentVersion=4;
_views[@"analyzeButton"]=[ResultsViewFact new];
_views[@"grammarDetailBodyLabel"]=[ResultsViewFact new];
_views[@"grammarDetailBookmarkButton"]=[ResultsViewFact new];
_views[@"grammarDetailFields"]=[ResultsViewFact new];
_views[@"grammarDetailLevelLabel"]=[ResultsViewFact new];
_views[@"grammarDetailNameLabel"]=[ResultsViewFact new];
_views[@"grammarEmptyAnalyzeButton"]=[ResultsViewFact new];
_views[@"grammarEmptyHint"]=[ResultsViewFact new];
_views[@"grammarEmptyPane"]=[ResultsViewFact new];
_views[@"grammarEmptyTitle"]=[ResultsViewFact new];
_views[@"grammarExamplesPane"]=[ResultsViewFact new];
_views[@"grammarExpandButton"]=[ResultsViewFact new];
_views[@"grammarExpandedLabel"]=[ResultsViewFact new];
_views[@"grammarFollowupDisclosure"]=[ResultsViewFact new];
_views[@"grammarFollowupResultLabel"]=[ResultsViewFact new];
_views[@"grammarFollowupToggle"]=[ResultsViewFact new];
_views[@"grammarOtherEmptyLabel"]=[ResultsViewFact new];
_views[@"grammarOtherStack"]=[ResultsViewFact new];
_views[@"grammarPageAnalyzeButton"]=[ResultsViewFact new];
_views[@"grammarPointsPane"]=[ResultsViewFact new];
_views[@"grammarReferenceNote"]=[ResultsViewFact new];
_views[@"grammarResultsLabel"]=[ResultsViewFact new];
_views[@"grammarReviewButton"]=[ResultsViewFact new];
_views[@"grammarSourceLinkButton"]=[ResultsViewFact new];
_views[@"grammarStatusLabel"]=[ResultsViewFact new];
_views[@"grammarStructureCard"]=[ResultsViewFact new];
_views[@"grammarTabRow"]=[ResultsViewFact new];
_views[@"liveLevelTag"]=[ResultsViewFact new];
_views[@"sentenceInsightLabel"]=[ResultsViewFact new];
_views[@"sentenceInsightStack"]=[ResultsViewFact new];
_views[@"sentenceStructureStack"]=[ResultsViewFact new];
_views[@"grammarTabButtons"]=@[[ResultsViewFact new],[ResultsViewFact new],[ResultsViewFact new]];_views[@"grammarTabUnderlines"]=@[[ResultsViewFact new],[ResultsViewFact new]];_views[@"grammarFollowupControls"]=@[[ResultsViewFact new],[ResultsViewFact new],[ResultsViewFact new]];}return self;}
- (NSButton *)analyzeButton{return (NSButton *)self.views[@"analyzeButton"];}
- (NSTextField *)grammarDetailBodyLabel{return (NSTextField *)self.views[@"grammarDetailBodyLabel"];}
- (NSButton *)grammarDetailBookmarkButton{return (NSButton *)self.views[@"grammarDetailBookmarkButton"];}
- (NSStackView *)grammarDetailFields{return (NSStackView *)self.views[@"grammarDetailFields"];}
- (NSTextField *)grammarDetailLevelLabel{return (NSTextField *)self.views[@"grammarDetailLevelLabel"];}
- (NSTextField *)grammarDetailNameLabel{return (NSTextField *)self.views[@"grammarDetailNameLabel"];}
- (NSButton *)grammarEmptyAnalyzeButton{return (NSButton *)self.views[@"grammarEmptyAnalyzeButton"];}
- (NSTextField *)grammarEmptyHint{return (NSTextField *)self.views[@"grammarEmptyHint"];}
- (NSView *)grammarEmptyPane{return (NSView *)self.views[@"grammarEmptyPane"];}
- (NSTextField *)grammarEmptyTitle{return (NSTextField *)self.views[@"grammarEmptyTitle"];}
- (NSView *)grammarExamplesPane{return (NSView *)self.views[@"grammarExamplesPane"];}
- (NSButton *)grammarExpandButton{return (NSButton *)self.views[@"grammarExpandButton"];}
- (NSTextField *)grammarExpandedLabel{return (NSTextField *)self.views[@"grammarExpandedLabel"];}
- (NSArray<NSControl *> *)grammarFollowupControls{return (NSArray<NSControl *> *)self.views[@"grammarFollowupControls"];}
- (NSView *)grammarFollowupDisclosure{return (NSView *)self.views[@"grammarFollowupDisclosure"];}
- (NSTextField *)grammarFollowupResultLabel{return (NSTextField *)self.views[@"grammarFollowupResultLabel"];}
- (NSButton *)grammarFollowupToggle{return (NSButton *)self.views[@"grammarFollowupToggle"];}
- (NSTextField *)grammarOtherEmptyLabel{return (NSTextField *)self.views[@"grammarOtherEmptyLabel"];}
- (NSStackView *)grammarOtherStack{return (NSStackView *)self.views[@"grammarOtherStack"];}
- (NSButton *)grammarPageAnalyzeButton{return (NSButton *)self.views[@"grammarPageAnalyzeButton"];}
- (NSView *)grammarPointsPane{return (NSView *)self.views[@"grammarPointsPane"];}
- (NSTextField *)grammarReferenceNote{return (NSTextField *)self.views[@"grammarReferenceNote"];}
- (NSTextField *)grammarResultsLabel{return (NSTextField *)self.views[@"grammarResultsLabel"];}
- (NSButton *)grammarReviewButton{return (NSButton *)self.views[@"grammarReviewButton"];}
- (NSButton *)grammarSourceLinkButton{return (NSButton *)self.views[@"grammarSourceLinkButton"];}
- (NSTextField *)grammarStatusLabel{return (NSTextField *)self.views[@"grammarStatusLabel"];}
- (NSView *)grammarStructureCard{return (NSView *)self.views[@"grammarStructureCard"];}
- (NSArray<NSButton *> *)grammarTabButtons{return (NSArray<NSButton *> *)self.views[@"grammarTabButtons"];}
- (NSView *)grammarTabRow{return (NSView *)self.views[@"grammarTabRow"];}
- (NSArray<NSView *> *)grammarTabUnderlines{return (NSArray<NSView *> *)self.views[@"grammarTabUnderlines"];}
- (NSTextField *)liveLevelTag{return (NSTextField *)self.views[@"liveLevelTag"];}
- (NSTextField *)sentenceInsightLabel{return (NSTextField *)self.views[@"sentenceInsightLabel"];}
- (NSStackView *)sentenceInsightStack{return (NSStackView *)self.views[@"sentenceInsightStack"];}
- (NSStackView *)sentenceStructureStack{return (NSStackView *)self.views[@"sentenceStructureStack"];}
- (FYAnalysisResult *)currentAnalysis{return self.core.currentAnalysis;}
- (void)setCurrentAnalysis:(FYAnalysisResult *)value{self.core.currentAnalysis=value;}
- (NSString *)grammarAnalysisError{return self.core.grammarAnalysisError;}
- (void)setGrammarAnalysisError:(NSString *)value{self.core.grammarAnalysisError=value;}
- (NSInteger)analysisRequestGeneration{return self.core.analysisRequestGeneration;}
- (void)setAnalysisRequestGeneration:(NSInteger)value{self.core.analysisRequestGeneration=value;}
- (NSInteger)followupRequestGeneration{return self.core.followupRequestGeneration;}
- (void)setFollowupRequestGeneration:(NSInteger)value{self.core.followupRequestGeneration=value;}
- (BOOL)learningAnalysisBusy{return self.core.learningAnalysisBusy;}
- (void)setLearningAnalysisBusy:(BOOL)value{self.core.learningAnalysisBusy=value;}
- (FYGrammarActionState *)grammarActions{return self.core.grammarActions;}
- (FYLearningCoordinator *)learningCoordinator{return (FYLearningCoordinator *)self.learning;}
- (NSColor *)uiInk{return NSColor.brownColor;}- (NSColor *)uiMuted{return NSColor.grayColor;}- (NSColor *)uiSelected{return NSColor.greenColor;}- (NSColor *)uiSurface{return NSColor.whiteColor;}
- (void)updateGrammarActionControlsForQuick:(BOOL)quick{Check(!quick,@"results only update original main actions");self.controls++;[self.events addObject:@"controls"];if(self.onControls)self.onControls();}
- (NSString *)currentSentenceLevelTag{[self.events addObject:@"level"];return self.levelTag;}
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick{Check(!quick,@"result captures main structure offset");[self.events addObject:@"offset"];return self.offset;}
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick{Check(!quick,@"result restores main structure offset");self.lastOffset=offset;[self.events addObject:@"restore"];}
- (void)clearArrangedSubviews:(NSStackView *)stack{NSString *name=stack==(id)self.views[@"sentenceStructureStack"]?@"clear-structure":stack==(id)self.views[@"grammarDetailFields"]?@"clear-fields":@"clear-other";[self.events addObject:name];[((ResultsViewFact *)stack).arrangedSubviews removeAllObjects];}
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)result source:(NSString *)source quick:(BOOL)quick{Check(!quick&&[source isEqual:self.learning.currentSourceText],@"structure factory receives original current source/main mode");[self.events addObject:@"structure-factory"];if(self.onStructure)self.onStructure(result);return (NSView *)self.structure;}
- (NSTextField *)mutedLabel:(NSString *)text{ResultsViewFact *v=[ResultsViewFact new];v.stringValue=text;return (NSTextField *)v;}
- (BOOL)analysisMatchesCurrentSentence{return self.core.currentAnalysis&&[FYLearningCoordinator analysisMatchesSentenceID:self.core.currentAnalysis.sentenceID version:self.core.currentAnalysis.version currentSentenceID:self.learning.currentSentenceID currentVersion:self.learning.currentVersion];}
- (void)clearGrammarHighlight{self.clears++;[self.events addObject:@"clear-highlight"];}
- (void)highlightGrammarMatches{self.highlights++;[self.events addObject:@"highlight"];}
- (void)renderGrammarDetailAtIndex:(NSInteger)index{self.details++;self.lastDetail=index;[self.events addObject:@"detail"];}
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary{Check([NSStringFromSelector(action)isEqual:@"selectGrammarItem:"]&&!primary,@"rows retain original selector/nonprimary native factory");ResultsViewFact *v=[ResultsViewFact new];v.title=title;[self.rows addObject:v];[self.factoryTitles addObject:title];if(self.onFactory)self.onFactory();return (NSButton *)v;}
@end
