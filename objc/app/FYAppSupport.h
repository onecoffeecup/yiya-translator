#pragma once
// Legacy private state is initialized in stages. Preserve its unspecified
// nullability during extraction instead of promising nonnull controls.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "../settings/FYSettingsStore.h"
#import "../settings/FYServiceTestController.h"
#import "../diagnostics/FYDiagnosticsController.h"
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <Vision/Vision.h>
#ifdef FY_ENABLE_UPDATES
#import "../FYAppUpdater.h"
#endif
#import "../learning/FYLearningModels.h"
#import "../learning/FYLearningStore.h"
#import "../learning/FYLearningAnalyzer.h"
#import "../FYGrammarActionState.h"
#import "../learning/FYJapaneseTokenizer.h"
#import "../learning/FYGrammarCatalog.h"
#import "../learning/FYLearningCoordinator.h"
#import "../learning/FYLearningViews.h"
#import "../learning/FYReferenceDictionary.h"
#import "../learning/FYSavedWordReferenceView.h"
#import "../FYTranslationTrace.h"
#import "../FYRuntimeDiagnostics.h"
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "../FYCaptureCardInput.h"
#import "../FYInlineLayout.h"
#import "../FYInlineLayoutDebug.h"
#import "../FYWindowManager.h"
#import "../FYOCRManager.h"
#import "../FYContentRouter.h"
#import "../FYGeometryManager.h"
#import "../FYTranslationManager.h"
#import "../FYTranslationServiceView.h"
#import "../learning/FYStudyChatSession.h"
#import "../learning/FYStudyChatView.h"
#import "../learning/FYStudyOverlayPanel.h"
#import "../learning/FYGlobalShortcuts.h"


// Shared models, views and legacy fixture helpers; no application state.
// Controllers, isolated tests and offline tools use these declarations.
typedef void (^RegionSelectionCompletion)(CGRect selectedRect, CGSize viewSize, BOOL cancelled);


#import "../presentation/FYInlinePanelLayoutTypes.h"
#import "../presentation/FYPresentationText.h"

@interface FYCaptureCalibrationView : NSView
@property(nonatomic, copy) void (^onFinish)(NSRect screenRect);
@property(nonatomic, copy) void (^onCancel)(void);
@property(nonatomic) NSRect selectionRect;
@end

#import "../presentation/FYInlineBlockSnapshot.h"



#import "../presentation/FYFlippedDocumentView.h"

#import "../presentation/FYFrameDrivenContentView.h"

@interface FYRegionSelectionPanel : NSPanel
@end

@interface RegionSelectionView : NSView
@property(nonatomic) NSPoint startPoint;
@property(nonatomic) CGRect selectionRect;
@property(nonatomic, copy) RegionSelectionCompletion completion;
@property(nonatomic) CGFloat helpFontSize;
@property(nonatomic, strong) NSColor *helpTextColor;
@end

extern NSString *const SettingsKey;
extern NSInteger const ContentModeDialogue;
extern NSInteger const ContentModeUI;
NSString *FYAppearanceColorHex(NSColor *color);
NSColor *FYAppearanceColorFromHex(NSString *hex, NSColor *fallback);
BOOL FuyiDiagEnabled(void);
void FYWritePrivateDiagnosticData(NSData *data, NSString *filename, BOOL append);
NSString *FYDiagTextLength(NSString *value);
NSArray<OCRTextItem *> *MergeRefinedOCRItems(NSArray<OCRTextItem *> *coarse,
                                                  NSArray<OCRTextItem *> *refined);
BOOL __attribute__((unused)) TextHitsUIToken(NSString *text);
NSUInteger __attribute__((unused)) UITokenHitCount(NSArray<OCRTextItem *> *blocks);
BOOL __attribute__((unused)) IsFuriganaNearLargerLine(OCRTextItem *small, NSArray<OCRTextItem *> *blocks);
BOOL LooksLikeUIFrame(NSArray<OCRTextItem *> *blocks);
BOOL __attribute__((unused)) IsCornerHelpButton(OCRTextItem *block);
BOOL __attribute__((unused)) IsOwnOverlayText(NSString *raw);
NSArray<OCRTextItem *> *OCRItemsExcludingOwnOverlay(NSArray<OCRTextItem *> *items,
                                                           NSSet<NSString *> *renderedTexts);
NSSet<NSString *> *RenderedTranslationSet(NSString *captionText, NSDictionary *inlineCache);
NSString *__attribute__((unused)) DialogueTextWithoutTrailingButton(NSString *text);
BOOL __attribute__((unused)) DialogueFrameIsSpeakerLabelOnly(NSArray<NSString *> *lines);
#import "../runtime/FYPreviewImage.h"
NSArray<OCRTextItem *> *SubtitleBandItemsFromBlocks(NSArray<OCRTextItem *> *blocks);
void SplitDialogueAndOptionsFromItems(NSArray<OCRTextItem *> *band,
                                     NSArray<OCRTextItem *> *allBlocks,
                                     NSMutableArray<OCRTextItem *> *outDialogue,
                                     NSMutableArray<OCRTextItem *> *outOptions);
BOOL BlockSitsOnBrightBackdrop(OCRTextItem *block, const unsigned char *pixels,
                              size_t width, size_t height, size_t bytesPerRow);
NSInteger DetectContentModeForBlocks(NSArray<OCRTextItem *> *blocks, NSInteger fallbackSegment);


void FuyiDiagLog(NSString *format, ...);
double SimilarityRatio(NSString *left, NSString *right);
void FYInlineDebugTracePerform(NSDictionary *trace, NSDictionary *layout, void (^work)(void));
NSColor *FYAppearanceBackdropForText(NSColor *textColor);
FYContentTextFilterObserver FYContentFilterDiagnosticObserver(void);
NSString *FYTranslationFailureMessage(NSError *error, NSUInteger reasonLimit);
BOOL ContainsJapaneseText(NSString *value);
NSString *SourceLanguageLabel(NSInteger segment);
NSArray *FYTraceOCRLines(NSArray<OCRTextItem *> *items);
extern const NSInteger kCaptureCardMappingVersion;
extern const double kCaptureCardMappingScoreUnavailable;
void FYRemoveOwnedLegacyDiagnosticFiles(void);
NSString *FYTranslationModelForSettings(NSDictionary *settings);
#pragma clang diagnostic pop
