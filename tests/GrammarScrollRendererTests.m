#import "presentation/FYGrammarScrollRenderer.h"
#import "FYGrammarScrollTestFacts.h"
@interface GrammarScrollDriverFact : NSObject <GrammarScrollDriver>
@property(nonatomic,strong) GrammarScrollFacts *facts;
@end
@implementation GrammarScrollDriverFact
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick{return [FYGrammarScrollRenderer structureScrollOffsetForQuick:quick source:(id<FYGrammarScrollSource>)self.facts];}
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick{[FYGrammarScrollRenderer restoreStructureScrollOffset:offset quick:quick source:(id<FYGrammarScrollSource>)self.facts];}
- (void)refreshQuickGrammarActionDetail{[FYGrammarScrollRenderer refreshQuickGrammarActionDetailWithSource:(id<FYGrammarScrollSource>)self.facts];}
- (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates{[FYGrammarScrollRenderer updateGrammarReviewDisplayForQuick:quick preservingPosition:updates source:(id<FYGrammarScrollSource>)self.facts];}
@end
int main(void){@autoreleasepool{GrammarScrollDriverFact *d=[GrammarScrollDriverFact new];d.facts=[GrammarScrollFacts new];d.facts.trace=[NSMutableArray new];unsigned int count=0;Ivar *ivars=class_copyIvarList(FYGrammarScrollRenderer.class,&count);free(ivars);Check(count==0,@"native renderer owns no duplicated view/state/idle source");RunGrammarScrollFixture(d,d.facts);printf("PASS GrammarScrollRendererTests: %lu checks\n",(unsigned long)checks);}return 0;}
