#import "FYOCRTextModels.h"
#import <math.h>

@implementation OCRTextItem
@end

NSString *FYNormalizeOCRTextForComparison(NSString *value) {
    if (!value) { return @""; }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableString *result = [NSMutableString stringWithCapacity:trimmed.length];
    NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        unichar character = [trimmed characterAtIndex:index];
        if (character == 0x3000 || [spaces characterIsMember:character]) { continue; }
        [result appendFormat:@"%C", character];
    }
    return result;
}

BOOL FYContainsJapaneseKana(NSString *value) {
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if ((character >= 0x3040 && character <= 0x30ff) || (character >= 0x31f0 && character <= 0x31ff)) {
            return YES;
        }
    }
    return NO;
}

NSComparisonResult FYOCRReadingOrder(OCRTextItem *left, OCRTextItem *right) {
    CGFloat delta = CGRectGetMaxY(left.boundingBox) - CGRectGetMaxY(right.boundingBox);
    if (fabs(delta) > 0.025) { return delta > 0 ? NSOrderedAscending : NSOrderedDescending; }
    if (left.boundingBox.origin.x < right.boundingBox.origin.x) { return NSOrderedAscending; }
    if (left.boundingBox.origin.x > right.boundingBox.origin.x) { return NSOrderedDescending; }
    return NSOrderedSame;
}

OCRTextItem *FYCopyInlineOCRItem(OCRTextItem *source) {
    OCRTextItem *copy = [OCRTextItem new];
    copy.text = source.text ?: @"";
    copy.boundingBox = source.boundingBox;
    copy.lastLineBox = source.lastLineBox;
    copy.lineTexts = source.lineTexts;
    copy.lineBoxes = source.lineBoxes;
    copy.lineCount = source.lineCount;
    copy.blockKind = source.blockKind;
    copy.confidence = source.confidence;
    copy.groupingConfidence = source.groupingConfidence;
    copy.sourceBlockID = source.sourceBlockID;
    copy.speakerLabel = source.speakerLabel;
    return copy;
}
