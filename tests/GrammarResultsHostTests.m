#import "presentation/FYGrammarPresentationController.h"
#import "FYGrammarResultsTestFacts.h"
@interface GrammarResultsHostFixture : FYGrammarPresentationController <GrammarResultsDriver>
@property(nonatomic,strong) GrammarResultsFacts *facts;
@end
@implementation GrammarResultsHostFixture
- (FYGrammarInteractionCoordinator *)grammarInteractionCoordinator{return self.facts.core;}
- (NSButton *)analyzeButton{return [self.facts analyzeButton];}
- (NSTextField *)grammarDetailBodyLabel{return [self.facts grammarDetailBodyLabel];}
- (NSButton *)grammarDetailBookmarkButton{return [self.facts grammarDetailBookmarkButton];}
- (NSStackView *)grammarDetailFields{return [self.facts grammarDetailFields];}
- (NSTextField *)grammarDetailLevelLabel{return [self.facts grammarDetailLevelLabel];}
- (NSTextField *)grammarDetailNameLabel{return [self.facts grammarDetailNameLabel];}
- (NSButton *)grammarEmptyAnalyzeButton{return [self.facts grammarEmptyAnalyzeButton];}
- (NSTextField *)grammarEmptyHint{return [self.facts grammarEmptyHint];}
- (NSView *)grammarEmptyPane{return [self.facts grammarEmptyPane];}
- (NSTextField *)grammarEmptyTitle{return [self.facts grammarEmptyTitle];}
- (NSView *)grammarExamplesPane{return [self.facts grammarExamplesPane];}
- (NSButton *)grammarExpandButton{return [self.facts grammarExpandButton];}
- (NSTextField *)grammarExpandedLabel{return [self.facts grammarExpandedLabel];}
- (NSArray<NSControl *> *)grammarFollowupControls{return [self.facts grammarFollowupControls];}
- (NSView *)grammarFollowupDisclosure{return [self.facts grammarFollowupDisclosure];}
- (NSTextField *)grammarFollowupResultLabel{return [self.facts grammarFollowupResultLabel];}
- (NSButton *)grammarFollowupToggle{return [self.facts grammarFollowupToggle];}
- (NSTextField *)grammarOtherEmptyLabel{return [self.facts grammarOtherEmptyLabel];}
- (NSStackView *)grammarOtherStack{return [self.facts grammarOtherStack];}
- (NSButton *)grammarPageAnalyzeButton{return [self.facts grammarPageAnalyzeButton];}
- (NSView *)grammarPointsPane{return [self.facts grammarPointsPane];}
- (NSTextField *)grammarReferenceNote{return [self.facts grammarReferenceNote];}
- (NSTextField *)grammarResultsLabel{return [self.facts grammarResultsLabel];}
- (NSButton *)grammarReviewButton{return [self.facts grammarReviewButton];}
- (NSButton *)grammarSourceLinkButton{return [self.facts grammarSourceLinkButton];}
- (NSTextField *)grammarStatusLabel{return [self.facts grammarStatusLabel];}
- (NSView *)grammarStructureCard{return [self.facts grammarStructureCard];}
- (NSArray<NSButton *> *)grammarTabButtons{return [self.facts grammarTabButtons];}
- (NSView *)grammarTabRow{return [self.facts grammarTabRow];}
- (NSArray<NSView *> *)grammarTabUnderlines{return [self.facts grammarTabUnderlines];}
- (NSTextField *)liveLevelTag{return [self.facts liveLevelTag];}
- (NSTextField *)sentenceInsightLabel{return [self.facts sentenceInsightLabel];}
- (NSStackView *)sentenceInsightStack{return [self.facts sentenceInsightStack];}
- (NSStackView *)sentenceStructureStack{return [self.facts sentenceStructureStack];}
- (NSInteger)selectedGrammarIndex{return self.facts.selectedGrammarIndex;}
- (void)setSelectedGrammarIndex:(NSInteger)value{self.facts.selectedGrammarIndex=value;}
- (NSInteger)selectedGrammarTab{return self.facts.selectedGrammarTab;}
- (FYLearningCoordinator *)learningCoordinator{return (FYLearningCoordinator *)self.facts.learning;}
- (NSColor *)uiInk{return self.facts.uiInk;}- (NSColor *)uiMuted{return self.facts.uiMuted;}- (NSColor *)uiSelected{return self.facts.uiSelected;}- (NSColor *)uiSurface{return self.facts.uiSurface;}
- (void)updateGrammarActionControlsForQuick:(BOOL)quick{[self.facts updateGrammarActionControlsForQuick:quick];}
- (NSString *)currentSentenceLevelTag{return [self.facts currentSentenceLevelTag];}
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick{return [self.facts structureScrollOffsetForQuick:quick];}
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick{[self.facts restoreStructureScrollOffset:offset quick:quick];}
- (void)clearArrangedSubviews:(NSStackView *)s{[self.facts clearArrangedSubviews:s];}
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)r source:(NSString *)source quick:(BOOL)quick{return [self.facts structureViewForAnalysis:r source:source quick:quick];}
- (NSTextField *)mutedLabel:(NSString *)t{return [self.facts mutedLabel:t];}
- (void)clearGrammarHighlight{[self.facts clearGrammarHighlight];}
- (void)highlightGrammarMatches{[self.facts highlightGrammarMatches];}
- (void)renderGrammarDetailAtIndex:(NSInteger)index{[self.facts renderGrammarDetailAtIndex:index];}
- (NSButton *)workspaceButton:(NSString *)t action:(SEL)a primary:(BOOL)p{return [self.facts workspaceButton:t action:a primary:p];}
- (void)setAnalyzeBusy:(BOOL)busy{self.facts.busyCalls++;[self.facts.events addObject:@"busy-call"];[super setAnalyzeBusy:busy];}
- (void)applyGrammarTabSelection{self.facts.tabCalls++;[self.facts.events addObject:@"tab"];[super applyGrammarTabSelection];}
@end
int main(void){@autoreleasepool{GrammarResultsHostFixture *s=[[GrammarResultsHostFixture alloc]initWithHost:nil];s.facts=[GrammarResultsFacts new];RunGrammarResultsFixture(s,s.facts);printf("PASS GrammarResultsHostTests: %lu checks, actual original/new five algorithms\n",(unsigned long)checks);}return 0;}
