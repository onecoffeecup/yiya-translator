#import "presentation/FYGrammarPresentationController.h"
#import "FYGrammarPageTestFacts.h"
#ifndef FY_GRAMMAR_PAGE_EXTRACTED
#define FY_GRAMMAR_PAGE_EXTRACTED 1
#endif
@interface FYGrammarPresentationController (GuardTestPeers)
- (NSArray<NSButton *> *)quickStructureButtons;
- (void)setQuickStructureButtons:(NSArray<NSButton *> *)buttons;
- (NSScrollView *)quickStructureScrollView;
- (void)setQuickStructureScrollView:(NSScrollView *)scroll;
@end
@interface GrammarPagePeerFact : NSObject
@property(nonatomic,copy) NSArray<NSButton *> *quickStructureButtons;
@property(nonatomic,strong) NSScrollView *quickStructureScrollView;
@end
@implementation GrammarPagePeerFact @end
@interface GrammarPageHostFixture : FYGrammarPresentationController <GrammarPageGuardDriver>
@property(nonatomic) NSUInteger hostReads;
@end
@implementation GrammarPageHostFixture
- (id<FYGrammarPresentationControllerHost>)host{self.hostReads++;return [super host];}
- (NSStackView *)verticalStack{return NativeBoundary();}
@end
int main(int argc,const char *argv[]){@autoreleasepool{GrammarPagePeerFact *peer=[GrammarPagePeerFact new];GrammarPageHostFixture *s=[[GrammarPageHostFixture alloc]initWithHost:(id<FYGrammarPresentationControllerHost>)peer];if(argc>1){RunValidGrammarBoundary(s,[NSString stringWithUTF8String:argv[1]]);return 2;}RunGrammarPageGuardFixture(s);Check(s.host==(id)peer,@"original weak Host remains native action target");
#if FY_GRAMMAR_PAGE_EXTRACTED
NSUInteger before=s.hostReads;Check(s.grammarControlTarget==peer&&s.hostReads==before+1,@"new native target adapter reads same weak Host exactly once");
#endif
CheckValidBoundaryChildren([NSString stringWithUTF8String:argv[0]]);printf("PASS GrammarPageHostTests: %lu checks; actual original/new controller guards and factory boundary, complete UI NOT RUN\n",(unsigned long)checks);}return 0;}
