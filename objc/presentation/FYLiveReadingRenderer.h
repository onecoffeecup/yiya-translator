#pragma once
#import <AppKit/AppKit.h>
#import "FYLiveReadingCoordinator.h"
@protocol FYLiveReadingFontSource <NSObject>
- (NSFont *)liveReadingJapaneseFontOfSize:(CGFloat)size;
- (NSFont *)liveReadingUIFontOfSize:(CGFloat)size;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSColor *)uiAccent;
- (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString **)speaker body:(NSString **)body;
@end
@protocol FYLiveReadingViewSource <NSObject>
@property(nonatomic,strong,readonly) NSTextView *learningSourceTextView;
@property(nonatomic,strong,readonly) NSLayoutConstraint *sourceReadingHeight;
@property(nonatomic,strong,readonly) NSTextField *liveScreenSpeakerLabel;
@property(nonatomic,strong,readonly) NSTextField *liveScreenDialogueLabel;
@property(nonatomic,strong,readonly) NSTextField *learningPinnedLabel;
@property(nonatomic,strong,readonly) NSTextField *grammarPinnedLabel;
@property(nonatomic,strong,readonly) NSButton *pinSentenceButton;
@property(nonatomic,strong,readonly) NSButton *analyzeButton;
@property(nonatomic,strong,readonly) NSButton *grammarPageAnalyzeButton;
- (void)refreshLiveChips;
- (void)applyGrammarTabSelection;
@end
@protocol FYLiveReadingRenderSource <FYLiveReadingStateSource,FYLiveReadingServices,FYLiveReadingFontSource,FYLiveReadingViewSource>
@end
@interface FYLiveReadingRenderer : NSObject
- (NSAttributedString *)liveReadingText:(NSString *)text japanese:(BOOL)japanese receiver:(id<FYLiveReadingRenderSource>)receiver;
- (void)updateLiveSourceReadingHeightWithReceiver:(id<FYLiveReadingRenderSource>)receiver;
- (void)refreshLiveDialoguePresentation:(NSString *)source receiver:(id<FYLiveReadingRenderSource>)receiver;
- (void)refreshLearningStatusWithReceiver:(id<FYLiveReadingRenderSource>)receiver;
@end
