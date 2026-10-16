#import "presentation/FYReferencePresentationController.h"
#import "FYReferenceRendererTestFacts.h"
@interface ReferenceRendererFixture : NSObject <FYReferenceQuerySource,FYSourceHoverSource,FYReferenceRenderSource,ReferenceRendererDriver>
@property(nonatomic,strong) ReferenceRendererFacts*facts;
@property(nonatomic,strong) ReferenceResourceBoundary*resourceBoundary;
@property(nonatomic,strong) FYReferenceQueryCoordinator*queryCoordinator;
@property(nonatomic,strong) FYSourceHoverCoordinator*hoverCoordinator;
@property(nonatomic,weak) id host;
@property(nonatomic, strong) NSView *referenceCard;
@property(nonatomic, strong) NSStackView *referenceDetailStack;
@property(nonatomic, strong) NSPopUpButton *referenceEntryPopup;
@property(nonatomic, strong) NSStackView *referenceMoreExamples;
@property(nonatomic, strong) NSTextField *referenceSearchField;
@property(nonatomic, strong) NSPopUpButton *referenceSensePopup;
@property(nonatomic, strong) NSStackView *referenceStack;
@property(nonatomic, strong) NSSegmentedControl *referenceTabs;
@end
@implementation ReferenceRendererFixture
- (instancetype)init{if((self=[super init])){_queryCoordinator=[FYReferenceQueryCoordinator new];_hoverCoordinator=[FYSourceHoverCoordinator new];}return self;}
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
- (NSStackView*)verticalStack{return(NSStackView*)Node();}
- (NSStackView*)horizontalStack{return(NSStackView*)Node();}
- (NSTextField*)label:(NSString*)text font:(NSFont*)font color:(NSColor*)color{ReferenceNodeFact*n=Node();n.stringValue=text;n.font=font;n.color=color;return(NSTextField*)n;}
- (NSTextField*)mutedLabel:(NSString*)text{return[self label:text font:[NSFont systemFontOfSize:12]color:NSColor.grayColor];}
- (NSTextField*)cardTitle:(NSString*)text{return[self label:text font:[NSFont boldSystemFontOfSize:15]color:NSColor.brownColor];}
- (NSTextField*)textField:(NSString*)placeholder{return[self label:@""font:[NSFont systemFontOfSize:13]color:NSColor.brownColor];}
- (NSSegmentedControl*)segmentedWithLabels:(NSArray*)labels action:(SEL)action{ReferenceNodeFact*n=Node();n.items=[labels mutableCopy];n.target=self.resourceBoundary;n.action=action;return(NSSegmentedControl*)n;}
- (NSButton*)workspaceButton:(NSString*)title action:(SEL)action primary:(BOOL)primary{ReferenceNodeFact*n=Node();n.title=title;n.action=action;n.target=self.resourceBoundary;return(NSButton*)n;}
- (NSColor*)uiInk{return NSColor.brownColor;}
- (NSColor*)uiMuted{return NSColor.grayColor;}
- (NSColor*)uiBorder{return NSColor.grayColor;}
- (NSColor*)uiAccent{return NSColor.brownColor;}
- (NSColor*)uiSurface{return NSColor.whiteColor;}
- (NSView*)cardWithStack:(NSStackView*)stack{ReferenceNodeFact*n=Node();[n addArrangedSubview:(id)stack];return(NSView*)n;}
- (NSView*)workspaceSection:(NSStackView*)stack{return[self cardWithStack:stack];}
- (void)clearArrangedSubviews:(NSStackView*)stack{self.facts.clears++;[((ReferenceNodeFact*)stack).arrangedSubviews removeAllObjects];}
- (FYSelectableSourceTextView*)learningSourceTextView{return(id)self.facts.main;}
- (NSTextView*)grammarSourceTextView{return(id)self.facts.grammar;}
- (FYSelectableSourceTextView*)quickSourceTextView{return(id)self.facts.quick;}
- (NSWindow*)mainWindow{return(id)self.facts.window;}
- (NSArray*)pages{return self.facts.pages;}
- (void)selectPageAtIndex:(NSInteger)index{[self.facts.events addObject:[NSString stringWithFormat:@"page%ld",(long)index]];}
- (FYVocabularyEntry*)wordForCardButton:(NSButton*)sender{return self.facts.savedWord;}
- (id)referenceActionTarget { return self.host; }
- (FYReferenceDictionary *)makeReferenceDictionary { return [[FYReferenceDictionary alloc] initWithURL:[self.host referenceResourceURL:@"reference.sqlite"]]; }
- (BOOL)hasReferenceStack { return self.referenceStack!=nil; }
- (void)setReferenceSearchText:(NSString *)text { self.referenceSearchField.stringValue=text; }
- (void)clearReferenceRows { [self clearArrangedSubviews:self.referenceStack]; }
- (void)showReferenceLoadingWord:(NSString *)word { [self.referenceStack addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"正在查询「%@」的本机资料…",word]]]; }
- (void)showReferenceEmptyWord:(NSString *)word error:(NSError *)error { [FYReferenceRenderer showEmptyWord:word error:error receiver:self]; }
- (void)renderReferenceRecords:(NSArray<NSDictionary *> *)records { [FYReferenceRenderer renderRecords:records receiver:self]; }
- (NSString *)mainHoverText { return self.learningSourceTextView.string; }
- (BOOL)mainHoverEditable { return self.learningSourceTextView.editable; }
- (NSArray *)mainHoverViews { return @[self.learningSourceTextView ?: (id)NSNull.null,self.grammarSourceTextView ?: (id)NSNull.null]; }
- (id<NSObject>)quickHoverView { return self.quickSourceTextView; }
- (NSString *)hoverTextForView:(id<NSObject>)view { return [(NSTextView *)view string]; }
- (BOOL)hoverEditableForView:(id<NSObject>)view { return [(NSTextView *)view isEditable]; }
- (void)clearSourceHoverAttributes:(NSArray *)views { [FYReferenceRenderer clearHoverAttributes:views]; }

- (void)lookupReferenceWord:(NSString *)word reading:(NSString *)reading { [self.queryCoordinator lookupWord:word reading:reading receiver:self]; }
- (void)applyAnalysisHoverTips:(FYAnalysisResult *)analysis source:(NSString *)source views:(NSArray *)views { [self.hoverCoordinator applyAnalysis:analysis source:source views:views receiver:self]; }
- (void)populateSourceHoverTips:(NSString *)source views:(NSArray *)views analysis:(FYAnalysisResult *)analysis fallback:(NSString *)fallback isCurrent:(BOOL (^)(void))isCurrent { [self.hoverCoordinator populateSource:source views:views analysis:analysis fallback:fallback isCurrent:isCurrent receiver:self]; }
- (void)refreshSourceHoverTips { [self.hoverCoordinator refreshMainWithReceiver:self]; }
- (void)refreshQuickSentenceHoverTips { [self.hoverCoordinator refreshQuickWithReceiver:self]; }
- (NSView *)makeIntegratedReferenceCard { return [FYReferenceRenderer makeReferenceCardWithReceiver:self]; }
- (NSButton *)referenceLink:(NSString *)title URL:(NSString *)url { return [FYReferenceRenderer referenceLink:title URL:url receiver:self]; }
- (void)revealReferenceCard { [FYReferenceRenderer revealReferenceCardWithReceiver:self]; }
- (void)showSavedWordReference:(NSButton *)sender { [FYReferenceRenderer showSavedWordReference:sender receiver:self]; }
- (void)referenceEntryChanged:(id)sender { [FYReferenceRenderer referenceEntryChangedWithReceiver:self]; }
- (void)referenceTabChanged:(id)sender { [FYReferenceRenderer referenceTabChangedWithReceiver:self]; }
- (void)addReferenceDisclosure:(NSString *)title content:(NSView *)content { [FYReferenceRenderer addDisclosure:title content:content receiver:self]; }
- (void)toggleReferenceExtra:(NSButton *)sender { [FYReferenceRenderer toggleExtra:sender receiver:self]; }
- (void)setSourceHoverTip:(NSString *)tip range:(NSRange)range source:(NSString *)source views:(NSArray *)views { [FYReferenceRenderer setHoverTip:tip range:range source:source views:views receiver:self]; }
@end
static id<ReferenceRendererDriver> Source(ReferenceRendererFacts*f){activeFacts=f;ReferenceRendererFixture*s=[ReferenceRendererFixture new];s.facts=f;s.resourceBoundary=[ReferenceResourceBoundary new];s.resourceBoundary.facts=f;s.host=s.resourceBoundary;return s;}
int main(void){@autoreleasepool{unsigned n=0;Ivar*v=class_copyIvarList(FYReferenceRenderer.class,&n);free(v);Check(n==0,@"Reference renderer has zero stored state");InstallServices();InstallNativeFactories();ReferenceRendererFacts*f=[ReferenceRendererFacts new];RunReferenceRenderer(Source(f),f);RestoreNativeFactories();RestoreServices();activeFacts=nil;printf("PASS ReferenceRendererTests: %lu checks\n",(unsigned long)checks);}return 0;}
