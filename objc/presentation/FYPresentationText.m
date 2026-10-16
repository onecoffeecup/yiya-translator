#import "FYPresentationText.h"
#import "../ocr/FYOCRTextModels.h"

NSString *Trim(NSString *value) {
    if (!value) { return @""; }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

NSString *NormalizeForComparison(NSString *value) {
    return FYNormalizeOCRTextForComparison(value);
}

NSString *Shorten(NSString *value, NSUInteger limit) {
    NSString *trimmed = Trim(value);
    if (trimmed.length <= limit) { return trimmed; }
    return [[trimmed substringToIndex:limit] stringByAppendingString:@"..."];
}
