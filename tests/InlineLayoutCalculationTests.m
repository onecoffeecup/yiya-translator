#import "inline/FYInlineLayoutCalculatorInternal.h"
static NSUInteger checks;
static void Check(BOOL ok, NSString *message) { checks++; if (!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(2); } }
// Direct geometry inputs are already measured rectangles. No text-measurement
// replacement, UI object, or copy of the production calculation is involved.
@interface FYInlineLayoutCalculator (GeometryTestAccess)
- (NSArray<FYInlineCandidate *> *)candidatesForPlacement:(FYInlinePlacement *)placement viewport:(CGRect)viewport compactEntry:(BOOL)compact widths:(NSArray<NSNumber *> *)widths;
- (void)filterCandidates:(NSArray<FYInlineCandidate *> *)candidates placement:(FYInlinePlacement *)placement viewport:(CGRect)viewport otherSources:(NSArray<NSValue *> *)sources sourceIndices:(NSArray<NSNumber *> *)indices sourceTexts:(NSArray<NSString *> *)texts selfIndex:(NSUInteger)index report:(NSMutableArray<NSString *> *)report;
- (FYInlineCandidate *)candidate:(FYInlineCandidate *)candidate resolvingCollisionsWithin:(CGFloat)tolerance viewport:(CGRect)viewport placement:(FYInlinePlacement *)placement otherSources:(NSArray<NSValue *> *)sources sourceTexts:(NSArray<NSString *> *)texts selfIndex:(NSUInteger)index placedFrames:(NSArray<NSValue *> *)placed;
- (CGFloat)scoreForCandidate:(FYInlineCandidate *)candidate placement:(FYInlinePlacement *)placement previous:(FYInlinePlacement *)previous columnAnchors:(NSDictionary *)anchors columnKey:(NSNumber *)key;
- (NSNumber *)columnKeyForSourceFrame:(CGRect)source viewport:(CGRect)viewport;
- (NSArray<NSNumber *> *)cardWidthCandidatesForSource:(CGRect)source viewport:(CGRect)viewport wide:(BOOL)wide;
- (BOOL)result:(FYInlineLayoutResult *)result differsFromPrevious:(FYInlineLayoutResult *)previous;
- (void)recordCandidateAttempt:(FYInlineCandidate *)original resolved:(FYInlineCandidate *)resolved placement:(FYInlinePlacement *)placement placed:(NSArray<FYInlinePlacement *> *)placed score:(CGFloat)score;
@end
static FYInlinePlacement *Placement(CGRect source) { FYInlinePlacement *p=[FYInlinePlacement new]; p.block=[FYInlineTextBlock new];p.block.text=@"合成字段";p.blockID=@"field";p.translation=@"合成译文";p.sourceFrame=source;p.translationFrame=CGRectMake(0,0,140,40);p.measuredContentHeight=300;p.bodyViewportHeight=20;p.scrollable=YES;return p; }
static FYInlineCandidate *Candidate(CGRect rect,FYInlineAnchor anchor) { FYInlineCandidate *c=[FYInlineCandidate new];c.frame=rect;c.anchor=anchor;c.name=@"fixture";return c; }
int main(void) { @autoreleasepool {
    FYInlineLayoutCalculator *engine=[FYInlineLayoutCalculator defaultCalculator];
    CGRect viewport=CGRectMake(20,30,800,600);FYInlinePlacement *p=Placement(CGRectMake(200,300,180,60));
    NSArray<FYInlineCandidate *> *c=[engine candidatesForPlacement:p viewport:viewport compactEntry:NO widths:@[@140,@280]];
    Check(c.count==5&&c[0].anchor==FYInlineAnchorBelow&&c[1].anchor==FYInlineAnchorAbove&&c.lastObject.anchor==FYInlineAnchorOverlay,@"middle source keeps below/above/right/left/overlay order");
    Check(CGRectEqualToRect(c[0].frame,CGRectMake(200,256,140,40))&&c[0].distance==4&&c[1].anchorRank==1,@"actual candidates use first width, measured height, original gap and rank");
    Check(c[0].scrollable&&c[0].measuredContentHeight==300&&c[0].bodyViewportHeight==20,@"candidate retains measured content/viewport/scroll metadata");
    p.sourceFrame=CGRectMake(200,35,180,60);c=[engine candidatesForPlacement:p viewport:viewport compactEntry:NO widths:@[@140]];
    Check(c[0].anchor==FYInlineAnchorAbove,@"bottom source prioritizes the direction with sufficient space");
    p.sourceFrame=CGRectMake(200,560,180,60);c=[engine candidatesForPlacement:p viewport:viewport compactEntry:NO widths:@[@140]];
    Check(c[0].anchor==FYInlineAnchorBelow,@"top source prioritizes the direction with sufficient space");
    p.sourceFrame=CGRectMake(790,300,20,60);c=[engine candidatesForPlacement:p viewport:viewport compactEntry:NO widths:@[@140]];
    Check(c[0].frame.origin.x==672&&c[2].frame.origin.x==672,@"right-edge source clamps both primary and right candidate inside margin");
    p.sourceFrame=CGRectMake(200,300,180,60);p.translationFrame=CGRectMake(0,0,100,10);c=[engine candidatesForPlacement:p viewport:viewport compactEntry:YES widths:@[@100]];
    Check(c.count==8&&c[0].anchor==FYInlineAnchorOverlay&&c[0].frame.size.height==34&&c[0].frame.origin.y==304&&c[3].anchorRank==3,@"compact candidates cover their own field first with original minimum height/ranks");
    p.translationFrame=CGRectMake(0,0,140,40);
    FYInlineCandidate *outside=Candidate(CGRectMake(0,300,140,40),FYInlineAnchorBelow),*search=Candidate(CGRectMake(200,20,140,40),FYInlineAnchorOverlay),*far=Candidate(CGRectMake(200,400,140,40),FYInlineAnchorAbove);far.distance=69;
    NSMutableArray *report=[NSMutableArray new];[engine filterCandidates:@[outside,search,far] placement:p viewport:viewport otherSources:@[] sourceIndices:@[] sourceTexts:@[] selfIndex:0 report:report];
    Check(outside.hardRejection&&[outside.rejection isEqual:@"超出可见区域"],@"horizontal out-of-bounds remains a hard rejection");
    Check(!search.hardRejection&&[search.rejection isEqual:@"超出可见区域"],@"overlay with legal width can still search its own region vertically");
    Check(far.hardRejection&&[far.rejection isEqual:@"离原文过远"]&&report.count==3,@"strict drift bound and all rejection diagnostics retained");
    CGRect obstacle=CGRectMake(200,310,180,50);FYInlineCandidate *duplicate=Candidate(CGRectMake(200,310,140,40),FYInlineAnchorOverlay);
    [engine filterCandidates:@[duplicate] placement:p viewport:viewport otherSources:@[@(p.sourceFrame),@(obstacle)] sourceIndices:@[@1,@2] sourceTexts:@[@"合成字段",@"合成字段"] selfIndex:0 report:[NSMutableArray new]];
    Check(duplicate.occlusionDepth==0&&[duplicate.rejection containsString:@"疑似重复识别"],@"identical highly overlapping source is diagnostic only, not obstruction");
    FYInlineCandidate *different=Candidate(duplicate.frame,FYInlineAnchorOverlay);[engine filterCandidates:@[different] placement:p viewport:viewport otherSources:@[@(p.sourceFrame),@(obstacle)] sourceIndices:@[@1,@2] sourceTexts:@[@"合成字段",@"不同字段"] selfIndex:0 report:[NSMutableArray new]];
    Check(different.occlusionDepth==40&&[different.rejection containsString:@"遮挡第 2"],@"different source text remains a real obstacle with original thickness");
    FYInlineCandidate *base=Candidate(CGRectMake(200,310,140,40),FYInlineAnchorOverlay);base.anchorRank=2;base.scrollable=YES;base.measuredContentHeight=300;base.bodyViewportHeight=20;
    FYInlineCandidate *resolved=[engine candidate:base resolvingCollisionsWithin:3 viewport:viewport placement:p otherSources:@[] sourceTexts:@[] selfIndex:0 placedFrames:@[]];
    Check(resolved!=base&&CGRectEqualToRect(resolved.frame,base.frame)&&resolved.anchorRank==2&&resolved.scrollable&&resolved.measuredContentHeight==300&&resolved.bodyViewportHeight==20,@"resolution returns a new candidate with exact frame and measurement metadata");
    CGRect blocker=CGRectMake(200,315,140,10);resolved=[engine candidate:base resolvingCollisionsWithin:3 viewport:viewport placement:p otherSources:@[] sourceTexts:@[] selfIndex:0 placedFrames:@[@(blocker)]];
    Check(resolved&&resolved.frame.origin.y==325.5&&!CGRectIntersectsRect(resolved.frame,blocker)&&CGRectEqualToRect(base.frame,CGRectMake(200,310,140,40)),@"closest legal field gap strictly avoids placed card without mutating original");
    Check([resolved.name containsString:@"字段内空隙避让"],@"moved candidate keeps original avoidance diagnostic");
    resolved=[engine candidate:base resolvingCollisionsWithin:3 viewport:viewport placement:p otherSources:@[] sourceTexts:@[] selfIndex:0 placedFrames:@[@(p.sourceFrame)]];
    Check(!resolved,@"fully blocked own region has no legal candidate");
    FYInlineCandidate *near=Candidate(CGRectMake(200,256,140,40),FYInlineAnchorBelow);
    resolved=[engine candidate:near resolvingCollisionsWithin:3 viewport:viewport placement:p otherSources:@[] sourceTexts:@[] selfIndex:0 placedFrames:@[@(CGRectMake(200,260,140,20))]];
    Check(!resolved,@"non-overlay movement stays inside original small tolerance");
    resolved=[engine candidate:base resolvingCollisionsWithin:3 viewport:viewport placement:p otherSources:@[@(p.sourceFrame),@(obstacle)] sourceTexts:@[@"合成字段",@"合成字段"] selfIndex:0 placedFrames:@[]];
    Check(resolved&&CGRectEqualToRect(resolved.frame,base.frame),@"duplicate-source exclusion also applies in actual collision resolver");
    base.distance=4;FYInlinePlacement *prior=Placement(p.sourceFrame);prior.anchor=base.anchor;prior.translationFrame=CGRectOffset(base.frame,20,10);
    Check([engine scoreForCandidate:base placement:p previous:nil columnAnchors:@{} columnKey:@1]==88,@"rank and distance retain original score");
    Check([engine scoreForCandidate:base placement:p previous:prior columnAnchors:@{@1:@(base.anchor)} columnKey:@1]==40.5,@"previous anchor, X/Y movement and same-column bonuses retain exact score");
    Check([engine scoreForCandidate:base placement:p previous:nil columnAnchors:@{@1:@(FYInlineAnchorBelow)} columnKey:@1]==102,@"different-column direction retains penalty");
    Check([[engine columnKeyForSourceFrame:CGRectMake(10,0,0,0) viewport:viewport]isEqual:@0]&&[[engine columnKeyForSourceFrame:CGRectMake(900,0,0,0) viewport:viewport]isEqual:@3]&&[[engine columnKeyForSourceFrame:CGRectMake(0,0,0,0) viewport:CGRectZero]isEqual:@2],@"column buckets use viewport origin, clamp and zero-width middle fallback");
    Check([[engine cardWidthCandidatesForSource:CGRectMake(0,0,180,60) viewport:viewport wide:NO]isEqual:@[@180,@225,@320]],@"finite width candidates preserve source, wider and baseline priority");
    Check([[engine cardWidthCandidatesForSource:CGRectMake(0,0,450,60) viewport:viewport wide:NO]isEqual:@[@416]]&&[[engine cardWidthCandidatesForSource:CGRectMake(0,0,450,60) viewport:viewport wide:YES]isEqual:@[@450,@496]],@"normal/wide fractions and dedup remain original");
    Check([[engine cardWidthCandidatesForSource:CGRectMake(0,0,20,60) viewport:CGRectMake(0,0,200,170) wide:NO]isEqual:@[@160]],@"narrow viewport keeps approved minimum width behavior");
    FYInlineLayoutResult *a=[FYInlineLayoutResult new],*b=[FYInlineLayoutResult new];FYInlinePlacement *before=Placement(p.sourceFrame),*now=Placement(p.sourceFrame);a.placements=@[now];b.placements=@[before];
    Check(![engine result:a differsFromPrevious:b]&&[engine result:a differsFromPrevious:nil],@"identical results retain no-change and absent history changes");
    now.measuredContentHeight+=.5;Check(![engine result:a differsFromPrevious:b],@"content-height change at original half-point threshold is stable");
    now.measuredContentHeight+=.01;Check([engine result:a differsFromPrevious:b],@"content-height change beyond original threshold changes revision");
    now.measuredContentHeight=before.measuredContentHeight;now.translationFrame=CGRectOffset(now.translationFrame,.01,0);Check([engine result:a differsFromPrevious:b],@"frame changes retain exact comparison without rounding");
    engine.collectsLayoutDiagnostics=NO;[engine recordCandidateAttempt:base resolved:base placement:p placed:@[] score:1];Check(!p.candidateDiagnostics.count,@"diagnostics remain opt-in");
    engine.collectsLayoutDiagnostics=YES;FYInlinePlacement *placed=Placement(p.sourceFrame);placed.blockID=@"other";placed.translationFrame=base.frame;
    [engine recordCandidateAttempt:base resolved:nil placement:p placed:@[placed] score:INFINITY];NSDictionary *event=p.candidateDiagnostics.lastObject;
    Check([event[@"translation_collisions"]isEqual:@[@"other"]]&&[event[@"score"]isEqual:NSNull.null]&&![event[@"feasible"]boolValue]&&[event[@"resolved_frame"]count]==0,@"failed attempt records original collisions, finite-score boundary and no fake frame");
    printf("PASS InlineLayoutCalculationTests: %lu checks; actual Foundation/CG candidates, filtering, collision resolution and scoring\n",(unsigned long)checks);
}return 0;}
