#pragma once
#import "FYOCRTextModels.h"
#import "FYDialogueStability.h"

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

// Synchronous stateless policy. Categories below are separate algorithm units;
// subclasses retain the same self/helper dispatch as the original facade.
@interface FYContentPolicy : NSObject
@end
@interface FYContentPolicy (ContentPolicy)
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

+ (BOOL)isWrappedDialogueBand:(NSArray<OCRTextItem *> *)band;
+ (NSArray<OCRTextItem *> *)separatedDialogueItemsInItems:(NSArray<OCRTextItem *> *)items;
@end
