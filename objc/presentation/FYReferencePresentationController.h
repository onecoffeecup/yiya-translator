#pragma once
#import <AppKit/AppKit.h>
#import "FYReferenceQueryCoordinator.h"
#import "FYSourceHoverCoordinator.h"
#import "FYReferenceRenderer.h"
@class FYSelectableSourceTextView;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Explicit context, peer actions and view factories; no application type dependency.
@protocol FYReferencePresentationControllerHost <NSObject, NSWindowDelegate, NSTextFieldDelegate>
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
- (void)selectPageAtIndex:(NSInteger)index;
- (BOOL)analysisMatchesCurrentSentence;
- (NSString *)selectedLearningText;
- (FYVocabularyEntry *)wordForCardButton:(NSButton *)sender;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSTextField *)textField:(NSString *)placeholder;
- (NSSegmentedControl *)segmentedWithLabels:(NSArray<NSString *> *)labels action:(SEL)action;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSColor *)uiBorder;
- (NSColor *)uiAccent;
- (NSColor *)uiSurface;
- (NSView *)cardWithStack:(NSStackView *)stack;
- (NSTextField *)cardTitle:(NSString *)text;
- (NSTextField *)mutedLabel:(NSString *)text;
- (NSView *)workspaceSection:(NSStackView *)stack;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (NSURL *)referenceResourceURL:(NSString *)file;
- (BOOL)openReferenceLicensesDirectory:(NSURL *)directory;
@end

// Owns reference views and ephemeral state. Persistence remains in learning services.
@interface FYReferencePresentationController : NSObject <FYReferenceQuerySource,FYSourceHoverSource,FYReferenceRenderSource>
@property(nonatomic,strong,readonly) FYReferenceQueryCoordinator *queryCoordinator;
@property(nonatomic,strong,readonly) FYSourceHoverCoordinator *hoverCoordinator;
@property(nonatomic, weak) id<FYReferencePresentationControllerHost> host;
- (instancetype)initWithHost:(id<FYReferencePresentationControllerHost>)host;
@property(nonatomic) NSUInteger quickSourceHoverGeneration;
@property(nonatomic, copy) NSString *referenceActiveWord;
@property(nonatomic, strong) NSView *referenceCard;
@property(nonatomic, strong) NSStackView *referenceDetailStack;
@property(nonatomic, strong) FYReferenceDictionary *referenceDictionary;
@property(nonatomic, strong) NSPopUpButton *referenceEntryPopup;
@property(nonatomic, strong) NSStackView *referenceMoreExamples;
@property(nonatomic, copy) NSArray<NSDictionary *> *referenceRecords;
@property(nonatomic) NSInteger referenceRequestGeneration;
@property(nonatomic, strong) NSTextField *referenceSearchField;
@property(nonatomic, strong) NSPopUpButton *referenceSensePopup;
@property(nonatomic, strong) NSStackView *referenceStack;
@property(nonatomic, strong) NSSegmentedControl *referenceTabs;
@property(nonatomic, strong) NSCache<NSString *,NSString *> *sourceHoverCache;
@property(nonatomic) NSUInteger sourceHoverGeneration;
@property(nonatomic) BOOL sourceHoverSuspended;
- (NSURL *)referenceResourceURL:(NSString *)file;
- (NSView *)makeIntegratedReferenceCard;
- (NSButton *)referenceLink:(NSString *)title URL:(NSString *)url;
- (void)openReferenceLink:(NSButton *)sender;
- (void)revealReferenceCard;
- (void)searchReferenceWord:(id)sender;
- (void)lookupReferenceWord:(NSString *)word reading:(NSString *)reading;
- (void)showSelectedWordReference:(id)sender;
- (void)showSavedWordReference:(NSButton *)sender;
- (void)referenceEntryChanged:(id)sender;
- (void)referenceTabChanged:(id)sender;
- (void)addReferenceDisclosure:(NSString *)title content:(NSView *)content;
- (void)toggleReferenceExtra:(NSButton *)sender;
- (void)showReferenceLicenses:(id)sender;
- (BOOL)openReferenceLicensesDirectory:(NSURL *)directory;
- (void)setSourceHoverTip:(NSString *)tip range:(NSRange)range source:(NSString *)source views:(NSArray *)views;
- (void)applyAnalysisHoverTips:(FYAnalysisResult *)analysis source:(NSString *)source views:(NSArray *)views;
- (void)populateSourceHoverTips:(NSString *)source views:(NSArray *)views analysis:(FYAnalysisResult *)analysis fallback:(NSString *)fallback isCurrent:(BOOL (^)(void))isCurrent;
- (void)refreshSourceHoverTips;
- (void)refreshQuickSentenceHoverTips;
@end
#pragma clang diagnostic pop
