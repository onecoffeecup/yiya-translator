#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, InlineBlockKind) {
    InlineBlockKindShort = 0,
    InlineBlockKindLong = 1,
};

// OCR model shared by recognition, grouping and rendering. Coordinates are normalized.
@interface OCRTextItem : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic) CGRect boundingBox;
@property(nonatomic) CGRect lastLineBox;
@property(nonatomic, copy) NSArray<NSString *> *lineTexts;
@property(nonatomic, copy) NSArray<NSValue *> *lineBoxes;
@property(nonatomic) NSInteger lineCount;
@property(nonatomic) InlineBlockKind blockKind;
@property(nonatomic) CGFloat confidence;
@property(nonatomic) CGFloat groupingConfidence;
@property(nonatomic, copy) NSString *sourceBlockID;
// Positive source-pixel evidence of a separate filled speaker plate.
@property(nonatomic) BOOL speakerLabel;
@end

FOUNDATION_EXPORT NSString *FYNormalizeOCRTextForComparison(NSString *value);
FOUNDATION_EXPORT BOOL FYContainsJapaneseKana(NSString *value);
FOUNDATION_EXPORT NSComparisonResult FYOCRReadingOrder(OCRTextItem *left, OCRTextItem *right);
// Shared original metadata-preserving observation copy, including speaker evidence.
FOUNDATION_EXPORT OCRTextItem *FYCopyInlineOCRItem(OCRTextItem *source);
