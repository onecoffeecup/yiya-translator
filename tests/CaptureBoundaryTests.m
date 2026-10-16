#import "capture/FYDisplayTargetTracker.h"
#import "capture/FYDisplayTargetResolver.h"
#import "capture/FYCaptureMapping.h"
#import "capture/FYCoordinateConversions.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *s){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",s.UTF8String);exit(2);}}
static NSDictionary *Window(uint32_t wid,int pid,CGRect r){return @{(id)kCGWindowNumber:@(wid),(id)kCGWindowOwnerPID:@(pid),(id)kCGWindowLayer:@0,(id)kCGWindowName:@"Preview",(id)kCGWindowBounds:CFBridgingRelease(CGRectCreateDictionaryRepresentation(r))};}
@interface GeometryProbe : NSObject <FYDisplayTargetGeometry>
@property(nonatomic) NSUInteger calls;
@property(nonatomic) CGFloat coverage;
@property(nonatomic) CGRect display;
@property(nonatomic) BOOL pickLast;
@property(nonatomic, strong) NSMutableArray *events;
@end
@implementation GeometryProbe
- (CGRect)displayBoundsContainingWindowInfo:(NSDictionary *)info { self.calls++;[self.events addObject:[NSString stringWithFormat:@"display%@",info[(id)kCGWindowNumber]]];return self.display; }
- (CGRect)mainDisplayBounds { self.calls++;[self.events addObject:@"main"];return self.display; }
- (CGFloat)screenCoverageForBounds:(CGRect)bounds { self.calls++;return self.coverage; }
- (NSArray *)strongestDisplayTargetCandidates:(NSArray *)candidates { self.calls++;return self.pickLast?@[candidates.lastObject]:[FYDisplayTargetResolver strongestDisplayTargetCandidates:candidates]; }
@end
int main(void){@autoreleasepool{
 FYDisplayTargetTracker *t=[FYDisplayTargetTracker new];Check(t&&!t.lastDisplayTargetProbeDate&&!t.lastWindowRecoveryAttemptDate&&!t.geometryGeneration&&!t.displayTargetResolved,@"cold tracker has zero state and no scheduled work");
 Check(!class_getInstanceVariable(t.class,"_host")&&!class_getInstanceVariable(t.class,"_timer"),@"tracker requires no host or timer storage");
 NSDate *zero=[NSDate dateWithTimeIntervalSinceReferenceDate:0];
 Check([t beginProbeAt:zero force:NO],@"first probe begins");Check(![t beginProbeAt:[zero dateByAddingTimeInterval:.39] force:NO]&&t.lastDisplayTargetProbeDate==zero,@"throttled probe preserves original date");
 Check([t beginProbeAt:[zero dateByAddingTimeInterval:.4] force:NO],@"exact .4 second probe boundary remains inclusive");Check([t beginProbeAt:zero force:YES]&&t.lastDisplayTargetProbeDate==zero,@"force bypasses throttle and records date");
 Check([t beginRecoveryAt:zero],@"first recovery begins");Check(![t beginRecoveryAt:[zero dateByAddingTimeInterval:1.99]]&&t.lastWindowRecoveryAttemptDate==zero,@"recovery is independently throttled");Check([t beginRecoveryAt:[zero dateByAddingTimeInterval:2]],@"exact two second recovery boundary remains inclusive");
 __block NSUInteger selections=0;uint32_t(^select)(void)=^uint32_t{selections++;return 17;};Check([t windowIDUsingSelection:select]==17&&selections==1,@"unresolved target lazily reads selected ID");
 Check([t acceptTargetID:0 ambiguous:NO],@"first resolved zero target is still a target change");Check([t windowIDUsingSelection:select]==0&&selections==1,@"resolved zero never falls back to selected ID");
 Check(![t acceptTargetID:0 ambiguous:NO],@"same resolved zero preserves changed flag");Check([t acceptTargetID:9 ambiguous:NO]&&[t windowIDUsingSelection:select]==9&&selections==1,@"resolved target keeps ID and skips selection read");
 CGRect r=CGRectMake(-400,100,800,400);Check([t recordPlacement:YES rect:r targetID:9 targetChanged:YES]&&t.geometryGeneration==1,@"first geometry advances revision");Check([t.lastDisplayGeometryToken isEqual:@"t=9|vp=-400.0,100.0,800.0,400.0"],@"geometry token retains original decimal precision and negative monitor coordinates");
 Check(![t recordPlacement:YES rect:CGRectMake(-399.999,100,800,400) targetID:9 targetChanged:NO]&&t.geometryGeneration==1,@"subprecision movement preserves old geometry identity");Check([t recordPlacement:YES rect:r targetID:9 targetChanged:YES]&&t.geometryGeneration==2,@"target change advances geometry even with equal viewport token");
 Check([t recordPlacement:NO rect:r targetID:9 targetChanged:NO]&&[t.lastDisplayGeometryToken isEqual:@"t=9|none"]&&t.geometryGeneration==3,@"missing placement keeps original none token");Check(![t recordPlacement:NO rect:CGRectZero targetID:9 targetChanged:NO],@"repeated unavailable placement does not advance geometry");
 Check([t acceptTargetID:0 ambiguous:YES]&&[t windowIDUsingSelection:select]==0&&selections==1,@"ambiguous target does not fall back or query selection");[t advanceAmbiguousGeometry];Check(t.geometryGeneration==4&&!t.lastDisplayGeometryToken,@"ambiguity advances and invalidates token");Check(![t acceptTargetID:0 ambiguous:YES],@"same ambiguity is not a target change");[t advanceAmbiguousGeometry];Check(t.geometryGeneration==5,@"repeated ambiguity still advances geometry by original rule");
 NSMutableString *token=[NSMutableString stringWithString:@"snapshot"];t.lastDisplayGeometryToken=token;[token appendString:@"changed"];Check([t.lastDisplayGeometryToken isEqual:@"snapshot"],@"compatibility token property retains copy semantics");
 __weak FYDisplayTargetTracker *weak;@autoreleasepool{FYDisplayTargetTracker *temporary=[FYDisplayTargetTracker new];weak=temporary;}Check(!weak,@"unused tracker releases without observers or external work");
 GeometryProbe *g=[GeometryProbe new];g.display=CGRectMake(0,0,1920,1080);g.coverage=1;g.events=[NSMutableArray array];BOOL ambiguous=YES;NSString *note=nil;
 Check([FYDisplayTargetResolver resolveWindowList:@[] selectedID:0 ownerPID:0 geometry:g ambiguous:&ambiguous note:&note]==0&&!ambiguous&&[note isEqual:@"请先选择显示窗口"]&&g.calls==0,@"empty selected ID keeps reason and does not query geometry");
 Check([FYDisplayTargetResolver resolveWindowList:@[] selectedID:17 ownerPID:0 geometry:g ambiguous:NULL note:NULL]==17&&g.calls==0,@"unobserved owner preserves selected ID and NULL outputs");
 NSDictionary *selected=Window(17,42,CGRectMake(100,100,800,600)),*front=Window(18,42,CGRectMake(0,0,1920,1080));
 Check([FYDisplayTargetResolver resolveWindowList:@[selected] selectedID:17 ownerPID:42 geometry:g ambiguous:&ambiguous note:NULL]==17&&!ambiguous,@"single selected window keeps original target");
 [g.events removeAllObjects];
 Check([FYDisplayTargetResolver resolveWindowList:@[front,selected] selectedID:17 ownerPID:42 geometry:g ambiguous:&ambiguous note:NULL]==18&&!ambiguous,@"front same-owner projection takes over");
 Check([g.events isEqual:@[@"display17",@"display18",@"display18",@"main"]],@"native geometry is queried lazily in the original exact order");
 Check([FYDisplayTargetResolver resolveWindowList:@[selected,front] selectedID:17 ownerPID:42 geometry:g ambiguous:&ambiguous note:NULL]==17,@"background projection cannot take over");
 NSDictionary *other=Window(19,99,CGRectMake(0,0,1920,1080));Check([FYDisplayTargetResolver resolveWindowList:@[other,selected] selectedID:17 ownerPID:42 geometry:g ambiguous:&ambiguous note:NULL]==17,@"other-owner large window cannot take over");
 NSDictionary *front2=Window(20,42,CGRectMake(0,0,1920,1080));Check([FYDisplayTargetResolver resolveWindowList:@[front,front2,selected] selectedID:17 ownerPID:42 geometry:g ambiguous:&ambiguous note:&note]==0&&ambiguous&&[note hasPrefix:@"检测到多个"],@"equal strongest candidates remain ambiguous");
 g.pickLast=YES;Check([FYDisplayTargetResolver resolveWindowList:@[front,front2,selected] selectedID:17 ownerPID:42 geometry:g ambiguous:NULL note:NULL]==20,@"explicit native candidate selector override remains in dispatch");g.pickLast=NO;
 NSUInteger calls=g.calls;g.coverage=0;Check([FYDisplayTargetResolver resolveWindowList:@[selected] selectedID:71 ownerPID:42 geometry:g ambiguous:NULL note:NULL]==0&&g.calls>calls,@"missing selected target still requires original .25 coverage for lone candidate");
 g.coverage=.25;Check([FYDisplayTargetResolver resolveWindowList:@[selected] selectedID:71 ownerPID:42 geometry:g ambiguous:NULL note:NULL]==17,@"exact .25 lone candidate coverage remains accepted");
 NSDictionary *large=Window(30,42,CGRectMake(0,0,1200,800)),*small=Window(31,42,CGRectMake(0,0,800,600));Check([FYDisplayTargetResolver resolveWindowList:@[large,small] selectedID:71 ownerPID:42 geometry:g ambiguous:NULL note:NULL]==30,@"offscreen selection follows uniquely dominant content window");
 g.display=CGRectZero;Check([FYDisplayTargetResolver resolveWindowList:@[front,selected] selectedID:17 ownerPID:42 geometry:g ambiguous:NULL note:NULL]==18,@"unresolved display geometry retains original projection fallback");
 FYCaptureMappingCache *cache=[FYCaptureMappingCache new];NSMutableDictionary *entries=[NSMutableDictionary dictionary];cache.entries=entries;[cache storeEntry:@{@"source":@"manual"} forWindowID:17];Check(cache.entries==entries&&[entries[@"17"] isEqual:@{@"source":@"manual"}],@"mapping owner preserves shared mutable container identity");
 Check(FYCaptureMappingVersion(@{@"source":@"manual",@"mappingVersion":@0},2)==FYCaptureMappingVersionNonAutomatic,@"manual mapping survives old automatic version gate");
 NSDictionary *map=[FYCaptureMappingAlgorithms captureMappingForRect:CGRectMake(-200,150,400,200) windowFrame:r videoAspect:2 deviceID:nil source:nil confidence:.75 version:2];Check([[map objectForKey:@"nx"] doubleValue]==.25&&CGRectEqualToRect([FYCaptureMappingAlgorithms captureMappingRect:map windowFrame:r],CGRectMake(-200,150,400,200)),@"independent mapping preserves plist and negative-monitor round trip");
 Check(CGRectEqualToRect([FYCoordinateConversions pixelCropForTopLeftRegion:CGRectMake(.9,.8,.3,.4) imageWidth:100 imageHeight:100],CGRectMake(90,80,10,20)),@"independent crop preserves clipping and top-left origin");
 Check(![FYCaptureMappingAlgorithms captureMappingScoreIsStale:-2 unavailableValue:-2]&&[FYCaptureMappingAlgorithms captureMappingScoreIsStale:.299 unavailableValue:-2],@"mapping sentinel and strict stale score preserved");
 printf("PASS capture boundary: %lu checks; Foundation/CG, target geometry/provider order, single state and canonical mapping\n",(unsigned long)checks);
 }return 0;}
