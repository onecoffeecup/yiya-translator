#import "FYInlineOCRFrameStabilizer.h"
#import <math.h>

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
