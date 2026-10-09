#import "FYOCRManager.h"

static NSUInteger assertions;
static void Expect(BOOL condition, NSString *message) {
    assertions++;
    if (!condition) { NSLog(@"FAIL %@", message); exit(1); }
}
static OCRTextItem *Item(NSString *text, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    OCRTextItem *item = [OCRTextItem new];
    item.text = text; item.boundingBox = CGRectMake(x, y, w, h);
    return item;
}
static CGImageRef Image(size_t width, size_t height) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}
static BOOL NearRect(CGRect a, CGRect b) {
    return fabs(a.origin.x-b.origin.x)<.000001 && fabs(a.origin.y-b.origin.y)<.000001 && fabs(a.size.width-b.size.width)<.000001 && fabs(a.size.height-b.size.height)<.000001;
}
static NSArray *Resolve(NSArray *items) { return [FYOCRManager resolveOverlappingItems:items]; }
static NSArray *Merge(NSArray *coarse, NSArray *fine) { return [FYOCRManager mergeCoarseItems:coarse refinedItems:fine]; }

int main(void) {
    @autoreleasepool {
        Expect(Resolve(nil).count == 0, @"nil input resolves to empty");
        Expect(Merge(nil, nil).count == 0, @"nil passes merge to empty");
        Expect([FYNormalizeOCRTextForComparison(@" \t日本　語\n、。") isEqual:@"日本語、。"], @"normalization strips only whitespace, preserving punctuation");
        Expect([FYNormalizeOCRTextForComparison(nil) isEqual:@""], @"nil normalization");
        OCRTextItem *top = Item(@"今日は", .1, .5, .4, .05);
        OCRTextItem *bottom = Item(@"いい天気", .1, .45, .4, .05);
        OCRTextItem *outer = Item(@"今日はいい天気", .1, .45, .4, .1);
        top.sourceBlockID = @"fixture-id"; top.lineTexts = @[@"今日は"];
        top.lineBoxes = @[[NSValue valueWithRect:top.boundingBox]];
        top.lastLineBox = top.boundingBox; top.lineCount = 1; top.confidence = .91;
        top.groupingConfidence = .8; top.blockKind = InlineBlockKindLong;
        NSMutableArray *input = [NSMutableArray arrayWithArray:@[outer, top, bottom]];
        NSArray *resolved = Resolve(input);
        Expect([resolved isEqual:@[top, bottom]], @"redundant outer removed with geometry and bidirectional text evidence");
        Expect(input.count == 3 && input[0] == outer, @"input array is not mutated");
        Expect(resolved[0] == top && [top.sourceBlockID isEqual:@"fixture-id"] && top.lineCount == 1 && top.blockKind == InlineBlockKindLong && top.confidence == .91 && top.groupingConfidence == .8 && CGRectEqualToRect(top.lastLineBox, top.boundingBox) && top.lineTexts.count == 1 && top.lineBoxes.count == 1, @"identity and all metadata survive");
        Expect([Resolve(@[top, bottom, outer]) isEqual:@[top, bottom]], @"outer removal does not depend on its position");
        OCRTextItem *duplicate = Item(top.text, .1, .5, .4, .05);
        Expect([Resolve(@[top, duplicate]) isEqual:@[top]], @"same-size duplicates deterministically retain first item");
        OCRTextItem *elsewhere = Item(top.text, .6, .5, .3, .05);
        Expect(Resolve(@[top, elsewhere]).count == 2, @"same text at different positions is retained");
        OCRTextItem *unrelated = Item(@"別の内容です", .1, .45, .4, .1);
        Expect(Resolve(@[unrelated, top, bottom]).count == 3, @"geometry without matching text cannot delete content");
        OCRTextItem *extra = Item(@"今日はいい天気追加の大切な内容", .1, .45, .4, .1);
        Expect(Resolve(@[extra, top, bottom]).count == 3, @"outer additional content survives bidirectional coverage check");
        OCRTextItem *repeated = Item(@"日日日日日日日日日日", .1, .5, .4, .05);
        OCRTextItem *one = Item(@"日", .1, .5, .4, .05);
        Expect(Resolve(@[repeated, one]).count == 2, @"coverage counts repeated characters, not set membership");
        OCRTextItem *sparse = Item(@"今日は", .1, .4, .4, .15);
        Expect(Resolve(@[sparse, top]).count == 2, @"matching text without sufficient area coverage is retained");
        OCRTextItem *partial = Item(top.text, .3, .5, .4, .05);
        Expect(Resolve(@[top, partial]).count == 2, @"partial containment is not deduplication");
        OCRTextItem *zero = Item(@"今日は", .1, .5, 0, .05);
        OCRTextItem *empty = Item(@"　 ", .1, .5, .4, .05);
        Expect(Resolve(@[zero, empty, top]).count == 3, @"zero-area and whitespace-only items remain unchanged");
        Expect([Resolve(@[bottom, top]) isEqual:@[bottom, top]], @"resolve alone preserves survivor order");
        Expect([Merge(@[bottom, top], @[]) isEqual:@[bottom, top]], @"empty refinement preserves existing order");
        OCRTextItem *correction = Item(@"今日わ", .1, .5, .4, .05);
        Expect([Merge(@[top, bottom], @[correction]) isEqual:@[correction, bottom]], @"corrected reading replaces by same-image geometry; missed line survives");
        Expect(Merge(@[top], @[elsewhere]).count == 2, @"refinement with identical text elsewhere does not replace coarse");
        OCRTextItem *tiny = Item(@"小さい文字", .1, .52, .4, .02);
        Expect(Merge(@[top], @[tiny]).count == 2, @"refinement too short cannot replace coarse");
        OCRTextItem *lowOverlap = Item(@"別行", .1, .54, .4, .05);
        Expect(Merge(@[top], @[lowOverlap]).count == 2, @"insufficient vertical overlap cannot replace coarse");
        OCRTextItem *left = Item(@"左", .1, .7, .1, .04);
        OCRTextItem *right = Item(@"右", .5, .69, .1, .04);
        Expect([Merge(@[bottom], @[right, left]) isEqual:@[left, right, bottom]], @"merge sorts top to bottom, near-row left to right");
        Expect([Merge(nil, @[outer, top, bottom]) isEqual:@[top, bottom]], @"refined-only pass also resolves duplicates");
        Expect([Merge(@[outer, top, bottom], nil) isEqual:@[top, bottom]], @"coarse-only pass still resolves duplicates");
        Expect([Resolve(@[top]) isEqual:@[top]], @"single item retained");
        Expect(![FYOCRManager isOwnOverlayText:nil] && ![FYOCRManager isOwnOverlayText:@"　 "], @"empty overlay text is not classified as noise");
        Expect([FYOCRManager isOwnOverlayText:@"翻译失败：服务异常"] && [FYOCRManager isOwnOverlayText:@"翻译失败:网络错误"], @"both error prefix variants excluded");
        Expect([FYOCRManager isOwnOverlayText:@"iee"] && [FYOCRManager isOwnOverlayText:@"？？？"], @"legacy short Latin/punctuation noise policy preserved");
        Expect(![FYOCRManager isOwnOverlayText:@"ことと"] && ![FYOCRManager isOwnOverlayText:@"平気。"], @"short kana/kanji dialogue preserved");
        Expect(![FYOCRManager isOwnOverlayText:@"abcdefg"], @"long Latin text not rejected by short-noise rule");
        Expect([FYOCRManager isOwnOverlayText:@"翻译 0.6s 总 0.8s"], @"truncated timing status excluded");
        Expect(![FYOCRManager isOwnOverlayText:@"数字は0.6Sです"], @"timing regex case sensitivity preserved");
        Expect([FYOCRManager isOwnOverlayText:@"译文已更新 2"], @"status needle plus digit excluded");
        Expect([FYOCRManager isOwnOverlayText:@"OCR 本次 2"], @"case-insensitive status needle excluded");
        Expect([FYOCRManager isOwnOverlayText:@"已暂停 秒"] && [FYOCRManager isOwnOverlayText:@"本次 三句"], @"status unit and count exclusions");
        Expect(![FYOCRManager isOwnOverlayText:@"已暂停"] && ![FYOCRManager isOwnOverlayText:@"今日は2回"], @"needle alone and unrelated digit are not enough");
        NSMutableDictionary *cache = [NSMutableDictionary dictionaryWithDictionary:@{@"a": @" 你好　世界 ", @"b": @"你好世界", @"c": @42, @"d": NSNull.null, @"e": @"单"}];
        NSSet *rendered = [FYOCRManager renderedTranslationSetForCaption:@" 字 幕 " inlineCache:cache];
        Expect([rendered isEqual:[NSSet setWithArray:@[@"字幕", @"你好世界"]]], @"rendered snapshot normalizes, deduplicates and ignores nonstrings/one-character values");
        cache[@"a"] = @"后来改变";
        Expect(![rendered containsObject:@"后来改变"], @"rendered snapshot does not track later cache changes");
        Expect([FYOCRManager renderedTranslationSetForCaption:nil inlineCache:nil].count == 0, @"nil rendered sources produce empty set");
        OCRTextItem *own = Item(@"你 好世界", .1, .1, .2, .05);
        OCRTextItem *status = Item(@"译文已更新 2", .1, .2, .2, .05);
        OCRTextItem *similar = Item(@"你好世界。", .1, .3, .2, .05);
        NSArray *overlayInput = @[own, top, status, similar];
        NSArray *filtered = [FYOCRManager itemsExcludingOwnOverlay:overlayInput renderedTexts:rendered];
        Expect([filtered isEqual:@[top, similar]], @"exclude own rendered text by normalized exact match, keep punctuation variant and dialogue");
        Expect(overlayInput.count == 4 && filtered[0] == top && [top.sourceBlockID isEqual:@"fixture-id"], @"exclusion preserves input and surviving identity/metadata/order");
        Expect([[FYOCRManager itemsExcludingOwnOverlay:@[own, top] renderedTexts:nil] isEqual:@[own, top]], @"without rendered snapshot ordinary text survives");
        Expect([FYOCRManager itemsExcludingOwnOverlay:nil renderedTexts:rendered] == nil, @"legacy nil exclusion result retained");
        Expect([[FYOCRManager textFromRecognizedLines:@[@" 二行目 ", @"一", @"　 ", @" 内 部 "]] isEqual:@"二行目\n一\n内 部"], @"string OCR preserves Vision order, single characters and internal spaces");
        Expect([[FYOCRManager textFromRecognizedLines:@[@"…", @"。", @"\n\t", @" 一 "]] isEqual:@"…\n。\n一"], @"string OCR does not apply model or dialogue punctuation filtering");
        Expect([[FYOCRManager textFromRecognizedLines:nil] isEqual:@""], @"nil string results produce empty text");
        Expect([[FYOCRManager textFromRecognizedLines:@[@"", @"　", @"\t"]] isEqual:@""], @"empty recognized lines omitted without blank separators");
        FYOCRStabilityOwner *stability=[FYOCRStabilityOwner new];
        __block NSString *seenPrevious=@"sentinel";
        BOOL (^equal)(NSString *,NSString *)=^BOOL(NSString *current,NSString *previous){seenPrevious=previous;return [current isEqual:previous];};
        Expect(![stability observe:@"first" equivalent:equal] && !seenPrevious && stability.count==1,@"stability starts with nil candidate and first observation count one");
        Expect([stability observe:@"first" equivalent:equal] && stability.count==2 && [stability.candidate isEqual:@"first"],@"second equivalent observation becomes stable");
        Expect(![stability observe:@"other" equivalent:equal] && stability.count==1,@"different candidate resets consecutive count");
        [stability reset]; Expect([stability.candidate isEqual:@""] && stability.count==0,@"explicit stability reset clears owned state");
        Expect(![stability observe:nil equivalent:equal] && !stability.candidate && stability.count==1,@"nil candidate remains nil not newly normalized");
        Expect(FYOCRFittedTextArea(@[])==0 && FYOCRFittedTextArea(@[Item(@"一",0,0,1,1)])==0,@"fitted area ignores empty input and single character");
        Expect(fabs(FYOCRFittedTextArea(@[Item(@"二字",.1,.2,.2,.1),Item(@"三字",.4,.5,.1,.1)])-.16)<1e-9,@"fitted area uses union bounds not sum of individual areas");
        Expect(fabs(FYOCRFittedTextArea(@[Item(@"二字",-.1,.2,.3,.2)])-.06)<1e-9,@"fitted area preserves out-of-image bounds without clamping");
        NSArray<OCRTextItem *> *processedBlocks=nil;
        NSString *processedText=[FYOCRManager postprocessedTextForItems:@[Item(@"二字",.1,.2,.2,.1)] renderedTexts:[NSSet set] blocks:&processedBlocks];
        Expect([processedText isEqual:@"二字"] && processedBlocks.count==1 && [processedBlocks[0].text isEqual:processedText],@"model OCR pipeline returns matching text and block output");
        Expect([[FYOCRManager postprocessedTextForItems:nil renderedTexts:[NSSet set] blocks:NULL] isEqual:@""],@"model OCR pipeline preserves empty text for missing observations");
        NSArray *combinedInput=@[own,outer,top,bottom,status];
        NSString *combined=[FYOCRManager postprocessedTextForItems:combinedInput renderedTexts:rendered blocks:&processedBlocks];
        Expect([processedBlocks isEqual:@[top,bottom]] && [combined isEqual:[@[top.text,bottom.text] componentsJoinedByString:@"\n"]],@"model pipeline combines overlay exclusion and redundant outer removal with original line order");
        Expect(combinedInput.count==5 && combinedInput[1]==outer && processedBlocks[0]==top && [top.sourceBlockID isEqual:@"fixture-id"],@"combined pipeline leaves input and survivor metadata identity untouched");
        Expect([[FYOCRManager postprocessedTextForItems:@[own,status] renderedTexts:rendered blocks:&processedBlocks] isEqual:@""] && processedBlocks.count==0,@"all-overlay pipeline clears both text and blocks");
        __block NSUInteger refinementCalls=0;
        NSString *accepted=@"unchanged";NSArray *acceptedBlocks=@[];
        NSArray *smallCoarse=@[Item(@"二字",.1,.2,.2,.1)];
        Expect(!FYRecognizeOCRRefinement(smallCoarse,NO,^NSString *(CGRect r,NSArray **b,NSError **e){refinementCalls++;return @"fine";},&accepted,&acceptedBlocks) && refinementCalls==0 && [accepted isEqual:@"unchanged"],@"disabled refinement neither invokes recognition nor overwrites output");
        Expect(!FYRecognizeOCRRefinement(smallCoarse,YES,^NSString *(CGRect r,NSArray **b,NSError **e){*e=[NSError errorWithDomain:@"fixture" code:1 userInfo:nil];return @"fine";},&accepted,&acceptedBlocks) && [accepted isEqual:@"unchanged"],@"refinement error rejects even nonempty text without overwriting slots");
        Expect(!FYRecognizeOCRRefinement(smallCoarse,YES,^NSString *(CGRect r,NSArray **b,NSError **e){return @"　 ";},&accepted,&acceptedBlocks),@"whitespace refinement is rejected");
        Expect(FYRecognizeOCRRefinement(smallCoarse,YES,^NSString *(CGRect r,NSArray **b,NSError **e){*b=smallCoarse;return @" fine ";},&accepted,&acceptedBlocks) && [accepted isEqual:@" fine "] && acceptedBlocks==smallCoarse,@"accepted refinement preserves raw text and original array identity");
        __block CGRect observedRegion=CGRectZero;
        refinementCalls=0;
        Expect(FYRecognizeOCRRefinement(smallCoarse,YES,^NSString *(CGRect r,NSArray **b,NSError **e){refinementCalls++;observedRegion=r;return @"一";},&accepted,&acceptedBlocks) && refinementCalls==1 && NearRect(observedRegion,CGRectMake(.07,.17,.26,.16)),@"refinement invokes recognizer once with padded union region");
        Expect([accepted isEqual:@"一"] && acceptedBlocks==nil,@"nonempty one-character refined text is accepted even with nil block output");
        accepted=@"original";acceptedBlocks=smallCoarse;
        Expect(!FYRecognizeOCRRefinement(smallCoarse,YES,^NSString *(CGRect r,NSArray **b,NSError **e){*b=@[];*e=[NSError errorWithDomain:@"fixture" code:2 userInfo:nil];return @"ignored";},&accepted,&acceptedBlocks) && [accepted isEqual:@"original"] && acceptedBlocks==smallCoarse,@"error rejects both outputs despite callback writing blocks");
        __block BOOL observedAccepted=NO; NSString *mergedText=nil; NSArray *mergedBlocks=nil;
        Expect(FYApplyOCRRefinement(smallCoarse,YES,^NSString *(CGRect r,NSArray **b,NSError **e){*b=@[Item(@"精",.1,.2,.2,.1)];return @"精";},^{observedAccepted=YES;},&mergedText,&mergedBlocks) && observedAccepted && [mergedText containsString:@"精"] && mergedBlocks.count>0,@"accepted refinement observes before merged output and returns merged text/blocks");
        observedAccepted=NO; mergedText=@"keep"; mergedBlocks=smallCoarse;
        Expect(!FYApplyOCRRefinement(smallCoarse,NO,^NSString *(CGRect r,NSArray **b,NSError **e){return @"ignored";},^{observedAccepted=YES;},&mergedText,&mergedBlocks) && !observedAccepted && [mergedText isEqual:@"keep"] && mergedBlocks==smallCoarse,@"rejected refinement does not observe or overwrite merged outputs");
        FYContentModeStability *mode=[FYContentModeStability new];mode.detectedMode=0;mode.candidateMode=-1;
        Expect([mode observeMode:1]==0 && mode.candidateHits==1,@"first different mode remains candidate");
        Expect([mode observeMode:1]==1 && mode.candidateHits==0,@"second consecutive mode commits and clears hits");
        [mode observeMode:0];
        Expect([mode observeMode:1]==1 && mode.candidateMode==1 && mode.candidateHits==0,@"return to current mode cancels pending switch");
        [mode observeMode:0];[mode observeMode:2];
        Expect(mode.detectedMode==1 && mode.candidateMode==2 && mode.candidateHits==1,@"different candidates do not accumulate across modes");
        NSString *displaySpeaker=nil,*displayBody=nil;
        [FYOCRManager splitSpeakerAndBody:@" 萩尾九段 \n本文\n次行" speaker:&displaySpeaker body:&displayBody];
        Expect([displaySpeaker isEqual:@"萩尾九段"] && [displayBody isEqual:@"本文\n次行"],@"speaker split trims name only and preserves body lines");
        [FYOCRManager splitSpeakerAndBody:@"かたぎりし、ゆうの\n萩尾九段\n 本文 " speaker:&displaySpeaker body:&displayBody];
        Expect([displaySpeaker isEqual:@"かたぎりし、ゆうの 萩尾九段"] && [displayBody isEqual:@" 本文 "],@"speaker split consumes ruby plus name but retains body whitespace");
        [FYOCRManager splitSpeakerAndBody:@"萩尾九段" speaker:&displaySpeaker body:&displayBody];
        Expect(!displaySpeaker && [displayBody isEqual:@"萩尾九段"],@"single speaker-like line remains full body");
        [FYOCRManager splitSpeakerAndBody:nil speaker:&displaySpeaker body:&displayBody];
        Expect(!displaySpeaker && [displayBody isEqual:@""],@"nil speaker source resets both outputs");
        CGRect planned=CGRectMake(9,9,9,9);
        OCRTextItem *refinementItem=Item(@"二字",.1,.2,.2,.1);
        Expect(FYOCRRefinementRegion(@[refinementItem],YES,.16,&planned) && fabs(planned.origin.x-.07)<1e-9 && fabs(planned.size.width-.26)<1e-9,@"refinement includes area threshold and three-percent padding");
        Expect(!FYOCRRefinementRegion(@[refinementItem],YES,.1601,&planned) && !FYOCRRefinementRegion(@[refinementItem],NO,.1,&planned) && !FYOCRRefinementRegion(@[refinementItem],YES,0,&planned),@"large zero area and disabled auto fit skip refinement");
        planned=CGRectMake(9,9,9,9);
        Expect(!FYOCRRefinementRegion(@[Item(@"一",0,0,1,1)],YES,.1,&planned) && CGRectEqualToRect(planned,CGRectMake(9,9,9,9)),@"single character omitted and failed plan leaves output untouched");
        Expect(FYOCRRefinementRegion(@[Item(@"二字",0,0,1,1)],YES,.1,&planned) && CGRectEqualToRect(planned,CGRectMake(0,0,1,1)),@"refinement padding clamps to image boundaries");
        CGImageRef source = Image(1000, 800); CGRect crop = CGRectZero;
        CGImageRef enlarged = [FYOCRManager copyEnlargedImage:source visionRegion:CGRectMake(.125, .25, .25, .25) pixelCrop:&crop];
        Expect(enlarged && CGRectEqualToRect(crop, CGRectMake(125,400,250,200)), @"Vision region flips to top-left pixel crop");
        Expect(CGImageGetWidth(enlarged)==500 && CGImageGetHeight(enlarged)==400, @"region enlarges twofold");
        CGImageRelease(enlarged);
        enlarged = [FYOCRManager copyEnlargedImage:source visionRegion:CGRectMake(-.125,.75,.25,.5) pixelCrop:&crop];
        Expect(enlarged && CGRectEqualToRect(crop, CGRectMake(0,0,125,200)), @"out-of-image region clips before scaling");
        CGImageRelease(enlarged);
        enlarged = [FYOCRManager copyEnlargedImage:source visionRegion:CGRectMake(.5,.5,0,0) pixelCrop:&crop];
        Expect(enlarged && crop.size.width==2 && crop.size.height==2 && CGImageGetWidth(enlarged)==4, @"legacy two-pixel minimum crop preserved");
        CGImageRelease(enlarged);
        crop=CGRectMake(1,2,3,4);
        enlarged = [FYOCRManager copyEnlargedImage:source visionRegion:CGRectMake(2,2,.1,.1) pixelCrop:&crop];
        Expect(!enlarged && CGRectEqualToRect(crop,CGRectMake(1,2,3,4)), @"failed crop does not overwrite caller output");
        OCRTextItem *callbackItem=Item(@"callback",0,0,1,1);
        NSArray *callbackItems=@[callbackItem]; __block NSUInteger calls=0;
        NSError *fixtureError=[NSError errorWithDomain:@"fixture" code:7 userInfo:nil];
        NSError *returnedError=nil; NSArray *returnedBlocks=nil;
        NSString *callbackText=[FYOCRManager recognizeEnlargedImage:source visionRegion:CGRectMake(.125,.25,.25,.25)
            recognizer:^NSString *(CGImageRef scaled, NSArray **items, NSError **error) {
                calls++; Expect(CGImageGetWidth(scaled)==500 && CGImageGetHeight(scaled)==400,@"injected recognition receives enlarged region before remap");
                *items=callbackItems; *error=fixtureError; return @" raw result ";
            } blocks:&returnedBlocks error:&returnedError];
        Expect(calls==1 && [callbackText isEqual:@" raw result "] && returnedError==fixtureError,@"recognition text/error passed through synchronously unchanged");
        Expect(returnedBlocks==callbackItems && CGRectEqualToRect(callbackItem.boundingBox,CGRectMake(.125,.25,.25,.25)),@"coordinator remaps original item and returns original array");
        returnedBlocks=callbackItems;
        NSString *failedText=[FYOCRManager recognizeEnlargedImage:source visionRegion:CGRectMake(2,2,.1,.1)
            recognizer:^NSString *(CGImageRef scaled,NSArray **items,NSError **error){ calls++;return @"unexpected"; }
            blocks:&returnedBlocks error:&returnedError];
        Expect([failedText isEqual:@""] && calls==1 && returnedBlocks==callbackItems && returnedError==fixtureError,@"failed preparation skips recognizer and leaves outputs untouched");
        CGImageRelease(source);
        source=Image(1200,1000);
        enlarged=[FYOCRManager copyEnlargedImage:source visionRegion:CGRectMake(0,0,1,1) pixelCrop:NULL];
        Expect(enlarged && CGImageGetWidth(enlarged)==1800 && CGImageGetHeight(enlarged)==1800, @"legacy per-axis 1800 cap preserved, not aspect-ratio redesign");
        CGImageRelease(enlarged); CGImageRelease(source);
        source=Image(1,1);
        Expect(![FYOCRManager copyEnlargedImage:source visionRegion:CGRectMake(0,0,1,1) pixelCrop:NULL], @"undersized source returns no prepared image");
        CGImageRelease(source);
        OCRTextItem *mapped=Item(@"回映射",.2,.3,.4,.1);
        mapped.lastLineBox=CGRectMake(.1,.1,.2,.05); mapped.lineBoxes=@[[NSValue valueWithRect:mapped.boundingBox]];
        mapped.sourceBlockID=@"keep"; mapped.confidence=.77;
        [FYOCRManager remapItems:@[mapped] fromPixelCrop:CGRectMake(125,400,250,200) imageSize:CGSizeMake(1000,800)];
        Expect(NearRect(mapped.boundingBox,CGRectMake(.175,.325,.1,.025)), @"bounding box maps into source Vision coordinates");
        Expect(NearRect(mapped.lastLineBox,CGRectMake(.15,.275,.05,.0125)), @"nonempty last-line box maps with same transform");
        Expect(NearRect(mapped.lineBoxes[0].rectValue,CGRectMake(.175,.325,.1,.025)) && [mapped.sourceBlockID isEqual:@"keep"] && mapped.confidence==.77,
               @"per-line boxes map with the union box while unrelated metadata stays intact");
        OCRTextItem *multiline=Item(@"帰宅部\n桜井琥一の弟。\nスリルは彼の活力。",.608,.079,.204,.164);
        multiline.lineBoxes=@[[NSValue valueWithRect:CGRectMake(.610,.201,.070,.041)],
                              [NSValue valueWithRect:CGRectMake(.610,.129,.154,.051)],
                              [NSValue valueWithRect:CGRectMake(.609,.079,.203,.060)]];
        NSArray<OCRTextItem *> *split=[FYOCRManager splitMultilineItems:@[multiline]];
        Expect(split.count==3 && [split[0].text isEqual:@"帰宅部"] &&
               [split[1].text isEqual:@"桜井琥一の弟。"] &&
               NearRect(split[1].boundingBox,CGRectMake(.610,.129,.154,.051)),
               @"Vision multiline observation retains separate text and character-range geometry");
        OCRTextItem *noLast=Item(@"無",0,0,1,1);
        [FYOCRManager remapItems:@[noLast] fromPixelCrop:CGRectMake(125,400,250,200) imageSize:CGSizeMake(1000,800)];
        Expect(CGRectEqualToRect(noLast.lastLineBox,CGRectZero), @"empty last-line box remains empty");
        Expect([FYOCRManager textHitsUIToken:@"戻る"] && [FYOCRManager textHitsUIToken:@"詳細を見る"], @"Japanese UI token exact/prefix policy");
        Expect(![FYOCRManager textHitsUIToken:@"River Books"] && ![FYOCRManager textHitsUIToken:@"booking"], @"Latin tokens cannot match inside words");
        Expect([FYOCRManager textHitsUIToken:@"Close!"] && [FYOCRManager textHitsUIToken:@"WEB 2"], @"Latin token boundaries and case folding retained");
        Expect(![FYOCRManager textHitsUIToken:nil], @"empty UI token input");
        OCRTextItem *ruby=Item(@"きょう",.2,.4,.08,.02);
        OCRTextItem *parent=Item(@"今日もいい天気",.18,.34,.3,.05);
        Expect([FYOCRManager isFurigana:ruby nearLargerLineInItems:@[ruby,parent]], @"small kana above overlapping larger line is ruby");
        OCRTextItem *below=Item(@"きょう",.2,.3,.08,.02);
        Expect(![FYOCRManager isFurigana:below nearLargerLineInItems:@[below,parent]], @"kana below parent is not ruby");
        OCRTextItem *farRuby=Item(@"きょう",.7,.4,.08,.02);
        Expect(![FYOCRManager isFurigana:farRuby nearLargerLineInItems:@[farRuby,parent]], @"ruby requires horizontal overlap");
        OCRTextItem *kanji=Item(@"今日",.2,.4,.08,.02);
        Expect(![FYOCRManager isFurigana:kanji nearLargerLineInItems:@[kanji,parent]], @"ruby requires kana character ratio");
        OCRTextItem *back=Item(@"戻る",.1,.5,.1,.03), *menu=Item(@"メニュー",.1,.6,.1,.03);
        Expect([FYOCRManager UITokenHitCount:@[back,menu,parent]]==2 && [FYOCRManager looksLikeUIFrame:@[back,menu,parent]], @"two UI tokens identify frame");
        Expect(![FYOCRManager looksLikeUIFrame:@[parent,ruby]] && ![FYOCRManager looksLikeUIFrame:nil], @"dialogue plus ruby and empty frame not UI");
        NSMutableArray *dense=[NSMutableArray array];
        for(NSUInteger i=0;i<6;i++) [dense addObject:Item(@"ニュース本文",.2,.1+i*.1,.25,.04)];
        Expect([FYOCRManager looksLikeUIFrame:dense], @"six substantial lines identify dense UI");
        NSMutableArray *smallItems=[NSMutableArray array];
        for(NSUInteger i=0;i<4;i++) [smallItems addObject:Item(@"項目",.1+i*.2,.5,.1,.02)];
        Expect([FYOCRManager looksLikeUIFrame:smallItems], @"four small non-ruby items identify UI");
        NSArray *shortDialogue=@[Item(@"青木",.28,.27,.05,.032), Item(@"あの、",.30,.20,.07,.032),
            Item(@"青木悠",.30,.14,.11,.032), Item(@"ですけど……",.30,.08,.14,.032)];
        Expect(![FYOCRManager looksLikeUIFrame:shortDialogue] && [FYOCRManager contentModeForItems:shortDialogue fallback:1]==0,
               @"speaker plus short spoken lines is dialogue, not four menu boxes");
        NSArray *lowerChoices=@[Item(@"彼と話す。",.30,.27,.14,.032), Item(@"彼女と話す。",.30,.207,.14,.032),
            Item(@"何もしない。",.30,.144,.14,.032), Item(@"立ち去る。",.30,.081,.14,.032)];
        Expect([FYOCRManager looksLikeUIFrame:lowerChoices] && [FYOCRManager contentModeForItems:lowerChoices fallback:0]==1,
               @"aligned lower-screen choices retain UI mode despite kana and sentence punctuation");
        NSArray *headedChoices=[@[Item(@"青木",.30,.333,.05,.032)] arrayByAddingObjectsFromArray:lowerChoices];
        Expect([FYOCRManager looksLikeUIFrame:headedChoices],
               @"a name-like heading cannot turn complete choice sentences into wrapped dialogue");
        NSArray *wrappedDialogue=@[Item(@"ルード",.30,.27,.07,.032), Item(@"あの、",.30,.207,.07,.032),
            Item(@"君のこと",.30,.144,.11,.032), Item(@"なんだけど……",.30,.081,.14,.032)];
        Expect(![FYOCRManager looksLikeUIFrame:wrappedDialogue],
               @"speaker and unfinished speech fragments retain the short wrapped-dialogue exemption");
        Expect([FYOCRManager looksLikeUIFrame:[shortDialogue arrayByAddingObjectsFromArray:@[back,menu]]],
               @"explicit menu controls still override a compact dialogue-shaped band");
        NSMutableArray *upperShort=[NSMutableArray new], *lowerLabels=[NSMutableArray new];
        for (NSUInteger i=0;i<shortDialogue.count;i++) {
            OCRTextItem *item=shortDialogue[i]; CGRect box=item.boundingBox; box.origin.y+=.5;
            [upperShort addObject:Item(item.text,box.origin.x,box.origin.y,box.size.width,box.size.height)];
            [lowerLabels addObject:Item(@"案内項目",item.boundingBox.origin.x,item.boundingBox.origin.y,item.boundingBox.size.width,item.boundingBox.size.height)];
        }
        Expect([FYOCRManager looksLikeUIFrame:upperShort] && [FYOCRManager looksLikeUIFrame:lowerLabels],
               @"upper-screen options and lower-screen non-spoken labels remain UI");
        Expect([[FYOCRManager dialogueTextWithoutTrailingButton:@" 思い出した。使用 "] isEqual:@"思い出した。"], @"two-kanji trailing button stripped from kana dialogue");
        Expect([[FYOCRManager dialogueTextWithoutTrailingButton:@"そうだ。操作説明"] isEqual:@"そうだ。"], @"four-kanji trailing button stripped");
        Expect([[FYOCRManager dialogueTextWithoutTrailingButton:@"そうだ。使"] isEqual:@"そうだ。使"], @"single trailing kanji retained");
        Expect([[FYOCRManager dialogueTextWithoutTrailingButton:@"そうだ。操作説明方法"] isEqual:@"そうだ。操作説明方法"], @"over-four trailing kanji retained");
        Expect([[FYOCRManager dialogueTextWithoutTrailingButton:@"日本語。使用"] isEqual:@"日本語。使用"], @"kanji-only line retained without kana evidence");
        Expect([[FYOCRManager dialogueTextWithoutTrailingButton:@"思い出した使用"] isEqual:@"思い出した使用"], @"trailing kanji without punctuation retained");
        Expect([[FYOCRManager dialogueTextWithoutTrailingButton:nil] isEqual:@""], @"nil cleanup input returns empty");
        Expect([FYOCRManager containsJapaneseKana:@"かな"] && [FYOCRManager containsJapaneseKana:@"ㇰ"] && ![FYOCRManager containsJapaneseKana:@"漢字"], @"legacy Japanese-text evidence means kana, not kanji alone");
        OCRTextItem *anchor=Item(@"今日はいい天気ですね。",.2,.18,.5,.05);
        OCRTextItem *firstLine=Item(@"平気。",.2,.26,.08,.04);
        OCRTextItem *sign=Item(@"街の看板です",.8,.6,.18,.04);
        Expect([FYOCRManager isDialogueAnchor:anchor] && [FYOCRManager isFormedTextLine:anchor], @"wide lower-frame dialogue anchor");
        Expect([[FYOCRManager subtitleBandItems:@[sign,anchor,firstLine]] isEqual:@[firstLine,anchor]], @"short first line collected by overlap and adjacency, sign excluded, top-to-bottom output");
        Expect(anchor.boundingBox.origin.x==.2 && [anchor.text isEqual:@"今日はいい天気ですね。"], @"subtitle band does not mutate item metadata");
        OCRTextItem *high=Item(anchor.text,.2,.65,.5,.05);
        Expect(![FYOCRManager isDialogueAnchor:high] && [FYOCRManager subtitleBandItems:@[high]].count==0, @"upper environmental long text is not dialogue anchor");
        OCRTextItem *shortOne=Item(@"行くぞ。",.2,.2,.08,.04);
        Expect([FYOCRManager isSingleLineDialogue:shortOne] && [[FYOCRManager subtitleBandItems:@[shortOne]] isEqual:@[shortOne]], @"single punctuated short dialogue survives without stacked name");
        OCRTextItem *unpunctuated=Item(@"ありがとう",.2,.2,.14,.05);
        Expect([FYOCRManager isUnpunctuatedSingleLineDialogue:unpunctuated.text box:unpunctuated.boundingBox] && [FYOCRManager isSingleLineDialogue:unpunctuated], @"central tall unpunctuated kana dialogue recognized");
        Expect(![FYOCRManager isUnpunctuatedSingleLineDialogue:@"HELLO" box:unpunctuated.boundingBox], @"unpunctuated Latin sign lacks kana evidence");
        OCRTextItem *help=Item(@"操作説明",.85,.05,.1,.04);
        Expect([FYOCRManager isCornerHelpButton:help] && ![FYOCRManager isCornerHelpButton:anchor], @"corner-help classification retains text and geometry evidence");
        Expect([FYOCRManager subtitleBandItems:nil].count==0, @"empty subtitle-band input");
        OCRTextItem *farLine=Item(@"離れた台詞です。",.2,.5,.3,.04);
        Expect([[FYOCRManager subtitleBandItems:@[anchor,farLine]] isEqual:@[anchor]], @"vertical gap beyond expansion threshold cannot join band");
        OCRTextItem *side=Item(@"他の文字",.8,.2,.12,.04);
        Expect([[FYOCRManager subtitleBandItems:@[anchor,side]] isEqual:@[anchor]], @"nearby line without horizontal overlap cannot join band");
        Expect([FYOCRManager looksLikeSpeakerName:@"萩尾九段"] && [FYOCRManager looksLikeSpeakerName:@"ルード"], @"kanji and katakana speaker names");
        Expect(![FYOCRManager looksLikeSpeakerName:@"うん、空いてるよ"] && ![FYOCRManager looksLikeSpeakerName:@"萩尾九段。"], @"hiragana dialogue and sentence-ending text not speaker names");
        Expect([FYOCRManager looksLikeSpeakerFurigana:@"かたぎりし、ゆうの"] && ![FYOCRManager looksLikeSpeakerFurigana:@"かたぎり。"], @"speaker ruby ratio and sentence-ending exclusion");
        Expect(![FYOCRManager dialogueFrameIsSpeakerLabelOnly:@[@"はい"]] && [FYOCRManager dialogueFrameIsSpeakerLabelOnly:@[@"萩尾九段",@"はぎお"]], @"speaker-only frame needs actual name, not just kana");
        OCRTextItem *name=Item(@"萩尾九段",.2,.4,.15,.04), *nameRuby=Item(@"はぎお",.2,.45,.08,.02);
        Expect([FYOCRManager looksLikeSpeakerLabelCluster:@[nameRuby,name]], @"name and ruby form label cluster");
        Expect([FYOCRManager isSpeakerLabelItem:nameRuby inPool:@[nameRuby,name]], @"ruby above horizontally overlapping name is label");
        Expect(![FYOCRManager isSpeakerLabelItem:nameRuby inPool:@[nameRuby]], @"ruby without nearby name is not label item");
        OCRTextItem *wideName=Item(@"萩尾九段",.2,.4,.4,.04);
        Expect(![FYOCRManager looksLikeSpeakerLabelCluster:@[wideName]], @"wide text cannot be swallowed as label cluster");
        OCRTextItem *option=Item(@"どこへ行こう？",.2,.7,.3,.04);
        NSMutableArray *dialogue=[NSMutableArray array], *options=[NSMutableArray array];
        [FYOCRManager splitDialogueAndOptions:@[nameRuby,name,anchor] allBlocks:@[option,nameRuby,name,anchor,sign] dialogue:dialogue options:options];
        Expect([dialogue isEqual:@[nameRuby,name,anchor]], @"speaker cluster immediately above dialogue merges into dialogue");
        Expect([options isEqual:@[option]], @"aligned distant option added, speaker and unrelated sign excluded");
        [FYOCRManager splitDialogueAndOptions:@[anchor] allBlocks:nil dialogue:dialogue options:options];
        Expect(dialogue.count==4 && dialogue.lastObject==anchor && options.count==1, @"split appends to caller outputs without clearing existing entries");
        [FYOCRManager splitDialogueAndOptions:nil allBlocks:nil dialogue:dialogue options:options];
        Expect(dialogue.count==4 && options.count==1, @"empty band leaves outputs unchanged");
        [FYOCRManager splitDialogueAndOptions:@[anchor] allBlocks:nil dialogue:nil options:nil];
        Expect([anchor.text isEqual:@"今日はいい天気ですね。"], @"nil outputs allowed and input item unchanged");
        const size_t pw=80, ph=60, stride=pw*4+16;
        NSMutableData *pixelData=[NSMutableData dataWithLength:stride*ph]; unsigned char *pixels=pixelData.mutableBytes;
        CGRect detected=CGRectMake(1,2,3,4); BOOL dimmed[80];
        Expect(!FYDetectBrightOCRContentRegion(NULL,pw,ph,stride,&detected,NULL,NULL,0), @"missing pixels does not detect content");
        Expect(!FYDetectBrightOCRContentRegion(pixels,pw,ph,stride,&detected,NULL,NULL,0) && CGRectEqualToRect(detected,CGRectMake(1,2,3,4)), @"dark frame leaves detection output unchanged");
        for(size_t y=10;y<50;y++) for(size_t x=20;x<60;x++) { unsigned char *p=pixels+y*stride+x*4; p[0]=p[1]=p[2]=220; p[3]=255; }
        Expect(FYDetectBrightOCRContentRegion(pixels,pw,ph,stride,&detected,dimmed,NULL,0) && NearRect(detected,CGRectMake(.25,1.0-50.0/60.0,.5,40.0/60.0)), @"bright rectangle detected with padded stride and bottom-left output");
        Expect(dimmed[0] && !dimmed[40], @"dark columns marked outside bright region");
        CGRect exclusion=detected;
        Expect(!FYDetectBrightOCRContentRegion(pixels,pw,ph,stride,&detected,NULL,&exclusion,1), @"own-panel exclusion cannot manufacture modal content");
        CGRect harmlessExclusion=CGRectMake(0,0,.01,.01);
        Expect(FYDetectBrightOCRContentRegion(pixels,pw,ph,stride,&detected,NULL,&harmlessExclusion,1),@"allocated exclusion mask success path preserves detection");
        NSMutableData *stripData=[NSMutableData dataWithLength:stride*ph];unsigned char *strip=stripData.mutableBytes;
        for(size_t y=0;y<ph;y++)for(size_t x=20;x<60;x++)if(y%2==0){unsigned char *p=strip+y*stride+x*4;p[0]=p[1]=p[2]=220;}
        Expect(!FYDetectBrightOCRContentRegion(strip,pw,ph,stride,&detected,NULL,&harmlessExclusion,1),@"allocated exclusion mask row-rejection path returns safely");
        OCRTextItem *brightBlock=Item(@"正文",.3,.4,.2,.1), *darkBlock=Item(@"底层",.01,.4,.1,.1);
        Expect(FYOCRBlockSitsOnBrightBackdrop(brightBlock,pixels,pw,ph,stride), @"text inside bright region has bright backdrop");
        Expect(!FYOCRBlockSitsOnBrightBackdrop(darkBlock,pixels,pw,ph,stride), @"text on dark leftover region has dim backdrop");
        Expect(FYOCRBlockSitsOnBrightBackdrop(brightBlock,NULL,pw,ph,stride), @"missing sampling buffer retains legacy fail-open behavior");
        Expect(!FYDetectBrightOCRContentRegion(pixels,7,ph,stride,&detected,NULL,NULL,0), @"undersized detection input rejected");
        Expect([FYOCRManager contentModeForItems:nil fallback:7]==7, @"empty mode input retains exact fallback");
        Expect([FYOCRManager contentModeForItems:@[anchor] fallback:1]==0, @"formed dialogue selects dialogue mode");
        Expect([FYOCRManager contentModeForItems:@[anchor,back,menu] fallback:0]==1, @"UI evidence takes precedence over dialogue anchor");
        OCRTextItem *fragment=Item(@"え",.25,.2,.03,.04);
        Expect([FYOCRManager contentModeForItems:@[fragment] fallback:0]==0 && [FYOCRManager contentModeForItems:@[fragment] fallback:1]==1, @"central short kana fragment cannot switch established mode");
        Expect([FYOCRManager contentModeForItems:@[help] fallback:0]==0, @"corner hint retains dialogue fallback");
        Expect([FYOCRManager contentModeForItems:@[sign] fallback:0]==1, @"unrelated environmental line selects UI without dialogue evidence");
        source=Image(1000,800);
        __block NSUInteger scopeCalls=0;
        NSArray *scopedItems=[FYOCRManager recognizeImage:source topLeftScope:CGRectMake(.2,.25,.5,.5) recognizer:^NSArray *(CGImageRef crop,NSError **e) {
            scopeCalls++;
            Expect(CGImageGetWidth(crop)==500 && CGImageGetHeight(crop)==400,@"manual scope crops input before recognition");
            return @[Item(@"框内",.1,.2,.4,.3)];
        } error:NULL];
        Expect(NearRect([scopedItems[0] boundingBox],CGRectMake(.25,.35,.2,.15)),@"manual scope restores bottom-left full-frame coordinates");
        NSArray *full=@[Item(@"整画面",.1,.1,.2,.2)];
        Expect([FYOCRManager recognizeImage:source topLeftScope:CGRectMake(0,0,1,1) recognizer:^NSArray *(CGImageRef image,NSError **e){Expect(image==source,@"automatic scope borrows unchanged full image");return full;} error:NULL]==full,@"automatic scope preserves output identity");
        Expect([FYOCRManager recognizeImage:source topLeftScope:CGRectMake(2,0,.2,.2) recognizer:^NSArray *(CGImageRef crop,NSError **e){scopeCalls++;return full;} error:NULL].count==0 && scopeCalls==1,@"invalid manual region never expands to full frame");
        CGImageRelease(source);
        source=Image(1000,800); FYOCRPixelBuffer buffer=FYCreateOCRPixelBuffer(source);
        Expect(buffer.pixels && buffer.context && buffer.width==480 && buffer.height==384 && buffer.bytesPerRow==480*4, @"sampling buffer scales width to 480 with original aspect ratio and RGBA stride");
        CGImageRelease(source); unsigned char sampled=buffer.pixels[0]; (void)sampled;
        FYReleaseOCRPixelBuffer(&buffer);
        Expect(!buffer.pixels && !buffer.context, @"release clears owned handles");
        FYReleaseOCRPixelBuffer(&buffer);
        Expect(!buffer.pixels && !buffer.context, @"repeat release safe");
        source=Image(1,1); buffer=FYCreateOCRPixelBuffer(source); CGImageRelease(source);
        Expect(!buffer.pixels && !buffer.context && buffer.width==0, @"small image creates empty buffer");
        Expect(FYOCRModalRectQualifiesForCropping(CGRectMake(.3,.2,.4,.3)), @"large centered modal rect qualifies");
        Expect(!FYOCRModalRectQualifiesForCropping(CGRectMake(.1,.2,.4,.3)) && !FYOCRModalRectQualifiesForCropping(CGRectMake(.4,.2,.2,.3)), @"offcenter and narrow rectangles rejected");
        Expect(!FYOCRModalSurroundingsAreDimmer(NULL,pw,ph,stride,exclusion), @"missing pixels cannot establish dimmed surroundings");
        Expect(FYOCRModalSurroundingsAreDimmer(pixels,pw,ph,stride,CGRectMake(.3,.3,.4,.4)), @"central bright interior with dark surround qualifies");
        CGRect modal=CGRectMake(.3,.3,.4,.3);
        OCRTextItem *insideA=Item(@"正文一",.35,.4,.1,.04), *insideB=Item(@"正文二",.5,.4,.1,.04);
        OCRTextItem *header=Item(@"标题",.4,.65,.1,.04), *outside=Item(@"底层",.05,.1,.1,.04);
        NSArray *modalInput=@[outside,insideA,header,insideB];
        Expect([[FYOCRManager items:modalInput inModalRegion:modal exclusions:nil] isEqual:@[insideA,header,insideB]], @"modal padding retains header while excluding underlying page, preserves order");
        NSValue *panel=[NSValue valueWithRect:insideA.boundingBox];
        Expect([[FYOCRManager items:modalInput inModalRegion:modal exclusions:@[panel]] isEqual:@[header,insideB]], @"own panel overlap removes its OCR readback");
        NSArray *tooFew=@[outside,insideA,insideB];
        Expect([FYOCRManager items:tooFew inModalRegion:modal exclusions:@[panel]]==tooFew, @"fewer than two surviving blocks returns original array");
        NSValue *partialPanel=[NSValue valueWithRect:CGRectMake(.35,.4,.02,.04)];
        Expect([[FYOCRManager items:modalInput inModalRegion:modal exclusions:@[partialPanel]] isEqual:@[insideA,header,insideB]], @"below 50-percent own-panel overlap does not delete block");
        Expect([FYOCRManager items:nil inModalRegion:modal exclusions:nil]==nil, @"nil modal input retained by fallback");
        Expect(CGRectEqualToRect(insideA.boundingBox,CGRectMake(.35,.4,.1,.04)), @"modal filtering does not mutate OCR metadata");
        NSLog(@"PASS OCRPostprocessingTests: %lu assertions, no AppDelegate, UI or Vision request", (unsigned long)assertions);
    }
    return 0;
}
