#import "presentation/FYReferencePresentationController.h"
#import "FYReferenceNativeTestFacts.h"
@interface ReferenceWorkflowHostFixture : FYReferencePresentationController <ReferenceWorkflowDriver>
@property(nonatomic,strong) ReferenceFacts*facts;
@property(nonatomic,strong) ReferenceResourceBoundary*resourceBoundary;
@end
@implementation ReferenceWorkflowHostFixture
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
- (void)referenceEntryChanged:(id)sender{self.facts.entryChanges++;}
- (void)setSourceHoverTip:(NSString*)tip range:(NSRange)range source:(NSString*)source views:(NSArray*)views{[self.facts.tips addObject:@{@"tip":tip,@"range":[NSValue valueWithRange:range],@"source":source,@"views":views}];[super setSourceHoverTip:tip range:range source:source views:views];}
@end
static id<ReferenceWorkflowDriver> Source(ReferenceFacts*f){activeFacts=f;ReferenceResourceBoundary*b=[ReferenceResourceBoundary new];b.facts=f;ReferenceWorkflowHostFixture*s=[[ReferenceWorkflowHostFixture alloc]initWithHost:(id)b];s.facts=f;s.resourceBoundary=b;s.referenceStack=(id)Node();return s;}
static BOOL(^heldCurrent)(void);
@interface ReferenceCurrentCaptureFixture : ReferenceWorkflowHostFixture
@end
@implementation ReferenceCurrentCaptureFixture
- (void)populateSourceHoverTips:(NSString*)source views:(NSArray*)views analysis:(FYAnalysisResult*)analysis fallback:(NSString*)fallback isCurrent:(BOOL(^)(void))isCurrent{heldCurrent=[isCurrent copy];}
@end
static void RunWeakCurrentClosure(void){ReferenceFacts*f=[ReferenceFacts new];__weak id weak;__weak ReferenceTextFact*view;@autoreleasepool{ReferenceCurrentCaptureFixture*s=[[ReferenceCurrentCaptureFixture alloc]initWithHost:nil];s.facts=f;weak=s;view=f.quick;[s refreshQuickSentenceHoverTips];f.quick=nil;}Check(!weak&&view&&heldCurrent&&!heldCurrent(),@"actual quick currentness closure retains view but keeps only a weak receiver");@autoreleasepool{heldCurrent=nil;}Check(!view,@"releasing held currentness closure releases original view lease");}
int main(void){@autoreleasepool{Check(NSApp==nil,@"actual Reference controller initializes without application/windows");InstallServices();InstallNativeFactories();ReferenceFacts*f=[ReferenceFacts new];RunReferenceWorkflow(Source(f),f);RunReferenceLeases(^id<ReferenceWorkflowDriver>(ReferenceFacts*f){return Source(f);});RestoreNativeFactories();RunWeakCurrentClosure();RestoreServices();activeFacts=nil;Check(NSApp==nil,@"all original/current query and hover methods stay headless");printf("PASS ReferenceWorkflowHostTests: %lu checks\n",(unsigned long)checks);}return 0;}
