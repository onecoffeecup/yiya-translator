#import "presentation/FYGrammarPresentationController.h"
#import "FYGrammarScrollTestFacts.h"
@interface GrammarScrollHostFixture : FYGrammarPresentationController <GrammarScrollDriver>
@property(nonatomic,strong) GrammarScrollFacts *facts;
@end
@implementation GrammarScrollHostFixture
- (NSScrollView *)mainStructureScrollView{return [self.facts mainStructureScrollView];}
- (NSScrollView *)quickStructureScrollView{return [self.facts quickStructureScrollView];}
- (NSStackView *)quickGrammarStack{return [self.facts quickGrammarStack];}
- (NSView *)quickGrammarDetailCard{return [self.facts quickGrammarDetailCard];}
- (void)setQuickGrammarDetailCard:(NSView *)v{[self.facts setQuickGrammarDetailCard:v];}
- (FYStudyOverlayPanel *)quickSentencePanel{return [self.facts quickSentencePanel];}
- (NSButton *)grammarReviewButton{return [self.facts grammarReviewButton];}
- (NSScrollView *)quickSentenceScrollView{return [self.facts quickSentenceScrollView];}
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick{return [self.facts grammarActionItemForQuick:quick];}
- (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item{return [self.facts quickGrammarDetailForItem:item];}
@end
int main(void){@autoreleasepool{GrammarScrollHostFixture *d=[[GrammarScrollHostFixture alloc]initWithHost:nil];d.facts=[GrammarScrollFacts new];d.facts.trace=[NSMutableArray new];RunGrammarScrollFixture(d,d.facts);printf("PASS GrammarScrollHostTests: %lu checks, actual original/new controller algorithms\n",(unsigned long)checks);}return 0;}
