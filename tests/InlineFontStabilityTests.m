#import <Cocoa/Cocoa.h>
#import "FYInlineLayout.h"

static NSUInteger failures = 0;
static void Check(BOOL ok, NSString *message) {
    if (!ok) { failures++; NSLog(@"FAIL %@", message); }
}
static FYInlineLayoutRequest *Request(NSString *text, NSString *translation, CGRect frame, BOOL paragraph) {
    FYInlineTextBlock *block = [FYInlineTextBlock new];
    block.text = text;
    block.lineTexts = [text componentsSeparatedByString:@"\n"];
    block.lineBoxes = @[[NSValue valueWithRect:frame]];
    block.boundingBox = frame;
    block.kind = paragraph ? FYInlineBlockKindLong : FYInlineBlockKindShort;
    block.blockID = [FYInlineBlockMatcher blockIDForText:text lineBoxes:block.lineBoxes];
    return [FYInlineLayoutRequest requestWithBlock:block translation:translation sourceFrame:frame];
}
// A paragraph between two source regions: OCR bounds near a wrapping threshold.
// Empty translations still reserve those regions, without creating unrelated panels.
static NSArray *Scene(CGFloat gap) {
    return @[
        Request(@"◆桜井琉夏の好み◆\n校内でスリリングなことばかりしている彼は、アクティブな遊びが好きみたい。",
                @"樱井琉夏的喜好。他似乎很喜欢刺激的活动，在校内总是做些惊险的事情。",
                CGRectMake(80, 80, 200, gap - 30), YES),
        Request(@"上部菜单", @"", CGRectMake(0, 65 + gap, 400, 335 - gap), NO),
        Request(@"下部菜单", @"", CGRectMake(0, 0, 400, 65), NO)
    ];
}
int main(void) { @autoreleasepool {
    fprintf(stderr,"FONT_PROBE before default engine\n");
    CGRect viewport = CGRectMake(0, 0, 400, 400);
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    fprintf(stderr,"FONT_PROBE before first layout\n");
    FYInlineLayoutResult *result = [engine layoutRequests:Scene(150) viewport:viewport previous:nil];
    fprintf(stderr,"FONT_PROBE after first layout\n");
    FYInlinePlacement *body = result.placements.firstObject;
    Check(body.mode == FYInlineDisplayModeFullCard && body.font.pointSize == 17,
          @"fixture starts with readable 17pt paragraph after fitting the crowded scene");
    NSString *identity = body.blockID;
    for (NSUInteger index = 0; index < 20; index++) {
        result = [engine layoutRequests:Scene(index % 2 ? 150 : 170) viewport:viewport previous:result];
        body = result.placements.firstObject;
        Check([identity isEqualToString:body.blockID], @"OCR geometry changes preserve paragraph identity");
        Check(body.mode == FYInlineDisplayModeFullCard && body.font.pointSize == 17,
              @"automatic reflow keeps the visible paragraph font instead of retrying 19pt");
    }
    result = [engine layoutRequests:Scene(100) viewport:viewport previous:result];
    Check(((FYInlinePlacement *)result.placements.firstObject).mode == FYInlineDisplayModeCompactEntry,
          @"temporary loss of space folds the paragraph instead of shrinking its font");
    result = [engine layoutRequests:Scene(170) viewport:viewport previous:result];
    Check(((FYInlinePlacement *)result.placements.firstObject).font.pointSize == 17,
          @"restoring space retains the reading font through a folded frame");

    engine.longBodyFontSize = 21;
    engine.minimumLongBodyFontSize = 17;
    NSArray *openScene = @[Request(@"◆桜井琉夏の好み◆\n校内でスリリングなことばかりしている彼は、アクティブな遊びが好きみたい。",
        @"樱井琉夏的喜好。他似乎很喜欢刺激的活动，在校内总是做些惊险的事情。",
        CGRectMake(80, 80, 200, 250), YES)];
    result = [engine layoutRequests:openScene viewport:viewport previous:result];
    Check(((FYInlinePlacement *)result.placements.firstObject).font.pointSize == 21,
          @"an explicit font setting change starts a new font choice immediately");
    FYInlineLayoutResult *fresh = [[FYInlineLayoutEngine defaultEngine] layoutRequests:Scene(170) viewport:viewport previous:nil];
    Check(((FYInlinePlacement *)fresh.placements.firstObject).font.pointSize == 19,
          @"a fresh scene does not inherit the previous paragraph's smaller font");
    NSLog(@"InlineFontStabilityTests: %lu failures", (unsigned long)failures);
    return failures ? 1 : 0;
} }
