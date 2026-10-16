#import "presentation/FYCollectionController.h"
#import "FYCollectionRendererTestFacts.h"
@interface CollectionRenderHostFixture : FYCollectionController <CollectionRendererDriver>
@property(nonatomic,strong) CollectionWorkflowFacts *facts;
@property(nonatomic,strong) NSObject *actionTarget;
@end
@implementation CollectionRenderHostFixture
- (FYLearningStore*)learningStore{return (FYLearningStore*)self.facts.store;}
- (FYLearningCoordinator*)learningCoordinator{return (FYLearningCoordinator*)self.facts.learning;}
- (FYAnalysisResult*)currentAnalysis{return self.facts.analysis;}
- (NSString*)quickSentenceID{return self.facts.quickID;}
- (BOOL)sentenceBookmarkPending{return self.facts.pending;}
- (void)setSentenceBookmarkPending:(BOOL)value{self.facts.pending=value;}
- (BOOL)analysisMatchesCurrentSentence{return self.facts.matches;}
- (FYGrammarBookmark*)bookmarkForCurrentGrammar{return self.facts.mainBookmark;}
- (BOOL)quickSentenceIsBookmarked{return self.facts.bookmarked;}
- (void)updateQuickGrammarBookmark{self.facts.quickUpdates++;}
- (void)refreshLearningSource{[self.facts.events addObject:@"source"];}
- (void)refreshLearningStatus{[self.facts.events addObject:@"status"];}
- (void)clearAnalysisDisplay{[self.facts.events addObject:@"clear-analysis"];}
- (void)selectPageAtIndex:(NSInteger)index{[self.facts.events addObject:[NSString stringWithFormat:@"page%ld",(long)index]];}
- (void)analyzeCurrentSentence:(id)sender{[self.facts.events addObject:@"analyze"];}
- (void)refreshVocabularyList{self.facts.vocabularyRefreshes++;}
- (NSStackView*)verticalStack{return (NSStackView*)Node();}
- (NSStackView*)horizontalStack{return (NSStackView*)Node();}
- (NSTextField*)label:(NSString*)text font:(NSFont*)font color:(NSColor*)color{return (NSTextField*)Label(text,font,color);}
- (NSTextField*)mutedLabel:(NSString*)text{return (NSTextField*)Label(text,[NSFont systemFontOfSize:12],[NSColor grayColor]);}
- (NSTextField*)cardTitle:(NSString*)text{return (NSTextField*)Label(text,[NSFont boldSystemFontOfSize:15],[NSColor brownColor]);}
- (NSView*)spacer{return (NSView*)Node();}
- (NSView*)separator{return (NSView*)Node();}
- (NSView*)cardWithStack:(NSStackView*)stack{CollectionNodeFact*n=Node();[n addArrangedSubview:(id)stack];return(NSView*)n;}
- (NSButton*)workspaceButton:(NSString*)title action:(SEL)action primary:(BOOL)primary{return ButtonFactory(nil,NULL,title,self.actionTarget,action);}
- (NSColor*)uiInk{return NSColor.brownColor;}
- (NSColor*)uiMuted{return NSColor.grayColor;}
- (FYGrammarCatalog*)grammarCatalog{return nil;}
- (void)clearArrangedSubviews:(NSStackView*)stack{for(CollectionNodeFact*n in [(id)stack arrangedSubviews])n.superview=nil;[((CollectionNodeFact*)stack).arrangedSubviews removeAllObjects];}
- (NSButton*)grammarDetailBookmarkButton{return(NSButton*)self.facts.mainButton;}
- (NSButton*)quickSentenceBookmarkButton{return(NSButton*)self.facts.quickButton;}
@end
static void Setup(id s,CollectionWorkflowFacts*f){[s setValue:f forKey:@"facts"];[s setValue:[NSObject new] forKey:@"actionTarget"];for(NSString*name in @[@"historyListStack",@"savedGrammarCardStack",@"savedSentenceStack",@"wordCardStack",@"learningCollectionHost"]){[s setValue:Node() forKey:name];}[s setValue:f.grammarLabel forKey:@"grammarBookmarkListLabel"];[s setValue:f.statusLabel forKey:@"vocabularyStatusLabel"];[s setValue:f.examplesLabel forKey:@"vocabularyExamplesLabel"];[s setValue:f.popup forKey:@"vocabularyExamplesPopup"];[s setValue:f.prompt forKey:@"reviewPromptLabel"];}
static id<CollectionRendererDriver> Source(CollectionWorkflowFacts*f){CollectionRenderHostFixture*s=[[CollectionRenderHostFixture alloc]initWithHost:nil];Setup(s,f);s.host=(id)s.actionTarget;return s;}
int main(void){@autoreleasepool{Check(NSApp==nil,@"actual renderer host is cold");InstallFactories();CollectionWorkflowFacts*f=[CollectionWorkflowFacts new];RunRenderer(Source(f),f);RestoreFactories();printf("PASS CollectionRendererHostTests: %lu checks\n",(unsigned long)checks);}return 0;}
