#pragma once
#import "FYOCRTextModels.h"

// Per-capture-context, serial OCR owner. Only one-to-one line replacements are
// compared across consecutive frames; new/multiline refinement remains intact.
@interface FYOCRRefinementStabilizer : NSObject
@property(nonatomic, readonly) NSUInteger fallbackCount;
- (NSArray<OCRTextItem *> *)observeCoarseItems:(NSArray<OCRTextItem *> *)coarse
                                refinedItems:(NSArray<OCRTextItem *> *)refined;
- (void)reset;
@end
// Synchronous recognition only when region is eligible; rejected output leaves caller slots untouched.
FOUNDATION_EXPORT BOOL FYRecognizeOCRRefinement(NSArray<OCRTextItem *> *coarse, BOOL autoFit,
    NSString *(^recognizer)(CGRect region, NSArray<OCRTextItem *> **blocks, NSError **error),
    NSString **outText, NSArray<OCRTextItem *> **outBlocks);
// Accepted observer runs before merging; rejection leaves output slots untouched.
FOUNDATION_EXPORT BOOL FYApplyOCRRefinement(NSArray<OCRTextItem *> *coarse, BOOL autoFit,
    NSString *(^recognizer)(CGRect region, NSArray<OCRTextItem *> **blocks, NSError **error),
    void (^acceptedObserver)(void), NSString **outText, NSArray<OCRTextItem *> **outBlocks);
FOUNDATION_EXPORT BOOL FYApplyOCRRefinementWithStabilizer(NSArray<OCRTextItem *> *coarse, BOOL autoFit,
    NSString *(^recognizer)(CGRect region, NSArray<OCRTextItem *> **blocks, NSError **error),
    void (^acceptedObserver)(void), FYOCRRefinementStabilizer *stabilizer,
    NSString **outText, NSArray<OCRTextItem *> **outBlocks);
FOUNDATION_EXPORT CGFloat FYOCRFittedTextArea(NSArray<OCRTextItem *> *blocks);
// Output changes only when a second-pass region is applicable.
FOUNDATION_EXPORT BOOL FYOCRRefinementRegion(NSArray<OCRTextItem *> *blocks, BOOL autoFit, CGFloat fittedArea, CGRect *outRegion);


// Pure pass selection and overlap resolution; preserves original items/metadata.
@interface FYOCRRefinement : NSObject
+ (NSArray<OCRTextItem *> *)resolveOverlappingItems:(NSArray<OCRTextItem *> *)items;
+ (NSArray<OCRTextItem *> *)mergeCoarseItems:(NSArray<OCRTextItem *> *)coarse refinedItems:(NSArray<OCRTextItem *> *)refined;
@end
