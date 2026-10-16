#pragma once
#import <AppKit/AppKit.h>
#import "../learning/FYLearningViews.h"
@protocol FYLivePagePreviewViews <NSObject>
@property(nonatomic, strong) NSTextField *currentWindowLabel;
@property(nonatomic, strong) NSImageView *framePreview;
@property(nonatomic, strong) NSTextField *previewPlaceholder;
@property(nonatomic, strong) NSTextField *liveChipRecognition;
@property(nonatomic, strong) NSTextField *liveChipAutoTranslate;
@property(nonatomic, strong) NSTextField *liveChipPauseFollow;
@property(nonatomic, strong) NSTextField *ocrDurationLabel;
@property(nonatomic, strong) NSTextField *translationDurationLabel;
@property(nonatomic, strong) NSTextField *translationCountLabel;
@property(nonatomic, strong) NSTextField *liveErrorLabel;
@end
@protocol FYLivePageReadingViews <NSObject>
@property(nonatomic, strong) NSTextField *learningTranslationLabel;
@property(nonatomic, strong) NSLayoutConstraint *translationReadingMinimumHeight;
@property(nonatomic, strong) NSTextField *liveLevelTag;
@property(nonatomic, strong) NSTextField *liveSourceEmptyLabel;
@property(nonatomic, strong) FYSelectableSourceTextView *learningSourceTextView;
@property(nonatomic, strong) NSLayoutConstraint *sourceReadingHeight;
@property(nonatomic, strong) NSTextField *liveSourceSelectionHintLabel;
@property(nonatomic, strong) NSButton *pinSentenceButton;
@property(nonatomic, strong) NSButton *followLatestButton;
@property(nonatomic, strong) NSTextField *learningPinnedLabel;
@property(nonatomic, strong) NSLayoutConstraint *sourceReadingMinimumHeight;
@end
@protocol FYLivePageWordViews <NSObject>
@property(nonatomic, strong) NSStackView *wordPickArea;
@property(nonatomic, strong) NSTextField *wordPickSurfaceLabel;
@property(nonatomic, strong) NSTextField *lemmaField;
@property(nonatomic, strong) NSTextField *readingField;
@property(nonatomic, strong) NSTextField *meaningField;
@property(nonatomic, strong) NSTextField *vocabularySelectionLabel;
@property(nonatomic) BOOL vocabCompletionFromAI;
@property(nonatomic) NSInteger vocabSelectionGeneration;
@end
@protocol FYLivePageFactories <NSObject>
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSView *)spacer;
- (NSTextField *)cardTitle:(NSString *)text;
- (NSTextField *)mutedLabel:(NSString *)text;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSTextField *)textField:(NSString *)placeholder;
- (NSView *)rowWithLabel:(NSString *)label view:(NSView *)view;
- (NSView *)cardWithStack:(NSStackView *)stack;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (NSTextField *)chipLabel:(NSString *)text;
- (NSView *)makeInlineTranslationListCard;
- (NSView *)makeIntegratedGrammarCard;
- (id)livePageActionTarget;
- (void)installLivePageVocabularyStatusLabel:(NSTextField *)field;
@property(nonatomic,strong,readonly) NSTextField *vocabularyStatusLabel;
- (NSColor *)uiMuted;
- (NSColor *)uiInk;
@end
@protocol FYLivePageSelectionSource <NSObject>
@property(nonatomic,strong,readonly) FYSelectableSourceTextView *learningSourceTextView;
@property(nonatomic,strong,readonly) NSTextField *lemmaField;
@property(nonatomic,strong,readonly) NSTextField *readingField;
@property(nonatomic,strong,readonly) NSTextField *meaningField;
@property(nonatomic) BOOL vocabCompletionFromAI;
@property(nonatomic) NSInteger vocabSelectionGeneration;
- (void)freezeLearningSentenceForSelection;
- (void)updateWordPickForSelection;
- (void)selectWordAtCharacterIndex:(NSUInteger)index;
@end
@protocol FYLivePageSource <FYLivePagePreviewViews,FYLivePageReadingViews,FYLivePageWordViews,FYLivePageFactories,FYLivePageSelectionSource>
@end
// Native builder owns no views/state/observer. Callbacks borrow the Main source.
@interface FYLivePageBuilder : NSObject
- (NSView *)makePageWithReceiver:(id<FYLivePageSource>)receiver;
// Production ignores the same center-owned token; tests remove their synthetic observer.
- (id)wireSourceSelectionWithReceiver:(id<FYLivePageSelectionSource>)receiver;
@end
