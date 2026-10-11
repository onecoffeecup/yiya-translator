#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class OCRTextItem;
@class FYOCRStabilityOwner;

typedef NS_ENUM(NSInteger, FYContentMode) {
    FYContentModeDialogue = 0,
    FYContentModeUI = 1,
};

// Per-run mode evidence. Kept public for existing replay/state adapters.
@interface FYContentModeStability : NSObject
@property(nonatomic) NSInteger detectedMode;
@property(nonatomic) NSInteger candidateMode;
@property(nonatomic) NSInteger candidateHits;
- (NSInteger)observeMode:(NSInteger)detected;
@end

@interface FYContentModeDecision : NSObject
@property(nonatomic, readonly) NSInteger mode;
@property(nonatomic, copy, readonly) NSString *reason;
@end

typedef NS_ENUM(NSInteger, FYContentTextFilterReason) {
    FYContentTextKeep = 0,
    FYContentTextEmpty,
    FYContentTextPunctuationOnly,
    FYContentTextDialogueControl,
    FYContentTextShortUIFragment,
    FYContentTextDecoration,
    FYContentTextDateOrNumber,
    FYContentTextCorner,
};
typedef void (^FYContentTextFilterObserver)(NSString *text, CGRect box, FYContentTextFilterReason reason);
typedef NSString *(^FYContentComparisonKey)(NSString *text);

// A dialogue frame can contain both routes. Arrays retain source item identities.
// Empty dialogue selection preserves the existing full-frame text fallback.
@interface FYContentRoute : NSObject
@property(nonatomic, copy, readonly) NSArray<OCRTextItem *> *bandItems;
@property(nonatomic, copy, readonly) NSArray<OCRTextItem *> *dialogueItems;
@property(nonatomic, copy, readonly) NSArray<OCRTextItem *> *optionItems;
@property(nonatomic, copy, readonly) NSString *dialogueText;
@property(nonatomic, readonly) BOOL speakerLabelOnly;
@property(nonatomic, readonly) BOOL usedFullFrameFallback;
@property(nonatomic, copy, readonly) NSString *reason;
@end

// Content policy only: no capture, Vision request, windows, cache, HTTP or keys.
// The caller preserves pipeline ordering, observes on one serial context and
// supplies explicit language/mapping/interaction state. Classification still
// precedes text filtering; extraction does not change the UI-first policy.
@interface FYContentRouter : NSObject
@property(nonatomic, strong, readonly) FYContentModeStability *modeStability;
@property(nonatomic, strong, readonly) FYContentModeDecision *lastModeDecision;
- (NSInteger)observeModeForItems:(NSArray<OCRTextItem *> *)items locked:(BOOL)locked;

+ (FYContentModeDecision *)modeDecisionForItems:(NSArray<OCRTextItem *> *)items fallback:(NSInteger)fallback;
+ (NSInteger)contentModeForItems:(NSArray<OCRTextItem *> *)items fallback:(NSInteger)fallback;
+ (FYContentRoute *)dialogueRouteForItems:(NSArray<OCRTextItem *> *)items
                  optionsCanPasteInline:(BOOL)optionsCanPasteInline
                         filterObserver:(FYContentTextFilterObserver)observer;
+ (NSString *)dialogueTextFromItems:(NSArray<OCRTextItem *> *)items
                  speakerLabelOnly:(BOOL *)speakerLabelOnly
                    filterObserver:(FYContentTextFilterObserver)observer;
+ (BOOL)isExcludedSpeakerLabelItem:(OCRTextItem *)item;
+ (FYContentTextFilterReason)filterReasonForText:(NSString *)text normalized:(NSString *)normalized
                                  boundingBox:(CGRect)box strict:(BOOL)strict;
+ (FYContentTextFilterReason)filterReasonForText:(NSString *)text normalized:(NSString *)normalized
                                  boundingBox:(CGRect)box strict:(BOOL)strict japanese:(BOOL)japanese;

+ (double)similarityRatio:(NSString *)left comparedTo:(NSString *)right;
// Reuse the learning model's comparison key through injection; no learning DB
// dependency or second implementation of dialogue identity normalization.
// Japanese comparison requires a nonnil key; the English path does not use it.
+ (BOOL)isSameSubtitleText:(NSString *)text comparedTo:(NSString *)previous
                     mode:(NSInteger)mode japanese:(BOOL)japanese comparisonKey:(FYContentComparisonKey)key;
+ (BOOL)isStableText:(NSString *)text owner:(FYOCRStabilityOwner *)owner
               mode:(NSInteger)mode japanese:(BOOL)japanese renderedText:(NSString *)rendered
      comparisonKey:(FYContentComparisonKey)key;
+ (NSTimeInterval)recognitionPollingIntervalForMode:(NSInteger)mode;
+ (NSTimeInterval)translationAttemptThrottleForMode:(NSInteger)mode;

+ (BOOL)looksLikeSpeakerName:(NSString *)text;
+ (BOOL)looksLikeSpeakerFurigana:(NSString *)text;
+ (BOOL)looksLikeSpeakerLabelCluster:(NSArray<OCRTextItem *> *)cluster;
+ (BOOL)isSpeakerLabelItem:(OCRTextItem *)item inPool:(NSArray<OCRTextItem *> *)pool;
+ (BOOL)dialogueFrameIsSpeakerLabelOnly:(NSArray<NSString *> *)lines;
+ (void)splitDialogueAndOptions:(NSArray<OCRTextItem *> *)band
                     allBlocks:(NSArray<OCRTextItem *> *)allBlocks
                      dialogue:(NSMutableArray<OCRTextItem *> *)outDialogue
                       options:(NSMutableArray<OCRTextItem *> *)outOptions;
+ (BOOL)containsJapaneseKana:(NSString *)text;
+ (BOOL)isFormedTextLine:(OCRTextItem *)block;
+ (BOOL)isShortDialogueAnchor:(OCRTextItem *)block;
+ (BOOL)isUnpunctuatedSingleLineDialogue:(NSString *)text box:(CGRect)box;
+ (BOOL)isCornerHelpButton:(OCRTextItem *)block;
+ (BOOL)isSingleLineDialogue:(OCRTextItem *)block;
+ (BOOL)isDialogueAnchor:(OCRTextItem *)block;
+ (NSArray<OCRTextItem *> *)subtitleBandItems:(NSArray<OCRTextItem *> *)blocks;
+ (BOOL)textHitsUIToken:(NSString *)text;
+ (NSUInteger)UITokenHitCount:(NSArray<OCRTextItem *> *)blocks;
+ (BOOL)isFurigana:(OCRTextItem *)small nearLargerLineInItems:(NSArray<OCRTextItem *> *)blocks;
+ (BOOL)looksLikeUIFrame:(NSArray<OCRTextItem *> *)blocks;
+ (NSString *)dialogueTextWithoutTrailingButton:(NSString *)text;
@end
