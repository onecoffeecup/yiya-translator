#import "FYInlineLayoutDebug.h"
#import "FYOCRManager.h"
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static NSString *const ContextKey = @"yiya.layout-debug.context";
NSDictionary *FYCurrentLayoutDebug(void) { return NSThread.currentThread.threadDictionary[ContextKey]; }
void FYLayoutDebugPerform(NSDictionary *context, void (^work)(void)) {
    NSMutableDictionary *thread = NSThread.currentThread.threadDictionary;
    id before = thread[ContextKey];
    if (context) thread[ContextKey] = context; else [thread removeObjectForKey:ContextKey];
    @try { work(); } @finally {
        if (before) thread[ContextKey] = before; else [thread removeObjectForKey:ContextKey];
    }
}
NSArray *FYLayoutDebugRect(CGRect r) { return @[@(r.origin.x), @(r.origin.y), @(r.size.width), @(r.size.height)]; }
static CGRect FYDebugRectFromArray(NSArray *a) { return a.count == 4 ? CGRectMake([a[0] doubleValue], [a[1] doubleValue], [a[2] doubleValue], [a[3] doubleValue]) : CGRectZero; }
void FYLayoutDebugPerformCrop(CGRect crop, CGSize size, void (^work)(void)) {
    NSDictionary *context = FYCurrentLayoutDebug();
    if (!context) { work(); return; }
    CGRect outer = context[@"vision_transform"] ? FYDebugRectFromArray(context[@"vision_transform"]) : CGRectMake(0, 0, 1, 1);
    CGRect local = CGRectMake(crop.origin.x / size.width, 1 - CGRectGetMaxY(crop) / size.height,
                             crop.size.width / size.width, crop.size.height / size.height);
    NSMutableDictionary *next = [context mutableCopy];
    next[@"vision_transform"] = FYLayoutDebugRect(CGRectMake(outer.origin.x + local.origin.x * outer.size.width,
        outer.origin.y + local.origin.y * outer.size.height, local.size.width * outer.size.width, local.size.height * outer.size.height));
    FYLayoutDebugPerform(next, work);
}
NSDictionary *FYLayoutDebugSnapshot(FYInlineLayoutResult *result, FYInlineLayoutResult *previous,
                                    CGRect viewport, NSDictionary *rendered, NSString *reason) {
    NSMutableArray *blocks = [NSMutableArray array];
    for (FYInlinePlacement *p in result.placements) {
        FYInlinePlacement *before = [previous placementForBlockID:p.blockID];
        NSMutableArray *sourceHits = [NSMutableArray array], *translationHits = [NSMutableArray array];
        for (FYInlinePlacement *other in result.placements) {
            if (other == p) continue;
            if (CGRectIntersectsRect(p.initialTranslationFrame, other.sourceFrame)) [sourceHits addObject:other.blockID];
            if (CGRectIntersectsRect(p.initialTranslationFrame, other.translationFrame)) [translationHits addObject:other.blockID];
        }
        NSMutableArray *lineBoxes = [NSMutableArray array];
        for (NSValue *value in p.block.lineBoxes) [lineBoxes addObject:FYLayoutDebugRect(value.rectValue)];
        NSDictionary *actual = rendered[p.blockID] ?: @{};
        [blocks addObject:@{@"stable_id": p.blockID ?: @"", @"source_id": p.sourceBlockID ?: @"",
            @"source": p.block.text ?: @"", @"translation": p.translation ?: @"",
            @"ocr_box": FYLayoutDebugRect(p.block.boundingBox), @"ocr_lines": lineBoxes,
            @"source_indices": p.block.sourceIndices ?: @[], @"kind": @(p.block.kind),
            @"grouping_confidence": @(p.groupingConfidence), @"target_box": FYLayoutDebugRect(p.sourceFrame),
            @"anchor": @[@(CGRectGetMinX(p.sourceFrame)), @(CGRectGetMinY(p.sourceFrame))],
            @"initial_frame": FYLayoutDebugRect(p.initialTranslationFrame), @"final_frame": FYLayoutDebugRect(p.translationFrame),
            @"predicted_panel_size": @[@(NSWidth(p.translationFrame)), @(NSHeight(p.translationFrame))],
            @"predicted_content_height": @(p.measuredContentHeight), @"predicted_label_frame": FYLayoutDebugRect(p.labelFrame),
            @"predicted_body_viewport": FYLayoutDebugRect(p.bodyViewportFrame), @"actual_render": actual,
            @"render_verified": @(actual.count > 0), @"font_name": p.font.fontName ?: @"", @"font_size": @(p.font.pointSize),
            @"mode": @(p.mode), @"anchor_direction": @(p.anchor), @"placement_reason": p.reason ?: @"",
            @"update_reason": reason ?: @"unspecified", @"source_collisions": sourceHits, @"translation_collisions": translationHits,
            @"candidate_evidence": p.candidateDiagnostics ?: @[], @"rejected_candidates": p.rejectedCandidates ?: @[],
            @"variant_evidence": p.variantDiagnostics ?: @[], @"manual": @(p.manuallyPlaced),
            @"avoidance_delta": @[@(NSMinX(p.translationFrame)-NSMinX(p.initialTranslationFrame)), @(NSMinY(p.translationFrame)-NSMinY(p.initialTranslationFrame))],
            @"automatic_origin_bounds": FYLayoutDebugRect(p.automaticOriginBounds),
            @"maximum_displacement": @[@(MAX(fabs(NSMinX(p.automaticOriginBounds)-NSMinX(p.initialTranslationFrame)),fabs(NSMaxX(p.automaticOriginBounds)-NSMinX(p.initialTranslationFrame)))),
                @(MAX(fabs(NSMinY(p.automaticOriginBounds)-NSMinY(p.initialTranslationFrame)),fabs(NSMaxY(p.automaticOriginBounds)-NSMinY(p.initialTranslationFrame))))],
            @"previous_present": @(before != nil),
            @"position_delta": @[@(before ? NSMinX(p.translationFrame)-NSMinX(before.translationFrame) : 0), @(before ? NSMinY(p.translationFrame)-NSMinY(before.translationFrame) : 0)]}];
    }
    return @{@"schema_version": @1, @"coordinate_system": @"AppKit screen points, bottom-left; OCR normalized bottom-left",
        @"viewport": FYLayoutDebugRect(viewport), @"layout_revision": @(result.revision),
        @"changed": @(result!=previous && result.changedFromPrevious), @"layout_reused": @(result==previous), @"layout_pass_count": @(result==previous ? 0 : result.layoutPassCount), @"update_reason": reason ?: @"unspecified", @"blocks": blocks};
}

#if defined(FY_ENABLE_LAYOUT_DEBUG) && FY_ENABLE_LAYOUT_DEBUG
// The same drawing routine serves the live overlay and the exported PNG.
static void DrawSnapshot(NSDictionary *snapshot) {
    CGRect viewport = FYDebugRectFromArray(snapshot[@"viewport"]);
    for (NSDictionary *raw in snapshot[@"raw_ocr"] ?: @[]) {
        CGRect b = FYDebugRectFromArray(raw[@"full_box"]);
        CGRect r = CGRectMake(b.origin.x*viewport.size.width, b.origin.y*viewport.size.height,
                              b.size.width*viewport.size.width, b.size.height*viewport.size.height);
        [NSColor.greenColor setStroke]; NSBezierPath *path = [NSBezierPath bezierPathWithRect:r]; path.lineWidth = 1; [path stroke];
    }
    NSUInteger index = 0;
    for (NSDictionary *b in snapshot[@"blocks"]) {
        CGRect target = CGRectOffset(FYDebugRectFromArray(b[@"target_box"]), -viewport.origin.x, -viewport.origin.y);
        CGRect initial = CGRectOffset(FYDebugRectFromArray(b[@"initial_frame"]), -viewport.origin.x, -viewport.origin.y);
        CGRect final = CGRectOffset(FYDebugRectFromArray(b[@"final_frame"]), -viewport.origin.x, -viewport.origin.y);
        [NSColor.yellowColor setStroke];
        NSBezierPath *cross = [NSBezierPath bezierPath];
        [cross moveToPoint:NSMakePoint(NSMinX(target)-5, NSMinY(target))]; [cross lineToPoint:NSMakePoint(NSMinX(target)+5, NSMinY(target))];
        [cross moveToPoint:NSMakePoint(NSMinX(target), NSMinY(target)-5)]; [cross lineToPoint:NSMakePoint(NSMinX(target), NSMinY(target)+5)]; [cross stroke];
        [NSColor.blueColor setStroke]; NSBezierPath *blue = [NSBezierPath bezierPathWithRect:initial]; blue.lineWidth=2; [blue stroke];
        if ([b[@"mode"] integerValue] != FYInlineDisplayModeUnplaceable) {
            [NSColor.redColor setStroke]; NSBezierPath *red=[NSBezierPath bezierPathWithRect:final]; red.lineWidth=2; [red stroke];
            NSBezierPath *line=[NSBezierPath bezierPath]; [line moveToPoint:target.origin]; [line lineToPoint:final.origin]; [line stroke];
        }
        [[NSString stringWithFormat:@"%lu", (unsigned long)++index] drawAtPoint:NSMakePoint(NSMinX(target), NSMaxY(target)+2)
            withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12], NSForegroundColorAttributeName:NSColor.yellowColor,
                             NSBackgroundColorAttributeName:NSColor.blackColor}];
    }
}
@interface FYLayoutDebugView : NSView
@property NSDictionary *snapshot;
@end
@implementation FYLayoutDebugView
- (void)drawRect:(NSRect)dirty { DrawSnapshot(self.snapshot); }
@end
@interface FYInlineLayoutDebug ()
@property NSString *directory;
@property NSMutableDictionary *frames;
@property NSString *session;
@property NSUInteger frameCount, layoutCount, savedBytes;
@property NSPanel *overlay;
@property NSTimer *expiryTimer;
@end
@implementation FYInlineLayoutDebug
+ (NSString *)defaultDirectory { return [NSString stringWithFormat:@"/tmp/yiya-layout-debug-%u", getuid()]; }
+ (instancetype)shared {
    static FYInlineLayoutDebug *debug; static dispatch_once_t once;
    dispatch_once(&once, ^{ debug=[[self alloc] initWithDirectory:self.defaultDirectory]; }); return debug;
}
- (instancetype)initWithDirectory:(NSString *)directory {
    if ((self=[super init])) { _directory=[directory copy]; _frames=[NSMutableDictionary dictionary]; } return self;
}
- (NSDictionary *)control {
#ifdef FY_TEST_ISOLATED_CREDENTIAL_STORE
    // Test binaries may use a private instance, never the live user's control.
    if ([self.directory isEqualToString:self.class.defaultDirectory]) return nil;
#endif
    struct stat st;
    if (lstat(self.directory.fileSystemRepresentation,&st) || !S_ISDIR(st.st_mode) || st.st_uid!=getuid() || (st.st_mode&077)) return nil;
    NSString *path=[self.directory stringByAppendingPathComponent:@"control.json"];
    int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);
    if (fd<0) return nil;
    BOOL safe=fstat(fd,&st)==0 && S_ISREG(st.st_mode) && st.st_uid==getuid() && !(st.st_mode&077) && st.st_nlink==1 && st.st_size>0 && st.st_size<=4096;
    char bytes[4096]; ssize_t count=safe?read(fd,bytes,sizeof(bytes)):-1; close(fd);
    if (count<=0) return nil;
    id c=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:count] options:0 error:NULL];
    if (![c isKindOfClass:NSDictionary.class] || ![c[@"session"] isKindOfClass:NSString.class] ||
        ![[NSUUID alloc] initWithUUIDString:c[@"session"]] || ![c[@"issued_at"] isKindOfClass:NSNumber.class] ||
        ![c[@"expires_at"] isKindOfClass:NSNumber.class]) return nil;
    double now=NSDate.date.timeIntervalSince1970, start=[c[@"issued_at"] doubleValue], end=[c[@"expires_at"] doubleValue];
    if (!isfinite(start) || !isfinite(end) || start>now || end<=now || end<=start || end-start>300) return nil;
    return c;
}
- (BOOL)isActive { @synchronized(self) { return [self control]!=nil; } }
- (BOOL)validContext:(NSDictionary *)context {
    NSDictionary *c=[self control]; return context && c && [c[@"session"] isEqual:context[@"session"]] && self.savedBytes<64*1024*1024;
}
- (BOOL)writeData:(NSData *)data name:(NSString *)name {
    if (!data || self.savedBytes+data.length>64*1024*1024) return NO;
    NSString *path=[self.directory stringByAppendingPathComponent:name];
    int fd=open(path.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if (fd<0) return NO;
    NSUInteger offset=0; BOOL ok=YES;
    while (offset<data.length) { ssize_t written=write(fd,(const char *)data.bytes+offset,data.length-offset); if(written<=0){ok=NO;break;} offset+=written; }
    close(fd); if (!ok) { unlink(path.fileSystemRepresentation); return NO; } self.savedBytes+=data.length; return YES;
}
- (NSDictionary *)beginFrameWithImage:(CGImageRef)image metadata:(NSDictionary *)metadata {
    @synchronized(self) {
        NSDictionary *control=[self control]; if (!control || !image) return nil;
        if (![self.session isEqual:control[@"session"]]) { self.session=control[@"session"]; self.frameCount=0; self.layoutCount=0; self.savedBytes=0; [self.frames removeAllObjects]; }
        if (self.frameCount>=120 || self.savedBytes>=64*1024*1024) return nil;
        NSString *frame=NSUUID.UUID.UUIDString;
        NSData *png=[[[NSBitmapImageRep alloc] initWithCGImage:image] representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (![self writeData:png name:[frame stringByAppendingString:@".source.png"]]) return nil;
        self.frameCount++;
        NSMutableDictionary *context=[@{@"session":self.session,@"frame_id":frame,@"time_unix_ms":@(llround(NSDate.date.timeIntervalSince1970*1000)),
            @"image_size":@[@(CGImageGetWidth(image)),@(CGImageGetHeight(image))]} mutableCopy];
        // Only geometry/session metadata, never arbitrary settings.
        for (NSString *key in @[@"input_source",@"input_epoch",@"window_id",@"generation",@"geometry_generation",@"frame_index",@"scope"]) if(metadata[key]) context[key]=metadata[key];
        self.frames[frame]=[NSMutableDictionary dictionaryWithDictionary:@{@"context":context,@"raw_ocr":[NSMutableArray array],@"stages":[NSMutableDictionary dictionary]}];
        return [context copy];
    }
}
- (void)recordItems:(NSArray<OCRTextItem *> *)items stage:(NSString *)stage context:(NSDictionary *)context {
    @synchronized(self) {
        if (![self validContext:context]) return;
        NSMutableDictionary *frame=self.frames[context[@"frame_id"]]; if (!frame) return;
        NSMutableArray *lines=[NSMutableArray array];
        CGRect transform=context[@"vision_transform"]?FYDebugRectFromArray(context[@"vision_transform"]):CGRectMake(0,0,1,1);
        for (OCRTextItem *item in items) {
            CGRect b=item.boundingBox;
            CGRect full=CGRectMake(transform.origin.x+b.origin.x*transform.size.width,transform.origin.y+b.origin.y*transform.size.height,
                                   b.size.width*transform.size.width,b.size.height*transform.size.height);
            [lines addObject:@{@"text":item.text?:@"",@"box":FYLayoutDebugRect(b),@"full_box":FYLayoutDebugRect(full),@"confidence":@(item.confidence),@"vision_transform":FYLayoutDebugRect(transform),@"vision_image_size":context[@"vision_image_size"] ?: @[]} ];
        }
        if ([stage isEqual:@"vision_raw"]) [frame[@"raw_ocr"] addObjectsFromArray:lines];
        else frame[@"stages"][stage]=lines;
    }
}
- (void)recordLayout:(NSDictionary *)snapshot context:(NSDictionary *)context {
    [self recordLayout:snapshot context:context renderedImages:@{}];
}
- (void)recordDecision:(NSString *)reason context:(NSDictionary *)context {
    @synchronized(self) {
        if (![self validContext:context] || self.layoutCount>=300) return;
        NSMutableDictionary *record=[context mutableCopy];record[@"decision"]=reason;
        record[@"time_unix_ms"]=@(llround(NSDate.date.timeIntervalSince1970*1000));
        NSString *name=[NSString stringWithFormat:@"%@.%04lu.decision.json",context[@"frame_id"],(unsigned long)++self.layoutCount];
        [self writeData:[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:NULL] name:name];
    }
}
- (void)recordLayout:(NSDictionary *)snapshot context:(NSDictionary *)context renderedImages:(NSDictionary<NSString *,NSData *> *)images {
    @synchronized(self) {
        if (![self validContext:context] || self.layoutCount>=300) return;
        NSDictionary *frame=self.frames[context[@"frame_id"]]; if(!frame) return;
        NSMutableDictionary *record=[snapshot mutableCopy]; [record addEntriesFromDictionary:frame[@"context"]];
        record[@"raw_ocr"]=frame[@"raw_ocr"]; record[@"stages"]=frame[@"stages"];
        record[@"layout_time_unix_ms"]=@(llround(NSDate.date.timeIntervalSince1970*1000));
        NSString *name=[NSString stringWithFormat:@"%@.%04lu",context[@"frame_id"],(unsigned long)++self.layoutCount];
        NSData *json=[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:NULL];
        if (![self writeData:json name:[name stringByAppendingString:@".json"]]) return;
        CGRect vp=FYDebugRectFromArray(record[@"viewport"]); CGSize size=NSMakeSize(ceil(vp.size.width),ceil(vp.size.height));
        if (size.width<2 || size.height<2 || size.width*size.height>16000000) return;
        NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:size.width pixelsHigh:size.height
            bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
        NSImage *source=[[NSImage alloc] initWithContentsOfFile:[self.directory stringByAppendingPathComponent:[context[@"frame_id"] stringByAppendingString:@".source.png"]]];
        [source drawInRect:NSMakeRect(0,0,size.width,size.height)];
        for (NSDictionary *block in record[@"blocks"]) {
            NSData *png=images[block[@"stable_id"]];if(!png) continue;
            NSImage *render=[[NSImage alloc] initWithData:png];
            CGRect panel=FYDebugRectFromArray(block[@"actual_render"][@"panel_frame"]);
            [render drawInRect:CGRectOffset(panel,-vp.origin.x,-vp.origin.y)];
        }
        DrawSnapshot(record);
        [NSGraphicsContext restoreGraphicsState];
        [self writeData:[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] name:[name stringByAppendingString:@".overlay.png"]];
        if (NSThread.isMainThread) [self showSnapshot:record viewport:vp];
    }
}
- (void)showSnapshot:(NSDictionary *)snapshot viewport:(CGRect)viewport {
    if (![self isActive] || ![[self control][@"overlay"] boolValue]) return;
    if (!self.overlay) {
        self.overlay=[[NSPanel alloc] initWithContentRect:viewport styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        self.overlay.backgroundColor=NSColor.clearColor; self.overlay.opaque=NO; self.overlay.hasShadow=NO; self.overlay.ignoresMouseEvents=YES;
        self.overlay.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
        self.overlay.contentView=[[FYLayoutDebugView alloc] initWithFrame:NSMakeRect(0,0,viewport.size.width,viewport.size.height)];
        __weak FYInlineLayoutDebug *weak=self;
        self.expiryTimer=[NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer *timer) { (void)timer; if(![weak isActive]) [weak clearOverlay]; }];
    }
    [self.overlay setFrame:viewport display:NO]; ((FYLayoutDebugView *)self.overlay.contentView).snapshot=snapshot; self.overlay.contentView.needsDisplay=YES;
}
- (void)refreshVisible:(BOOL)visible level:(NSInteger)level {
    if (![self isActive]) { [self clearOverlay]; return; }
    self.overlay.level=level+1; if(visible) [self.overlay orderFrontRegardless]; else [self.overlay orderOut:nil];
}
- (void)clearOverlay { [self.overlay close]; self.overlay=nil; [self.expiryTimer invalidate]; self.expiryTimer=nil; }
@end

#else
// Default and release builds cannot be armed by another process's control file.
@implementation FYInlineLayoutDebug
+ (NSString *)defaultDirectory { return [NSString stringWithFormat:@"/tmp/yiya-layout-debug-%u", getuid()]; }
+ (instancetype)shared { static FYInlineLayoutDebug *debug; static dispatch_once_t once;
    dispatch_once(&once, ^{ debug=[self new]; }); return debug; }
- (instancetype)initWithDirectory:(NSString *)directory { return [super init]; }
- (BOOL)isActive { return NO; }
- (NSDictionary *)beginFrameWithImage:(CGImageRef)image metadata:(NSDictionary *)metadata { return nil; }
- (void)recordItems:(NSArray *)items stage:(NSString *)stage context:(NSDictionary *)context {}
- (void)recordLayout:(NSDictionary *)snapshot context:(NSDictionary *)context {}
- (void)recordLayout:(NSDictionary *)snapshot context:(NSDictionary *)context renderedImages:(NSDictionary *)images {}
- (void)recordDecision:(NSString *)reason context:(NSDictionary *)context {}
- (void)showSnapshot:(NSDictionary *)snapshot viewport:(CGRect)viewport {}
- (void)refreshVisible:(BOOL)visible level:(NSInteger)level {}
- (void)clearOverlay {}
@end
#endif
