#import "FYOCRRefinement.h"
#import <math.h>

BOOL FYApplyOCRRefinement(NSArray<OCRTextItem *> *coarse, BOOL autoFit,
    NSString *(^recognizer)(CGRect, NSArray<OCRTextItem *> **, NSError **), void (^acceptedObserver)(void),
    NSString **outText, NSArray<OCRTextItem *> **outBlocks) {
    return FYApplyOCRRefinementWithStabilizer(coarse,autoFit,recognizer,acceptedObserver,nil,outText,outBlocks);
}

BOOL FYApplyOCRRefinementWithStabilizer(NSArray<OCRTextItem *> *coarse, BOOL autoFit,
    NSString *(^recognizer)(CGRect, NSArray<OCRTextItem *> **, NSError **), void (^acceptedObserver)(void),
    FYOCRRefinementStabilizer *stabilizer, NSString **outText, NSArray<OCRTextItem *> **outBlocks) {
    NSString *fineText=nil;NSArray<OCRTextItem *> *fineBlocks=nil;
    if (!FYRecognizeOCRRefinement(coarse,autoFit,recognizer,&fineText,&fineBlocks)) {
        [stabilizer reset]; return NO;
    }
    if (acceptedObserver) acceptedObserver();
    NSArray *merged=stabilizer ? [stabilizer observeCoarseItems:coarse refinedItems:fineBlocks]
        : [FYOCRRefinement mergeCoarseItems:coarse refinedItems:fineBlocks];
    if (outBlocks) *outBlocks=merged;
    if (outText) *outText=[[merged valueForKey:@"text"] componentsJoinedByString:@"\n"];
    return YES;
}

BOOL FYRecognizeOCRRefinement(NSArray<OCRTextItem *> *coarse, BOOL autoFit,
    NSString *(^recognizer)(CGRect, NSArray<OCRTextItem *> **, NSError **), NSString **outText, NSArray<OCRTextItem *> **outBlocks) {
    CGRect region=CGRectZero;
    if (!FYOCRRefinementRegion(coarse,autoFit,FYOCRFittedTextArea(coarse),&region)) return NO;
    NSError *error=nil;NSArray<OCRTextItem *> *blocks=nil;
    NSString *text=recognizer(region,&blocks,&error);
    if (error || FYNormalizeOCRTextForComparison(text).length==0) return NO;
    if (outText) *outText=text;
    if (outBlocks) *outBlocks=blocks;
    return YES;
}

CGFloat FYOCRFittedTextArea(NSArray<OCRTextItem *> *blocks) {
    CGFloat minX=1,minY=1,maxX=0,maxY=0;BOOL any=NO;
    for (OCRTextItem *block in blocks) {
        if (FYNormalizeOCRTextForComparison(block.text).length<2) continue;
        minX=MIN(minX,CGRectGetMinX(block.boundingBox));minY=MIN(minY,CGRectGetMinY(block.boundingBox));
        maxX=MAX(maxX,CGRectGetMaxX(block.boundingBox));maxY=MAX(maxY,CGRectGetMaxY(block.boundingBox));any=YES;
    }
    return any ? (maxX-minX)*(maxY-minY) : 0;
}


static BOOL FYOCRRefinementReplacesItem(OCRTextItem *coarse, OCRTextItem *fine) {
    CGRect a=coarse.boundingBox,b=fine.boundingBox;
    CGFloat y=MIN(CGRectGetMaxY(a),CGRectGetMaxY(b))-MAX(CGRectGetMinY(a),CGRectGetMinY(b));
    CGFloat x=MIN(CGRectGetMaxX(a),CGRectGetMaxX(b))-MAX(CGRectGetMinX(a),CGRectGetMinX(b));
    return b.size.height>=a.size.height*.6 && y>MIN(a.size.height,b.size.height)*.45 && x>0;
}

static BOOL FYOCRRefinementDuplicatesSingleLine(OCRTextItem *coarse, OCRTextItem *fine) {
    // A tighter glyph box can fall below the height replacement gate even
    // though both passes read the same physical line. Require matching content,
    // aligned centers and near-full coverage; text alone cannot remove a row.
    if (coarse.lineCount>1 || fine.lineCount>1 || coarse.lineTexts.count>1 || fine.lineTexts.count>1 ||
        [coarse.text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound ||
        [fine.text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound) return NO;
    NSString *text=FYNormalizeOCRTextForComparison(coarse.text);
    if (text.length<2 || ![text isEqualToString:FYNormalizeOCRTextForComparison(fine.text)]) return NO;
    CGRect a=coarse.boundingBox,b=fine.boundingBox,hit=CGRectIntersection(a,b);
    CGFloat area=MIN(a.size.width*a.size.height,b.size.width*b.size.height);
    if (area<=0 || CGRectIsNull(hit) || CGRectIsEmpty(hit)) return NO;
    return hit.size.width>=MAX(a.size.width,b.size.width)*.85 &&
        hit.size.width*hit.size.height>=area*.85 &&
        fabs(CGRectGetMidY(a)-CGRectGetMidY(b))<=MAX(a.size.height,b.size.height)*.25;
}

static NSArray<NSValue *> *FYOCRQuoteRanges(NSString *text) {
    // Some games print the closing curly glyph on both sides of a word.
    NSString *openers=@"「『“”‘’\"'", *closers=@"」』””’’\"'";
    NSMutableArray *ranges=[NSMutableArray new];
    for (NSUInteger start=0; start<text.length; start++) {
        NSRange kind=[openers rangeOfString:[text substringWithRange:NSMakeRange(start,1)]];
        if (kind.location==NSNotFound) continue;
        NSString *close=[closers substringWithRange:NSMakeRange(kind.location,1)];
        NSRange end=[text rangeOfString:close options:0 range:NSMakeRange(start+1,text.length-start-1)];
        if (end.location==NSNotFound) continue;
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(start,end.location-start+1)]];
        start=end.location;
    }
    return ranges;
}

static BOOL FYOCRRefinementLosesQuotation(OCRTextItem *coarse, OCRTextItem *fine) {
    if (coarse.lineCount>1 || fine.lineCount>1 || coarse.lineTexts.count>1 || fine.lineTexts.count>1 ||
        [coarse.text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound ||
        [fine.text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound) return NO;
    CGRect a=coarse.boundingBox,b=fine.boundingBox;
    CGFloat overlap=MIN(CGRectGetMaxX(a),CGRectGetMaxX(b))-MAX(CGRectGetMinX(a),CGRectGetMinX(b));
    if (!FYOCRRefinementReplacesItem(coarse,fine) || overlap<MAX(a.size.width,b.size.width)*.65) return NO;
    NSString *original=FYNormalizeOCRTextForComparison(coarse.text), *replacement=FYNormalizeOCRTextForComparison(fine.text);
    NSArray<NSValue *> *quotes=FYOCRQuoteRanges(original);
    if (quotes.count!=1) return NO; // Ambiguous/nested or multiple quotations keep the normal policy.
    NSRange span=quotes.firstObject.rangeValue;
    NSString *word=[original substringWithRange:NSMakeRange(span.location+1,span.length-2)];
    NSCharacterSet *quoteGlyphs=[NSCharacterSet characterSetWithCharactersInString:@"「」『』“”‘’\"'"];
    if ([word rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet].location==NSNotFound ||
        [word rangeOfCharacterFromSet:quoteGlyphs].location!=NSNotFound) return NO;
    NSString *prefix=[original substringToIndex:span.location], *suffix=[original substringFromIndex:NSMaxRange(span)];
    if (!FYContainsJapaneseKana([prefix stringByAppendingString:suffix]) ||
        replacement.length<prefix.length+suffix.length || (prefix.length && ![replacement hasPrefix:prefix]) ||
        (suffix.length && ![replacement hasSuffix:suffix])) return NO;
    NSString *middle=[replacement substringWithRange:NSMakeRange(prefix.length,replacement.length-prefix.length-suffix.length)];
    NSString *bare=[[middle componentsSeparatedByCharactersInSet:quoteGlyphs] componentsJoinedByString:@""];
    if ([bare isEqualToString:word]) return NO; // Removing quote punctuation alone did not lose the word.
    for (NSValue *value in FYOCRQuoteRanges(middle)) {
        NSRange range=value.rangeValue;
        NSString *content=[middle substringWithRange:NSMakeRange(range.location+1,range.length-2)];
        if ([content rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet].location!=NSNotFound) return NO;
    }
    // Reject only deletion/empty quotes or a short malformed quoted reading,
    // with an otherwise identical sentence. A complete corrected quotation wins.
    return !middle.length || (middle.length<=span.length &&
        [middle rangeOfCharacterFromSet:quoteGlyphs].location!=NSNotFound);
}

@interface FYOCRRefinementTrack : NSObject
@property(nonatomic, copy) NSString *coarseText, *refinedText;
@property(nonatomic) CGRect box;
@property(nonatomic) NSUInteger coarseHits, refinedHits;
@property(nonatomic) BOOL preferCoarse;
@end
@implementation FYOCRRefinementTrack
@end

@interface FYOCRRefinementStabilizer ()
@property(nonatomic, readwrite) NSUInteger fallbackCount;
@property(nonatomic, copy) NSArray<FYOCRRefinementTrack *> *tracks;
@end
@implementation FYOCRRefinementStabilizer
- (void)reset { self.tracks=@[]; self.fallbackCount=0; }
- (NSArray<OCRTextItem *> *)observeCoarseItems:(NSArray<OCRTextItem *> *)coarse
                                refinedItems:(NSArray<OCRTextItem *> *)refined {
    NSMutableArray *selected=[NSMutableArray arrayWithArray:refined ?: @[]];
    NSMutableArray *next=[NSMutableArray new];
    NSMutableSet *used=[NSMutableSet new];
    self.fallbackCount=0;
    for (OCRTextItem *original in coarse) {
        NSIndexSet *matches=[refined indexesOfObjectsPassingTest:^BOOL(OCRTextItem *fine, NSUInteger i, BOOL *stop) {
            return FYOCRRefinementReplacesItem(original,fine);
        }];
        if (matches.count!=1) continue;
        NSUInteger index=matches.firstIndex;
        OCRTextItem *fine=refined[index];
        NSUInteger covered=0;
        for (OCRTextItem *item in coarse) if (FYOCRRefinementReplacesItem(item,fine)) covered++;
        CGRect a=original.boundingBox,b=fine.boundingBox;
        CGFloat overlap=MIN(CGRectGetMaxX(a),CGRectGetMaxX(b))-MAX(CGRectGetMinX(a),CGRectGetMinX(b));
        // Do not veto a split/merged paragraph or a partial crop. Such candidates
        // may recover previously unknown lines and keep the existing merge policy.
        if (covered!=1 || overlap<MAX(a.size.width,b.size.width)*.65) continue;
        NSString *coarseText=FYNormalizeOCRTextForComparison(original.text);
        NSString *fineText=FYNormalizeOCRTextForComparison(fine.text);
        if (!coarseText.length || !fineText.length) continue;
        FYOCRRefinementTrack *previous=nil;
        CGFloat best=0;
        for (FYOCRRefinementTrack *track in self.tracks) {
            if ([used containsObject:track] || ![coarseText isEqual:track.coarseText]) continue;
            CGRect hit=CGRectIntersection(a,track.box);
            CGFloat area=a.size.width*a.size.height+track.box.size.width*track.box.size.height;
            CGFloat intersection=CGRectIsEmpty(hit) ? 0 : hit.size.width*hit.size.height;
            CGFloat score=intersection/MAX((CGFloat).000001,area-intersection);
            if (score>.6 && score>best) { previous=track; best=score; }
        }
        if (previous) [used addObject:previous];
        FYOCRRefinementTrack *track=[FYOCRRefinementTrack new];
        track.coarseText=coarseText; track.refinedText=fineText; track.box=a;
        track.coarseHits=previous ? MIN(previous.coarseHits+1,3) : 1;
        track.refinedHits=[fineText isEqual:previous.refinedText] ? MIN(previous.refinedHits+1,3) : 1;
        track.preferCoarse=previous.preferCoarse;
        if (track.coarseHits>=2 && previous && ![fineText isEqual:previous.refinedText]) track.preferCoarse=YES;
        // Once refinement has jittered, require three uninterrupted hits to
        // restore it. Two-frame bursts must not repeatedly reopen instability.
        if (track.refinedHits>=3) track.preferCoarse=NO;
        if (track.preferCoarse) { selected[index]=original; self.fallbackCount++; }
        [next addObject:track];
    }
    self.tracks=next; // Missing/ambiguous lines break consecutive evidence.
    return [FYOCRRefinement mergeCoarseItems:coarse refinedItems:selected];
}
@end


BOOL FYOCRRefinementRegion(NSArray<OCRTextItem *> *blocks, BOOL autoFit, CGFloat fittedArea, CGRect *outRegion) {
    if (!autoFit || !(fittedArea > 0 && fittedArea <= .16) || !blocks.count) return NO;
    CGFloat minX=1,minY=1,maxX=0,maxY=0; BOOL any=NO;
    for (OCRTextItem *block in blocks) {
        if (FYNormalizeOCRTextForComparison(block.text).length < 2) continue;
        CGRect b=block.boundingBox;
        minX=MIN(minX,CGRectGetMinX(b));minY=MIN(minY,CGRectGetMinY(b));
        maxX=MAX(maxX,CGRectGetMaxX(b));maxY=MAX(maxY,CGRectGetMaxY(b));any=YES;
    }
    if (!any) return NO;
    minX=MAX(0,minX-.03);minY=MAX(0,minY-.03);
    maxX=MIN(1,maxX+.03);maxY=MIN(1,maxY+.03);
    if (outRegion) *outRegion=CGRectMake(minX,minY,MAX((CGFloat).05,maxX-minX),MAX((CGFloat).05,maxY-minY));
    return YES;
}

static CGFloat FYOCRTextCoverage(NSString *text, NSString *covered) {
    if (text.length == 0) { return 0; }
    NSMutableDictionary<NSString *, NSNumber *> *pool = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < covered.length; index++) {
        NSString *unit = [covered substringWithRange:NSMakeRange(index, 1)];
        pool[unit] = @(pool[unit].integerValue + 1);
    }
    NSUInteger coveredCount = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        NSString *unit = [text substringWithRange:NSMakeRange(index, 1)];
        NSInteger available = pool[unit].integerValue;
        if (available > 0) { pool[unit] = @(available - 1); coveredCount += 1; }
    }
    return (CGFloat)coveredCount / (CGFloat)text.length;
}

@implementation FYOCRRefinement
+ (NSArray<OCRTextItem *> *)resolveOverlappingItems:(NSArray<OCRTextItem *> *)items {
    if (items.count < 2) { return items ?: @[]; }
    NSMutableIndexSet *redundant = [NSMutableIndexSet indexSet];
    for (NSUInteger outerIndex = 0; outerIndex < items.count; outerIndex++) {
        if ([redundant containsIndex:outerIndex]) { continue; }
        OCRTextItem *outer = items[outerIndex]; CGRect outerBox = outer.boundingBox;
        CGFloat outerArea = outerBox.size.width * outerBox.size.height;
        NSString *outerText = FYNormalizeOCRTextForComparison(outer.text ?: @"");
        if (outerArea <= 0 || outerText.length == 0) { continue; }
        NSMutableArray<NSNumber *> *insideIndexes = [NSMutableArray array]; CGFloat coveredArea = 0;
        for (NSUInteger innerIndex = 0; innerIndex < items.count; innerIndex++) {
            if (innerIndex == outerIndex || [redundant containsIndex:innerIndex]) { continue; }
            OCRTextItem *inner = items[innerIndex]; CGRect box = inner.boundingBox;
            CGFloat boxArea = box.size.width * box.size.height; if (boxArea <= 0) { continue; }
            CGRect intersection = CGRectIntersection(outerBox, box); if (CGRectIsNull(intersection)) { continue; }
            CGFloat intersectionArea = intersection.size.width * intersection.size.height;
            if (intersectionArea / boxArea < 0.85) { continue; }
            if (CGRectGetWidth(box) >= CGRectGetWidth(outerBox) - 0.001 && CGRectGetHeight(box) >= CGRectGetHeight(outerBox) - 0.001 && innerIndex > outerIndex) { continue; }
            [insideIndexes addObject:@(innerIndex)]; coveredArea += intersectionArea;
        }
        if (insideIndexes.count == 0 || coveredArea / outerArea < 0.85) { continue; }
        NSArray<NSNumber *> *sorted = [insideIndexes sortedArrayUsingComparator:^NSComparisonResult(NSNumber *left, NSNumber *right) {
            // Preserve the original coverage traversal; coverage itself counts characters.
            OCRTextItem *a = items[left.unsignedIntegerValue];
            OCRTextItem *b = items[right.unsignedIntegerValue];
            CGFloat delta = CGRectGetMaxY(b.boundingBox) - CGRectGetMaxY(a.boundingBox);
            if (fabs(delta) > 0.025) { return delta > 0 ? NSOrderedAscending : NSOrderedDescending; }
            if (a.boundingBox.origin.x < b.boundingBox.origin.x) { return NSOrderedAscending; }
            if (a.boundingBox.origin.x > b.boundingBox.origin.x) { return NSOrderedDescending; }
            return NSOrderedSame;
        }];
        NSMutableString *innerRaw = [NSMutableString string];
        for (NSNumber *index in sorted) [innerRaw appendString:FYNormalizeOCRTextForComparison(items[index.unsignedIntegerValue].text ?: @"")];
        if (innerRaw.length == 0) { continue; }
        if (FYOCRTextCoverage(outerText, innerRaw) >= 0.8 && FYOCRTextCoverage(innerRaw, outerText) >= 0.8) [redundant addIndex:outerIndex];
    }
    if (redundant.count == 0) { return items; }
    NSMutableArray<OCRTextItem *> *kept = [NSMutableArray array];
    for (NSUInteger index = 0; index < items.count; index++) if (![redundant containsIndex:index]) [kept addObject:items[index]];
    return kept;
}

+ (NSArray<OCRTextItem *> *)mergeCoarseItems:(NSArray<OCRTextItem *> *)coarse refinedItems:(NSArray<OCRTextItem *> *)refined {
    if (!refined.count) { return [self resolveOverlappingItems:coarse]; }
    NSMutableArray<OCRTextItem *> *selected = [refined mutableCopy];
    for (OCRTextItem *original in coarse) {
        NSIndexSet *matches=[refined indexesOfObjectsPassingTest:^BOOL(OCRTextItem *fine, NSUInteger index, BOOL *stop) {
            return FYOCRRefinementReplacesItem(original,fine);
        }];
        if (matches.count!=1) continue;
        OCRTextItem *fine=refined[matches.firstIndex];
        NSUInteger covered=0;
        for (OCRTextItem *item in coarse) if (FYOCRRefinementReplacesItem(item,fine)) covered++;
        if (covered==1 && FYOCRRefinementLosesQuotation(original,fine)) selected[matches.firstIndex]=original;
    }
    NSMutableArray<OCRTextItem *> *merged = [selected mutableCopy];
    for (OCRTextItem *original in coarse) {
        BOOL replaced = NO;
        for (OCRTextItem *better in selected) {
            if (FYOCRRefinementReplacesItem(original,better) ||
                FYOCRRefinementDuplicatesSingleLine(original,better)) { replaced = YES; break; }
        }
        if (!replaced) [merged addObject:original];
    }
    [merged sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) { return FYOCRReadingOrder(left, right); }];
    return [self resolveOverlappingItems:merged];
}
@end
