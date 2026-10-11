#import "FYOCRManager.h"
#import "FYInlineLayoutDebug.h"
#import <Vision/Vision.h>

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
        : [FYOCRManager mergeCoarseItems:coarse refinedItems:fineBlocks];
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

@implementation FYOCRStabilityOwner
- (BOOL)observe:(NSString *)normalized equivalent:(BOOL (^)(NSString *, NSString *))equivalent {
    if (equivalent(normalized,self.candidate)) self.count++;
    else { self.candidate=normalized; self.count=1; }
    return self.count>=2;
}
- (void)reset { self.candidate=@""; self.count=0; }
@end

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
    if (![FYContentRouter containsJapaneseKana:[prefix stringByAppendingString:suffix]] ||
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
    return [FYOCRManager mergeCoarseItems:coarse refinedItems:selected];
}
@end

@interface FYInlineOCRTrack : NSObject
@property(nonatomic, strong) OCRTextItem *item;
@property(nonatomic, copy) NSString *pendingText;
@property(nonatomic) NSInteger pendingTextHits;
@property(nonatomic) NSInteger pendingGeometryHits;
@property(nonatomic) CGRect pendingGeometry;
@property(nonatomic) InlineBlockKind pendingKind;
@property(nonatomic) NSInteger missingHits;
@end
@implementation FYInlineOCRTrack
@end

@interface FYInlineOCRFrameStabilizer ()
@property(nonatomic, readwrite) BOOL ready;
@property(nonatomic, strong) NSMutableArray<FYInlineOCRTrack *> *tracks;
@property(nonatomic, copy) NSArray<OCRTextItem *> *openingFrame;
@property(nonatomic, copy) NSArray<OCRTextItem *> *pageCandidate;
@property(nonatomic) NSInteger pageCandidateHits;
@property(nonatomic, strong) NSMutableArray<FYInlineOCRTrack *> *pendingAdditions;
@property(nonatomic) NSInteger blankHits;
@end

static OCRTextItem *FYCopyInlineOCRItem(OCRTextItem *source) {
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

static NSArray<OCRTextItem *> *FYCopyInlineOCRFrame(NSArray<OCRTextItem *> *items) {
    NSMutableArray *copies = [NSMutableArray arrayWithCapacity:items.count];
    for (OCRTextItem *item in items) { [copies addObject:FYCopyInlineOCRItem(item)]; }
    return copies;
}

static CGFloat FYInlineOCRGeometryDelta(CGRect a, CGRect b) {
    return MAX(MAX(fabs(NSMinX(a)-NSMinX(b)), fabs(NSMinY(a)-NSMinY(b))),
               MAX(fabs(NSWidth(a)-NSWidth(b)), fabs(NSHeight(a)-NSHeight(b))));
}

static CGRect FYInlineOCRMapRect(CGRect box, CGRect from, CGRect to) {
    CGFloat sx = NSWidth(to) / MAX((CGFloat)0.0001, NSWidth(from));
    CGFloat sy = NSHeight(to) / MAX((CGFloat)0.0001, NSHeight(from));
    return CGRectMake(NSMinX(to) + (NSMinX(box)-NSMinX(from))*sx,
                      NSMinY(to) + (NSMinY(box)-NSMinY(from))*sy, NSWidth(box)*sx, NSHeight(box)*sy);
}

static CGFloat FYInlineOCRMatchScore(OCRTextItem *left, OCRTextItem *right) {
    CGRect a = left.boundingBox, b = right.boundingBox;
    CGRect hit = CGRectIntersection(a, b);
    CGFloat areaA = NSWidth(a) * NSHeight(a), areaB = NSWidth(b) * NSHeight(b);
    CGFloat areaHit = CGRectIsNull(hit) || CGRectIsEmpty(hit) ? 0 : NSWidth(hit) * NSHeight(hit);
    CGFloat unionArea = areaA + areaB - areaHit;
    CGFloat overlap = unionArea > 0 ? areaHit / unionArea : 0;
    NSString *aText = FYNormalizeOCRTextForComparison(left.text);
    NSString *bText = FYNormalizeOCRTextForComparison(right.text);
    CGFloat dx = fabs(NSMidX(a) - NSMidX(b)), dy = fabs(NSMidY(a) - NSMidY(b));
    if (overlap < 0.12 && !([aText isEqualToString:bText] && dx < 0.025 && dy < 0.025)) { return 0; }
    return overlap + ([aText isEqualToString:bText] ? 1.0 : 0.0);
}

static NSUInteger FYInlineOCRFrameMatches(NSArray<OCRTextItem *> *left, NSArray<OCRTextItem *> *right, BOOL sameText) {
    NSMutableIndexSet *used = [NSMutableIndexSet indexSet];
    NSUInteger matched = 0;
    for (OCRTextItem *item in left) {
        CGFloat best = 0;
        NSInteger bestIndex = -1;
        for (NSUInteger index = 0; index < right.count; index++) {
            if ([used containsIndex:index]) { continue; }
            CGFloat score = FYInlineOCRMatchScore(item, right[index]);
            if (sameText && ![item.text isEqualToString:right[index].text]) { continue; }
            if (score > best) { best = score; bestIndex = (NSInteger)index; }
        }
        if (bestIndex >= 0) { [used addIndex:(NSUInteger)bestIndex]; matched++; }
    }
    return matched;
}

@implementation FYInlineOCRFrameStabilizer
- (void)reset {
    self.ready = NO;
    self.tracks = nil;
    self.openingFrame = nil;
    self.pageCandidate = nil;
    self.pageCandidateHits = 0;
    self.pendingAdditions = nil;
    self.blankHits = 0;
}
- (void)acceptFrame:(NSArray<OCRTextItem *> *)items {
    self.tracks = [NSMutableArray arrayWithCapacity:items.count];
    for (OCRTextItem *item in items) {
        FYInlineOCRTrack *track = [FYInlineOCRTrack new];
        track.item = FYCopyInlineOCRItem(item);
        [self.tracks addObject:track];
    }
    self.ready = YES;
    self.openingFrame = nil;
    self.pageCandidate = nil;
    self.pageCandidateHits = 0;
    self.pendingAdditions = [NSMutableArray array];
}
- (NSArray<OCRTextItem *> *)acceptedItems {
    NSMutableArray<OCRTextItem *> *items = [NSMutableArray arrayWithCapacity:self.tracks.count];
    for (FYInlineOCRTrack *track in self.tracks) { [items addObject:track.item]; }
    return items;
}
- (NSArray<OCRTextItem *> *)itemsPreservingConfirmedBoundaries:(NSArray<OCRTextItem *> *)items {
    NSMutableArray *result = [NSMutableArray array];
    for (OCRTextItem *seen in items) {
        NSMutableArray<OCRTextItem *> *parts = [NSMutableArray array];
        NSString *text = FYNormalizeOCRTextForComparison(seen.text);
        for (FYInlineOCRTrack *track in self.tracks) {
            CGRect box = track.item.boundingBox;
            CGRect hit = CGRectIntersection(box, seen.boundingBox);
            CGFloat area = NSWidth(box) * NSHeight(box);
            NSString *partText = FYNormalizeOCRTextForComparison(track.item.text);
            if (partText.length && [text containsString:partText] && area > 0 &&
                !CGRectIsNull(hit) && NSWidth(hit) * NSHeight(hit) / area >= 0.65) {
                [parts addObject:track.item];
            }
        }
        [parts sortUsingComparator:^NSComparisonResult(OCRTextItem *a, OCRTextItem *b) {
            return [[NSNumber numberWithUnsignedInteger:[text rangeOfString:FYNormalizeOCRTextForComparison(a.text)].location]
                compare:@([text rangeOfString:FYNormalizeOCRTextForComparison(b.text)].location)];
        }];
        NSString *joined = FYNormalizeOCRTextForComparison([[parts valueForKey:@"text"] componentsJoinedByString:@"\n"]);
        // A union observation containing the exact same independently confirmed
        // fields is evidence that they still exist, not that their boundary vanished.
        // Different text or a genuinely different layout follows normal confirmation.
        NSArray *output = @[seen];
        if (parts.count >= 2 && [joined isEqualToString:text]) {
            CGRect unionBox = parts.firstObject.boundingBox;
            for (OCRTextItem *part in parts) { unionBox = CGRectUnion(unionBox, part.boundingBox); }
            NSMutableArray *mapped = [NSMutableArray array];
            for (OCRTextItem *part in parts) {
                OCRTextItem *copy = FYCopyInlineOCRItem(part);
                copy.boundingBox = FYInlineOCRMapRect(part.boundingBox, unionBox, seen.boundingBox);
                if (!CGRectIsEmpty(part.lastLineBox)) { copy.lastLineBox = FYInlineOCRMapRect(part.lastLineBox, unionBox, seen.boundingBox); }
                NSMutableArray *boxes = [NSMutableArray array];
                for (NSValue *box in part.lineBoxes) {
                    [boxes addObject:[NSValue valueWithRect:FYInlineOCRMapRect(box.rectValue, unionBox, seen.boundingBox)]];
                }
                copy.lineBoxes = boxes; [mapped addObject:copy];
            }
            output = mapped;
        }
        for (OCRTextItem *part in output) {
            BOOL duplicate = NO;
            for (OCRTextItem *kept in result) {
                if ([part.text isEqualToString:kept.text] && FYInlineOCRMatchScore(part, kept) > 1.5) { duplicate = YES; break; }
            }
            if (!duplicate) { [result addObject:part]; }
        }
    }
    return result;
}
- (NSArray<OCRTextItem *> *)observeItems:(NSArray<OCRTextItem *> *)items {
    items = items ?: @[];
    if (items.count == 0) {
        self.pendingAdditions = nil;
        self.pageCandidate = nil;
        self.pageCandidateHits = 0;
        self.openingFrame = nil;
        for (FYInlineOCRTrack *track in self.tracks) {
            track.pendingText = nil; track.pendingTextHits = 0; track.pendingGeometryHits = 0;
        }
        self.blankHits++;
        if (self.blankHits >= 3) { [self reset]; }
        return self.ready ? [self acceptedItems] : @[];
    }
    self.blankHits = 0;
    if (!self.ready) {
        if (self.openingFrame.count > 0 &&
            FYInlineOCRFrameMatches(self.openingFrame, items, YES) >= MAX(self.openingFrame.count, items.count) * 0.65) {
            [self acceptFrame:items];
            return [self acceptedItems];
        }
        self.openingFrame = FYCopyInlineOCRFrame(items);
        return @[];
    }

    NSArray<OCRTextItem *> *accepted = [self acceptedItems];
    NSUInteger matches = FYInlineOCRFrameMatches(accepted, items, NO);
    if (accepted.count >= 3 && items.count >= 3 && matches < MIN(accepted.count, items.count) * 0.40) {
        if (self.pageCandidate.count > 0 &&
            FYInlineOCRFrameMatches(self.pageCandidate, items, YES) >= MAX(self.pageCandidate.count, items.count) * 0.60) {
            self.pageCandidateHits++;
        } else {
            self.pageCandidate = FYCopyInlineOCRFrame(items);
            self.pageCandidateHits = 1;
        }
        if (self.pageCandidateHits >= 2) { [self acceptFrame:items]; }
        return [self acceptedItems];
    }
    self.pageCandidate = nil;
    self.pageCandidateHits = 0;

    items = [self itemsPreservingConfirmedBoundaries:items];

    // Pair by strongest geometry/text evidence globally. A temporary merged
    // OCR box overlaps two old rows, but can replace at most one of them.
    NSMutableIndexSet *usedTracks = [NSMutableIndexSet indexSet];
    NSMutableIndexSet *usedItems = [NSMutableIndexSet indexSet];
    NSMutableArray<NSArray<NSNumber *> *> *scores = [NSMutableArray arrayWithCapacity:self.tracks.count];
    for (FYInlineOCRTrack *track in self.tracks) {
        NSMutableArray *row = [NSMutableArray arrayWithCapacity:items.count];
        for (OCRTextItem *item in items) { [row addObject:@(FYInlineOCRMatchScore(track.item, item))]; }
        [scores addObject:row];
    }
    while (YES) {
        CGFloat best = 0;
        NSInteger trackIndex = -1, itemIndex = -1;
        for (NSUInteger t = 0; t < self.tracks.count; t++) {
            if ([usedTracks containsIndex:t]) { continue; }
            for (NSUInteger i = 0; i < items.count; i++) {
                if ([usedItems containsIndex:i]) { continue; }
                CGFloat score = scores[t][i].doubleValue;
                if (score > best) { best = score; trackIndex = (NSInteger)t; itemIndex = (NSInteger)i; }
            }
        }
        if (trackIndex < 0) { break; }
        [usedTracks addIndex:(NSUInteger)trackIndex];
        [usedItems addIndex:(NSUInteger)itemIndex];
        FYInlineOCRTrack *track = self.tracks[(NSUInteger)trackIndex];
        OCRTextItem *seen = items[(NSUInteger)itemIndex];
        track.missingHits = 0;
        if ([track.item.text isEqualToString:seen.text] && track.item.blockKind == seen.blockKind) {
            track.pendingText = nil;
            track.pendingTextHits = 0;
            CGRect old = track.item.boundingBox, now = seen.boundingBox;
            CGFloat delta = FYInlineOCRGeometryDelta(old, now);
            if (delta >= 0.010) {
                track.pendingGeometryHits = track.pendingGeometryHits > 0 &&
                    FYInlineOCRGeometryDelta(track.pendingGeometry, now) < 0.005 ? track.pendingGeometryHits + 1 : 1;
                track.pendingGeometry = now;
                if (track.pendingGeometryHits >= 2) { track.item = FYCopyInlineOCRItem(seen); track.pendingGeometryHits = 0; }
            } else { track.pendingGeometryHits = 0; }
        } else {
            track.pendingGeometryHits = 0;
            if ([track.pendingText isEqualToString:seen.text] && track.pendingKind == seen.blockKind) { track.pendingTextHits++; }
            else { track.pendingText = seen.text; track.pendingKind = seen.blockKind; track.pendingTextHits = 1; }
            if (track.pendingTextHits >= 3) {
                track.item = FYCopyInlineOCRItem(seen);
                track.pendingText = nil;
                track.pendingTextHits = 0;
                track.pendingGeometryHits = 0;
            }
        }
    }
    NSMutableIndexSet *expired = [NSMutableIndexSet indexSet];
    for (NSUInteger t = 0; t < self.tracks.count; t++) {
        if ([usedTracks containsIndex:t]) { continue; }
        FYInlineOCRTrack *track = self.tracks[t];
        track.pendingText = nil; track.pendingTextHits = 0; track.pendingGeometryHits = 0;
        track.missingHits++;
        if (track.missingHits >= 3) { [expired addIndex:t]; }
    }
    [self.tracks removeObjectsAtIndexes:expired];

    NSMutableArray<FYInlineOCRTrack *> *nextNew = [NSMutableArray array];
    for (NSUInteger i = 0; i < items.count; i++) {
        if ([usedItems containsIndex:i]) { continue; }
        OCRTextItem *seen = items[i];
        FYInlineOCRTrack *prior = nil;
        for (FYInlineOCRTrack *candidate in [self.pendingAdditions copy]) {
            if ([candidate.item.text isEqualToString:seen.text] && FYInlineOCRMatchScore(candidate.item, seen) > 0) {
                prior = candidate; [self.pendingAdditions removeObject:candidate]; break;
            }
        }
        FYInlineOCRTrack *track = prior ?: [FYInlineOCRTrack new];
        track.item = FYCopyInlineOCRItem(seen);
        track.pendingTextHits = prior ? prior.pendingTextHits + 1 : 1;
        if (track.pendingTextHits >= 2) { [self.tracks addObject:track]; }
        else { [nextNew addObject:track]; }
    }
    self.pendingAdditions = nextNew;
    return [self acceptedItems];
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

// Modal detector thresholds: RGB mean on 0..255 pixels, dimensionless fractions.
// Keep these together for tuning; values intentionally preserve the established detector.
static const double kFYModalBrightThreshold = 150.0;
static const double kFYModalDimThreshold = 140.0;
static const double kFYModalMinColumnFraction = 0.45;
static const double kFYModalMinRowBrightFraction = 0.55;
static const double kFYModalMinRunFraction = 0.15;
static const size_t kFYModalMinRunPixels = 8;
static const double kFYModalDimColumnFraction = 0.62;

static void FYFreeExcludedMask(unsigned char **buffer) {
    free(*buffer);
    *buffer = NULL;
}

// 找出画面里那块“大白矩形”（详情弹窗 / 模态窗），返回它在**归一化底左坐标**下的范围。
// 依据：模态窗一定是一块又大又亮、轮廓连续的矩形；
// 而被压暗的底层页面虽然也有亮像素，但成不了这种又大又连片的区域。
// 找不到就返回 NO（当帧不裁剪）。
BOOL FYDetectBrightOCRContentRegion(const unsigned char *pixels,
                                      size_t width,
                                      size_t height,
                                      size_t bytesPerRow,
                                      CGRect *outNormalizedRect,
                                      BOOL *outDimmedColumns,
                                      const CGRect *exclusions,
                                      size_t exclusionCount) {
    if (!pixels || width < 8 || height < 8) { return NO; }

    // 把自己浮窗覆盖的像素预先标进一张位图。
    // 之前是对每个像素遍历一遍所有面板（13 万像素 × 20 个面板 ≈ 260 万次循环），
    // 跑在主线程上直接让界面卡住十几秒。
    __attribute__((cleanup(FYFreeExcludedMask))) unsigned char *excludedMask = NULL;
    if (exclusionCount > 0) {
        excludedMask = (unsigned char *)calloc(width * height, 1);
        if (!excludedMask) { return NO; }
        for (size_t i = 0; i < exclusionCount; i++) {
            CGRect r = exclusions[i];
            size_t x0 = (size_t)MAX(0, r.origin.x * width);
            size_t x1 = (size_t)MIN((CGFloat)width, CGRectGetMaxX(r) * width);
            size_t y0 = (size_t)MAX(0, (1.0 - CGRectGetMaxY(r)) * height);
            size_t y1 = (size_t)MIN((CGFloat)height, (1.0 - r.origin.y) * height);
            for (size_t y = y0; y < y1; y++) {
                for (size_t x = x0; x < x1; x++) { excludedMask[y * width + x] = 1; }
            }
        }
    }
    #define FUYI_EXCLUDED(px, py) (excludedMask != NULL && excludedMask[(py) * width + (px)] != 0)

    const size_t minRunColumns = MAX(kFYModalMinRunPixels, (size_t)(width * kFYModalMinRunFraction));
    const size_t minRunRows = MAX(kFYModalMinRunPixels, (size_t)(height * kFYModalMinRunFraction));

    size_t bestX0 = 0, bestXLen = 0, run = 0;
    for (size_t x = 0; x <= width; x++) {
        BOOL ok = NO;
        if (x < width) {
            size_t bright = 0, considered = 0;
            for (size_t y = 0; y < height; y++) {
                if (FUYI_EXCLUDED(x, y)) { continue; }
                const unsigned char *pixel = pixels + y * bytesPerRow + x * 4;
                considered += 1;
                if ((pixel[0] + pixel[1] + pixel[2]) / 3.0 >= kFYModalBrightThreshold) { bright += 1; }
            }
            ok = (considered >= height / 4) && (((double)bright / (double)considered) >= kFYModalMinColumnFraction);
        }
        if (ok) {
            if (run == 0) { run = 1; } else { run += 1; }
        } else {
            if (run > bestXLen) { bestXLen = run; bestX0 = x - run; }
            run = 0;
        }
    }
    if (bestXLen < minRunColumns) { return NO; }

    // 纵向：仍然只在**已确定的列范围**里找最长连续亮段 —— 必须用“亮”而不是“没被压暗”。
    // 曾经为了不切掉橙色页眉，把判据改成“有没有被压暗”，结果上半屏（被压得较浅的页面）
    // 也满足条件，弹窗范围变成 y 0.09..0.83（几乎整屏），左边栏目的译文就又冒出来了。
    // 宁可靠外层把范围向下外扩一点来容纳页眉页脚。
    size_t bestY0 = 0, bestYLen = 0;
    run = 0;
    for (size_t y = 0; y <= height; y++) {
        BOOL brightRow = NO;
        if (y < height) {
            const unsigned char *row = pixels + y * bytesPerRow;
            size_t bright = 0;
            size_t considered = 0;
            for (size_t x = bestX0; x < bestX0 + bestXLen; x++) {
                if (FUYI_EXCLUDED(x, y)) { continue; }
                const unsigned char *pixel = row + x * 4;
                if ((pixel[0] + pixel[1] + pixel[2]) / 3.0 >= kFYModalBrightThreshold) { bright += 1; }
                considered += 1;
            }
            brightRow = (considered >= bestXLen / 4) &&
                        (((double)bright / (double)considered) >= kFYModalMinRowBrightFraction);
        }
        if (brightRow) {
            if (run == 0) { run = 1; } else { run += 1; }
        } else {
            if (run > bestYLen) { bestYLen = run; bestY0 = y - run; }
            run = 0;
        }
    }
    if (bestYLen < minRunRows) { return NO; }

    // 压暗掩码：落在被压暗的列上、且位于弹窗之外的地方，属于“上一级残留文字”
    if (outDimmedColumns) {
        for (size_t x = 0; x < width; x++) { outDimmedColumns[x] = NO; }
        for (size_t x = 0; x < width; x++) {
            size_t dim = 0;
            for (size_t y = 0; y < height; y++) {
                if (FUYI_EXCLUDED(x, y)) { continue; }
                const unsigned char *pixel = pixels + y * bytesPerRow + x * 4;
                if ((pixel[0] + pixel[1] + pixel[2]) / 3.0 < kFYModalDimThreshold) { dim += 1; }
            }
            outDimmedColumns[x] = ((double)dim / (double)height) > kFYModalDimColumnFraction;
        }
    }

    // 位图 y 是从上往下，转回 Vision 的底左原点
    CGFloat nx0 = (CGFloat)bestX0 / (CGFloat)width;
    CGFloat nx1 = (CGFloat)(bestX0 + bestXLen) / (CGFloat)width;
    CGFloat nyTop = (CGFloat)bestY0 / (CGFloat)height;
    CGFloat nyBottom = (CGFloat)(bestY0 + bestYLen) / (CGFloat)height;

    *outNormalizedRect = CGRectMake(nx0, 1.0 - nyBottom, nx1 - nx0, nyBottom - nyTop);
    return YES;
}
#undef FUYI_EXCLUDED

// 判断某个文字块是不是压在半透明遮罩上（= 上一级页面残留的文字）。
// OCR 只给文字和坐标，读不出明暗，所以这里真的去采样像素：
//   弹窗正文是「深色字 + 亮底」，而被压暗的底层页面是「字和底都偏暗」。
// 用「文字外圈一点的平均亮度」近似底色：够亮才算当前这一层的内容。
BOOL FYOCRBlockSitsOnBrightBackdrop(OCRTextItem *block,
                                      const unsigned char *gray,
                                      size_t width,
                                      size_t height,
                                      size_t bytesPerRow) {
    if (!gray || width < 4 || height < 4) { return YES; }

    CGFloat minX = CGRectGetMinX(block.boundingBox) * (CGFloat)width;
    CGFloat maxX = CGRectGetMaxX(block.boundingBox) * (CGFloat)width;
    // Vision 的 y 是底左原点，位图是从上往下存，所以这里要把 y 翻过来
    CGFloat minY = (1.0 - CGRectGetMaxY(block.boundingBox)) * (CGFloat)height;
    CGFloat maxY = (1.0 - CGRectGetMinY(block.boundingBox)) * (CGFloat)height;

    // 往上/下各扩一点作为“底色”采样带（避开文字本身的笔画）
    CGFloat bandTop = MAX(0, minY - 3.0);
    CGFloat bandBottom = MIN((CGFloat)height - 1, maxY + 3.0);
    size_t x0 = (size_t)MAX(0, MIN(minX, (CGFloat)width - 1));
    size_t x1 = (size_t)MAX(0, MIN(maxX, (CGFloat)width - 1));
    if (x1 <= x0) { return YES; }

    double sum = 0;
    size_t count = 0;
    for (size_t y = (size_t)bandTop; y <= (size_t)bandBottom; y += 2) {
        // 只取文字行上下那两条窄带，不统计文字笔画本身
        if (y > (size_t)minY + 1 && y + 1 < (size_t)maxY) { continue; }
        const unsigned char *row = gray + y * bytesPerRow;
        for (size_t x = x0; x <= x1; x += 2) {
            const unsigned char *pixel = row + x * 4;
            sum += (pixel[0] + pixel[1] + pixel[2]) / 3.0;
            count += 1;
        }
    }
    if (count == 0) { return YES; }
    double mean = sum / (double)count;
    return mean >= 150.0;
}

FYOCRPixelBuffer FYCreateOCRPixelBuffer(CGImageRef image) {
    FYOCRPixelBuffer buffer = {NULL, 0, 0, 0, NULL};
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    if (imageWidth < 2 || imageHeight < 2) { return buffer; }

    size_t width = MIN(imageWidth, (size_t)480);
    size_t height = MAX((size_t)2, (size_t)((double)imageHeight * ((double)width / (double)imageWidth)));

    // 用 RGBA 而不是纯灰度：CGBitmapContext 不支持 kCGImageAlphaNone 的灰度格式，
    // 之前传它导致 context 创建失败、缓冲变成 0x0，后面所有判断都退化成“亮底”。
    size_t stride = width * 4;
    unsigned char *pixels = (unsigned char *)calloc(height, stride);
    if (!pixels) { return buffer; }
    // 必须给颜色空间：第三个参数（colorspace）传 NULL 时 CGBitmapContextCreate 会直接失败，
    // 之前就是这样导致缓冲一直是 0x0、所有判断退化成“亮底”。
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, stride, space,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        free(pixels);
        return buffer;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);

    buffer.pixels = pixels;
    buffer.width = width;
    buffer.height = height;
    buffer.bytesPerRow = CGBitmapContextGetBytesPerRow(context);
    buffer.context = context;
    return buffer;
}

void FYReleaseOCRPixelBuffer(FYOCRPixelBuffer *buffer) {
    if (buffer->context) { CGContextRelease(buffer->context); }
    if (buffer->pixels) { free(buffer->pixels); }
    buffer->context = NULL;
    buffer->pixels = NULL;
}

BOOL FYOCRModalSurroundingsAreDimmer(unsigned char *pixels, size_t width, size_t height,
                                       size_t bytesPerRow, CGRect rect) {
    if (!pixels || width == 0 || height == 0) { return NO; }
    CGRect inner = CGRectIntersection(rect, CGRectMake(0, 0, 1, 1));
    if (CGRectIsNull(inner)) { return NO; }
    CGRect outer = CGRectInset(inner, -0.08, -0.08);
    outer = CGRectIntersection(outer, CGRectMake(0, 0, 1, 1));

    double innerSum = 0, outerSum = 0, innerCount = 0, outerCount = 0;
    size_t stepX = MAX((size_t)1, width / 160);
    size_t stepY = MAX((size_t)1, height / 160);
    for (size_t y = 0; y < height; y += stepY) {
        double normalizedY = 1.0 - (double)y / (double)height;
        if (normalizedY < outer.origin.y || normalizedY > CGRectGetMaxY(outer)) { continue; }
        const unsigned char *row = pixels + y * bytesPerRow;
        for (size_t x = 0; x < width; x += stepX) {
            double normalizedX = (double)x / (double)width;
            if (normalizedX < outer.origin.x || normalizedX > CGRectGetMaxX(outer)) { continue; }
            const unsigned char *pixel = row + x * 4;
            double brightness = (pixel[0] + pixel[1] + pixel[2]) / 3.0;
            BOOL insideInner = (normalizedX >= inner.origin.x && normalizedX <= CGRectGetMaxX(inner)
                                && normalizedY >= inner.origin.y && normalizedY <= CGRectGetMaxY(inner));
            if (insideInner) { innerSum += brightness; innerCount += 1; }
            else { outerSum += brightness; outerCount += 1; }
        }
    }
    if (innerCount < 20 || outerCount < 20) { return NO; }
    double innerMean = innerSum / innerCount;
    double outerMean = outerSum / outerCount;
    return (innerMean - outerMean) > 30.0;
}

BOOL FYOCRModalRectQualifiesForCropping(CGRect rect) {
    if (rect.size.width < 0.35 || rect.size.height < 0.16) { return NO; }
    CGFloat centerX = CGRectGetMidX(rect);
    return centerX > 0.40 && centerX < 0.60;
}

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

static NSComparisonResult FYOCRReadingOrder(OCRTextItem *left, OCRTextItem *right) {
    CGFloat delta = CGRectGetMaxY(left.boundingBox) - CGRectGetMaxY(right.boundingBox);
    if (fabs(delta) > 0.025) { return delta > 0 ? NSOrderedAscending : NSOrderedDescending; }
    if (left.boundingBox.origin.x < right.boundingBox.origin.x) { return NSOrderedAscending; }
    if (left.boundingBox.origin.x > right.boundingBox.origin.x) { return NSOrderedDescending; }
    return NSOrderedSame;
}

@implementation FYOCRManager
// A structural label needs both a separate filled backdrop and a following
// dialogue body. Text length/script alone must never suppress spoken lines.
// This operates on the existing downsampled source pixels; no extra OCR,
// screenshots, stored images or game-specific colors are used.
static BOOL FYPlateColorNear(const unsigned char *a, const unsigned char *b) {
    return abs(a[0]-b[0])<=22 && abs(a[1]-b[1])<=22 && abs(a[2]-b[2])<=22;
}
static const unsigned char *FYPlatePixel(FYOCRPixelBuffer *buffer, CGFloat x, CGFloat y) {
    if (!isfinite(x) || !isfinite(y) || x<0 || x>=1 || y<0 || y>=1) { return NULL; }
    // CGBitmapContext row zero is the image's top; OCR has a bottom origin.
    size_t col=MIN(buffer->width-1,(size_t)(x*buffer->width));
    size_t row=MIN(buffer->height-1,(size_t)((1-y)*buffer->height));
    return buffer->pixels+row*buffer->bytesPerRow+col*4;
}
static BOOL FYPlateDominantColor(FYOCRPixelBuffer *buffer, CGRect box, unsigned char *color) {
    unsigned char samples[63][3]; NSUInteger count=0,best=0,bestIndex=0;
    for (NSUInteger row=0;row<7;row++) for (NSUInteger col=0;col<9;col++) {
        const unsigned char *p=FYPlatePixel(buffer,box.origin.x+box.size.width*(col+.5)/9,
            box.origin.y+box.size.height*(row+.5)/7);
        if (!p) { continue; }
        memcpy(samples[count++],p,3);
    }
    if (count*100<7*9*60) { return NO; }
    for (NSUInteger i=0;i<count;i++) {
        NSUInteger hits=0;
        for (NSUInteger j=0;j<count;j++) if (FYPlateColorNear(samples[i],samples[j])) { hits++; }
        if (hits>best) { best=hits;bestIndex=i; }
    }
    if (best*100<count*55) { return NO; }
    memcpy(color,samples[bestIndex],3);return YES;
}
static BOOL FYPlateBodyHasDistinctBackdrop(FYOCRPixelBuffer *buffer, CGRect box, const unsigned char *color) {
    NSUInteger distinct=0,total=0;
    for (NSUInteger row=0;row<7;row++) for (NSUInteger col=0;col<9;col++) {
        const unsigned char *p=FYPlatePixel(buffer,box.origin.x+box.size.width*(col+.5)/9,
            box.origin.y+box.size.height*(row+.5)/7);
        if (!p) { continue; }
        total++;
        if (abs(p[0]-color[0])>=45 || abs(p[1]-color[1])>=45 || abs(p[2]-color[2])>=45) { distinct++; }
    }
    // Translucent dialogue can show a textured scene. It need not have one
    // uniform color, but most of it must differ from the filled name plate.
    // An edge may clip the sampling collar; require 60% of the grid to remain
    // visible, then measure backdrop evidence only among those valid pixels.
    return total*100>=7*9*60 && distinct*100>=total*80;
}
+ (NSArray<OCRTextItem *> *)itemsByMarkingSpeakerLabels:(NSArray<OCRTextItem *> *)items inImage:(CGImageRef)image {
    if (!image) { return items; }
    NSArray<OCRTextItem *> *band=[FYContentRouter subtitleBandItems:items];
    // With just a plate and a very short reply, neither row may satisfy the
    // existing text anchor. Test their pixels without changing mode rules.
    if (band.count<2 && items.count==2) {
        band=[items sortedArrayUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
            return FYOCRReadingOrder(left,right);
        }];
    }
    if (band.count<2) { return items; }
    OCRTextItem *label=band[0],*body=band[1];
    CGRect a=label.boundingBox,b=body.boundingBox;
    // The game can sit above OBS controls. The selected band and local plate
    // geometry supply evidence; its absolute position in the window does not.
    CGFloat widestBody=0;
    for (NSUInteger i=1;i<band.count;i++) widestBody=MAX(widestBody,band[i].boundingBox.size.width);
    CGFloat height=MAX(a.size.height,b.size.height),gap=CGRectGetMinY(a)-CGRectGetMaxY(b);
    if (label.lineCount>1 || label.lineTexts.count>1 ||
        [label.text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound ||
        a.size.width<=0 || a.size.height<=0 ||
        a.size.width>MAX(widestBody*.6,height*2.5) || a.size.height<b.size.height*.35 || a.size.height>b.size.height*1.8 ||
        gap< -height*.25 || gap>height*1.2 ||
        CGRectGetMinX(a)>CGRectGetMinX(b)+height*.5) { return items; }
    FYOCRPixelBuffer buffer=FYCreateOCRPixelBuffer(image);
    if (!buffer.pixels) { return items; }
    unsigned char labelColor[3];
    CGRect bodySample=CGRectInset(b,-b.size.height*.15,-b.size.height*.1);
    BOOL confirmed=NO;
    // Tight ink bounds need a collar; smaller embedded video can instead mix
    // the collar with the body at sampling resolution. Try both, requiring the
    // same fill, distinct body and visible plate bounds for either candidate.
    for (NSUInteger attempt=0;attempt<2 && !confirmed;attempt++) {
        CGFloat padding=attempt==0 ? a.size.height*.2 : 0;
        CGRect labelSample=CGRectInset(a,-padding,-padding);
        if (!FYPlateDominantColor(&buffer,labelSample,labelColor) ||
            !FYPlateBodyHasDistinctBackdrop(&buffer,bodySample,labelColor)) { continue; }
        // A broad scene color or a highlight spanning the whole body fails.
        NSUInteger outside=0,total=0;
        for (NSUInteger i=0;i<5;i++) {
            const unsigned char *above=FYPlatePixel(&buffer,CGRectGetMinX(a)+a.size.width*(i+.5)/5,
                CGRectGetMaxY(a)+a.size.height);
            const unsigned char *right=FYPlatePixel(&buffer,CGRectGetMaxX(a)+height*3,
                CGRectGetMinY(a)+a.size.height*(i+.5)/5);
            if (above) { total++;if (!FYPlateColorNear(above,labelColor)) outside++; }
            if (right) { total++;if (!FYPlateColorNear(right,labelColor)) outside++; }
        }
        confirmed=total==10 && outside>=8;
    }
    FYReleaseOCRPixelBuffer(&buffer);
    if (!confirmed) { return items; }
    NSMutableArray *result=[items mutableCopy];
    NSUInteger index=[items indexOfObjectIdenticalTo:label];
    if (index!=NSNotFound) {
        OCRTextItem *copy=FYCopyInlineOCRItem(label);copy.speakerLabel=YES;result[index]=copy;
    }
    return result;
}
+ (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString **)outSpeaker body:(NSString **)outBody {
    NSString *speaker=nil,*body=text ?: @"";
    NSArray<NSString *> *lines=[body componentsSeparatedByString:@"\n"];
    if (lines.count>=2) {
        NSString *first=[lines.firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (first.length>0 && ([self looksLikeSpeakerName:first] || [self looksLikeSpeakerFurigana:first])) {
            NSUInteger consumed=1;speaker=first;
            if (lines.count>=3) {
                NSString *second=[lines[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if ([self looksLikeSpeakerFurigana:first] && [self looksLikeSpeakerName:second]) {
                    speaker=[NSString stringWithFormat:@"%@ %@",first,second];consumed=2;
                }
            }
            body=[[lines subarrayWithRange:NSMakeRange(consumed,lines.count-consumed)] componentsJoinedByString:@"\n"];
        }
    }
    if (outSpeaker) *outSpeaker=speaker;
    if (outBody) *outBody=body;
}
+ (NSString *)postprocessedTextForItems:(NSArray<OCRTextItem *> *)items renderedTexts:(NSSet<NSString *> *)renderedTexts blocks:(NSArray<OCRTextItem *> **)outBlocks {
    items=[self itemsExcludingOwnOverlay:items renderedTexts:renderedTexts];
    return [self sourceTextForItems:items blocks:outBlocks];
}
+ (NSString *)sourceTextForItems:(NSArray<OCRTextItem *> *)items blocks:(NSArray<OCRTextItem *> **)outBlocks {
    items=[self resolveOverlappingItems:items];
    if (outBlocks) *outBlocks=items;
    return [[items valueForKey:@"text"] componentsJoinedByString:@"\n"] ?: @"";
}
+ (NSString *)recognizeEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region
    recognizer:(NSString *(^)(CGImageRef, NSArray<OCRTextItem *> **, NSError **))recognizer
    blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error {
    CGRect crop=CGRectZero;
    CGImageRef scaled=[self copyEnlargedImage:image visionRegion:region pixelCrop:&crop];
    if (!scaled) return @"";
    __block NSArray<OCRTextItem *> *localBlocks=nil;
    __block NSString *text;
    __block NSError *cropError=error ? *error : nil;
    BOOL wantsError=error != NULL;
    FYLayoutDebugPerformCrop(crop, CGSizeMake(CGImageGetWidth(image),CGImageGetHeight(image)), ^{
        text=recognizer(scaled,&localBlocks,wantsError ? &cropError : NULL);
    });
    if (error) *error=cropError;
    [self remapItems:localBlocks fromPixelCrop:crop imageSize:CGSizeMake(CGImageGetWidth(image),CGImageGetHeight(image))];
    if (outBlocks) *outBlocks=localBlocks;
    CGImageRelease(scaled);
    return text;
}
+ (NSArray<OCRTextItem *> *)items:(NSArray<OCRTextItem *> *)blocks
           scopedToModalInImage:(CGImageRef)image
                    exclusions:(NSArray<NSValue *> *)exclusionValues {
    if (!image || blocks.count < 2) { return blocks; }
    FYOCRPixelBuffer buffer = FYCreateOCRPixelBuffer(image);
    if (!buffer.pixels) { return blocks; }
    NSUInteger count = exclusionValues.count;
    CGRect *exclusions = count ? calloc(count, sizeof(CGRect)) : NULL;
    if (count && !exclusions) { FYReleaseOCRPixelBuffer(&buffer); return blocks; }
    for (NSUInteger i = 0; i < count; i++) { exclusions[i] = exclusionValues[i].rectValue; }
    CGRect region = CGRectZero;
    BOOL qualifies = FYDetectBrightOCRContentRegion(buffer.pixels, buffer.width, buffer.height,
        buffer.bytesPerRow, &region, NULL, exclusions, count) &&
        FYOCRModalRectQualifiesForCropping(region) &&
        FYOCRModalSurroundingsAreDimmer(buffer.pixels, buffer.width, buffer.height, buffer.bytesPerRow, region);
    free(exclusions);
    FYReleaseOCRPixelBuffer(&buffer);
    if (!qualifies) { return blocks; }

    // 亮块和暗背景本身不足以区分邮件/照片与弹窗。还必须有位于该面板底部的
    // 独立关闭按钮；正文里提到“关闭”、画面角落的“返回”都不能触发裁剪。
    BOOL hasDismiss = NO;
    CGRect footer = CGRectMake(NSMinX(region), MAX((CGFloat)0, NSMinY(region) - 0.13),
                               NSWidth(region), NSHeight(region) * 0.35 + 0.13);
    for (OCRTextItem *item in blocks) {
        NSString *text = [FYNormalizeOCRTextForComparison(item.text) lowercaseString];
        if (![@[@"閉じる", @"とじる", @"关闭", @"關閉", @"close"] containsObject:text]) { continue; }
        if (NSWidth(item.boundingBox) > 0.22 || NSHeight(item.boundingBox) > 0.09 ||
            !CGRectContainsRect(footer, item.boundingBox)) { continue; }
        BOOL covered = NO;
        for (NSValue *value in exclusionValues) {
            if (CGRectIntersectsRect(value.rectValue, item.boundingBox)) { covered = YES; break; }
        }
        if (!covered) { hasDismiss = YES; break; }
    }
    if (!hasDismiss) { return blocks; }
    NSArray *scoped = [self items:blocks inModalRegion:region exclusions:exclusionValues];
    NSMutableArray *inside = [NSMutableArray array];
    for (OCRTextItem *item in scoped) {
        // 页眉/页脚可以向上下延伸；左右边界保持贴合面板，避免重新纳入左栏日期。
        if (NSMinX(item.boundingBox) >= NSMinX(region) - 0.005 &&
            NSMaxX(item.boundingBox) <= NSMaxX(region) + 0.005) { [inside addObject:item]; }
    }
    return inside.count >= 2 ? inside : blocks;
}

+ (NSArray<OCRTextItem *> *)items:(NSArray<OCRTextItem *> *)blocks inModalRegion:(CGRect)modalRect exclusions:(NSArray<NSValue *> *)exclusionValues {
    // 弹窗的橙色页眉/页脚不够亮，纵向外扩一点，避免把弹窗自己的标题丢掉。
    // 不能扩太多，否则上一层页面的文字会重新落进范围里（实测 0.18 会把左侧栏目带回来）。
    CGRect grown = CGRectInset(modalRect, -0.04, -0.13);
    NSMutableArray<OCRTextItem *> *kept = [NSMutableArray array];
    for (OCRTextItem *block in blocks) {
        if (!CGRectContainsRect(grown, block.boundingBox)) { continue; }
        // 我们自己贴的译文面板会盖在弹窗正文上，OCR 会把面板上的字也读出来。
        // 这一类是我们自己画的，直接按面板位置排除，不再当作页面内容。
        BOOL overlapsOwnPanel = NO;
        for (NSValue *value in exclusionValues) {
            CGRect panelRect = value.rectValue;
            CGRect intersection = CGRectIntersection(panelRect, block.boundingBox);
            if (CGRectIsNull(intersection)) { continue; }
            CGFloat blockArea = block.boundingBox.size.width * block.boundingBox.size.height;
            CGFloat overlapArea = intersection.size.width * intersection.size.height;
            if (blockArea > 0 && (overlapArea / blockArea) >= 0.5) { overlapsOwnPanel = YES; break; }
        }
        if (overlapsOwnPanel) { continue; }
        [kept addObject:block];
    }
    // 过滤后剩得太少说明判断不可靠，宁可不裁，避免整屏不翻
    if (kept.count < 2) { return blocks; }
    return kept;
}

// Compatibility content-policy API delegates to FYContentRouter.
+ (NSInteger)contentModeForItems:(NSArray<OCRTextItem *> *)blocks fallback:(NSInteger)fallbackSegment {
    return [FYContentRouter contentModeForItems:blocks fallback:fallbackSegment];
}

+ (BOOL)looksLikeSpeakerName:(NSString *)raw {
    return [FYContentRouter looksLikeSpeakerName:raw];
}

+ (BOOL)looksLikeSpeakerFurigana:(NSString *)raw {
    return [FYContentRouter looksLikeSpeakerFurigana:raw];
}

+ (BOOL)looksLikeSpeakerLabelCluster:(NSArray<OCRTextItem *> *)cluster {
    return [FYContentRouter looksLikeSpeakerLabelCluster:cluster];
}

+ (BOOL)isSpeakerLabelItem:(OCRTextItem *)item inPool:(NSArray<OCRTextItem *> *)pool {
    return [FYContentRouter isSpeakerLabelItem:item inPool:pool];
}

+ (BOOL)dialogueFrameIsSpeakerLabelOnly:(NSArray<NSString *> *)lines {
    return [FYContentRouter dialogueFrameIsSpeakerLabelOnly:lines];
}

+ (void)splitDialogueAndOptions:(NSArray<OCRTextItem *> *)band
                     allBlocks:(NSArray<OCRTextItem *> *)allBlocks
                      dialogue:(NSMutableArray<OCRTextItem *> *)outDialogue
                       options:(NSMutableArray<OCRTextItem *> *)outOptions {
    [FYContentRouter splitDialogueAndOptions:band allBlocks:allBlocks dialogue:outDialogue options:outOptions];
}

+ (BOOL)containsJapaneseKana:(NSString *)value {
    return [FYContentRouter containsJapaneseKana:value];
}

+ (BOOL)isFormedTextLine:(OCRTextItem *)block {
    return [FYContentRouter isFormedTextLine:block];
}

+ (BOOL)isShortDialogueAnchor:(OCRTextItem *)block {
    return [FYContentRouter isShortDialogueAnchor:block];
}

+ (BOOL)isUnpunctuatedSingleLineDialogue:(NSString *)text box:(CGRect)box {
    return [FYContentRouter isUnpunctuatedSingleLineDialogue:text box:box];
}

+ (BOOL)isCornerHelpButton:(OCRTextItem *)block {
    return [FYContentRouter isCornerHelpButton:block];
}

+ (BOOL)isSingleLineDialogue:(OCRTextItem *)block {
    return [FYContentRouter isSingleLineDialogue:block];
}

+ (BOOL)isDialogueAnchor:(OCRTextItem *)block {
    return [FYContentRouter isDialogueAnchor:block];
}

+ (NSArray<OCRTextItem *> *)subtitleBandItems:(NSArray<OCRTextItem *> *)blocks {
    return [FYContentRouter subtitleBandItems:blocks];
}

+ (BOOL)textHitsUIToken:(NSString *)text {
    return [FYContentRouter textHitsUIToken:text];
}

+ (NSUInteger)UITokenHitCount:(NSArray<OCRTextItem *> *)blocks {
    return [FYContentRouter UITokenHitCount:blocks];
}

+ (BOOL)isFurigana:(OCRTextItem *)small nearLargerLineInItems:(NSArray<OCRTextItem *> *)blocks {
    return [FYContentRouter isFurigana:small nearLargerLineInItems:blocks];
}

+ (BOOL)looksLikeUIFrame:(NSArray<OCRTextItem *> *)blocks {
    return [FYContentRouter looksLikeUIFrame:blocks];
}

+ (NSString *)dialogueTextWithoutTrailingButton:(NSString *)text {
    return [FYContentRouter dialogueTextWithoutTrailingButton:text];
}

+ (CGImageRef)copyEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region pixelCrop:(CGRect *)outCrop {
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    if (imageWidth < 2 || imageHeight < 2) { return NULL; }

    // Region and OCR boxes use Vision's bottom-left origin; CGImage cropping
    // uses the top-left origin. Convert both the crop and its returned boxes.
    CGRect crop = CGRectMake(floor(region.origin.x * imageWidth),
                             floor((1.0 - region.origin.y - region.size.height) * imageHeight),
                             MAX((size_t)2, floor(region.size.width * imageWidth)),
                             MAX((size_t)2, floor(region.size.height * imageHeight)));
    crop = CGRectIntersection(crop, CGRectMake(0, 0, imageWidth, imageHeight));
    if (crop.size.width < 2 || crop.size.height < 2) { return NULL; }

    CGImageRef cropped = CGImageCreateWithImageInRect(image, crop);
    if (!cropped) { return NULL; }

    // 放大 2 倍，但对最长边设硬上限：超过约 1800px 之后 OCR 精度基本不再提升，
    // 耗时却随像素数线性增长 —— 之前上限 4000 会跑出 3000x950 这种巨图，一轮好几秒。
    size_t scaledWidth = MIN((size_t)(crop.size.width * 2.0), (size_t)1800);
    size_t scaledHeight = MIN((size_t)(crop.size.height * 2.0), (size_t)1800);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, scaledWidth, scaledHeight, 8, 0, space,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        CGImageRelease(cropped);
        return NULL;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, scaledWidth, scaledHeight), cropped);
    CGImageRef scaled = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGImageRelease(cropped);
    if (!scaled) { return NULL; }

    if (outCrop) { *outCrop = crop; }
    return scaled;
}

+ (void)remapItems:(NSArray<OCRTextItem *> *)items fromPixelCrop:(CGRect)crop imageSize:(CGSize)imageSize {
    CGFloat baseX = crop.origin.x / imageSize.width, baseY = 1.0 - CGRectGetMaxY(crop) / imageSize.height;
    CGFloat scaleX = crop.size.width / imageSize.width, scaleY = crop.size.height / imageSize.height;
    for (OCRTextItem *block in items) {
        CGRect b = block.boundingBox;
        block.boundingBox = CGRectMake(baseX + b.origin.x * scaleX, baseY + b.origin.y * scaleY,
                                       b.size.width * scaleX, b.size.height * scaleY);
        CGRect last = block.lastLineBox;
        if (!CGRectIsEmpty(last)) {
            block.lastLineBox = CGRectMake(baseX + last.origin.x * scaleX, baseY + last.origin.y * scaleY,
                                          last.size.width * scaleX, last.size.height * scaleY);
        }
        if (block.lineBoxes.count > 0) {
            NSMutableArray<NSValue *> *mapped = [NSMutableArray arrayWithCapacity:block.lineBoxes.count];
            for (NSValue *value in block.lineBoxes) {
                CGRect line = value.rectValue;
                if (!CGRectIsEmpty(line)) {
                    line = CGRectMake(baseX + line.origin.x * scaleX, baseY + line.origin.y * scaleY,
                                      line.size.width * scaleX, line.size.height * scaleY);
                }
                [mapped addObject:[NSValue valueWithRect:line]];
            }
            block.lineBoxes = mapped;
        }
    }
}

// 这两串是「译芽」自己画在屏幕上的状态栏文字（状态行 + 句数行）。
// 它们常常正好压在目标窗口上（实测在左下角），于是被下一轮 OCR 读回来当成正文：
// 混进字幕带、占住锚点位置，把真正的对白行挤出字幕带（实测「平気。」就是这么丢的）。
+ (BOOL)isOwnOverlayText:(NSString *)raw {
    NSString *t = raw ? [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    if (t.length == 0) { return NO; }
    NSString *lower = t.lowercaseString;
    // 翻译全失败时状态串会长成「翻译失败：<服务端报错>」，形状不固定，用前缀识别
    if ([t hasPrefix:@"翻译失败："] || [t hasPrefix:@"翻译失败:"]) { return YES; }
    NSArray<NSString *> *needles = @[@"译文已更新", @"自动判别", @"翻译界面", @"正在翻译",
                                     @"等待文本稳定", @"已暂停", @"本次 ", @"OCr ".lowercaseString];
    // 短且**完全没有日文假名/汉字**的碎片：`？？？` 之类的字形被误读成拉丁字母
    // （实测名字框读成 `iee`、`ことと`）。这类东西发去翻译只会得到编造的译文。
    if (t.length <= 6) {
        BOOL hasKanaOrKanji = NO;
        for (NSUInteger index = 0; index < t.length; index++) {
            unichar character = [t characterAtIndex:index];
            if ((character >= 0x3040 && character <= 0x30FF) ||
                (character >= 0x4E00 && character <= 0x9FFF)) { hasKanaOrKanji = YES; break; }
        }
        if (!hasKanaOrKanji) { return YES; }
    }

    // 状态行被 OCR 截断成片段时（实测 `翻译 0.6s 总 0.8s`）关键词会丢，但**计时格式**还在。
    // 游戏正文里不会出现 `0.6s` 这种「数字.数字s」的秒表写法，所以这条很安全。
    BOOL hasTimingPattern = NO;
    {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[0-9]+\\.[0-9]+s"
                                                                              options:0
                                                                                error:NULL];
        if (regex) {
            NSRange full = NSMakeRange(0, t.length);
            hasTimingPattern = [regex firstMatchInString:t options:0 range:full] != nil;
        }
    }
    if (hasTimingPattern) { return YES; }

    BOOL hasNeedle = NO;
    for (NSString *needle in needles) {
        if ([t containsString:needle] || [lower containsString:needle.lowercaseString]) { hasNeedle = YES; break; }
    }
    if (!hasNeedle) { return NO; }
    // 状态行一定带数字（秒数）。这里放宽到“含数字”即可：
    // OCR 常把它读花（实测 `译文已要新・OCR 0.25南译0.3550.55）。••`），
    // 原来要求含「秒/句/s」就漏过了 —— 于是这行乱码混进字幕带、被当成台词送去翻译，
    // 模型自然给出一句完全不相干的译文。
    BOOL hasDigit = NO;
    for (NSUInteger index = 0; index < t.length; index++) {
        unichar character = [t characterAtIndex:index];
        if (character >= '0' && character <= '9') { hasDigit = YES; break; }
    }
    if (hasDigit) { return YES; }

    BOOL looksStatus = [t containsString:@"s"] || [t containsString:@"S"] || [t containsString:@"秒"];
    BOOL looksCount = [t containsString:@"句"];
    return looksStatus || looksCount;
}

// 从 OCR 结果里剔除我们自己的浮窗文字。
// 两种来源：
//   ① 形状可辨的状态栏（IsOwnOverlayText）
//   ② 我们刚画上去的译文（由调用方传入已渲染过的文本）——
//      贴译面板会盖住原文，下一轮 OCR 必然把它们读回来；
//      若不过滤，这些中文会被当成“原文”再翻一次，对白框里就会混进重复/错位的句子。
+ (NSArray<OCRTextItem *> *)itemsExcludingOwnOverlay:(NSArray<OCRTextItem *> *)items
                                     renderedTexts:(NSSet<NSString *> *)renderedTexts {
    if (items.count == 0) { return items; }
    NSMutableArray<OCRTextItem *> *kept = [NSMutableArray arrayWithCapacity:items.count];
    for (OCRTextItem *item in items) {
        if ([self isOwnOverlayText:item.text]) { continue; }
        if (renderedTexts.count > 0) {
            NSString *normalized = FYNormalizeOCRTextForComparison(item.text);
            if (normalized.length > 0 && [renderedTexts containsObject:normalized]) { continue; }
        }
        [kept addObject:item];
    }
    return kept;
}

// 我们画过的所有译文（字幕窗 + 贴译面板），归一化后供 OCR 去重
+ (NSSet<NSString *> *)renderedTranslationSetForCaption:(NSString *)captionText inlineCache:(NSDictionary *)inlineCache {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    NSString *normalizedCaption = FYNormalizeOCRTextForComparison(captionText);
    if (normalizedCaption.length >= 2) { [set addObject:normalizedCaption]; }
    for (NSString *value in inlineCache.allValues) {
        if (![value isKindOfClass:NSString.class]) { continue; }
        NSString *normalized = FYNormalizeOCRTextForComparison(value);
        if (normalized.length >= 2) { [set addObject:normalized]; }
    }
    return set;
}

// Deduplication needs geometry AND bidirectional character coverage, never text alone.
// Inner blocks must lie >=85% inside and cover >=85% of the outer area;
// both character coverages must reach 80%. Same-sized duplicates retain the first.
// These are the existing thresholds, including summed (not union) covered area.
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
+ (NSArray<OCRTextItem *> *)splitMultilineItems:(NSArray<OCRTextItem *> *)items {
    NSMutableArray<OCRTextItem *> *result = [NSMutableArray array];
    for (OCRTextItem *item in items ?: @[]) {
        NSArray<NSString *> *parts = [item.text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
        NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        NSUInteger longest = 0;
        for (NSUInteger index = 0; index < parts.count; index++) {
            NSString *line = [parts[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (line.length == 0) { continue; }
            [indexes addObject:@(index)];
            [lines addObject:line];
            longest = MAX(longest, line.length);
        }
        if (lines.count < 2) { [result addObject:item]; continue; }
        CGRect outer = item.boundingBox;
        for (NSUInteger ordinal = 0; ordinal < lines.count; ordinal++) {
            NSUInteger originalIndex = indexes[ordinal].unsignedIntegerValue;
            CGRect lineBox = CGRectZero;
            if (item.lineBoxes.count == parts.count) { lineBox = item.lineBoxes[originalIndex].rectValue; }
            if (CGRectIsEmpty(lineBox) ||
                (fabs(CGRectGetWidth(lineBox) - CGRectGetWidth(outer)) < 0.001 &&
                 fabs(CGRectGetHeight(lineBox) - CGRectGetHeight(outer)) < 0.001)) {
                // Older OCR results provide only the union box. Preserve row order and
                // approximate widths until Vision's character-range boxes are available.
                CGFloat height = CGRectGetHeight(outer) / (CGFloat)lines.count;
                CGFloat width = CGRectGetWidth(outer) * (CGFloat)lines[ordinal].length / (CGFloat)MAX((NSUInteger)1, longest);
                lineBox = CGRectMake(CGRectGetMinX(outer), CGRectGetMaxY(outer) - (ordinal + 1) * height,
                                     MIN(CGRectGetWidth(outer), MAX((CGFloat)0.005, width)), height);
            }
            OCRTextItem *lineItem = [OCRTextItem new];
            lineItem.text = lines[ordinal];
            lineItem.boundingBox = lineBox;
            lineItem.lastLineBox = lineBox;
            lineItem.lineTexts = @[lineItem.text];
            lineItem.lineBoxes = @[[NSValue valueWithRect:lineBox]];
            lineItem.lineCount = 1;
            lineItem.blockKind = item.blockKind;
            lineItem.confidence = item.confidence;
            lineItem.groupingConfidence = item.groupingConfidence;
            lineItem.speakerLabel = item.speakerLabel;
            [result addObject:lineItem];
        }
    }
    return result;
}
+ (NSString *)textFromRecognizedLines:(NSArray<NSString *> *)lines {
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *value in lines) {
        NSString *line = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (line.length > 0) { [kept addObject:line]; }
    }
    return [kept componentsJoinedByString:@"\n"];
}

+ (NSArray<OCRTextItem *> *)recognizeImage:(CGImageRef)image topLeftScope:(CGRect)scope
    recognizer:(NSArray<OCRTextItem *> *(^)(CGImageRef cropped, NSError **error))recognizer error:(NSError **)error {
    if (CGRectEqualToRect(scope, CGRectMake(0,0,1,1))) return recognizer(image,error);
    if (!image || !isfinite(scope.origin.x) || !isfinite(scope.origin.y) ||
        !isfinite(scope.size.width) || !isfinite(scope.size.height) || scope.size.width<=0 || scope.size.height<=0) return @[];
    CGRect bounded=CGRectIntersection(scope,CGRectMake(0,0,1,1));
    if (CGRectIsNull(bounded) || CGRectIsEmpty(bounded)) return @[];
    CGSize size=CGSizeMake(CGImageGetWidth(image),CGImageGetHeight(image));
    CGRect crop=CGRectIntersection(CGRectIntegral(CGRectMake(bounded.origin.x*size.width,bounded.origin.y*size.height,
        bounded.size.width*size.width,bounded.size.height*size.height)),CGRectMake(0,0,size.width,size.height));
    CGImageRef cropped=CGImageCreateWithImageInRect(image,crop);
    if (!cropped) {
        if (error) *error=[NSError errorWithDomain:@"LiveCaptionTranslator" code:901 userInfo:@{NSLocalizedDescriptionKey:@"无法读取手动识别区域。"}];
        return @[];
    }
    __block NSArray<OCRTextItem *> *items;
    __block NSError *cropError=error ? *error : nil;
    BOOL wantsError=error != NULL;
    FYLayoutDebugPerformCrop(crop, size, ^{ items=recognizer(cropped,wantsError ? &cropError : NULL); });
    if (error) *error=cropError;
    CGImageRelease(cropped);
    [self remapItems:items fromPixelCrop:crop imageSize:size];
    return items;
}

- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error {
    __block NSMutableArray<OCRTextItem *> *items = [NSMutableArray array];
    __block NSError *requestError = nil;
    NSMutableDictionary *localLayoutContext=[FYCurrentLayoutDebug() mutableCopy];
    if (localLayoutContext) localLayoutContext[@"vision_image_size"]=@[@(CGImageGetWidth(image)),@(CGImageGetHeight(image))];
    NSDictionary *layoutContext=[localLayoutContext copy];

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *innerError) {
        if (innerError) {
            requestError = innerError;
            return;
        }

        NSMutableArray *diagnosticRaw=layoutContext ? [NSMutableArray array] : nil;
        for (VNRecognizedTextObservation *observation in request.results) {
            VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
            if (diagnosticRaw) {
                OCRTextItem *raw=[OCRTextItem new]; raw.text=candidate.string ?: @""; raw.boundingBox=observation.boundingBox; raw.confidence=candidate.confidence;
                [diagnosticRaw addObject:raw];
            }
            NSString *line = [candidate.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (line.length < 2) { continue; }
            if (observation.boundingBox.size.width < 0.010 || observation.boundingBox.size.height < 0.006) { continue; }

            OCRTextItem *item = [[OCRTextItem alloc] init];
            item.text = line;
            item.boundingBox = observation.boundingBox;
            if ([line rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
                NSMutableArray<NSString *> *lineTexts = [NSMutableArray array];
                NSMutableArray<NSValue *> *lineBoxes = [NSMutableArray array];
                [candidate.string enumerateSubstringsInRange:NSMakeRange(0, candidate.string.length)
                                                     options:NSStringEnumerationByLines
                                                  usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
                    NSString *part = [substring stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    if (part.length == 0) { return; }
                    VNRectangleObservation *rangeBox = [candidate boundingBoxForRange:substringRange error:nil];
                    [lineTexts addObject:part];
                    [lineBoxes addObject:[NSValue valueWithRect:rangeBox ? rangeBox.boundingBox : CGRectZero]];
                }];
                if (lineTexts.count > 1) {
                    item.text = [lineTexts componentsJoinedByString:@"\n"];
                    item.lineTexts = lineTexts;
                    item.lineBoxes = lineBoxes;
                    item.lineCount = lineTexts.count;
                    item.lastLineBox = lineBoxes.lastObject.rectValue;
                }
            }
            // 保留识别置信度：分组/布局只把它用于诊断，不当作几何证据。
            item.confidence = candidate.confidence;
            [items addObject:item];
        }
        if (layoutContext) [[FYInlineLayoutDebug shared] recordItems:diagnosticRaw stage:@"vision_raw" context:layoutContext];
    }];

    request.recognitionLevel = fastOCR ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = !fastOCR;
    request.recognitionLanguages = languageSegment == 1 ? @[@"en-US"] : @[@"ja-JP"];
    // minimumTextHeight 是相对图像高度的比例，固定值会在不同窗口尺寸下失效：
    // 实测 2727×1536 截图时 0.02 正好，但运行时窗口 1710×963 里对白文字占 0.054，
    // 0.02 会把它当“太小的字”漏掉 → 整句对白凭空消失。
    // 改成按绝对像素换算：准确模式目标为 48px，快速模式为 32px，随图像高度自适应。
    CGFloat imageHeight = (CGFloat)CGImageGetHeight(image);
    // 实测：对白文字高 52px，但 minH 设成 28px 仍读不到，要设到 48px 才读到。
    // Vision 的这个阈值不是“小于就丢弃”的线性开关，实际有效值比文字高度略低几像素。
    CGFloat targetTextPixels = fastOCR ? 32.0 : 48.0;
    CGFloat adaptiveMinH = imageHeight > 0 ? (targetTextPixels / imageHeight) : 0.02;
    if (adaptiveMinH < 0.005) { adaptiveMinH = 0.005; }
    if (adaptiveMinH > 0.10) { adaptiveMinH = 0.10; }
    request.minimumTextHeight = adaptiveMinH;
    if (self.configurationObserver) {
        self.configurationObserver(fastOCR, languageSegment, CGImageGetWidth(image), CGImageGetHeight(image), request.minimumTextHeight);
    }

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
    BOOL ok = [handler performRequests:@[request] error:error];
    if (!ok) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                         code:900
                                     userInfo:@{NSLocalizedDescriptionKey: @"OCR 引擎执行失败，已跳过这一轮。"}];
        }
        return @[];
    }
    if (requestError && error) { *error = requestError; }

    [items sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        return FYOCRReadingOrder(left, right);
    }];

    return items;
}
@end
