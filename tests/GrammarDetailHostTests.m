#import "presentation/FYGrammarPresentationController.h"
#import "FYGrammarDetailTestFacts.h"
@interface GrammarDetailHostFixture : FYGrammarPresentationController <GrammarDetailDriver>
@property(nonatomic,strong) GrammarDetailFacts *facts;
@end
@implementation GrammarDetailHostFixture
#define FORWARD_DETAIL_VIEW(type,name) - (type *)name{return [self.facts name];}
DETAIL_VIEWS(FORWARD_DETAIL_VIEW)
#undef FORWARD_DETAIL_VIEW
- (FYAnalysisResult *)currentAnalysis{return self.facts.currentAnalysis;}
- (FYAnalysisResult *)quickSentenceAnalysis{return self.facts.quickSentenceAnalysis;}
- (NSString *)quickSentenceSource{return self.facts.quickSentenceSource;}
- (NSString *)quickSentenceAnalysisSource{return self.facts.quickSentenceAnalysisSource;}
- (NSInteger)selectedGrammarIndex{return self.facts.selectedGrammarIndex;}
- (NSInteger)quickSelectedGrammarIndex{return self.facts.quickSelectedGrammarIndex;}
- (BOOL)quickSentenceAnalyzing{return self.facts.quickSentenceAnalyzing;}
- (BOOL)learningAnalysisBusy{return self.facts.learningAnalysisBusy;}
- (NSArray<NSButton *> *)mainStructureButtons{return self.facts.mainStructureButtons;}
- (FYLearningCoordinator *)learningCoordinator{return (FYLearningCoordinator *)self.facts.learning;}
- (FYGrammarBookmark *)bookmarkForCurrentGrammar{return self.facts.bookmark;}
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick{return [self.facts grammarActionsForQuick:quick];}
- (NSColor *)uiInk{return self.facts.uiInk;}- (NSColor *)uiAccent{return self.facts.uiAccent;}- (NSColor *)uiSelected{return self.facts.uiSelected;}- (NSColor *)uiSurface{return self.facts.uiSurface;}
- (NSStackView *)verticalStack{return [self.facts verticalStack];}
- (NSTextField *)mutedLabel:(NSString *)t{return [self.facts mutedLabel:t];}
- (NSTextField *)label:(NSString *)t font:(NSFont *)font color:(NSColor *)color{return [self.facts label:t font:font color:color];}
- (void)clearArrangedSubviews:(NSStackView *)s{[self.facts clearArrangedSubviews:s];}
- (void)refreshSourceHoverTips{[self.facts refreshSourceHoverTips];}
- (void)renderGrammarDetailAtIndex:(NSInteger)index{[self.facts.events addObject:@"detail"];[super renderGrammarDetailAtIndex:index];}
- (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)view{[self.facts.events addObject:view==(id)self.learningSourceTextView?@"apply-learning":@"apply-grammar"];[super applyHighlight:color toTextView:view];}
- (void)updateGrammarActionControlsForQuick:(BOOL)quick{[self.facts.events addObject:quick?@"controls-quick":@"controls-main"];[super updateGrammarActionControlsForQuick:quick];}
@end
int main(void){@autoreleasepool{GrammarDetailHostFixture *s=[[GrammarDetailHostFixture alloc]initWithHost:nil];s.facts=[GrammarDetailFacts new];RunGrammarDetailFixture(s,s.facts);printf("PASS GrammarDetailHostTests: %lu checks, actual original/new controller six algorithms\n",(unsigned long)checks);}return 0;}
