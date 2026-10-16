#import "presentation/FYStudyPresentationController.h"
#import "FYStudyRendererTestFacts.h"
@interface StudyRendererHostFixture:FYStudyPresentationController<StudyRendererDriver>
@property(nonatomic,strong) StudyRendererFacts*facts;
@end
@implementation StudyRendererHostFixture

- (FYStudyChatSession*)studyChatSession{return (FYStudyChatSession*)self.facts.session;}
- (FYStudyChatView*)mainStudyChatView{return (FYStudyChatView*)self.facts.main;}
- (FYStudyChatView*)overlayStudyChatView{return (FYStudyChatView*)self.facts.overlay;}
- (BOOL)chatResolvingSource{return self.facts.resolving;}
- (FYInlineBlockSnapshot*)inlineReturnSnapshot{return self.facts.returnSnapshot;}
- (NSButton*)inlineReturnButton{return self.facts.returnButton;}
- (void)setInlineReturnButton:(NSButton*)b{self.facts.returnButton=b;}
- (void)ensureStudyChatSession{self.facts.ensures++;}
- (void)sendStudyChat:(NSString*)text{self.facts.sends++;self.facts.sent=text;}
- (void)referenceLatestStudySentence:(id)sender{Check(sender==nil,@"chat latest keeps nil original sender");self.facts.latest++;}
- (void)returnFromStudyChatToInlineLearning:(id)sender{Check(sender==nil,@"chat return keeps nil original sender");self.facts.returns++;}
- (void)closeStudyOverlay:(id)sender{Check(sender==nil,@"chat close keeps nil original sender");self.facts.closes++;}
- (NSColor*)uiSurface{return FYAdventureColor(@"paper");}
- (NSColor*)uiSelected{return FYAdventureColor(@"reading");}
- (NSColor*)uiInk{return FYAdventureColor(@"ink");}
- (NSColor*)uiMuted{return FYAdventureColor(@"muted");}
- (NSColor*)uiAccent{return FYAdventureColor(@"orange");}
- (FYStudyOverlayPanel*)quickSentencePanel{return (FYStudyOverlayPanel*)self.facts.panel;}
- (CGFloat)quickSentenceScrollOffset{return self.facts.offset;}
- (void)setQuickSentenceScrollOffset:(CGFloat)v{self.facts.offset=v;}
- (NSArray<NSButton*>*)quickGrammarChoices{return self.facts.choices;}
- (NSArray<NSButton*>*)quickStructureButtons{return self.facts.structure;}
- (NSTextField*)quickGrammarBookmarkStatus{return (NSTextField*)self.facts.status;}
- (NSButton*)quickGrammarBookmarkButton{return (NSButton*)self.facts.bookmarkButton;}
- (BOOL)quickGrammarBookmarkPending{return self.facts.pending;}
- (NSString*)quickSentenceID{return self.facts.sentenceID;}
- (FYGrammarBookmark*)quickGrammarBookmark{return self.facts.bookmark;}
- (FYAnalysisResult*)quickSentenceAnalysis{return self.facts.analysis;}
- (NSStackView*)quickGrammarStack{return (NSStackView*)self.facts.stack;}
- (NSView*)quickGrammarDetailCard{return (NSView*)self.facts.detail;}
- (void)setQuickGrammarDetailCard:(NSView*)v{self.facts.detail=(StudyNodeFact*)v;}
- (NSButton*)quickSelectedGrammarButton{return (NSButton*)self.facts.selected;}
- (void)setQuickSelectedGrammarButton:(NSButton*)v{self.facts.selected=(StudyNodeFact*)v;}
- (NSInteger)quickSelectedGrammarIndex{return self.facts.index;}
- (void)setQuickSelectedGrammarIndex:(NSInteger)v{self.facts.index=v;}
- (FYGrammarActionState*)quickGrammarActions{return self.facts.actions;}
- (void)selectQuickGrammar:(NSButton*)sender{self.facts.selects++;self.facts.selected=(StudyNodeFact*)sender;}
- (NSView*)quickGrammarDetailForItem:(FYGrammarItem*)item{Check(item==self.facts.analysis.grammar[self.facts.index],@"native selected detail factory receives original exact item");self.facts.factories++;[self.facts.trace addObject:@"factory"];return (NSView*)self.facts.replacement;}
- (NSView*)card{return (NSView*)self.facts.card;}
- (void)setQuickGrammarBookmarkButton:(NSButton*)v{self.facts.bookmarkButton=(id)v;}
- (void)setQuickGrammarBookmarkStatus:(NSTextField*)v{self.facts.status=(id)v;}
- (NSButton*)quickGrammarExpandButton{return (id)self.facts.expand;}
- (void)setQuickGrammarExpandButton:(NSButton*)v{self.facts.expand=(id)v;}
- (NSStackView*)verticalStack{StudyNodeFact*n=SNode(@"vertical",self.facts.trace);n.leadingAnchor=[StudyAnchorFact new];n.trailingAnchor=[StudyAnchorFact new];n.topAnchor=[StudyAnchorFact new];n.bottomAnchor=[StudyAnchorFact new];for(StudyAnchorFact*a in @[n.leadingAnchor,n.trailingAnchor,n.topAnchor,n.bottomAnchor])a.constraints=self.facts.constraints;return (id)n;}
- (NSStackView*)horizontalStack{return [self verticalStack];}
- (NSButton*)workspaceButton:(NSString*)title action:(SEL)action primary:(BOOL)primary{StudyNodeFact*n=SNode(@"workspace-button",self.facts.trace);n.title=title;return (id)n;}
- (NSTextField*)mutedLabel:(NSString*)text{StudyNodeFact*n=SNode(@"muted",self.facts.trace);n.stringValue=text;return (id)n;}
- (FYGrammarActionState*)grammarActionsForQuick:(BOOL)quick{Check(quick,@"detail uses original quick action-state scope");return self.facts.actions;}
- (void)updateGrammarActionControlsForQuick:(BOOL)quick{Check(quick,@"detail updates quick controls");self.facts.actionUpdates++;}

- (NSView*)performQuickDetail:(FYGrammarItem*)item{return [super quickGrammarDetailForItem:item];}
- (void)performQuickGrammar:(NSButton*)sender{[super selectQuickGrammar:sender];}
@end
static id<StudyRendererDriver>Source(StudyRendererFacts*f){StudyRendererHostFixture*s=[[StudyRendererHostFixture alloc]initWithHost:nil];s.facts=f;return s;}
int main(void){@autoreleasepool{Check(NSApp==nil,@"actual old/new Study native fixture starts with no UI/application");StudyRendererFacts*f=[StudyRendererFacts new];RunStudyRendererFixture(Source(f),f);RunStudyRendererLeases(^id<StudyRendererDriver>(StudyRendererFacts*f){return Source(f);});Check(NSApp==nil,@"actual native wrappers/body complete without NSApp or windows");printf("PASS StudyRendererHostTests: %lu checks; actual original/new same fixture with primitive native boundaries\n",(unsigned long)checks);}return 0;}
