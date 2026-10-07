// Opt-in offline replay of a locally collected text trace. Never starts capture,
// reads preferences/credentials, submits requests, or prints recorded text.
#import "LearningAppTestSupport.h"

int main(void) { @autoreleasepool {
    const char *path = getenv("FY_INLINE_REPLAY_PATH");
    Require(path != NULL, @"set FY_INLINE_REPLAY_PATH to an existing private trace");
    NSString *jsonl = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:path]
                                             encoding:NSUTF8StringEncoding error:NULL];
    Require(jsonl.length > 0, @"trace is readable");
    AppDelegate *app = [AppDelegate new];
    NSUInteger frames = 0, readyFrames = 0, profileFrames = 0, dateFrames = 0;
    NSUInteger contentChanges = 0;
    NSArray *lastTexts = nil;
    NSTimeInterval processingTime = 0;
    for (NSString *line in [jsonl componentsSeparatedByString:@"\n"]) {
        if (!line.length) { continue; }
        NSDictionary *event = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding]
                                                              options:0 error:NULL];
        if (![event[@"stage"] isEqual:@"modal_scoped"]) { continue; }
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *row in event[@"ocr_lines"]) {
            OCRTextItem *item = [OCRTextItem new]; item.text = row[@"text"];
            item.boundingBox = CGRectMake([row[@"x"] doubleValue], [row[@"y"] doubleValue],
                                          [row[@"w"] doubleValue], [row[@"h"] doubleValue]);
            item.confidence = .9; [items addObject:item];
        }
        NSTimeInterval start = NSDate.timeIntervalSinceReferenceDate;
        NSArray *grouped = [app filteredInlineTextItems:[app mergedInlineTextItemsFromItems:items] strict:NO];
        NSArray *stable = [app.inlineFrameStabilizer observeItems:grouped];
        processingTime += NSDate.timeIntervalSinceReferenceDate - start;
        frames++;
        if (!app.inlineFrameStabilizer.ready) { continue; }
        readyFrames++;
        NSArray *texts = [stable valueForKey:@"text"];
        if (lastTexts && ![lastTexts isEqual:texts]) { contentChanges++; }
        lastTexts = texts;
        BOOL club = NO, remark = NO, date = NO;
        for (OCRTextItem *item in stable) {
            NSString *text = item.text;
            if ([text containsString:@"帰宅部"]) {
                Require(![text containsString:@"桜井琥一の弟。"] && ![text containsString:@"桜井琉夏の兄。"],
                        @"independent profile fields stay separate in recorded frames");
                club = YES;
            }
            if ([text containsString:@"桜井琥一の弟。"] || [text containsString:@"桜井琉夏の兄。"]) {
                Require(item.blockKind == InlineBlockKindLong, @"compact profile prose is not a button list");
                remark = YES;
            }
            if ([text containsString:@"4月12日（日）"]) {
                Require([text isEqualToString:@"4月12日（日）"], @"date never absorbs intermittent background text");
                date = YES;
            }
        }
        if (club && remark) { profileFrames++; }
        if (date) { dateFrames++; }
    }
    Require(frames >= 10 && readyFrames >= 9, @"replayed a sustained sequence through the production grouper, filter and stabilizer");
    Require(profileFrames > 0 || dateFrames > 0, @"trace includes a reported regression scene");
    printf("PASS recorded replay: frames=%lu ready=%lu separated-profile=%lu clean-date=%lu content-changes=%lu mean-processing-ms=%.3f\n",
           (unsigned long)frames, (unsigned long)readyFrames, (unsigned long)profileFrames,
           (unsigned long)dateFrames, (unsigned long)contentChanges, processingTime * 1000 / frames);
    return 0;
}}
