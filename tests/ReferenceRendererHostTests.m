#import "presentation/FYReferencePresentationController.h"
#import "FYReferenceRendererTestFacts.h"
@interface ReferenceRendererHostFixture : FYReferencePresentationController <ReferenceRendererDriver>
@property(nonatomic,strong) ReferenceRendererFacts*facts;
@property(nonatomic,strong) ReferenceResourceBoundary*resourceBoundary;
@end
@implementation ReferenceRendererHostFixture
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
@end
static id<ReferenceRendererDriver> Source(ReferenceRendererFacts*f){activeFacts=f;ReferenceResourceBoundary*b=[ReferenceResourceBoundary new];b.facts=f;ReferenceRendererHostFixture*s=[[ReferenceRendererHostFixture alloc]initWithHost:(id)b];s.facts=f;s.resourceBoundary=b;return s;}
int main(void){@autoreleasepool{Check(NSApp==nil,@"actual Reference renderer fixture starts cold");InstallServices();InstallNativeFactories();ReferenceRendererFacts*f=[ReferenceRendererFacts new];RunReferenceRenderer(Source(f),f);RestoreNativeFactories();RestoreServices();activeFacts=nil;printf("PASS ReferenceRendererHostTests: %lu checks\n",(unsigned long)checks);}return 0;}
