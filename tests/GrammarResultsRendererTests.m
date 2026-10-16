#import "presentation/FYGrammarResultsRenderer.h"
#import "FYGrammarResultsTestFacts.h"
#import <objc/runtime.h>
@interface GrammarResultsNativeSource : GrammarResultsFacts <FYGrammarResultsSource,GrammarResultsDriver> @end
@implementation GrammarResultsNativeSource
- (void)setAnalyzeBusy:(BOOL)busy{self.busyCalls++;[self.events addObject:@"busy-call"];[FYGrammarResultsRenderer setAnalyzeBusy:busy receiver:self];}
- (void)refreshGrammarResults{[FYGrammarResultsRenderer refreshGrammarResultsWithReceiver:self];}
- (void)clearAnalysisDisplay{[FYGrammarResultsRenderer clearAnalysisDisplayWithReceiver:self];}
- (void)applyGrammarTabSelection{self.tabCalls++;[self.events addObject:@"tab"];[FYGrammarResultsRenderer applyGrammarTabSelectionWithReceiver:self];}
- (void)toggleGrammarFollowup:(id)sender{[FYGrammarResultsRenderer toggleGrammarFollowupWithReceiver:self];}
@end
int main(void){@autoreleasepool{GrammarResultsNativeSource *s=[GrammarResultsNativeSource new];unsigned int n=0;Ivar *v=class_copyIvarList(FYGrammarResultsRenderer.class,&n);free(v);Check(n==0,@"results renderer owns no duplicate state/views/idle source");RunGrammarResultsFixture(s,s);__weak GrammarResultsNativeSource *weak;@autoreleasepool{GrammarResultsNativeSource *p=[GrammarResultsNativeSource new];weak=p;[p applyGrammarTabSelection];}Check(!weak,@"results renderer does not retain borrowed source");printf("PASS GrammarResultsRendererTests: %lu checks\n",(unsigned long)checks);}return 0;}
