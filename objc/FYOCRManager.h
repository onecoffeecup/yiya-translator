#import <Cocoa/Cocoa.h>
#import "FYContentRouter.h"

#import "ocr/FYOCRTextModels.h"
#import "ocr/FYOCRRefinement.h"
#import "ocr/FYOCRImageGeometry.h"
#import "ocr/FYOCRVisionEngine.h"
#import "ocr/FYDialogueStability.h"
#import "ocr/FYInlineOCRFrameStabilizer.h"
#import "ocr/FYOCRPixelAnalysis.h"
#import "ocr/FYOCRTextProcessing.h"

// Recognition and pure postprocessing; no UI, caches, credentials or capture devices.
// Dedup/exclusion preserve identity/metadata and do not mutate input arrays or items.
// Region remapping intentionally mutates only boundingBox/nonempty lastLineBox.
// resolve preserves surviving input order; merge sorts only when refinement is present.
@interface FYOCRManager : NSObject
@property(nonatomic, strong, readonly) FYOCRVisionEngine *visionEngine;
+ (NSArray<OCRTextItem *> *)itemsByMarkingSpeakerLabels:(NSArray<OCRTextItem *> *)items inImage:(CGImageRef)image;
// Require a centered bright panel, dim surround and an explicit dismiss control.
// Ambiguous images pass through unchanged; no capture or extra OCR is performed.
+ (NSArray<OCRTextItem *> *)items:(NSArray<OCRTextItem *> *)blocks
           scopedToModalInImage:(CGImageRef)image
                    exclusions:(NSArray<NSValue *> *)exclusionValues;
// Caller must qualify modal first; preserves legacy padding and <2-result fallback.
+ (NSArray<OCRTextItem *> *)items:(NSArray<OCRTextItem *> *)blocks
                  inModalRegion:(CGRect)modalRect
                     exclusions:(NSArray<NSValue *> *)exclusionValues;
// Compatibility content-policy API delegates to FYContentRouter.
// Existing mode values: dialogue=0, UI=1; empty/ambiguous fragments keep explicit fallback.
+ (NSInteger)contentModeForItems:(NSArray<OCRTextItem *> *)blocks fallback:(NSInteger)fallback;
+ (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString **)outSpeaker body:(NSString **)outBody;
+ (BOOL)looksLikeSpeakerName:(NSString *)text;
+ (BOOL)looksLikeSpeakerFurigana:(NSString *)text;
+ (BOOL)looksLikeSpeakerLabelCluster:(NSArray<OCRTextItem *> *)cluster;
+ (BOOL)isSpeakerLabelItem:(OCRTextItem *)item inPool:(NSArray<OCRTextItem *> *)pool;
+ (BOOL)dialogueFrameIsSpeakerLabelOnly:(NSArray<NSString *> *)lines;
// Appends to caller-owned arrays (including pre-existing entries); nil outputs allowed.
+ (void)splitDialogueAndOptions:(NSArray<OCRTextItem *> *)band
                     allBlocks:(NSArray<OCRTextItem *> *)allBlocks
                      dialogue:(NSMutableArray<OCRTextItem *> *)outDialogue
                       options:(NSMutableArray<OCRTextItem *> *)outOptions;
+ (BOOL)containsJapaneseKana:(NSString *)value;
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
// Explicit top-left normalized scope; full-frame returns recognizer output unchanged.
// Invalid/empty manual scope returns no items (never falls back to the full frame).
+ (NSArray<OCRTextItem *> *)recognizeImage:(CGImageRef)image topLeftScope:(CGRect)scope
    recognizer:(NSArray<OCRTextItem *> *(^)(CGImageRef cropped, NSError **error))recognizer
    error:(NSError **)error;
// Synchronous preparation/recognition/remap; injected recognizer retains caller filtering.
+ (NSString *)recognizeEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region
    recognizer:(NSString *(^)(CGImageRef scaled, NSArray<OCRTextItem *> **items, NSError **error))recognizer
    blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error;
// Vision bottom-left normalized region -> top-left pixel crop, 2x scale capped per axis.
// Caller owns returned image. Output crop changes only when preparation succeeds.
+ (CGImageRef)copyEnlargedImage:(CGImageRef)image
                visionRegion:(CGRect)region
                   pixelCrop:(CGRect *)outCrop CF_RETURNS_RETAINED;
+ (void)remapItems:(NSArray<OCRTextItem *> *)items
    fromPixelCrop:(CGRect)crop
        imageSize:(CGSize)imageSize;
// Clean source pixels: deduplicate overlapping OCR observations without excluding
// original text that happens to equal an already displayed translation.
+ (NSString *)sourceTextForItems:(NSArray<OCRTextItem *> *)items blocks:(NSArray<OCRTextItem *> **)outBlocks;
// Explicit rendered-text snapshots for callers whose image contains overlays.
+ (NSString *)postprocessedTextForItems:(NSArray<OCRTextItem *> *)items renderedTexts:(NSSet<NSString *> *)renderedTexts
    blocks:(NSArray<OCRTextItem *> **)outBlocks;
+ (BOOL)isOwnOverlayText:(NSString *)text;
+ (NSSet<NSString *> *)renderedTranslationSetForCaption:(NSString *)captionText
                                           inlineCache:(NSDictionary *)inlineCache;
+ (NSArray<OCRTextItem *> *)itemsExcludingOwnOverlay:(NSArray<OCRTextItem *> *)items
                                     renderedTexts:(NSSet<NSString *> *)renderedTexts;
+ (NSArray<OCRTextItem *> *)resolveOverlappingItems:(NSArray<OCRTextItem *> *)items;
+ (NSArray<OCRTextItem *> *)mergeCoarseItems:(NSArray<OCRTextItem *> *)coarse
                             refinedItems:(NSArray<OCRTextItem *> *)refined;
// Vision may return several visual lines in one observation; inline layout needs line-level boxes.
+ (NSArray<OCRTextItem *> *)splitMultilineItems:(NSArray<OCRTextItem *> *)items;
// String path deliberately retains one-character lines and Vision result order.
+ (NSString *)textFromRecognizedLines:(NSArray<NSString *> *)lines;
@property(nonatomic, copy) void (^configurationObserver)(BOOL fastOCR, NSInteger languageSegment, size_t width, size_t height, CGFloat minimumHeight);
- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image
                                           fastOCR:(BOOL)fastOCR
                                   languageSegment:(NSInteger)languageSegment
                                             error:(NSError **)error;
@end
