#import "FYReferencePresentationController.h"
#import "../app/FYAppSupport.h"

@interface FYReferencePresentationController ()
@property(nonatomic,strong,readwrite) FYReferenceQueryCoordinator *queryCoordinator;
@property(nonatomic,strong,readwrite) FYSourceHoverCoordinator *hoverCoordinator;
@property(nonatomic, strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic, strong) NSTextView *grammarSourceTextView;
@property(nonatomic, strong) FYJapaneseTokenizer *japaneseTokenizer;
@property(nonatomic, strong) FYSelectableSourceTextView *learningSourceTextView;
@property(nonatomic, strong) NSTextField *lemmaField;
@property(nonatomic, strong) NSWindow *mainWindow;
@property(nonatomic, strong) NSArray<NSView *> *pages;
@property(nonatomic, strong) FYAnalysisResult *quickSentenceAnalysis;
@property(nonatomic, copy) NSString *quickSentenceAnalysisSource;
@property(nonatomic, copy) NSString *quickSentenceID;
@property(nonatomic) BOOL quickSentenceRequested;
@property(nonatomic, copy) NSString *quickSentenceSource;
@property(nonatomic) NSInteger quickSentenceVersion;
@property(nonatomic, strong) FYSelectableSourceTextView *quickSourceTextView;
@property(nonatomic, strong) NSTextField *readingField;
@end

@implementation FYReferencePresentationController
- (instancetype)initWithHost:(id<FYReferencePresentationControllerHost>)host {
    if ((self = [super init])) { _host = host; _queryCoordinator=[FYReferenceQueryCoordinator new]; _hoverCoordinator=[FYSourceHoverCoordinator new]; }
    return self;
}


// Original fields have one physical owner; peer facades continue to share them.
- (NSInteger)referenceRequestGeneration { return self.queryCoordinator.referenceRequestGeneration; }
- (void)setReferenceRequestGeneration:(NSInteger)value { self.queryCoordinator.referenceRequestGeneration=value; }
- (NSString *)referenceActiveWord { return self.queryCoordinator.referenceActiveWord; }
- (void)setReferenceActiveWord:(NSString *)value { self.queryCoordinator.referenceActiveWord=value; }
- (NSArray<NSDictionary *> *)referenceRecords { return self.queryCoordinator.referenceRecords; }
- (void)setReferenceRecords:(NSArray<NSDictionary *> *)value { self.queryCoordinator.referenceRecords=value; }
- (FYReferenceDictionary *)referenceDictionary { return self.queryCoordinator.referenceDictionary; }
- (void)setReferenceDictionary:(FYReferenceDictionary *)value { self.queryCoordinator.referenceDictionary=value; }
- (NSUInteger)sourceHoverGeneration { return self.hoverCoordinator.sourceHoverGeneration; }
- (void)setSourceHoverGeneration:(NSUInteger)value { self.hoverCoordinator.sourceHoverGeneration=value; }
- (NSUInteger)quickSourceHoverGeneration { return self.hoverCoordinator.quickSourceHoverGeneration; }
- (void)setQuickSourceHoverGeneration:(NSUInteger)value { self.hoverCoordinator.quickSourceHoverGeneration=value; }
- (NSCache<NSString *,NSString *> *)sourceHoverCache { return self.hoverCoordinator.sourceHoverCache; }
- (void)setSourceHoverCache:(NSCache<NSString *,NSString *> *)value { self.hoverCoordinator.sourceHoverCache=value; }
- (BOOL)sourceHoverSuspended { return self.hoverCoordinator.sourceHoverSuspended; }
- (void)setSourceHoverSuspended:(BOOL)value { self.hoverCoordinator.sourceHoverSuspended=value; }
- (id)referenceActionTarget { return self.host; }
- (FYReferenceDictionary *)makeReferenceDictionary { return [[FYReferenceDictionary alloc] initWithURL:[self.host referenceResourceURL:@"reference.sqlite"]]; }
- (BOOL)hasReferenceStack { return self.referenceStack!=nil; }
- (void)setReferenceSearchText:(NSString *)text { self.referenceSearchField.stringValue=text; }
- (void)clearReferenceRows { [self clearArrangedSubviews:self.referenceStack]; }
- (void)showReferenceLoadingWord:(NSString *)word { [self.referenceStack addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"正在查询「%@」的本机资料…",word]]]; }
- (void)showReferenceEmptyWord:(NSString *)word error:(NSError *)error { [FYReferenceRenderer showEmptyWord:word error:error receiver:self]; }
- (void)renderReferenceRecords:(NSArray<NSDictionary *> *)records { [FYReferenceRenderer renderRecords:records receiver:self]; }
- (NSString *)mainHoverText { return self.learningSourceTextView.string; }
- (BOOL)mainHoverEditable { return self.learningSourceTextView.editable; }
- (NSArray *)mainHoverViews { return @[self.learningSourceTextView ?: (id)NSNull.null,self.grammarSourceTextView ?: (id)NSNull.null]; }
- (id<NSObject>)quickHoverView { return self.quickSourceTextView; }
- (NSString *)hoverTextForView:(id<NSObject>)view { return [(NSTextView *)view string]; }
- (BOOL)hoverEditableForView:(id<NSObject>)view { return [(NSTextView *)view isEditable]; }
- (void)clearSourceHoverAttributes:(NSArray *)views { [FYReferenceRenderer clearHoverAttributes:views]; }

// Explicit peer adapters. Every property has one owning controller.
- (FYAnalysisResult *)currentAnalysis { return self.host.currentAnalysis; }
- (void)setCurrentAnalysis:(FYAnalysisResult *)value { self.host.currentAnalysis = value; }
- (NSTextView *)grammarSourceTextView { return self.host.grammarSourceTextView; }
- (void)setGrammarSourceTextView:(NSTextView *)value { self.host.grammarSourceTextView = value; }
- (FYJapaneseTokenizer *)japaneseTokenizer { return self.host.japaneseTokenizer; }
- (void)setJapaneseTokenizer:(FYJapaneseTokenizer *)value { self.host.japaneseTokenizer = value; }
- (FYSelectableSourceTextView *)learningSourceTextView { return self.host.learningSourceTextView; }
- (void)setLearningSourceTextView:(FYSelectableSourceTextView *)value { self.host.learningSourceTextView = value; }
- (NSTextField *)lemmaField { return self.host.lemmaField; }
- (void)setLemmaField:(NSTextField *)value { self.host.lemmaField = value; }
- (NSWindow *)mainWindow { return self.host.mainWindow; }
- (void)setMainWindow:(NSWindow *)value { self.host.mainWindow = value; }
- (NSArray<NSView *> *)pages { return self.host.pages; }
- (void)setPages:(NSArray<NSView *> *)value { self.host.pages = value; }
- (FYAnalysisResult *)quickSentenceAnalysis { return self.host.quickSentenceAnalysis; }
- (void)setQuickSentenceAnalysis:(FYAnalysisResult *)value { self.host.quickSentenceAnalysis = value; }
- (NSString *)quickSentenceAnalysisSource { return self.host.quickSentenceAnalysisSource; }
- (void)setQuickSentenceAnalysisSource:(NSString *)value { self.host.quickSentenceAnalysisSource = value; }
- (NSString *)quickSentenceID { return self.host.quickSentenceID; }
- (void)setQuickSentenceID:(NSString *)value { self.host.quickSentenceID = value; }
- (BOOL)quickSentenceRequested { return self.host.quickSentenceRequested; }
- (void)setQuickSentenceRequested:(BOOL)value { self.host.quickSentenceRequested = value; }
- (NSString *)quickSentenceSource { return self.host.quickSentenceSource; }
- (void)setQuickSentenceSource:(NSString *)value { self.host.quickSentenceSource = value; }
- (NSInteger)quickSentenceVersion { return self.host.quickSentenceVersion; }
- (void)setQuickSentenceVersion:(NSInteger)value { self.host.quickSentenceVersion = value; }
- (FYSelectableSourceTextView *)quickSourceTextView { return self.host.quickSourceTextView; }
- (void)setQuickSourceTextView:(FYSelectableSourceTextView *)value { self.host.quickSourceTextView = value; }
- (NSTextField *)readingField { return self.host.readingField; }
- (void)setReadingField:(NSTextField *)value { self.host.readingField = value; }

- (void)selectPageAtIndex:(NSInteger)index { [self.host selectPageAtIndex:index]; }
- (BOOL)analysisMatchesCurrentSentence { return [self.host analysisMatchesCurrentSentence]; }
- (NSString *)selectedLearningText { return [self.host selectedLearningText]; }
- (FYVocabularyEntry *)wordForCardButton:(NSButton *)sender { return [self.host wordForCardButton:sender]; }
- (void)clearArrangedSubviews:(NSStackView *)stack { [self.host clearArrangedSubviews:stack]; }
- (NSStackView *)verticalStack { return [self.host verticalStack]; }
- (NSStackView *)horizontalStack { return [self.host horizontalStack]; }
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color { return [self.host label:text font:font color:color]; }
- (NSTextField *)textField:(NSString *)placeholder { return [self.host textField:placeholder]; }
- (NSSegmentedControl *)segmentedWithLabels:(NSArray<NSString *> *)labels action:(SEL)action { return [self.host segmentedWithLabels:labels action:action]; }
- (NSColor *)uiInk { return [self.host uiInk]; }
- (NSColor *)uiMuted { return [self.host uiMuted]; }
- (NSColor *)uiBorder { return [self.host uiBorder]; }
- (NSColor *)uiAccent { return [self.host uiAccent]; }
- (NSColor *)uiSurface { return [self.host uiSurface]; }
- (NSView *)cardWithStack:(NSStackView *)stack { return [self.host cardWithStack:stack]; }
- (NSTextField *)cardTitle:(NSString *)text { return [self.host cardTitle:text]; }
- (NSTextField *)mutedLabel:(NSString *)text { return [self.host mutedLabel:text]; }
- (NSView *)workspaceSection:(NSStackView *)stack { return [self.host workspaceSection:stack]; }
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary { return [self.host workspaceButton:title action:action primary:primary]; }

- (NSURL *)referenceResourceURL:(NSString *)file {
    return [[NSBundle mainBundle] URLForResource:file.stringByDeletingPathExtension withExtension:file.pathExtension subdirectory:@"learning/reference"];
}

- (NSView *)makeIntegratedReferenceCard { return [FYReferenceRenderer makeReferenceCardWithReceiver:self]; }

- (NSButton *)referenceLink:(NSString *)title URL:(NSString *)url { return [FYReferenceRenderer referenceLink:title URL:url receiver:self]; }

- (void)openReferenceLink:(NSButton *)sender {
    NSURL *url=[NSURL URLWithString:sender.identifier ?: @""];
    if ([url.scheme isEqualToString:@"https"]) { [NSWorkspace.sharedWorkspace openURL:url]; }
}

- (void)revealReferenceCard { [FYReferenceRenderer revealReferenceCardWithReceiver:self]; }

- (void)searchReferenceWord:(id)sender {
    NSString *word=Trim(self.referenceSearchField.stringValue);
    if(word.length){[self lookupReferenceWord:word reading:@""];}
}

- (void)lookupReferenceWord:(NSString *)word reading:(NSString *)reading { [self.queryCoordinator lookupWord:word reading:reading receiver:self]; }

- (void)showSelectedWordReference:(id)sender {
    NSString *surface=[self selectedLearningText]; if(!surface.length){return;}
    NSString *lemma=Trim(self.lemmaField.stringValue);
    [self lookupReferenceWord:lemma.length ? lemma : surface reading:Trim(self.readingField.stringValue)];
    [self revealReferenceCard];
}

- (void)showSavedWordReference:(NSButton *)sender { [FYReferenceRenderer showSavedWordReference:sender receiver:self]; }

- (void)referenceEntryChanged:(id)sender { [FYReferenceRenderer referenceEntryChangedWithReceiver:self]; }

- (void)referenceTabChanged:(id)sender { [FYReferenceRenderer referenceTabChangedWithReceiver:self]; }

- (void)addReferenceDisclosure:(NSString *)title content:(NSView *)content { [FYReferenceRenderer addDisclosure:title content:content receiver:self]; }

- (void)toggleReferenceExtra:(NSButton *)sender { [FYReferenceRenderer toggleExtra:sender receiver:self]; }

- (void)showReferenceLicenses:(id)sender {
    NSURL *manifest=[self.host referenceResourceURL:@"reference-manifest.json"];
    NSURL *directory=[[manifest URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"licenses" isDirectory:YES];
    BOOL isDirectory=NO;
    if(directory && [NSFileManager.defaultManager fileExistsAtPath:directory.path isDirectory:&isDirectory] && isDirectory &&
       [self.host openReferenceLicensesDirectory:directory]){return;}
    NSAlert *alert=[NSAlert new];
    alert.messageText=@"无法打开完整许可文件";
    alert.informativeText=@"请在「资料来源与许可」中阅读说明。若应用缺少随包的许可文件，请重新安装完整应用。";
    if(self.mainWindow.isVisible){[alert beginSheetModalForWindow:self.mainWindow completionHandler:nil];}
    else{[alert runModal];}
}

- (BOOL)openReferenceLicensesDirectory:(NSURL *)directory {
    return [NSWorkspace.sharedWorkspace openURL:directory];
}

- (void)setSourceHoverTip:(NSString *)tip range:(NSRange)range source:(NSString *)source views:(NSArray *)views { [FYReferenceRenderer setHoverTip:tip range:range source:source views:views receiver:self]; }

- (void)applyAnalysisHoverTips:(FYAnalysisResult *)analysis source:(NSString *)source views:(NSArray *)views { [self.hoverCoordinator applyAnalysis:analysis source:source views:views receiver:self]; }

- (void)populateSourceHoverTips:(NSString *)source views:(NSArray *)views analysis:(FYAnalysisResult *)analysis fallback:(NSString *)fallback isCurrent:(BOOL (^)(void))isCurrent { [self.hoverCoordinator populateSource:source views:views analysis:analysis fallback:fallback isCurrent:isCurrent receiver:self]; }

- (void)refreshSourceHoverTips { [self.hoverCoordinator refreshMainWithReceiver:self]; }

- (void)refreshQuickSentenceHoverTips { [self.hoverCoordinator refreshQuickWithReceiver:self]; }

@end
