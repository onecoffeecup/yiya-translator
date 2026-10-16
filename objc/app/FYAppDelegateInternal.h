#pragma once
#import "FYAppDelegate.h"
#import "FYAppSupport.h"
#import "../runtime/FYCaptureRuntimeController.h"
#import "../runtime/FYTranslationRuntimeController.h"
#import "../presentation/FYInlineOverlayController.h"
#import "../presentation/FYSubtitlePresenter.h"
#import "../presentation/FYMainWindowController.h"
#import "../presentation/FYCollectionController.h"
#import "../presentation/FYGrammarPresentationController.h"
#import "../presentation/FYStudyPresentationController.h"
#import "../presentation/FYReferencePresentationController.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
@interface AppDelegate ()
@property(nonatomic, strong) FYCaptureRuntimeController *captureRuntimeController;
@property(nonatomic, strong) FYTranslationRuntimeController *translationRuntimeController;
@property(nonatomic, strong) FYInlineOverlayController *inlineOverlayController;
@property(nonatomic, strong) FYSubtitlePresenter *subtitlePresenter;
@property(nonatomic, strong) FYSettingsStore *settingsStore;
@property(nonatomic, strong) FYServiceTestController *serviceTestController;
@property(nonatomic, strong) FYDiagnosticsController *diagnosticsController;
- (FYTranslationConfiguration *)translationConfiguration;
- (FYSettingsSnapshot *)settingsSnapshot;
#ifdef FY_ENABLE_UPDATES
@property(nonatomic, strong) FYAppUpdater *appUpdater;
#endif
@property(nonatomic, strong) NSWindow *mainWindow;
@property(nonatomic, strong) FYReferenceDictionary *referenceDictionary;
@property(nonatomic) NSUInteger sourceHoverGeneration;
@property(nonatomic) BOOL sourceHoverSuspended;
@property(nonatomic, strong) NSCache<NSString *,NSString *> *sourceHoverCache;
@property(nonatomic, strong) NSView *referenceCard;
@property(nonatomic, strong) NSTextField *referenceSearchField;
@property(nonatomic, strong) NSSegmentedControl *referenceTabs;
@property(nonatomic, strong) NSPopUpButton *referenceSensePopup;
@property(nonatomic, strong) NSStackView *referenceDetailStack;
@property(nonatomic, strong) NSStackView *referenceMoreExamples;
@property(nonatomic, copy) NSString *referenceActiveWord;
@property(nonatomic, strong) NSStackView *referenceStack;
@property(nonatomic, strong) NSPopUpButton *referenceEntryPopup;
@property(nonatomic, copy) NSArray<NSDictionary *> *referenceRecords;
@property(nonatomic) NSInteger referenceRequestGeneration;
@property(nonatomic, strong) NSPanel *captionPanel;
@property(nonatomic, strong) NSPanel *captionAppearancePreviewPanel;
@property(nonatomic, strong) FYAdventurePanel *captionAppearancePreviewContainer;
@property(nonatomic, strong) NSTextField *captionAppearancePreviewText;
@property(nonatomic, strong) NSTextField *captionAppearancePreviewBrand;
@property(nonatomic, strong) FYStudyChatSession *studyChatSession;
@property(nonatomic, strong) FYGlobalShortcuts *globalShortcuts;
@property(nonatomic, strong) NSStackView *mainWorkspaceRoot;
@property(nonatomic, strong) FYStudyChatView *mainStudyChatView;
@property(nonatomic, strong) FYStudyChatView *overlayStudyChatView;
@property(nonatomic, strong) FYStudyOverlayPanel *studyChatPanel;
@property(nonatomic, strong) FYStudyOverlayPanel *quickSentencePanel;
@property(nonatomic, strong) NSPanel *captionDockPanel;
@property(nonatomic) BOOL captionDockHasAnchor;
@property(nonatomic, strong) NSLayoutConstraint *workspaceWidth;
@property(nonatomic, strong) NSLayoutConstraint *mainChatWidth;
@property(nonatomic, strong) NSLayoutConstraint *mainWindowContentWidth;
@property(nonatomic, strong) NSLayoutConstraint *mainWindowMinimumWidth;
@property(nonatomic) BOOL mainChatWantsVisible;
@property(nonatomic, strong) NSButton *mainChatToggle;
@property(nonatomic) BOOL studyChatOverlayRequested;
@property(nonatomic) BOOL quickSentenceRequested;
@property(nonatomic) NSInteger chatContextGeneration;
@property(nonatomic) BOOL chatResolvingSource;
@property(nonatomic) NSInteger quickSentenceGeneration;
@property(nonatomic, copy) NSString *quickSentenceSource;
@property(nonatomic, strong) FYSelectableSourceTextView *quickSourceTextView;
@property(nonatomic) NSUInteger quickSourceHoverGeneration;
@property(nonatomic, copy) NSString *quickSentenceTranslation;
@property(nonatomic, copy) NSString *quickSentenceID;
@property(nonatomic) NSInteger quickSentenceVersion;
// 贴译长卡片 → 语法学习 → AI 返回的不可变块快照与返回关系。
@property(nonatomic, strong) FYInlineBlockSnapshot *inlineBlockSnapshot;
@property(nonatomic, strong) FYInlineBlockSnapshot *inlineReturnSnapshot;
@property(nonatomic, copy) NSString *inlineReturnSourceText;
@property(nonatomic, strong) NSButton *inlineReturnButton;
// 贴译长卡片打开的学习卡（而非对白查句）：标题与底部操作按预览切换。
@property(nonatomic) BOOL quickSentenceIsInlineBlock;
@property(nonatomic) CGFloat quickSentenceScrollOffset;
@property(nonatomic) NSInteger quickSelectedGrammarIndex;
@property(nonatomic, strong) NSButton *quickSelectedGrammarButton;
@property(nonatomic, copy) NSArray<FYRequestIdentity *> *savedSentences;
@property(nonatomic, strong) NSStackView *savedSentenceStack;
@property(nonatomic, strong) NSStackView *learningCollectionHost;
@property(nonatomic, copy) NSArray<NSView *> *learningCollectionSections;
@property(nonatomic, copy) NSArray<NSButton *> *learningCollectionTabs;
@property(nonatomic) NSInteger learningCollectionIndex;
@property(nonatomic, strong) NSTextField *learningCollectionTitle;
@property(nonatomic, strong) NSTextField *learningCollectionCount;
@property(nonatomic, strong) NSMutableSet<NSString *> *expandedWordCards;
@property(nonatomic, strong) NSButton *quickSentenceBookmarkButton;
@property(nonatomic) BOOL sentenceBookmarkPending;
@property(nonatomic, copy) NSArray<NSButton *> *quickStructureButtons;
// 主界面结构图的节点按钮与横向滚动视图：点击节点只做局部高亮，不重建结构图。
@property(nonatomic, copy) NSArray<NSButton *> *mainStructureButtons;
@property(nonatomic, strong) NSScrollView *mainStructureScrollView;
@property(nonatomic, strong) NSScrollView *quickStructureScrollView;
@property(nonatomic, strong) NSStackView *sentenceStructureStack;
@property(nonatomic, strong) NSButton *quickGrammarBookmarkButton;
@property(nonatomic, strong) NSTextField *quickGrammarBookmarkStatus;
@property(nonatomic) BOOL quickGrammarBookmarkPending;
@property(nonatomic, strong) NSStackView *quickGrammarStack;
@property(nonatomic, strong) NSView *quickGrammarDetailCard;
@property(nonatomic, copy) NSArray<NSButton *> *quickGrammarChoices;
@property(nonatomic, strong) FYLearningAnalyzer *quickSentenceAnalyzer;
@property(nonatomic, strong) FYAnalysisResult *quickSentenceAnalysis;
@property(nonatomic, copy) NSString *quickSentenceAnalysisSource;
@property(nonatomic, copy) NSString *quickSentenceAnalysisTranslation;
@property(nonatomic, copy) NSString *quickSentenceAnalysisError;
@property(nonatomic) BOOL quickSentenceAnalyzing;
@property(nonatomic) NSInteger quickAnalysisGeneration;
@property(nonatomic, strong) NSPanel *regionSelectionPanel;
@property(nonatomic, strong) id regionSelectionKeyMonitor;
@property(nonatomic) BOOL selectOCRRegionAfterCaptureCalibration;
@property(nonatomic, strong) NSPanel *ocrPreviewPanel;
@property(nonatomic, strong) NSTextField *ocrPreviewLabel;
@property(nonatomic, strong) NSView *captionContainer;
@property(nonatomic, strong) NSTextField *captionTextLabel;
@property(nonatomic, strong) NSTextField *captionBrandLabel;

@property(nonatomic, strong) FYWindowManager *windowManager;
@property(nonatomic, strong) FYOCRManager *ocrManager;
@property(nonatomic, strong) dispatch_queue_t captureQueue;
@property(nonatomic, strong) dispatch_queue_t previewQueue;
@property(nonatomic, strong) NSTimer *previewTimer;
@property(nonatomic) BOOL previewInFlight;
@property(nonatomic) NSUInteger previewRequestSerial;
@property(nonatomic) NSUInteger previewRenderSerial;
@property(nonatomic) uint64_t lastPreviewCaptureFrameIndex;
@property(nonatomic, strong) NSMutableArray<WindowItem *> *windows;
@property(nonatomic, strong) NSTextField *diagnosticStatusLabel;
@property(nonatomic, strong) NSDate *lastDiagnosticCheckDate;
@property(nonatomic) BOOL exportingDiagnostics;
@property(nonatomic, strong) NSSharingService *diagnosticMailService;
@property(nonatomic, strong) NSPopUpButton *windowPopup;
// 窗口选择卡片：标题/说明随「识别输入源」变化；"显示全部窗口"只在有推荐窗口时才有意义。
@property(nonatomic, strong) NSTextField *windowCardTitleLabel;
@property(nonatomic, strong) NSTextField *windowCardHintLabel;
@property(nonatomic, strong) NSTextField *windowCardNoteLabel;
@property(nonatomic, strong) NSButton *windowScopeButton;
// 列表当前是否展开了全部窗口（默认精简）。
@property(nonatomic) BOOL showAllWindowsInPicker;
// 下拉框里的占位提示（例如「原窗口已关闭，请重新选择」）。
@property(nonatomic, copy) NSString *windowPickerPlaceholder;
// 占位提示是不是"原来的窗口没了"这一类：只有这一种才该盖掉贴译定位的通用原因，
// 「没有找到可用窗口」之类的提示不该改变定位原因文案。
@property(nonatomic) BOOL windowSelectionLost;
// 用户选择 vs 实际承载游戏画面的窗口。
// OBS 的「全屏投影」是另一个窗口：用户选编辑器时画面可能已经不在编辑器里，
// 继续按编辑器算映射就是贴译不跟随的根因，所以这里单独解析"实际显示目标"。
@property(nonatomic) BOOL displayTargetResolved;
@property(nonatomic) BOOL displayTargetAmbiguous;
@property(nonatomic) uint32_t resolvedDisplayTargetID;
@property(nonatomic, strong) NSDate *lastDisplayTargetProbeDate;
// 几何代次：实际显示目标或画面区域每变化一次就 +1。
// 异步翻译回来时校验它，避免旧回调把贴译按旧几何放回去。
@property(nonatomic) NSInteger geometryGeneration;
@property(nonatomic, copy) NSString *lastDisplayGeometryToken;
// 最近一次真正渲染过的译文/原文块：几何变化时用它重排，不重新请求翻译。
@property(nonatomic, copy) NSArray<NSString *> *lastInlineRenderedTranslations;
@property(nonatomic, copy) NSArray<OCRTextItem *> *lastInlineRenderedItems;
@property(nonatomic, strong) FYInlineOCRFrameStabilizer *inlineFrameStabilizer;
@property(nonatomic, strong) FYOCRRefinementStabilizer *ocrRefinementStabilizer;
@property(nonatomic, copy) NSDictionary *ocrRefinementContext;
// A raw OCR string can stay identical while its line boundaries change. Require
// two matching frames before replacing the currently rendered grouping.
@property(nonatomic, copy) NSArray<NSString *> *inlinePendingGroupedTexts;
@property(nonatomic) NSInteger inlinePendingGroupedCount;
@property(nonatomic, copy) NSArray<NSValue *> *lastInlineLayoutBoxes;
@property(nonatomic, copy) NSString *lastInlineLayoutContentKey;
@property(nonatomic, copy) NSString *lastInlineLayoutGeometryKey;
// 最近一次渲染时用的几何上下文。和 lastDisplayGeometryToken 不一致 =
// 画面目标/区域已经变了但贴译还是按旧几何渲染的 → 必须重排（哪怕文本一个字都没变）。
@property(nonatomic, copy) NSString *lastInlineRenderGeometryToken;
// A foreground poll must not revive panels hidden while waiting for valid geometry.
@property(nonatomic) BOOL inlineGeometryPending;
// 本轮 OCR 用的显示目标与几何代次（异步回调据此判断是否已过期）。
@property(nonatomic) NSInteger ocrGeometryGeneration;
@property(nonatomic) uint32_t ocrDisplayTargetWindowID;
// 采集卡输入：识别输入源与"字幕显示窗口"分开选择。
// 输入源只决定 OCR 从哪里取画面；字幕始终跟随上面选中的 QuickTime／OBS 窗口。
@property(nonatomic, strong) FYCaptureCardInput *captureCardInput;
// 采集卡视频显示区域（屏幕坐标），由校准写入。没有它就认为映射不可用：
// 「有帧 + 有窗口」不等于映射有效（窗口标题栏／工具栏／OBS 面板／裁剪都会让整窗估算整体偏移）。
@property(nonatomic, strong) FYCaptureMappingCache *captureMappingCache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *captureCardVideoRects;
// 上一次对缓存映射做「定点复核」的时间：限流用，避免每帧都截屏。
@property(nonatomic, strong) FYMappingValidationSchedule *mappingValidationSchedule;
@property(nonatomic, strong) NSDate *lastMappingValidationDate;
@property(nonatomic, strong) NSPanel *inlineExpandedReadingPanel;
// 展开态的稳定性：按**稳定块身份**管理；单帧 OCR 漏读不算换页（连续丢 2 帧才收起）。
@property(nonatomic) NSUInteger inlineExpandedMissingFrames;
// 极端降级：连折叠入口都贴不到原文附近时，在游戏显示区域边缘给「还有 N 条译文」。
@property(nonatomic, strong) NSPanel *inlineOverflowPanel;
@property(nonatomic, strong) NSPanel *inlineOverflowChoicePanel;
@property(nonatomic) NSUInteger inlineOverflowCount;
@property(nonatomic) NSUInteger inlineOverflowPanelCount;
@property(nonatomic, strong) NSArray<NSDictionary *> *inlineOverflowEntries;
@property(nonatomic) NSUInteger inlineOverflowCandidateCount;
@property(nonatomic) NSUInteger inlineOverflowCandidateFrames;
@property(nonatomic) NSTimeInterval inlineOverflowEmptySince;
@property(nonatomic, strong) id inlineOverflowChoiceKeyMonitor;
@property(nonatomic, strong) id inlineExpandedReadingKeyMonitor;
@property(nonatomic, strong) NSPanel *captureCalibrationPanel;
@property(nonatomic, strong) id captureCalibrationKeyMonitor;
@property(nonatomic, strong) FYAutoLocateSchedule *autoLocateSchedule;
@property(nonatomic, strong) NSDate *lastAutoLocateAttempt;
@property(nonatomic, strong) NSButton *captureCalibrateButton;
@property(nonatomic, strong) NSButton *captureCalibrateClearButton;
@property(nonatomic, strong) NSTextField *captureCalibrationLabel;
@property(nonatomic, strong) NSSegmentedControl *inputSourceControl;
@property(nonatomic, strong) NSPopUpButton *captureDevicePopup;
@property(nonatomic, strong) NSTextField *liveChipRecognition;
@property(nonatomic, strong) NSTextField *liveChipAutoTranslate;
@property(nonatomic, strong) NSTextField *liveChipPauseFollow;
@property(nonatomic, strong) NSTextField *liveScreenSpeakerLabel;
@property(nonatomic, strong) NSTextField *liveScreenDialogueLabel;
@property(nonatomic, strong) NSTextField *liveLevelTag;
@property(nonatomic, strong) NSLayoutConstraint *previewAspectConstraint;
@property(nonatomic, strong) NSTextField *permissionStatusLabel;
@property(nonatomic, strong) NSView *grammarStructureCard;
@property(nonatomic, copy) NSArray<NSButton *> *grammarTabButtons;
@property(nonatomic, copy) NSArray<NSView *> *grammarTabUnderlines;
@property(nonatomic) NSInteger selectedGrammarTab;
@property(nonatomic, strong) NSView *grammarPointsPane;
@property(nonatomic, strong) NSView *grammarTabRow;
@property(nonatomic, strong) NSView *grammarEmptyPane;
@property(nonatomic, strong) NSTextField *grammarEmptyTitle;
@property(nonatomic, strong) NSTextField *grammarEmptyHint;
@property(nonatomic, strong) NSButton *grammarEmptyAnalyzeButton;
@property(nonatomic, strong) NSTextField *grammarReferenceNote;
@property(nonatomic, copy) NSString *grammarAnalysisError;
@property(nonatomic, strong) NSView *grammarExamplesPane;
@property(nonatomic, strong) NSTextField *grammarExampleLabel;
@property(nonatomic, strong) NSView *grammarFollowupDisclosure;
@property(nonatomic, strong) NSTextField *captureStatusLabel;
@property(nonatomic, strong) NSTextField *inputSourceHintLabel;
@property(nonatomic, strong) NSView *captureCardControlsView;
@property(nonatomic, strong) NSButton *captureSettingsButton;
@property(nonatomic) NSInteger inputSourceSegment;
@property(nonatomic, copy, nullable) NSString *selectedCaptureDeviceID;
@property(nonatomic) BOOL captureDeviceListLoaded;
@property(nonatomic) uint64_t lastOCRedCaptureFrameIndex;
@property(nonatomic, strong) NSSegmentedControl *languageControl;
@property(nonatomic, strong) FYContentRouter *contentRouter;
@property(nonatomic) NSInteger detectedModeSegment;
@property(nonatomic) NSInteger candidateModeSegment;
@property(nonatomic) NSInteger candidateModeHits;
@property(nonatomic) BOOL captionPanelShownByUser;
@property(nonatomic) BOOL captionSuppressedForUIMode;
@property(nonatomic) BOOL selectingCaptureRegion;
@property(nonatomic, strong) NSTimer *overlayVisibilityTimer;
@property(nonatomic, copy) NSArray<NSDictionary *> *overlayWindowSnapshot;
@property(nonatomic, strong) NSNumber *overlayOwnerPIDSnapshot;
@property(nonatomic, strong) NSButton *captionHideButton;
@property(nonatomic, strong) NSSlider *regionXSlider;
@property(nonatomic, strong) NSSlider *regionYSlider;
@property(nonatomic, strong) NSSlider *regionWidthSlider;
@property(nonatomic, strong) NSSlider *regionHeightSlider;
@property(nonatomic, strong) NSSlider *captionOpacitySlider;
@property(nonatomic, strong) NSSlider *captionFontSizeSlider;
@property(nonatomic, strong) NSSlider *captionHeightSlider;
@property(nonatomic, strong) NSSlider *captionWidthSlider;
@property(nonatomic, strong) NSColorWell *captionTextColorWell;
@property(nonatomic) BOOL captionTextColorCustomized;
@property(nonatomic, strong) NSSlider *batchFontSizeSlider;
@property(nonatomic, strong) NSSlider *batchWidthSlider;
@property(nonatomic, strong) NSSlider *batchHeightSlider;
@property(nonatomic, strong) NSColorWell *batchTextColorWell;
@property(nonatomic) BOOL batchTextColorCustomized;
@property(nonatomic, strong) NSSegmentedControl *batchThemeControl;
@property(nonatomic, strong) NSSegmentedControl *appearanceModeControl;
@property(nonatomic, copy) NSArray<NSButton *> *appearanceModeButtons;
@property(nonatomic, strong) NSArray<NSView *> *appearanceEditors;
@property(nonatomic, strong) NSArray<FYSubtitleStyleButton *> *batchThemeSwatches;
@property(nonatomic, strong) NSArray<FYSubtitleAppearancePreview *> *appearanceSamples;
@property(nonatomic, strong) NSMapTable<NSControl *, NSTextField *> *appearanceValueLabels;
@property(nonatomic, strong) NSArray<NSTextField *> *appearanceColorStateLabels;
@property(nonatomic, strong) NSArray<NSTextField *> *appearanceThemeLabels;
@property(nonatomic, strong) NSTimer *batchAppearanceTimer;
@property(nonatomic, strong) NSSegmentedControl *captionThemeControl;
#ifdef FY_TEST_ISOLATED_CREDENTIAL_STORE
// Tests may bypass stability/refinement to isolate downstream boundaries.
@property(nonatomic, strong) NSButton *stableTextCheckbox;
@property(nonatomic, strong) NSButton *autoFitRegionCheckbox;
#endif
@property(nonatomic, strong) NSButton *manualOCRScopeCheckbox;
@property(nonatomic, strong) FYTranslationServiceView *translationServiceView;
@property(nonatomic, strong) FYTranslationServiceTestPresentation *serviceTestPresentation;
@property(nonatomic, strong) NSTextField *baseURLField;
@property(nonatomic, strong) NSTextField *modelField;
@property(nonatomic, strong) NSSecureTextField *apiKeyField;
@property(nonatomic, copy) NSString *persistedAPIKey;
@property(nonatomic) BOOL credentialLoadFailed;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *currentWindowLabel;
@property(nonatomic, strong) NSTextField *translationCountLabel;
@property(nonatomic, strong) NSButton *runButton;
@property(nonatomic, strong) NSTextField *runStateLabel;
@property(nonatomic, strong) NSTextField *headerTitleLabel;
@property(nonatomic, strong) NSTextField *ocrDurationLabel;
@property(nonatomic, strong) NSTextField *translationDurationLabel;
@property(nonatomic, strong) NSTextField *latestTranslationLabel;
@property(nonatomic, strong) NSTextField *latestSourceLabel;
@property(nonatomic, strong) NSTextField *liveErrorLabel;
@property(nonatomic, strong) NSTextField *themeSummaryLabel;
@property(nonatomic, strong) NSArray<NSButton *> *themeSwatches;
@property(nonatomic, strong) NSTextField *serviceStatusLabel;
@property(nonatomic, strong) NSTextField *serviceErrorLabel;
@property(nonatomic, strong) NSTextField *serviceTestModelLabel;
@property(nonatomic, strong) NSTextField *serviceTestResultLabel;
@property(nonatomic, strong) NSButton *serviceTestButton;
@property(nonatomic, strong) NSImageView *serviceStatusIcon;
@property(nonatomic, strong) FYAdventurePanel *serviceTestResultPanel;
@property(nonatomic, strong) NSTextField *serviceTestMessageLabel;
@property(nonatomic, strong) NSImageView *framePreview;
@property(nonatomic, strong) NSTextField *previewPlaceholder;
@property(nonatomic, strong) NSArray<NSView *> *pages;
@property(nonatomic, strong) NSArray<NSButton *> *pageButtons;
@property(nonatomic, strong) NSMutableArray<NSView *> *disclosureViews;
@property(nonatomic, strong) NSTimer *saveTimer;
@property(nonatomic, strong) NSDate *lastPreviewDate;
@property(nonatomic, strong) NSDate *lastWindowRecoveryAttemptDate;
@property(nonatomic) BOOL captureUnavailable;
@property(nonatomic) BOOL loadingSettings;
@property(nonatomic) NSInteger selectedPage;
@property(nonatomic) NSInteger serviceTestGeneration;

@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSURLSessionDataTask *activeTranslationTask;
@property(nonatomic, strong) FYTranslationTaskOwner *translationTaskOwner;
@property(nonatomic, strong) FYTranslationTaskOwner *serviceTestTaskOwner;
@property(nonatomic) NSInteger translationGeneration;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL inFlight;
// Capture/OCR owns inFlight. Network work has a separate latest-content lease.
@property(nonatomic) NSUInteger contentTranslationRevision;
@property(nonatomic) NSUInteger contentTranslationOperations;
@property(nonatomic, copy) NSString *contentTranslationText;
@property(nonatomic) NSInteger contentTranslationMode;
@property(nonatomic, copy) NSArray<OCRTextItem *> *contentTranslationUIItems;
@property(nonatomic) NSInteger contentTranslationGeometryGeneration;
@property(nonatomic) uint32_t contentTranslationDisplayTarget;
@property(nonatomic) NSUInteger inlineTranslationSerial;
@property(nonatomic, strong) FYInlinePendingLongBatch *pendingInlineLongBatch;
@property(nonatomic) BOOL screenAccessRequestedDuringSession;
@property(nonatomic) BOOL mainWindowVisibleBeforeRegionSelection;
@property(nonatomic) BOOL captionPanelVisibleBeforeRegionSelection;
@property(nonatomic) BOOL ocrPreviewVisibleBeforeRegionSelection;
@property(nonatomic, strong) FYTranslationRunState *translationRunState;
@property(nonatomic, copy) NSString *lastTranslatedNormalizedText;
@property(nonatomic, copy) NSString *lastSubmittedNormalizedText;
@property(nonatomic, strong) FYTranslationCache *dialogueTranslationCache;
@property(nonatomic, strong) NSDate *lastTranslationAttemptDate;
@property(nonatomic, strong) FYOCRStabilityOwner *ocrStabilityOwner;
@property(nonatomic, copy) NSString *stableCandidate;
@property(nonatomic) NSInteger stableCandidateCount;
@property(nonatomic, copy) NSString *inlineOCRPendingText;
@property(nonatomic) NSInteger inlineOCRPendingCount;
@property(nonatomic) NSInteger translationCount;
@property(nonatomic, strong) NSMutableArray<NSPanel *> *inlineTranslationPanels;
@property(nonatomic, strong) NSMutableArray<NSPanel *> *inlineLongCardPanels;
@property(nonatomic, copy) NSString *lastInlineTranslationKey;
@property(nonatomic, strong) FYInlineTranslationCache *inlineCacheOwner;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inlineTranslationCache;
// 自适应分组与布局：分组器、布局引擎、上一帧结果、按块身份复用的面板表。
@property(nonatomic, strong) FYInlineGrouper *inlineGrouper;
@property(nonatomic, strong) FYInlineLayoutEngine *inlineLayoutEngine;
@property(nonatomic, strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic, copy) NSDictionary *lastInlineLayoutDebugContext;
@property(nonatomic) NSRect lastInlineLayoutDebugViewport;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSPanel *> *inlinePanelsByBlockID;
// 最近一帧的降级统计（状态区提示用，不写字幕框）。
@property(nonatomic) NSUInteger lastInlineUnplaceableCount;
@property(nonatomic) NSUInteger lastInlineCompactEntryCount;
// 当前展开的完整阅读卡属于哪个块（再点同一个紧凑入口要收起它）。
@property(nonatomic, copy) NSString *inlineExpandedReadingBlockID;
// 本帧「原始身份 → 布局稳定身份」映射：让选中判定/快照在任何调用点都用稳定身份。
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inlineStableBlockIDs;
// 用户手动拖动过的贴译位置：键 = 文本 + 原文锚点的粗分桶（抖动不换键），值 = 相对锚点的偏移。
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *inlineManualOffsets;
// 连续多少帧没再看到这个块：超过上限就丢弃偏移，绝不继承给别的块。
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *inlineManualOffsetAge;
// 「界面译文」集中查看列表：暂不可放置/改用入口的译文都在这里完整可读（可滚动、不截断）。
@property(nonatomic, strong) NSView *inlineTranslationListCard;
@property(nonatomic, strong) NSStackView *inlineTranslationListStack;
@property(nonatomic, strong) NSTextField *inlineTranslationListCount;
@property(nonatomic, copy) NSArray<FYInlineBlockSnapshot *> *inlineTranslationListSnapshots;
@property(nonatomic, copy) NSString *inlineTranslationListSignature;
// 按住 Option 才允许拖动短贴片：定时读一次修饰键状态，避免要求辅助功能权限。
@property(nonatomic, strong) NSTimer *inlineModifierTimer;
@property(nonatomic) BOOL inlineOptionDragArmed;
@property(nonatomic, weak) NSPanel *inlineDraggingPanel;

// 日语学习模块
@property(nonatomic, strong) FYLearningStore *learningStore;
@property(nonatomic, strong) FYLearningAnalyzer *learningAnalyzer;
@property(nonatomic, strong) FYJapaneseTokenizer *japaneseTokenizer;
@property(nonatomic, strong) FYGrammarCatalog *grammarCatalog;
@property(nonatomic, strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic, strong) NSTextField *learningModelField;
@property(nonatomic, strong) FYSelectableSourceTextView *learningSourceTextView;
@property(nonatomic, strong) NSTextField *learningTranslationLabel;
@property(nonatomic, strong) NSTextField *learningPinnedLabel;
@property(nonatomic, strong) NSButton *pinSentenceButton;
@property(nonatomic, strong) NSButton *followLatestButton;
@property(nonatomic, strong) NSButton *analyzeButton;
@property(nonatomic, strong) NSTextField *grammarStatusLabel;
@property(nonatomic, strong) NSTextField *grammarResultsLabel;
@property(nonatomic, strong) NSPopUpButton *grammarSelector;
@property(nonatomic, strong) NSTextField *vocabularyListLabel;
@property(nonatomic, strong) NSTextField *vocabularyStatusLabel;
@property(nonatomic, strong) NSTextField *lemmaField;
@property(nonatomic, strong) NSTextField *readingField;
@property(nonatomic, strong) NSTextField *meaningField;
@property(nonatomic, strong) NSTextField *reviewPromptLabel;
@property(nonatomic, strong) NSTextField *grammarSourceLabel;
@property(nonatomic, strong) NSTextField *grammarFollowupResultLabel;
@property(nonatomic, strong) NSTextField *grammarQuestionField;
@property(nonatomic) BOOL learningAnalysisBusy;
@property(nonatomic, strong) NSLayoutConstraint *sourceReadingHeight;
@property(nonatomic, strong) NSLayoutConstraint *translationReadingMinimumHeight;
@property(nonatomic, strong) NSLayoutConstraint *sourceReadingMinimumHeight;
@property(nonatomic, strong) NSTextField *liveSourceEmptyLabel;
@property(nonatomic, strong) NSTextField *liveSourceSelectionHintLabel;
@property(nonatomic, strong) NSStackView *sentenceInsightStack;
@property(nonatomic, strong) NSTextField *sentenceInsightLabel;
@property(nonatomic, strong) NSArray<NSControl *> *grammarFollowupControls;
@property(nonatomic, strong) NSStackView *grammarBookmarkStack;
@property(nonatomic, strong) NSStackView *grammarFollowupStack;
@property(nonatomic, strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic, strong) NSTextField *vocabularySelectionLabel;
@property(nonatomic, strong) NSTextField *reviewWordLabel;
@property(nonatomic, strong) NSTextField *reviewMeaningLabel;
@property(nonatomic, strong) NSPopUpButton *historyPopup;
@property(nonatomic, strong) NSArray<FYSentenceRecord *> *historyRecords;
@property(nonatomic, copy) NSString *displayedSentenceID;
@property(nonatomic) NSInteger displayedVersion;
@property(nonatomic, copy) NSString *displayedSourceText;
@property(nonatomic, copy, nullable) NSString *displayedTranslation;
@property(nonatomic, strong) NSButton *revealButton;
@property(nonatomic, strong) NSButton *knownButton;
@property(nonatomic, strong) NSButton *notYetButton;
@property(nonatomic, strong) FYVocabularyEntry *reviewingEntry;
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> *reviewList;
@property(nonatomic) NSInteger reviewIndex;
@property(nonatomic) BOOL vocabCompletionFromAI;
@property(nonatomic) NSInteger vocabSelectionGeneration;
@property(nonatomic, strong) NSButton *grammarPageAnalyzeButton;
@property(nonatomic, strong) NSTextField *grammarBookmarkListLabel;
@property(nonatomic, strong) NSPopUpButton *grammarBookmarkPopup;
@property(nonatomic, strong) NSArray<FYGrammarBookmark *> *grammarBookmarks;
@property(nonatomic, strong) NSTextField *vocabularyExamplesLabel;
@property(nonatomic, strong) NSPopUpButton *vocabularyExamplesPopup;
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> *vocabularyExamplesList;
// UI 还原新增：卡片/词条确认/历史列表/词卡/语法详情两列
@property(nonatomic, strong) NSStackView *wordPickArea;
@property(nonatomic, strong) NSTextField *wordPickSurfaceLabel;
@property(nonatomic, strong) NSStackView *historyListStack;
@property(nonatomic, strong) NSStackView *wordCardStack;
@property(nonatomic, strong) NSTextField *grammarDetailNameLabel;
@property(nonatomic, strong) NSTextField *grammarDetailLevelLabel;
@property(nonatomic, strong) NSTextField *grammarDetailBodyLabel;
@property(nonatomic, strong) NSButton *grammarDetailBookmarkButton;
@property(nonatomic, strong) FYGrammarActionState *grammarActions;
@property(nonatomic, strong) FYGrammarActionState *quickGrammarActions;
@property(nonatomic, strong) NSButton *grammarExpandButton;
@property(nonatomic, strong) NSButton *grammarReviewButton;
@property(nonatomic, strong) NSTextField *grammarExpandedLabel;
@property(nonatomic, strong) NSButton *quickGrammarExpandButton;
@property(nonatomic, strong) NSButton *quickGrammarReviewButton;
@property(nonatomic, strong) NSTextField *quickGrammarReviewStatus;

@property(nonatomic, strong) NSStackView *grammarOtherStack;
@property(nonatomic, strong) NSTextField *grammarOtherEmptyLabel;
@property(nonatomic) NSInteger selectedGrammarIndex;
@property(nonatomic, strong) NSTextView *grammarSourceTextView;
@property(nonatomic, strong) NSButton *grammarBackToSourceButton;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *revealedMeanings;
@property(nonatomic, strong) NSView *learningPageHost;
@property(nonatomic, strong) NSTextField *headerDescriptionLabel;
@property(nonatomic, strong) NSTextField *grammarPinnedLabel;
@property(nonatomic, strong) NSView *vocabularyEmptyCard;
@property(nonatomic) BOOL savingVocabulary;
@property(nonatomic) NSInteger analysisRequestGeneration;
@property(nonatomic) NSInteger followupRequestGeneration;
@property(nonatomic, strong) NSStackView *grammarDetailFields;
@property(nonatomic, strong) NSStackView *grammarUsageBlock;
@property(nonatomic, strong) NSButton *grammarFollowupToggle;
@property(nonatomic, strong) NSStackView *savedGrammarCardStack;
@property(nonatomic, strong) NSButton *grammarSourceLinkButton;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *wordExampleIndices;
@property(nonatomic) NSInteger wordCardsGeneration;

@property(nonatomic, strong) FYMainWindowController *mainWindowController;
@property(nonatomic, strong) FYCollectionController *collectionController;
@property(nonatomic, strong) FYGrammarPresentationController *grammarPresentationController;
@property(nonatomic, strong) FYStudyPresentationController *studyPresentationController;
@property(nonatomic, strong) FYReferencePresentationController *referencePresentationController;
@end

// Actions are implemented in the primary class and explicit compatibility categories.
@interface AppDelegate (FYInternalActions)
// Existing production actions and injectable boundaries.
- (NSURLSessionDataTask *)activeTranslationTask;
- (void)setActiveTranslationTask:(NSURLSessionDataTask *)task;
- (instancetype)init;
- (void)createApplicationMenu;
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender;
- (void)windowDidResize:(NSNotification *)notification;
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible;
- (NSURL *)learningCatalogURL;
- (void)setupLearning;
- (void)syncLearningAnalyzerConfig;
- (NSString *)bundledLicenseNotes;
- (NSScrollView *)makeLicenseNotesView;
- (void)createMainWindow;
- (NSView *)makeSidebar;
- (NSView *)makeRunHeader;
- (NSScrollView *)makePageScrollWithContent:(NSView *)content;
- (void)selectPage:(NSButton *)sender;
- (void)selectPageAtIndex:(NSInteger)index;
- (NSView *)makeLivePage;
- (NSView *)makeInlineTranslationListCard;
- (void)refreshInlineTranslationList;
- (void)openInlineTranslationRow:(NSButton *)sender;
- (NSView *)makeRunSettingsPage;
- (void)focusWindowSelection:(id)sender;
- (NSView *)makeVocabularyPage;
- (void)updateLearningCollectionSummary;
- (void)selectLearningCollection:(NSButton *)sender;
- (void)toggleLearningPin:(id)sender;
- (void)vocabularyFormChanged:(id)sender;
- (void)freezeLearningSentenceForSelection;
- (void)selectWordAtCharacterIndex:(NSUInteger)characterIndex;
- (void)updateWordPickForSelection;
- (void)closeWordPick:(id)sender;
- (void)openHistoryAnalysis:(NSButton *)sender;
- (void)grammarSelectorChanged:(id)sender;
- (void)pinLearningSentence:(id)sender;
- (void)followLatestSentence:(id)sender;
- (void)setAnalyzeBusy:(BOOL)busy;
- (void)analyzeCurrentSentence:(id)sender;
- (void)refreshGrammarResults;
- (void)renderGrammarDetailAtIndex:(NSInteger)index;
- (void)openGrammarSource:(id)sender;
- (FYGrammarBookmark *)bookmarkForCurrentGrammar;
- (BOOL)analysisMatchesCurrentSentence;
- (void)highlightGrammarMatches;
- (void)applyHighlight:(NSColor *)color toTextView:(NSTextView *)textView;
- (void)clearGrammarHighlight;
- (void)clearAnalysisDisplay;
- (void)bookmarkGrammarItem:(NSButton *)sender;
- (void)bookmarkSelectedGrammar:(id)sender;
- (void)selectGrammarItem:(NSButton *)sender;
- (void)applyGrammarSelectionLocally;
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick;
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick;
- (FYGrammarItem *)selectedGrammarItem;
- (void)backToSourcePage:(id)sender;
- (void)simplerExplanationForGrammar:(id)sender;
- (void)exampleSentenceForGrammar:(id)sender;
- (void)requestGrammarFollowupExample:(BOOL)example;
- (NSString *)selectedLearningText;
- (void)bookmarkSelectedVocabulary:(id)sender;
- (void)completeSelectedVocabulary:(id)sender;
- (NSAttributedString *)liveReadingText:(NSString *)text japanese:(BOOL)japanese;
- (void)updateLiveSourceReadingHeight;
- (void)refreshLearningSource;
- (void)syncCoordinatorToDisplayed;
- (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString * _Nullable * _Nullable)outSpeaker body:(NSString * _Nullable * _Nullable)outBody;
- (nullable NSString *)currentSentenceLevelTag;
- (void)refreshLiveDialoguePresentation:(NSString *)source;
- (void)refreshLearningStatus;
- (void)refreshHistory;
- (void)refreshHistoryAction:(id)sender;
- (void)historyChanged:(id)sender;
- (void)refreshVocabularyList;
- (void)rebuildWordCards;
- (void)toggleSavedWordDetails:(NSButton *)sender;
- (FYVocabularyEntry *)wordForCardButton:(NSButton *)sender;
- (void)nextWordExample:(NSButton *)sender;
- (void)toggleWordMeaning:(NSButton *)sender;
- (void)toggleWordMastered:(NSButton *)sender;
- (void)removeWordCard:(NSButton *)sender;
- (void)nextReviewWord:(id)sender;
- (void)revealReviewMeaning:(id)sender;
- (void)markReviewKnown:(id)sender;
- (void)markReviewLearning:(id)sender;
- (void)setReviewStatus:(FYReviewStatus)status;
- (void)removeReviewWord:(id)sender;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (void)refreshGrammarBookmarks:(id)sender;
- (void)grammarBookmarkChanged:(id)sender;
- (void)deleteGrammarBookmark:(NSButton *)sender;
- (void)refreshVocabularyExamplesPopup;
- (void)vocabularyExamplesChanged:(id)sender;
- (void)showVocabularyExamples:(id)sender;
- (NSArray<NSString *> *)textsFromItems:(NSArray<OCRTextItem *> *)items;
- (void)bindTranslations:(NSArray<NSString *> *)translations toIdentities:(NSArray<FYRequestIdentity *> *)identities;
- (void)selectCaptionSwatch:(NSButton *)sender;
- (void)resetCaptionTextColor:(id)sender;
- (void)updateThemeSummary;
- (NSView *)permissionControls;
- (void)openPermissionSettings:(id)sender;
- (NSView *)recognitionCard;
- (NSView *)windowCard;
- (NSView *)translationCard;
- (NSView *)captionCard;
- (NSView *)batchCaptionCard;
- (void)createCaptionWindow;
- (void)showCaptionAppearancePreview:(id)sender;
- (void)updateCaptionAppearancePreview;
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSView *)settingsRowWithLabel:(NSString *)label view:(NSView *)view;
- (NSView *)rowWithLabel:(NSString *)label view:(NSView *)view;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSTextField *)textField:(NSString *)placeholder;
- (NSView *)disclosureWithTitle:(NSString *)title content:(NSView *)content;
- (void)toggleDisclosure:(NSButton *)sender;
- (NSSlider *)sliderWithMin:(double)min max:(double)max value:(double)value action:(SEL)action;
- (NSSegmentedControl *)segmentedWithLabels:(NSArray<NSString *> *)labels action:(SEL)action;
- (NSView *)spacer;
- (NSView *)separator;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSColor *)uiBorder;
- (NSColor *)uiAccent;
- (NSColor *)uiSelected;
- (NSColor *)uiSurface;
- (NSView *)card;
- (NSView *)cardWithStack:(NSStackView *)stack;
- (void)pinFullWidth:(NSView *)view toStack:(NSStackView *)stack;
- (NSTextField *)cardTitle:(NSString *)text;
- (NSTextField *)mutedLabel:(NSString *)text;
- (void)invalidateContentTranslation;
- (BOOL)pendingContentMatchesText:(NSString *)text mode:(NSInteger)mode;
- (BOOL)pendingInlineMatchesItems:(NSArray<OCRTextItem *> *)items;
- (NSUInteger)beginContentTranslation:(NSString *)text mode:(NSInteger)mode;
- (NSArray<NSString *> *)longInlineKeysForItems:(NSArray<OCRTextItem *> *)items;
- (NSUInteger)beginInlineContentTranslation:(NSString *)text items:(NSArray<OCRTextItem *> *)items trace:(NSDictionary *)trace;
- (void)finishContentTranslation:(NSUInteger)revision;
- (void)advanceTranslationGeneration;
- (void)toggleRunning:(id)sender;
- (void)start;
- (void)stop;
- (void)handleInlineTranslationResult:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items error:(NSError *)translationError failureStatus:(NSString *)failureStatus successPrefix:(NSString *)successPrefix;
- (pid_t)selectedWindowOwnerPID;
- (NSArray<NSDictionary *> *)windowInfosIncludingWindow:(uint32_t)windowID;
- (NSArray<NSDictionary *> *)onScreenWindowInfos;
- (BOOL)targetQualifiesForOverlayWithFrontmostPID:(pid_t)frontPID
                                        targetPID:(pid_t)targetPID
                                   targetOnScreen:(BOOL)targetOnScreen
                         ownerHasOnScreenWindow:(BOOL)ownerHasOnScreenWindow
                            interactingWithOverlay:(BOOL)interactingWithOverlay;
- (NSWindowLevel)overlayLevelForTargetPID:(pid_t)targetPID inWindowList:(NSArray<NSDictionary *> *)windows;
- (BOOL)translationTargetIsForeground;
- (BOOL)translationTargetIsForegroundWithWindowList:(NSArray<NSDictionary *> *)visibleWindows;
- (void)refreshOverlayVisibility:(id)sender;
- (void)anchorCaptionDockToCaption;
- (void)hideCaptionPanel:(id)sender;
- (void)showCaptionPanel:(id)sender;
- (void)setCaptionPanelVisibleForUIMode:(BOOL)uiMode;
- (BOOL)captionPanelShouldBeHidden;
- (void)timerFired:(NSTimer *)timer;
- (FYOCRManager *)ocrManager;
- (FYWindowManager *)windowManager;
- (NSArray<WindowItem *> *)availableWindowItems;
- (NSInteger)quickTimeCapturePriority:(WindowItem *)item;
- (NSArray<WindowItem *> *)displayedWindowItems;
- (BOOL)hasRecommendedWindowItems;
- (NSString *)windowBaseTitleForItem:(WindowItem *)item;
- (NSString *)windowMenuTitleForItem:(WindowItem *)item occurrence:(NSUInteger)occurrence;
- (void)rebuildWindowMenuPreservingSelection;
- (void)refreshWindows:(id)sender;
- (void)toggleWindowListScope:(id)sender;
- (BOOL)selectWindowWithID:(uint32_t)windowID notifyChange:(BOOL)notify;
- (BOOL)recoverWindowSelectionIfRecreated;
- (void)windowSelectionChanged:(id)sender;
- (void)resetForSelectedWindowChange;
- (void)hideInlineTranslationPanelsForGeometryChange;
- (void)refreshDisplayGeometryIfNeeded:(BOOL)force;
- (void)updateWindowCardCopy;
- (FYCaptureCardInput *)captureCardInput;
- (BOOL)captureCardInputEnabled;
- (void)updateCaptureCardStatus;
- (void)ensureCaptureCardPermissionThen:(void (^)(BOOL granted))continuation;
- (NSString *)captionLinesFromTranslations:(NSArray<NSString *> *)translations;
- (nullable NSString *)captureDeviceIDFromPopup;
- (void)refreshCaptureDevices:(id)sender;
- (void)captureDeviceChanged:(id)sender;
- (void)inputSourceChanged:(id)sender;
- (void)resetForInputSourceChange;
- (BOOL)startCaptureCardSessionIfPossible;
- (void)reconnectCaptureDevice:(id)sender;
- (void)openCameraAccessSettings:(id)sender;
- (CGRect)selectedOCRScope;
- (void)controlValueChanged:(id)sender;
- (void)scheduleBatchAppearanceLayout;
- (void)selectOCRRegion:(id)sender;
- (void)hideInterfaceForRegionSelection;
- (void)restoreInterfaceAfterRegionSelectionShowingOCRPreview:(BOOL)showOCRPreview;
- (void)showOCRPreview:(id)sender;
- (void)hideOCRPreview:(id)sender;
- (void)updateOCRPreviewIfVisible;
- (void)useDefaultSubtitleRegion:(id)sender;
- (void)useLargeSubtitleRegion:(id)sender;
- (void)useFullWindowRegion:(id)sender;
- (void)useInterfaceFullWindowPreset:(id)sender;
- (void)translateCurrentInterface:(id)sender;
- (void)requestScreenAccess:(id)sender;
- (void)checkScreenAccess:(id)sender;
- (void)relaunchApp:(id)sender;
- (void)openScreenAccessSettings:(id)sender;
- (void)invalidateServiceTest;
- (NSString *)configuredTranslationModel;
- (void)updateServiceTestModelLabel;
- (void)presentServiceTestState:(NSString *)state error:(NSString *)error result:(NSString *)result;
- (void)testTranslation:(id)sender;
- (void)applyTranslationServicePreset:(NSString *)identifier model:(NSString *)model;
- (void)useDeepSeekPreset:(id)sender;
- (void)useDeepSeekFlashPreset:(id)sender;
- (void)useOpenAIPreset:(id)sender;
- (void)pasteAPIKeyFromClipboard:(id)sender;
- (void)clearAPIKey:(id)sender;
- (void)saveSettings:(id)sender;
- (void)scheduleSettingsSave;
- (void)controlTextDidChange:(NSNotification *)notification;
- (void)controlTextDidEndEditing:(NSNotification *)notification;
- (void)applicationWillTerminate:(NSNotification *)notification;
- (void)serviceSettingsChanged;
- (void)loadSettings;
- (NSArray<OCRTextItem *> *)mergedInlineTextItemsFromItems:(NSArray<OCRTextItem *> *)items;
- (FYInlineTextBlock *)inlineLayoutBlockForItem:(OCRTextItem *)item order:(NSInteger)order;
- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items;
- (NSArray<OCRTextItem *> *)filteredInlineTextItems:(NSArray<OCRTextItem *> *)items strict:(BOOL)strict;
- (NSString *)dialogueTextFromItems:(NSArray<OCRTextItem *> *)items speakerLabelOnly:(BOOL *)speakerLabelOnly;
- (BOOL)shouldIgnoreInlineText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box strict:(BOOL)strict;
- (BOOL)isButtonLikeInlineText:(NSString *)normalized;
- (double)inlinePriorityForText:(NSString *)text normalized:(NSString *)normalized boundingBox:(CGRect)box;
- (NSString *)inlineTranslationCacheKeyForItem:(OCRTextItem *)item;
- (void)translateInlineTextItems:(NSArray<OCRTextItem *> *)items completion:(void (^)(NSArray<NSString *> *translations, NSError *error))completion;
- (void)translateInlineLongItems:(NSArray<OCRTextItem *> *)items indexes:(NSArray<NSNumber *> *)indexes
    keys:(NSArray<NSString *> *)keys translations:(NSMutableArray<NSString *> *)translations
    completion:(void (^)(NSError *))completion;
- (void)translateInlineBatch:(NSArray<OCRTextItem *> *)items
                     indexes:(NSArray<NSNumber *> *)indexes
                        keys:(NSArray<NSString *> *)keys
                translations:(NSMutableArray<NSString *> *)translations
                        long:(BOOL)isLong
                  completion:(void (^)(NSError *error))completion;
- (void)cacheInlineTranslation:(NSString *)value forKey:(NSString *)key;
- (NSArray<NSString *> *)parseNumberedTranslations:(NSString *)text expectedCount:(NSUInteger)count;
- (void)clearInlineTranslationPanels;
- (NSString *)inlineTranslationIdentityForTranslations:(NSArray<NSString *> *)translations
                                              forItems:(NSArray<OCRTextItem *> *)items;
- (void)updateInlinePanel:(NSPanel *)panel
              translation:(NSString *)translation
               sourceText:(NSString *)sourceText
              sourceFrame:(NSRect)sourceFrame
              windowFrame:(NSRect)windowFrame
                   layout:(InlinePanelLayout)layout;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items;
- (void)recordInlineLayoutDebug:(FYInlineLayoutResult *)result previous:(FYInlineLayoutResult *)previous viewport:(NSRect)viewport reason:(NSString *)reason;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items placementRect:(NSRect)windowFrame;
- (void)updateInlineOverflowEntryWithPlacements:(NSArray<FYInlinePlacement *> *)placements
                                          items:(NSDictionary<NSString *, OCRTextItem *> *)itemsByBlockID
                                       viewport:(NSRect)viewport
                                    unplaceable:(NSUInteger)unplaceable;
- (void)expireInlineOverflowEntryIfNeeded;
- (void)positionInlineOverflowEntryInViewport:(NSRect)viewport;
- (void)buildInlineOverflowEntryForViewport:(NSRect)viewport;
- (void)showInlineOverflowChooser;
- (void)closeInlineOverflowChoiceAction:(id)sender;
- (NSString *)overflowRowTitleForEntry:(NSDictionary *)entry;
- (void)openInlineOverflowRow:(NSButton *)sender;
- (void)closeInlineOverflowChoice;
- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box;
- (NSValue *)inlineManualOffsetForText:(NSString *)text normalizedBox:(CGRect)box;
- (void)recordInlineManualOffsetForPanel:(NSPanel *)panel;
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement;
- (void)startInlineModifierMonitor;
- (void)stopInlineModifierMonitor;
- (void)inlineModifierTick:(NSTimer *)timer;
- (void)applyInlineDragMode:(BOOL)armed;
- (InlinePanelLayout)inlinePanelLayoutFromPlacement:(FYInlinePlacement *)placement;
- (BOOL)inlineBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item;
- (BOOL)inlineBlockIsSelectedForItem:(OCRTextItem *)item;
- (NSParagraphStyle *)inlineLongCardBodyStyle;
- (NSFont *)inlineLongCardBodyFont;
- (CGFloat)inlineLongCardBodyLineHeight;
- (CGFloat)inlineLongCardMinimumHeight;
- (CGFloat)inlineLongCardBodyViewportForHeight:(CGFloat)cardHeight;
- (void)applyInlineLongCardBody:(NSString *)translation toLabel:(NSTextField *)label cardWidth:(CGFloat)cardWidth;
- (void)applyInlineLongCardBody:(NSString *)translation
                        toLabel:(NSTextField *)label
                       cardWidth:(CGFloat)cardWidth
                       placement:(FYInlinePlacement *)placement;
- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation size:(NSSize)size selected:(BOOL)selected compact:(BOOL)compact;
- (NSView *)inlineLongCardContentForTranslation:(NSString *)translation
                                           size:(NSSize)size
                                       selected:(BOOL)selected
                                        compact:(BOOL)compact
                                      placement:(FYInlinePlacement *)placement;
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation;
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)translation expandedReading:(BOOL)expandedReading;
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame;
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement;
- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame;
- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame compact:(BOOL)compact;
- (void)updateInlineLongCard:(NSPanel *)panel
                 translation:(NSString *)translation
                        item:(OCRTextItem *)item
                       frame:(NSRect)frame
                     compact:(BOOL)compact
                   placement:(FYInlinePlacement *)placement;
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item;
- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item translation:(NSString *)translation;
- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item
                                     translation:(NSString *)translation
                                   stableBlockID:(NSString *)stableBlockID;
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block
                                      translation:(NSString *)translation
                                    stableBlockID:(NSString *)stableBlockID;
- (void)wireInlineLongCardPanel:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(NSRect)frame;
- (void)wireInlineLongCardPanel:(NSPanel *)panel
                           item:(OCRTextItem *)item
                    translation:(NSString *)translation
                          frame:(NSRect)frame
                  stableBlockID:(NSString *)stableBlockID;
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation;
- (NSSize)expandedInlineReadingSizeForTranslation:(NSString *)translation viewport:(NSRect)viewport;
- (void)refreshExpandedInlineReadingCardAppearanceInRect:(NSRect)viewport;
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item
                             translation:(NSString *)translation
                           stableBlockID:(NSString *)stableBlockID;
- (void)repositionExpandedInlineReadingCardInRect:(NSRect)viewport;
- (void)advanceExpandedReadingState;
- (void)closeExpandedInlineReadingCard;
- (void)hideOtherInlinePanelsForExpandedReading:(NSPanel *)expandedPanel;
- (NSArray<NSPanel *> *)inlinePanelsPresentInCurrentLayout;
- (NSArray<NSPanel *> *)allInlineOverlayPanels;
- (void)restoreOtherInlinePanelsAfterExpandedReading;
- (void)openInlineLearningForBlockText:(NSString *)source translation:(NSString *)translation;
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot;
- (void)bindInlineStudyChatToSource:(NSString *)source translation:(NSString *)translation;
- (void)returnFromStudyChatToInlineLearning:(id)sender;
- (NSScrollView *)quickSentenceScrollView;
- (void)captureQuickSentenceScrollPosition;
- (void)restoreQuickSentenceScrollPosition;
- (void)updateInlineReturnButtonVisibility;
- (NSRect)appKitFrameForOCRItem:(OCRTextItem *)item inWindowFrame:(NSRect)windowFrame;
- (NSInteger)captionThemeIndex;
- (NSColor *)captionBackgroundColorWithAlpha:(CGFloat)alpha;
- (NSColor *)captionThemeTextColor;
- (NSColor *)captionTextColor;
- (NSColor *)captionSecondaryTextColor;
- (NSColor *)captionBorderColor;
- (FYInlineOCRFrameStabilizer *)inlineFrameStabilizer;
- (FYInlineGrouper *)inlineGrouper;
- (FYInlineLayoutEngine *)inlineLayoutEngine;
- (void)applyBatchAppearanceToLayoutEngine;
- (CGFloat)inlinePanelFillAlpha;
- (NSColor *)inlinePanelFillColor;
- (void)refreshInlinePanelAppearance;
- (void)applyInlineTextColor:(NSColor *)color toView:(NSView *)view;
- (void)refreshInlinePanelTextAppearance;
- (NSColor *)inlinePanelBorderColor;
- (NSColor *)inlinePanelTextColor;
- (NSColor *)inlinePanelTitleColor;
- (NSFont *)inlinePanelFontOfSize:(CGFloat)size;
- (NSFont *)inlinePanelFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
- (InlinePanelLayout)inlinePanelLayoutForTranslation:(NSString *)translation
                                          sourceText:(NSString *)sourceText
                                         sourceFrame:(NSRect)sourceFrame
                                         windowFrame:(NSRect)windowFrame;
- (InlinePanelLayout)inlinePanelLayoutForTranslation:(NSString *)translation
                                          sourceText:(NSString *)sourceText
                                         sourceFrame:(NSRect)sourceFrame
                                         windowFrame:(NSRect)windowFrame
                                       placedFrames:(NSArray<NSValue *> *)placedFrames
                                       hugTextWidth:(BOOL)hugTextWidth;
- (NSAttributedString *)inlinePanelAttributedText:(NSString *)translation font:(NSFont *)font;
- (void)applyInlineChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius;
- (void)applyInlineCompactEntryChromeToContent:(NSView *)content cornerRadius:(CGFloat)cornerRadius;
- (NSTextField *)inlineCompactEntryLabel:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame;
- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)sourceText sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout;
- (BOOL)livePreviewVisible;
- (void)refreshPreviewVisibility:(id)sender;
- (void)windowDidChangeOcclusionState:(NSNotification *)notification;
- (void)windowDidMiniaturize:(NSNotification *)notification;
- (void)windowDidDeminiaturize:(NSNotification *)notification;
- (void)invalidatePreviewResults;
- (void)restartPreviewTimerIfRunning;
- (void)previewTimerFired:(NSTimer *)timer;
- (void)applyPreviewImage:(CGImageRef)image;
- (BOOL)hasScreenAccess;
- (BOOL)hasUsableScreenCaptureAccess;
- (BOOL)canCaptureSelectedWindowOnce;
- (void)handleMissingScreenAccessForStart;
- (NSURL *)preferredBundleURLForRelaunch;
- (uint32_t)selectedWindowID;
- (WindowItem *)windowItemForWindowID:(uint32_t)windowID;
- (WindowItem *)selectedWindowItem;
- (BOOL)liveBoundsForWindowID:(uint32_t)windowID outBounds:(CGRect *)outBounds;
- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                           ambiguous:(BOOL *)outAmbiguous
                                                note:(NSString **)outNote;
- (uint32_t)displayTargetWindowID;
- (WindowItem *)displayTargetWindowItem;
- (WindowItem *)windowItemForResolvedTargetID:(uint32_t)windowID;
- (NSScreen *)screenForWindowItem:(WindowItem *)item;
- (NSRect)appKitFrameForWindowItem:(WindowItem *)item;
- (BOOL)buildCaptureGridsWithFrame:(double **)outTempl templateW:(size_t *)outTW templateH:(size_t *)outTH
                             scene:(double **)outScene sceneW:(size_t *)outWW sceneH:(size_t *)outWH
                       videoAspect:(CGFloat *)outAspect
                        sceneWidth:(size_t)sceneWidth
                         forWindow:(WindowItem *)window
                            reason:(NSString **)outReason;
- (BOOL)autoDetectCaptureCardVideoRectForWindow:(WindowItem *)window reason:(NSString **)outReason;
- (void)resetInlineLayoutCacheAfterMappingChange;
- (double)captureCardMappingScoreForWindow:(WindowItem *)window entry:(NSDictionary *)entry;
- (void)storeCaptureCardMapping:(NSRect)screenRect
                     windowFrame:(NSRect)windowFrame
                     videoAspect:(CGFloat)videoAspect
                        deviceID:(NSString *)deviceID
                          source:(NSString *)source
                      confidence:(CGFloat)confidence
                     forWindowID:(uint32_t)windowID;
- (void)calibrateCaptureCardVideoRect:(NSRect)screenRect
                          windowFrame:(NSRect)windowFrame
                          videoAspect:(CGFloat)videoAspect
                             deviceID:(NSString *)deviceID
                          forWindowID:(uint32_t)windowID;
- (void)clearCaptureCardCalibrationForWindowID:(uint32_t)windowID;
- (BOOL)captureCardHasCalibratedVideoRectForWindow:(WindowItem *)window;
- (NSString *)captureCardCalibrationSummaryForWindow:(WindowItem *)window;
- (BOOL)captureCardEstimatedDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect;
- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect;
- (BOOL)captureCardDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)outRect reason:(NSString **)outReason;
- (void)updateCaptureCalibrationStatus;
- (void)beginCaptureCardCalibration:(id)sender;
- (void)endCaptureCardCalibration;
- (void)finishCaptureCardCalibration:(NSRect)screenRect
                         windowFrame:(NSRect)windowFrame
                         videoAspect:(CGFloat)videoAspect
                            deviceID:(NSString *)deviceID
                          windowID:(uint32_t)windowID;
- (void)clearCaptureCardCalibration:(id)sender;
- (NSString *)inlineTargetUnavailableReasonWithFallback:(NSString *)fallback;
- (BOOL)inlinePlacementRect:(NSRect *)outRect reason:(NSString **)outReason;
- (void)showInlineMappingUnavailableNotice:(NSString *)reason;
- (CGRect)quartzRectFromSelectionRect:(CGRect)selectionRect panelFrame:(NSRect)panelFrame;
- (NSRect)appKitOCRPreviewFrameForWindowItem:(WindowItem *)item;
- (BOOL)updateOCRPreviewPanel;
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID;
- (CGImageRef)copyCapturedImageForWindow:(uint32_t)windowID regionX:(double)x regionY:(double)y regionWidth:(double)width regionHeight:(double)height;
- (NSString *)recognizeEnlargedRegionOfImage:(CGImageRef)image
                                    regionX:(double)x
                                    regionY:(double)y
                                regionWidth:(double)width
                               regionHeight:(double)height
                                     fastOCR:(BOOL)fastOCR
                             languageSegment:(NSInteger)languageSegment
                                      blocks:(NSArray<OCRTextItem *> **)outBlocks
                                       error:(NSError **)error;
- (NSString *)recognizeTextBlocksInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error;
- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error;
- (void)translateText:(NSString *)text completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateDialogueText:(NSString *)text
                     identity:(FYRequestIdentity *)identity
                 systemPrompt:(NSString *)systemPrompt
                   completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateTextRealtime:(NSString *)text
                 systemPrompt:(NSString *)systemPrompt
                    maxTokens:(NSInteger)maxTokens
                   completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateText:(NSString *)text
          systemPrompt:(NSString *)systemPrompt
             maxTokens:(NSInteger)maxTokens
         modelOverride:(NSString *)modelOverride
            completion:(void (^)(NSString *translated, NSError *error))completion;
- (void)translateText:(NSString *)text systemPrompt:(NSString *)systemPrompt maxTokens:(NSInteger)maxTokens
        modelOverride:(NSString *)modelOverride longText:(BOOL)longText serviceTest:(BOOL)serviceTest
        completion:(void (^)(NSString *, NSError *))completion;
- (NSURL *)chatCompletionsURL;
- (NSString *)systemPrompt;
- (BOOL)autoContentModeEnabled;
- (NSTimeInterval)translationAttemptThrottleForMode:(NSInteger)modeSegment;
- (NSArray<OCRTextItem *> *)blocksInsideModalIfPresent:(NSArray<OCRTextItem *> *)blocks
                                              inImage:(CGImageRef)image
                                    normalizedExclusions:(NSArray<NSValue *> *)exclusionValues;
- (NSInteger)effectiveModeSegment;
- (NSInteger)stableContentModeForBlocks:(NSArray<OCRTextItem *> *)blocks;
- (NSString *)systemPromptForMode:(NSInteger)modeSegment;
- (FYInlineTranslationCache *)inlineCache;
- (NSMutableDictionary *)inlineTranslationCache;
- (void)setInlineTranslationCache:(NSMutableDictionary<NSString *, NSString *> *)value;
- (FYContentRouter *)contentRouter;
- (FYContentModeStability *)modeStability;
- (NSInteger)detectedModeSegment;
- (void)setDetectedModeSegment:(NSInteger)value;
- (NSInteger)candidateModeSegment;
- (void)setCandidateModeSegment:(NSInteger)value;
- (NSInteger)candidateModeHits;
- (void)setCandidateModeHits:(NSInteger)value;
- (FYAutoLocateSchedule *)locateSchedule;
- (NSDate *)lastAutoLocateAttempt;
- (void)setLastAutoLocateAttempt:(NSDate *)value;
- (FYCaptureMappingCache *)mappingCache;
- (NSMutableDictionary *)captureCardVideoRects;
- (void)setCaptureCardVideoRects:(NSMutableDictionary<NSString *, NSDictionary *> *)value;
- (FYMappingValidationSchedule *)validationSchedule;
- (NSDate *)lastMappingValidationDate;
- (void)setLastMappingValidationDate:(NSDate *)value;
- (FYTranslationRunState *)translationState;
- (NSDate *)translationProcessingDate;
- (NSString *)lastTranslatedNormalizedText;
- (void)setLastTranslatedNormalizedText:(NSString *)value;
- (NSString *)lastSubmittedNormalizedText;
- (void)setLastSubmittedNormalizedText:(NSString *)value;
- (NSDate *)lastTranslationAttemptDate;
- (void)setLastTranslationAttemptDate:(NSDate *)value;
- (NSTimeInterval)recognitionPollingInterval;
- (void)restartTimerIfRunning;
- (FYOCRStabilityOwner *)stabilityOwner;
- (NSString *)stableCandidate;
- (void)setStableCandidate:(NSString *)value;
- (NSInteger)stableCandidateCount;
- (void)setStableCandidateCount:(NSInteger)value;
- (BOOL)isStableText:(NSString *)normalized;
- (BOOL)shouldAcceptInlineOCRCorrection:(NSString *)text comparedTo:(NSString *)rendered;
- (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous;
- (NSString *)displayableTranslation:(NSString *)translated sourceText:(NSString *)sourceText;
- (void)setStatus:(NSString *)status;
- (void)updateRunState;
- (void)updateTranslationCount;
- (void)showPreviewUnavailable:(NSString *)message;
- (void)updatePreviewFromImage:(CGImageRef)image generation:(NSInteger)generation;
- (void)showError:(NSString *)error;
- (void)updateCurrentWindowLabel;
- (void)clampRegionSliders;
- (void)updateCaptionWindowWithText:(NSString *)text status:(NSString *)status;
- (void)setCaptionDisplayText:(NSString *)text;
- (void)updateCaptionAppearance;
- (void)resizeCaptionWindowForText:(NSString *)text;
- (NSView *)makeAppearancePage;
- (void)styleAppearanceSlider:(NSSlider *)slider;
- (NSView *)appearanceSliderRow:(NSString *)title slider:(NSSlider *)slider;
- (NSView *)subtitleAppearanceEditor:(BOOL)inlineMode;
- (void)toggleSubtitleDimensions:(NSButton *)sender;
- (void)selectAppearanceMode:(id)sender;
- (void)selectBatchSwatch:(NSButton *)sender;
- (void)resetBatchTextColor:(id)sender;
- (NSInteger)inlineThemeIndex;
- (NSColor *)inlineThemeTextColor;
- (void)updateSubtitleAppearancePage;
- (NSDictionary *)subtitleAppearanceSettings;
- (void)loadSubtitleAppearanceSettings:(NSDictionary *)settings;
- (NSView *)workspaceSection:(NSStackView *)stack;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (NSTextField *)chipLabel:(NSString *)text;
- (void)setChip:(NSTextField *)chip active:(BOOL)active;
- (void)refreshLiveChips;
- (NSView *)grammarInfoCellWithLabel:(NSString *)labelText value:(NSString *)valueText;
- (void)selectGrammarTab:(NSButton *)sender;
- (void)applyGrammarTabSelection;
- (NSView *)makeHistoryPage;
- (NSView *)makeIntegratedGrammarCard;
- (void)toggleGrammarFollowup:(id)sender;
- (void)askGrammarTone:(id)sender;
- (void)askGrammarQuestion:(id)sender;
- (void)requestGrammarQuestion:(NSString *)question;
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
- (void)ensureStudyChatSession;
- (FYStudyChatView *)makeStudyChatViewForOverlay:(BOOL)overlay;
- (void)referenceLatestStudySentence:(id)sender;
- (void)resolveLatestStudyIdentity:(void (^)(FYRequestIdentity *))completion;
- (void)resolveLatestStudySentence:(void (^)(NSString *,NSString *))completion;
- (void)captureLatestStudySentenceWithCompletion:(void (^)(NSString *,NSError *))completion;
- (void)askQuickSentence:(id)sender;
- (void)refreshStudyChatViews;
- (void)sendStudyChat:(NSString *)text;
- (void)toggleMainStudyChat:(id)sender;
- (void)updateMainChatForWindowWidth;
- (void)updateMainChatToggle;
- (void)configureStudyOverlay:(NSPanel *)panel;
- (void)showStudyChatOverlay:(id)sender;
- (void)closeStudyOverlay:(id)sender;
- (void)cancelQuickSentenceAnalysis;
- (void)analyzeQuickSentence:(id)sender;
- (void)showQuickSentence:(id)sender;
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick;
- (void)selectMainStructure:(NSButton *)sender;
- (void)selectQuickStructure:(NSButton *)sender;
- (BOOL)quickSentenceIsBookmarked;
- (void)refreshSavedSentences;
- (FYRequestIdentity *)savedSentenceForButton:(NSButton *)sender;
- (void)openSavedSentence:(NSButton *)sender;
- (void)removeSavedSentence:(NSButton *)sender;
- (void)bookmarkQuickSentence:(id)sender;
- (FYGrammarBookmark *)quickGrammarBookmark;
- (void)updateQuickGrammarBookmark;
- (void)bookmarkQuickGrammar:(id)sender;
- (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item;
- (void)selectQuickGrammar:(NSButton *)sender;
- (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color;
- (NSView *)quickReadingCard:(NSStackView *)stack tinted:(BOOL)tinted;
- (void)renderQuickSentence;
- (void)openStudyWorkspace:(id)sender;
- (void)toggleCaptionCollapsed:(id)sender;
- (void)createCaptionDock;
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick;
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick;
- (void)updateGrammarActionControlsForQuick:(BOOL)quick;
- (void)refreshQuickGrammarActionDetail;
- (void)toggleGrammarExplanation:(NSButton *)sender;
- (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates;
- (void)reviewGrammarSentence:(NSButton *)sender;
- (NSArray<NSDictionary *> *)diagnosticWindowInfos;
- (BOOL)diagnosticQuickTimeRunning;
- (NSDictionary *)runtimeDiagnosticSnapshot;
- (NSArray<NSDictionary *> *)updateRuntimeDiagnostics;
- (void)runRuntimeDiagnostics:(id)sender;
- (NSView *)diagnosticControls;
- (void)exportRuntimeDiagnostics:(id)sender;
- (void)emailRuntimeDiagnostics:(id)sender;
- (NSSharingService *)newDiagnosticMailService;
- (void)showDiagnosticMailFallback;
- (void)composeDiagnosticEmailForURL:(NSURL *)url;
- (void)sharingService:(NSSharingService *)service didFailToShareItems:(NSArray *)items error:(NSError *)error;
- (void)sharingService:(NSSharingService *)service didShareItems:(NSArray *)items;
- (void)saveRuntimeDiagnosticsForEmail:(BOOL)email;
@end

// The host conforms after its legacy property declarations, avoiding extension redeclarations.
@interface AppDelegate (FYPresentationHost) <FYMainWindowControllerHost, FYCollectionControllerHost, FYGrammarPresentationControllerHost, FYStudyPresentationControllerHost, FYReferencePresentationControllerHost, FYSubtitlePresenterHost, FYInlineOverlayControllerHost, FYTranslationRuntimeControllerHost, FYCaptureRuntimeControllerHost>
@end
#pragma clang diagnostic pop
