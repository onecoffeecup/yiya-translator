#import "LearningAppTestSupport.h"

static void Expect(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL %@", message); exit(1); }
}
static OCRTextItem *ModalItem(NSString *text, CGRect rect) {
    OCRTextItem *item = [OCRTextItem new]; item.text = text; item.boundingBox = rect;
    item.lineTexts = @[text]; item.lineBoxes = @[[NSValue valueWithRect:rect]];
    item.lineCount = 1; item.confidence = 1;
    return item;
}
static CGImageRef ModalImage(CGRect panel) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:480 pixelsHigh:270 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    for (NSUInteger y = 0; y < 270; y++) for (NSUInteger x = 0; x < 480; x++) {
        BOOL inside = CGRectContainsPoint(panel, CGPointMake(x / 480.0, 1 - y / 270.0));
        unsigned char *p = bitmap.bitmapData + y * bitmap.bytesPerRow + x * 4;
        p[0] = p[1] = p[2] = inside ? 240 : 140; p[3] = 255;
    }
    return CGImageRetain(bitmap.CGImage);
}

// Exercise production visibility refresh without displaying windows or taking focus.
@interface ModalFakePanel : NSPanel
@property BOOL pretendVisible;
@end
@implementation ModalFakePanel
- (BOOL)isVisible { return self.pretendVisible; }
- (void)orderFrontRegardless { self.pretendVisible = YES; }
- (void)orderOut:(id)sender { self.pretendVisible = NO; }
- (void)close { self.pretendVisible = NO; }
@end
@interface ModalTestApp : AppDelegate
@property BOOL targetActive;
@end
@implementation ModalTestApp
- (BOOL)translationTargetIsForeground { return self.targetActive; }
- (pid_t)selectedWindowOwnerPID { return 0; }
@end

int main(int argc, const char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    ModalTestApp *app = [ModalTestApp new];
    NSArray *items = @[
        ModalItem(@"はばたきNEW", CGRectMake(.07,.62,.13,.036)),
        ModalItem(@"KCH交響楽団", CGRectMake(.41,.76,.18,.05)),
        ModalItem(@"4月1日～4月30日", CGRectMake(.56,.70,.18,.035)),
        ModalItem(@"地域密着型の交響楽団。", CGRectMake(.34,.24,.31,.42)),
        ModalItem(@"閉じる", CGRectMake(.47,.16,.06,.038)),
        ModalItem(@"04/12（日）", CGRectMake(.83,.88,.09,.035)),
        ModalItem(@"ルームへ", CGRectMake(.03,.08,.10,.04))];
    CGImageRef image = ModalImage(CGRectMake(.20,.12,.60,.76));
    NSArray *scoped = [app blocksInsideModalIfPresent:items inImage:image normalizedExclusions:@[]];
    Expect([scoped isEqual:[items subarrayWithRange:NSMakeRange(1,4)]],
           @"popup retains heading, date, body and close; removes all background labels");
    NSMutableArray *noClose = [items mutableCopy]; [noClose removeObjectAtIndex:4];
    Expect([app blocksInsideModalIfPresent:noClose inImage:image normalizedExclusions:@[]] == noClose,
           @"centered bright mail/photo page without dismiss control is unchanged");
    Expect([app blocksInsideModalIfPresent:items inImage:NULL normalizedExclusions:@[]] == items,
           @"missing image passes through");
    Expect([app blocksInsideModalIfPresent:items inImage:image normalizedExclusions:@[[NSValue valueWithRect:[items[4] boundingBox]]]] == items,
           @"own translated close cannot manufacture a modal");
    NSMutableArray *cornerClose = [noClose mutableCopy];
    [cornerClose addObject:ModalItem(@"閉じる",CGRectMake(.88,.03,.06,.035))];
    Expect([app blocksInsideModalIfPresent:cornerClose inImage:image normalizedExclusions:@[]] == cornerClose,
           @"close outside the panel cannot crop a normal page");
    CGImageRelease(image);
    image = ModalImage(CGRectMake(.15,.33,.41,.34));
    Expect([app blocksInsideModalIfPresent:items inImage:image normalizedExclusions:@[]] == items,
           @"offcenter room photo does not crop page");
    CGImageRelease(image);
    CGRect upperPanel = CGRectMake(.3,.62,.4,.25);
    image = ModalImage(upperPanel);
    FYOCRPixelBuffer pixels = FYCreateOCRPixelBuffer(image);
    Expect(FYOCRModalSurroundingsAreDimmer(pixels.pixels,pixels.width,pixels.height,pixels.bytesPerRow,upperPanel),
           @"pixel brightness uses Vision bottom-left coordinates for an asymmetric panel");
    Expect(!FYOCRModalSurroundingsAreDimmer(pixels.pixels,pixels.width,pixels.height,pixels.bytesPerRow,CGRectMake(.3,.13,.4,.25)),
           @"mirrored empty region is not bright modal content");
    FYReleaseOCRPixelBuffer(&pixels); CGImageRelease(image);

    // Raw soft lines reproduce the mismatch: layout and actual AppKit document must agree.
    NSString *raw = @"拥有压倒性知名度与实力的扎根当地的交响乐团。\n为振兴音乐文化，\n在县内各市举办巡回音乐会、\n为中小学生举办音乐鉴赏教室等，\n推出了贴近市民、\n亲切易懂的构成。";
    FYInlineTextBlock *block = [FYInlineTextBlock new]; block.blockID = @"body";
    block.text = @"地域密着型の交響楽団。"; block.kind = FYInlineBlockKindLong;
    block.boundingBox = CGRectMake(.34,.24,.31,.42);
    FYInlineLayoutEngine *engine = app.inlineLayoutEngine;
    FYInlineLayoutRequest *request = [FYInlineLayoutRequest requestWithBlock:block translation:raw sourceFrame:NSMakeRect(580,240,519,440)];
    NSRect viewport = NSMakeRect(0,0,1680,945);
    FYInlinePlacement *rawPlacement = [engine layoutRequests:@[request] viewport:viewport previous:nil].placements.firstObject;
    request.translation = FYInlineNormalizeTranslationParagraphs(raw);
    FYInlinePlacement *cleanPlacement = [engine layoutRequests:@[request] viewport:viewport previous:nil].placements.firstObject;
    Expect(fabs(NSHeight(rawPlacement.translationFrame)-NSHeight(cleanPlacement.translationFrame)) < .5,
           @"soft line breaks cannot inflate card height");
    FYInlineLongCardView *card = (id)[app inlineLongCardContentForTranslation:raw size:rawPlacement.translationFrame.size selected:NO compact:NO placement:rawPlacement];
    NSScrollView *scroll = nil;
    for (NSView *view in card.subviews) if ([view isKindOfClass:NSScrollView.class]) scroll=(id)view;
    Expect(scroll && fabs(NSHeight(scroll.documentView.frame) - NSHeight(scroll.contentView.bounds)) <= 2,
           @"actual AppKit document fills its viewport with no phantom blank rows");
    Expect(!rawPlacement.scrollable, @"short normalized paragraph is not classified as scrolling");
    NSString *paragraphs = @"第一段。\n\n第二段。";
    Expect([FYInlineNormalizeTranslationParagraphs(paragraphs) isEqual:paragraphs], @"intentional paragraph breaks preserved");
    NSArray *grouped = [app mergedInlineTextItemsFromItems:@[
        ModalItem(@"やすい構成を打ち出しています。",CGRectMake(.34,.23,.31,.057)),
        ModalItem(@"閉じる",CGRectMake(.47,.16,.06,.038))]];
    Expect(grouped.count == 2, @"close control must not become last word of the translated body");

    app.inlineTranslationPanels = [NSMutableArray array]; app.inlineLongCardPanels = [NSMutableArray array];
    ModalFakePanel *overflow = [[ModalFakePanel alloc] init];
    app.inlineOverflowPanel = overflow; app.inlineOverflowCount = 1; app.targetActive = YES;
    [app refreshOverlayVisibility:nil]; Expect(overflow.isVisible, @"real overflow appears");
    app.inlineOverflowCount = 0;
    [app refreshOverlayVisibility:nil]; Expect(!overflow.isVisible, @"timer cannot resurrect zero-count entry");
    app.inlineOverflowCount = 1;
    [app updateInlineOverflowEntryWithPlacements:@[] items:@{} viewport:viewport unplaceable:0];
    Expect(app.inlineOverflowPanel == overflow && app.inlineOverflowEmptySince > 0,
           @"one empty frame retains entry during the latest OCR grace period");
    app.inlineOverflowEmptySince = [NSDate timeIntervalSinceReferenceDate] - 2;
    [app refreshOverlayVisibility:nil];
    Expect(!app.inlineOverflowPanel && app.inlineOverflowCount == 0 && app.inlineOverflowEntries.count == 0,
           @"sustained resolved overflow discards old panel and state");
    for (NSUInteger i=0; i<3; i++) [app refreshOverlayVisibility:nil];
    Expect(!overflow.isVisible, @"empty entry stays absent across repeated timer ticks");
    NSString *fixture = NSProcessInfo.processInfo.environment[@"FY_MODAL_FIXTURE"];
    if (fixture.length) {
        NSImage *frame = [[NSImage alloc] initWithContentsOfFile:fixture];
        CGImageRef cg = [frame CGImageForProposedRect:NULL context:nil hints:nil];
        Expect(cg != NULL, @"local capture fixture loads");
        NSArray *recognized = [[FYOCRManager new] recognizeTextItemsInImage:cg fastOCR:NO languageSegment:0 error:NULL];
        NSArray *foreground = [app blocksInsideModalIfPresent:recognized inImage:cg normalizedExclusions:@[]];
        Expect(foreground.count >= 8 && foreground.count < recognized.count, @"real captured modal scopes content");
        for (OCRTextItem *item in foreground) {
            Expect(NSMinX(item.boundingBox) >= .20 && NSMaxX(item.boundingBox) <= .80,
                   @"real capture retains only text inside popup horizontal edges");
        }
        NSString *joined = [[foreground valueForKey:@"text"] componentsJoinedByString:@"\n"];
        Expect([joined containsString:@"KCH"] && [joined containsString:@"4月"] && [joined containsString:@"閉じる"],
               @"real popup heading, date and close survive");
        NSArray *groups = [app filteredInlineTextItems:[app mergedInlineTextItemsFromItems:foreground] strict:NO];
        NSMutableArray *requests = [NSMutableArray array];
        for (NSUInteger i=0; i<groups.count; i++) {
            OCRTextItem *item = groups[i];
            NSString *translated = [item.text containsString:@"KCH"] ? @"KCH交响乐团" :
                [item.text containsString:@"4月"] ? @"4月1日～4月30日" :
                [item.text isEqual:@"閉じる"] ? @"关闭" : raw;
            FYInlineTextBlock *b = [app inlineLayoutBlockForItem:item order:(NSInteger)i];
            [requests addObject:[FYInlineLayoutRequest requestWithBlock:b translation:translated
                sourceFrame:[app appKitFrameForOCRItem:item inWindowFrame:viewport]]];
        }
        FYInlineLayoutResult *fieldLayout = [engine layoutRequests:requests viewport:viewport previous:nil];
        for (FYInlinePlacement *placement in fieldLayout.placements) {
            Expect(placement.mode != FYInlineDisplayModeUnplaceable && !placement.compactEntry,
                   @"scoped popup has space for every translation, no overflow entry needed");
            NSLog(@"FIELD card %@ frame=%@", placement.translation, NSStringFromRect(placement.translationFrame));
        }
        NSLog(@"FIELD modal OCR %lu -> %lu lines; all background labels excluded", (unsigned long)recognized.count,(unsigned long)foreground.count);
    }
    NSLog(@"PASS ModalOverlayRegressionTests (modal evidence, native sizing, grouping, overflow lifecycle)");
} return 0; }
