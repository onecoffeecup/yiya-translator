#import "presentation/FYGrammarPageBuilder.h"
#import "FYGrammarPageTestFacts.h"
#import <objc/runtime.h>
@interface GrammarPageSourceFact : NSObject <FYGrammarPageSource,GrammarPageGuardDriver>
@property(nonatomic) NSInteger selectedGrammarIndex;
@property(nonatomic) NSInteger quickSelectedGrammarIndex;
@property(nonatomic) NSInteger selectedGrammarTab;
@property(nonatomic,strong) NSButton *analyzeButton;
@property(nonatomic,strong) NSButton *grammarBackToSourceButton;
@property(nonatomic,strong) NSTextField *grammarDetailBodyLabel;
@property(nonatomic,strong) NSButton *grammarDetailBookmarkButton;
@property(nonatomic,strong) NSStackView *grammarDetailFields;
@property(nonatomic,strong) NSTextField *grammarDetailLevelLabel;
@property(nonatomic,strong) NSTextField *grammarDetailNameLabel;
@property(nonatomic,strong) NSButton *grammarEmptyAnalyzeButton;
@property(nonatomic,strong) NSTextField *grammarEmptyHint;
@property(nonatomic,strong) NSView *grammarEmptyPane;
@property(nonatomic,strong) NSTextField *grammarEmptyTitle;
@property(nonatomic,strong) NSTextField *grammarExampleLabel;
@property(nonatomic,strong) NSView *grammarExamplesPane;
@property(nonatomic,strong) NSButton *grammarExpandButton;
@property(nonatomic,strong) NSTextField *grammarExpandedLabel;
@property(nonatomic,copy) NSArray<NSControl *> *grammarFollowupControls;
@property(nonatomic,strong) NSView *grammarFollowupDisclosure;
@property(nonatomic,strong) NSTextField *grammarFollowupResultLabel;
@property(nonatomic,strong) NSTextField *grammarOtherEmptyLabel;
@property(nonatomic,strong) NSStackView *grammarOtherStack;
@property(nonatomic,strong) NSButton *grammarPageAnalyzeButton;
@property(nonatomic,strong) NSTextField *grammarPinnedLabel;
@property(nonatomic,strong) NSView *grammarPointsPane;
@property(nonatomic,strong) NSTextField *grammarQuestionField;
@property(nonatomic,strong) NSTextField *grammarReferenceNote;
@property(nonatomic,strong) NSTextField *grammarResultsLabel;
@property(nonatomic,strong) NSButton *grammarReviewButton;
@property(nonatomic,strong) NSTextField *grammarSourceLabel;
@property(nonatomic,strong) NSButton *grammarSourceLinkButton;
@property(nonatomic,strong) NSTextView *grammarSourceTextView;
@property(nonatomic,strong) NSTextField *grammarStatusLabel;
@property(nonatomic,strong) NSView *grammarStructureCard;
@property(nonatomic,copy) NSArray<NSButton *> *grammarTabButtons;
@property(nonatomic,strong) NSView *grammarTabRow;
@property(nonatomic,copy) NSArray<NSView *> *grammarTabUnderlines;
@property(nonatomic,strong) NSStackView *grammarUsageBlock;
@property(nonatomic,copy) NSArray<NSButton *> *mainStructureButtons;
@property(nonatomic,strong) NSScrollView *mainStructureScrollView;
@property(nonatomic,copy) NSArray<NSButton *> *quickStructureButtons;
@property(nonatomic,strong) NSScrollView *quickStructureScrollView;
@property(nonatomic,strong) NSTextField *sentenceInsightLabel;
@property(nonatomic,strong) NSStackView *sentenceInsightStack;
@property(nonatomic,strong) NSStackView *sentenceStructureStack;
@end
@implementation GrammarPageSourceFact
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)a source:(NSString *)s quick:(BOOL)q{return [FYGrammarPageBuilder structureViewForAnalysis:a source:s quick:q receiver:self];}
- (NSStackView *)verticalStack{return NativeBoundary();}
- (NSStackView *)horizontalStack{Check(NO,@"unexpected UI construction");return nil;}
- (id)grammarControlTarget{Check(NO,@"invalid guard must not query original target");return nil;}
- (NSColor *)uiInk{return nil;}- (NSColor *)uiMuted{return nil;}- (NSColor *)uiBorder{return nil;}- (NSColor *)uiSelected{return nil;}- (NSColor *)uiSurface{return nil;}- (NSColor *)uiAccent{return nil;}
- (NSTextField *)label:(NSString *)t font:(NSFont *)f color:(NSColor *)c{Check(NO,@"unexpected UI construction");return nil;}
- (NSTextField *)mutedLabel:(NSString *)t{Check(NO,@"unexpected UI construction");return nil;}
- (NSTextField *)cardTitle:(NSString *)t{Check(NO,@"unexpected UI construction");return nil;}
- (NSTextField *)textField:(NSString *)p{Check(NO,@"unexpected UI construction");return nil;}
- (NSView *)spacer{Check(NO,@"unexpected UI construction");return nil;}
- (NSView *)card{Check(NO,@"unexpected UI construction");return nil;}
- (NSView *)cardWithStack:(NSStackView *)s{Check(NO,@"unexpected UI construction");return nil;}
- (NSButton *)workspaceButton:(NSString *)t action:(SEL)a primary:(BOOL)p{Check(NO,@"unexpected UI construction");return nil;}
- (NSTextField *)quickReadingLabel:(NSString *)t size:(CGFloat)s weight:(NSFontWeight)w color:(NSColor *)c{Check(NO,@"unexpected UI construction");return nil;}
- (void)applyGrammarTabSelection{Check(NO,@"invalid input must not dispatch UI tab action");}
@end
int main(int argc,const char *argv[]){@autoreleasepool{GrammarPageSourceFact *s=[GrammarPageSourceFact new];if(argc>1){RunValidGrammarBoundary(s,[NSString stringWithUTF8String:argv[1]]);return 2;}unsigned int n=0;Ivar *v=class_copyIvarList(FYGrammarPageBuilder.class,&n);free(v);FYGrammarPageBuilder *cold=[FYGrammarPageBuilder new];Check(cold&&n==0&&NSApp==nil,@"cold builder owns no state/idle source or native views");RunGrammarPageGuardFixture(s);CheckValidBoundaryChildren([NSString stringWithUTF8String:argv[0]]);__weak GrammarPageSourceFact *weak;@autoreleasepool{GrammarPageSourceFact *p=[GrammarPageSourceFact new];weak=p;[p structureViewForAnalysis:nil source:nil quick:NO];}Check(!weak,@"builder does not retain borrowed source");printf("PASS GrammarPageBuilderTests: %lu checks; cold/guards/native-factory boundary only, full graphs NOT RUN\n",(unsigned long)checks);}return 0;}
