#pragma once
#import "FYOCRTextModels.h"

// Keeps UI OCR content and its geometry tied to the same on-screen regions
// across frames. Transient missing/merged/misread observations do not replace
// a confirmed block; sustained edits and page changes do.
@interface FYInlineOCRFrameStabilizer : NSObject
@property(nonatomic, readonly) BOOL ready;
- (NSArray<OCRTextItem *> *)observeItems:(NSArray<OCRTextItem *> *)items;
- (void)reset;
@end
