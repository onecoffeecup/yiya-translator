// Field count and unrelated grouping changes must not manufacture OCR disappearances.
// Optional private replay exercises the production pipeline without capture, network or credentials.
#import "LearningAppTestSupport.h"

static OCRTextItem *Field(NSString *text, CGRect box) {
    OCRTextItem *item = [OCRTextItem new];
    item.text = text; item.boundingBox = box; item.confidence = .95;
    item.lineTexts = @[text]; item.lineBoxes = @[[NSValue valueWithRect:box]];
    item.lineCount = 1; item.blockKind = InlineBlockKindShort;
    return item;
}
static OCRTextItem *Find(NSArray<OCRTextItem *> *items, NSString *text) {
    for (OCRTextItem *item in items) { if ([item.text isEqual:text]) { return item; } }
    return nil;
}
static void CheckDenseFields(void) {
    AppDelegate *app = [AppDelegate new];
    NSMutableArray *base = [NSMutableArray array];
    for (NSUInteger index = 0; index < 32; index++) {
        [base addObject:Field([NSString stringWithFormat:@"項目%lu", (unsigned long)index],
                             CGRectMake(.15 + (index % 4) * .18, .15 + (index / 4) * .075, .12, .035))];
    }
    [base addObject:Field(@"桜井 琥一", CGRectMake(.775, .905, .133, .053))];
    [base addObject:Field(@"閉じる", CGRectMake(.74, .10, .12, .035))];
    for (NSUInteger frame = 0; frame < 24; frame++) {
        NSMutableArray *observed = [base mutableCopy];
        if ((frame / 4) % 2) {
            [observed addObject:Field(@"説明の見出し", CGRectMake(.15, .80, .25, .04))];
        }
        // Same source/position is deduplicated; the same text elsewhere survives.
        [observed addObject:Field(@"桜井 琥一", CGRectMake(.775, .905, .133, .053))];
        [observed addObject:Field(@"桜井 琥一", CGRectMake(.15, .88, .133, .053))];
        [observed addObject:Field(@"……", CGRectMake(.15, .04, .20, .035))];
        NSArray<OCRTextItem *> *filtered = [app filteredInlineTextItems:observed strict:NO];
        Require(filtered.count == base.count + 1 + (((frame / 4) % 2) ? 1 : 0),
                @"dense screens retain every eligible field and control, with geometric deduplication");
        Require([filtered.lastObject.text isEqual:@"閉じる"], @"controls remain after content in reading order");
        NSArray *stable = [app.inlineFrameStabilizer observeItems:filtered];
        if (!app.inlineFrameStabilizer.ready) { continue; }
        Require(Find(stable, @"桜井 琥一") != nil, @"unrelated additions never evict a continuously observed name");
        for (NSUInteger index = 0; index < 32; index++) {
            Require(Find(stable, [NSString stringWithFormat:@"項目%lu", (unsigned long)index]) != nil,
                    @"all continuously observed fields survive changing block counts");
        }
    }
    // Genuine disappearance still follows the existing consecutive-frame confirmation.
    NSArray *withoutNames = [base subarrayWithRange:NSMakeRange(0, 32)];
    for (NSUInteger frame = 0; frame < 3; frame++) { [app.inlineFrameStabilizer observeItems:withoutNames]; }
    Require(!Find([app.inlineFrameStabilizer observeItems:withoutNames], @"桜井 琥一"),
            @"retaining observed fields does not freeze fields that really disappear");
}

static void ReplayPrivateProfile(void) {
    const char *path = getenv("FY_INLINE_REPLAY_PATH");
    if (!path) { return; }
    NSString *jsonl = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:path]
                                             encoding:NSUTF8StringEncoding error:NULL];
    Require(jsonl.length > 0, @"private replay is readable");
    NSMutableArray<NSDictionary *> *events = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSArray *> *stableByCycle = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *translations = [NSMutableDictionary dictionary];
    for (NSString *line in [jsonl componentsSeparatedByString:@"\n"]) {
        NSDictionary *event = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding]
                                                              options:0 error:NULL];
        if (!event) { continue; }
        [events addObject:event];
        if ([event[@"stage"] isEqual:@"inline_stable"]) { stableByCycle[event[@"cycle"]] = event[@"ocr_lines"]; }
        if ([event[@"event"] isEqual:@"inline_apply"]) {
            NSArray *rows = stableByCycle[event[@"cycle"]];
            NSArray *values = [event[@"translation"] componentsSeparatedByString:@"\n"];
            NSString *source = [[rows valueForKey:@"text"] componentsJoinedByString:@"\n"];
            if (rows.count != values.count || ![source isEqual:event[@"source"]]) { continue; }
            for (NSUInteger i = 0; i < rows.count; i++) { translations[rows[i][@"text"]] = values[i]; }
        }
    }
    Require(translations[@"桜井 琥一"] && translations[@"KOUICHI SAKURAI"], @"replay contains both observed name translations");
    AppDelegate *app = [AppDelegate new];
    [app createMainWindow];
    app.inlineTranslationPanels = [NSMutableArray array]; app.inlineLongCardPanels = [NSMutableArray array];
    CGRect viewport = CGRectMake(488, 472, 966, 546);
    WindowItem *window = [WindowItem new]; window.windowID = 9302; window.bounds = viewport;
    app.windows = [NSMutableArray arrayWithObject:window]; app.windowPopup = [NSPopUpButton new];
    [app.windowPopup addItemWithTitle:@"Private replay"];
    app.windowPopup.menu.itemArray.firstObject.representedObject = @(9302);
    app.inlineLayoutEngine.shortFontSize = 14.51022581335616;
    app.inlineLayoutEngine.coverFontSize = 15.51022581335616;
    app.inlineLayoutEngine.longBodyFontSize = 17.51022581335616;
    app.inlineLayoutEngine.minimumLongBodyFontSize = 13.51022581335616;
    app.inlineLayoutEngine.longTitleFontSize = 12.51022581335616;
    app.inlineLayoutEngine.compactEntryFontSize = 11.51022581335616;
    app.inlineLayoutEngine.cardMaxWidth = 314.5881849315068;
    app.inlineLayoutEngine.shortMaxWidth = 314.5881849315068 * 360 / 560;
    NSPanel *namePanel = nil, *overflowPanel = nil;
    CGRect nameFrame = CGRectZero;
    NSUInteger frames = 0, ready = 0, overflowCount = NSNotFound;
    for (NSDictionary *event in events) {
        if (![event[@"stage"] isEqual:@"modal_scoped"]) { continue; }
        NSMutableArray *raw = [NSMutableArray array];
        for (NSDictionary *row in event[@"ocr_lines"]) {
            [raw addObject:Field(row[@"text"], CGRectMake([row[@"x"] doubleValue], [row[@"y"] doubleValue],
                                                        [row[@"w"] doubleValue], [row[@"h"] doubleValue]))];
        }
        Require(Find(raw, @"桜井 琥一") != nil, @"profile replay continuously observes the Japanese name");
        NSArray *grouped = [app mergedInlineTextItemsFromItems:raw];
        NSArray *filtered = [app filteredInlineTextItems:grouped strict:NO];
        Require(Find(filtered, @"桜井 琥一") != nil, @"profile filtering never drops an observed name");
        NSArray<OCRTextItem *> *stable = [app.inlineFrameStabilizer observeItems:filtered];
        frames++;
        if (!app.inlineFrameStabilizer.ready) { continue; }
        ready++;
        Require(Find(stable, @"桜井 琥一") != nil, @"profile name remains present through unrelated grouping changes");
        NSMutableArray *values = [NSMutableArray array];
        for (OCRTextItem *item in stable) { [values addObject:translations[item.text] ?: item.text]; }
        [app showInlineTranslations:values forItems:stable placementRect:viewport];
        FYInlinePlacement *name = nil;
        for (FYInlinePlacement *p in app.lastInlineLayoutResult.placements) {
            if ([p.block.text isEqual:@"桜井 琥一"]) { name = p; }
        }
        Require(name.mode == FYInlineDisplayModeShortLabel, @"profile name has a visible panel");
        NSPanel *currentName = app.inlinePanelsByBlockID[name.blockID];
        if (!namePanel) { namePanel = currentName; nameFrame = name.translationFrame; }
        Require(currentName == namePanel && NSEqualRects(name.translationFrame, nameFrame),
                @"profile name retains its panel and exact position across the recorded sequence");
        if (overflowCount == NSNotFound) { overflowCount = app.inlineOverflowCount; }
        Require(app.inlineOverflowCount == overflowCount, @"profile overflow entry count remains stable");
        if (app.inlineOverflowPanel) {
            if (!overflowPanel) { overflowPanel = app.inlineOverflowPanel; }
            Require(overflowPanel == app.inlineOverflowPanel, @"profile overflow entry is reused instead of rebuilt");
        }
    }
    Require(frames >= 30 && ready >= 29, @"profile replay covers a sustained sequence");
    printf("PASS private profile retention: frames=%lu ready=%lu name-position-changes=0 overflow-count-changes=0 overflow=%lu\n",
           (unsigned long)frames, (unsigned long)ready, (unsigned long)overflowCount);
    [app clearInlineTranslationPanels];
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; CheckDenseFields(); ReplayPrivateProfile();
    NSLog(@"PASS InlineFieldRetentionTests: dense fields, deduplication, controls and genuine disappearance");
} return 0; }
