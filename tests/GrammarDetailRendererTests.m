#import "presentation/FYGrammarDetailRenderer.h"
#import "FYGrammarDetailTestFacts.h"
#import <objc/runtime.h>
@interface GrammarDetailNativeSource : GrammarDetailFacts <FYGrammarDetailSource,GrammarDetailDriver> @end
@implementation GrammarDetailNativeSource
- (void)renderGrammarDetailAtIndex:(NSInteger)index{[self.events addObject:@"detail"];[FYGrammarDetailRenderer renderGrammarDetailAtIndex:index source:self];}
- (void)highlightGrammarMatches{[FYGrammarDetailRenderer highlightGrammarMatchesWithSource:self];}
- (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)view{[self.events addObject:view==(id)self.learningSourceTextView?@"apply-learning":@"apply-grammar"];[FYGrammarDetailRenderer applyHighlight:color toTextView:view source:self];}
- (void)clearGrammarHighlight{[FYGrammarDetailRenderer clearGrammarHighlightWithSource:self];}
- (void)applyGrammarSelectionLocally{[FYGrammarDetailRenderer applyGrammarSelectionLocallyWithSource:self];}
- (void)updateGrammarActionControlsForQuick:(BOOL)quick{[self.events addObject:quick?@"controls-quick":@"controls-main"];[FYGrammarDetailRenderer updateGrammarActionControlsForQuick:quick source:self];}
@end
int main(void){@autoreleasepool{GrammarDetailNativeSource *s=[GrammarDetailNativeSource new];unsigned int n=0;Ivar *v=class_copyIvarList(FYGrammarDetailRenderer.class,&n);free(v);Check(n==0,@"detail renderer owns no duplicate views/state/idle source");RunGrammarDetailFixture(s,s);__weak GrammarDetailNativeSource *weak;@autoreleasepool{GrammarDetailNativeSource *p=[GrammarDetailNativeSource new];weak=p;[p applyHighlight:nil toTextView:nil];}Check(!weak,@"renderer does not retain borrowed native source");printf("PASS GrammarDetailRendererTests: %lu checks\n",(unsigned long)checks);}return 0;}
