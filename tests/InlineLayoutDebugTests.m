// Headless production geometry/grouping/layout and real NSCell/scroll-body updates.
// No NSApplication, NSWindow, screen capture, hardware, settings, database or HTTP.
#import "LearningAppTestSupport.h"
#import <sys/stat.h>
static NSUInteger Assertions;
static NSString *Stage;
static NSMutableDictionary *Report;
static NSString *EvidenceOutput;
static NSDictionary *LoadScene(NSString *name);
static void ExportScene(NSDictionary *scene, NSArray *requests, FYInlineLayoutResult *result);
static void Check(BOOL ok, NSString *message) {
    Assertions++;
    if (!ok) @throw [NSException exceptionWithName:@"LayoutGateFailure" reason:message userInfo:nil];
}
static CGRect R(NSArray *a) { return CGRectMake([a[0] doubleValue],[a[1] doubleValue],[a[2] doubleValue],[a[3] doubleValue]); }
static FYInlineTextBlock *Block(NSString *text, CGRect box, BOOL longBody) {
    FYInlineTextBlock *b=[FYInlineTextBlock new]; b.text=text; b.lineTexts=[text componentsSeparatedByString:@"\n"];
    b.lineBoxes=@[[NSValue valueWithRect:box]]; b.boundingBox=box; b.kind=longBody?FYInlineBlockKindLong:FYInlineBlockKindShort;
    b.blockID=[FYInlineBlockMatcher blockIDForText:text lineBoxes:b.lineBoxes]; return b;
}
// The actual update method only needs these NSPanel endpoints. There is no window server allocation.
@interface LayoutPanelSink : NSObject
@property NSRect frame;
@property NSView *contentView;
- (void)setFrame:(NSRect)frame display:(BOOL)display;
- (void)displayIfNeeded;
@end
@implementation LayoutPanelSink
- (void)setFrame:(NSRect)frame display:(BOOL)display { self.frame=frame; }
- (void)displayIfNeeded {}
@end
@interface LayoutHeadlessApp : AppDelegate @end
@implementation LayoutHeadlessApp
- (NSInteger)effectiveModeSegment { return ContentModeUI; }
- (uint32_t)displayTargetWindowID { return 100; }
- (BOOL)inlinePlacementRect:(NSRect *)rect reason:(NSString **)reason { if(rect)*rect=CGRectMake(0,0,800,600);return YES; }
- (BOOL)inlineBlockID:(NSString *)identity isSelectedForItem:(OCRTextItem *)item { return NO; }
- (void)wireInlineLongCardPanel:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(NSRect)frame stableBlockID:(NSString *)identity {}
@end
static CGImageRef SyntheticImage(NSDictionary *scene) {
    if(scene[@"image"]) {
        NSImage *image=[[NSImage alloc] initWithContentsOfFile:[@"tests/fixtures/layout" stringByAppendingPathComponent:scene[@"image"]]];
        CGImageRef pixels=[image CGImageForProposedRect:NULL context:nil hints:nil];
        Check(pixels!=NULL,@"fixed screenshot asset loads without a screen capture");
        return CGImageRetain(pixels);
    }
    size_t width=[scene[@"image_size"][0] unsignedIntegerValue],height=[scene[@"image_size"][1] unsignedIntegerValue];
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(NULL,width,height,8,width*4,space,kCGImageAlphaPremultipliedLast); CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(ctx,.16,.17,.20,1); CGContextFillRect(ctx,CGRectMake(0,0,width,height));
    [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO]];
    for(NSDictionary *line in scene[@"lines"]) {
        CGRect b=R(line[@"box"]); CGRect box=CGRectMake(b.origin.x*width,b.origin.y*height,b.size.width*width,b.size.height*height);
        [line[@"text"] drawInRect:box withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:24],NSForegroundColorAttributeName:NSColor.whiteColor}];
    }
    [NSGraphicsContext restoreGraphicsState]; CGImageRef image=CGBitmapContextCreateImage(ctx); CGContextRelease(ctx); return image;
}
static NSArray *SceneRequests(NSDictionary *scene, CGFloat noise) {
    NSMutableArray *lines=[NSMutableArray array];
    for(NSDictionary *raw in scene[@"lines"]) {
        CGRect box=R(raw[@"box"]); box.origin.x+=noise; box.origin.y-=noise;
        [lines addObject:[FYInlineTextLine lineWithText:raw[@"text"] rect:box confidence:.95 sourceIndex:lines.count]];
    }
    NSArray *blocks=[[FYInlineGrouper defaultGrouper] blocksFromLines:lines];
    Check(blocks.count==[scene[@"expected_blocks"] unsignedIntegerValue], [scene[@"name"] stringByAppendingString:@": production grouping preserves expected fields/paragraphs"]);
    NSMutableArray *requests=[NSMutableArray array];
    for(FYInlineTextBlock *block in blocks) {
        NSMutableArray *translations=[NSMutableArray array];
        for(NSNumber *index in block.sourceIndices) [translations addObject:scene[@"lines"][index.unsignedIntegerValue][@"translation"]];
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:block translation:[translations componentsJoinedByString:@"\n"]
            sourceFrame:[FYGeometryManager frameForNormalizedBox:block.boundingBox inViewport:R(scene[@"viewport"])]]];
    }
    return requests;
}
static void P0(void) {
    FYInlineLayoutEngine *engine=[FYInlineLayoutEngine defaultEngine];
    CGRect viewport=CGRectMake(-400,140,800,600), box=CGRectMake(.125,.625,.25,.05);
    // Expected values are analytic; independent of the conversion implementation.
    Check(NSEqualRects([FYGeometryManager frameForNormalizedBox:box inViewport:viewport],CGRectMake(-300,515,200,30)),@"P0: bottom-left OCR to screen points including negative screen origin");
    Check(NSEqualRects([FYGeometryManager frameForTopLeftNormalizedBox:CGRectMake(.125,.325,.25,.05) inViewport:viewport],CGRectMake(-300,515,200,30)),@"P0: top-left capture region inversion occurs exactly once");
    for (NSNumber *scale in @[@1,@2]) {
        size_t width=1600*scale.unsignedIntegerValue,height=1200*scale.unsignedIntegerValue;
        CGColorSpaceRef space=CGColorSpaceCreateDeviceGray(); CGContextRef c=CGBitmapContextCreate(NULL,width,height,8,width,space,kCGImageAlphaNone);CGColorSpaceRelease(space);
        CGImageRef image=CGBitmapContextCreateImage(c);CGContextRelease(c);
        OCRTextItem *local=[OCRTextItem new];local.text=@"設定";local.boundingBox=CGRectMake(.25,.5,.5,.1);
        __block NSArray *mapped;
        FYLayoutDebugPerform(@{@"frame_id":@"synthetic-context"}, ^{ mapped=[FYOCRManager recognizeImage:image topLeftScope:CGRectMake(.25,.2,.5,.5) recognizer:^NSArray *(CGImageRef crop,NSError **error) {
            CGRect transform=R(FYCurrentLayoutDebug()[@"vision_transform"]);
            Check(fabs(transform.origin.x-.25)<1e-9 && fabs(transform.origin.y-.3)<1e-9 && transform.size.width==.5 && transform.size.height==.5,
                @"P0: diagnostic green boxes use the actual crop transform");
            return @[local];
        } error:NULL]; });
        Check(FYCurrentLayoutDebug()==nil,@"P0: immutable crop context does not leak to the next frame");
        CGRect expected=CGRectMake(.375,.55,.25,.05);
        Check(fabs(((OCRTextItem *)mapped[0]).boundingBox.origin.x-expected.origin.x)<1e-9 && fabs(local.boundingBox.origin.y-expected.origin.y)<1e-9,@"P0: actual pixel crop remaps Vision local coordinates, independent of Retina scale");
        CGRect frame=[FYGeometryManager frameForNormalizedBox:local.boundingBox inViewport:viewport];
        Check(NSEqualRects(frame,CGRectMake(-100,470,200,30)),@"P0: captured pixels normalize into points without a second backing-scale multiplication");
        FYInlinePlacement *p=[engine initialPlacementForRequest:[FYInlineLayoutRequest requestWithBlock:Block(@"設定",box,NO) translation:@"设置" sourceFrame:CGRectMake(-300,515,200,30)] viewport:viewport];
        Check(p.anchor==FYInlineAnchorBelow && NSMinX(p.translationFrame)==-300 && NSMaxY(p.translationFrame)==511,@"P0: one measured box uses the production below-anchor with avoidance/history disabled");
        CGImageRelease(image);
    }
    NSDictionary *scene=LoadScene(@"sparse-menu");
    FYInlineLayoutRequest *single=SceneRequests(scene,0).firstObject;
    FYInlinePlacement *initial=[engine initialPlacementForRequest:single viewport:R(scene[@"viewport"])];
    FYInlineLayoutResult *result=[FYInlineLayoutResult new];result.placements=@[initial];
    NSMutableDictionary *sample=[scene mutableCopy];sample[@"name"]=@"p0-single";ExportScene(sample,@[single],result);
    Report[@"P0"]=@{@"status":@"passed",@"scope":@"fixed pixels + fixed Vision observations; no real device mapping"};
}
static BOOL HasVisibleLabel(NSView *view, NSString *text) {
    if(view.hidden)return NO;
    if([view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue isEqualToString:text])return YES;
    for(NSView *child in view.subviews)if(HasVisibleLabel(child,text))return YES;
    return NO;
}
static NSScrollView *BodyScroll(NSView *view) {
    for(NSView *child in view.subviews)if([child isKindOfClass:NSScrollView.class])return (NSScrollView *)child;
    return nil;
}
static void P1OrdinaryTitlePolicy(void) {
    LayoutHeadlessApp *app=[LayoutHeadlessApp new];FYInlineLayoutEngine *engine=app.inlineLayoutEngine;
    FYInlineLayoutRequest *request=[FYInlineLayoutRequest requestWithBlock:Block(@"合成通知正文。\n请查看活动安排。",CGRectMake(.2,.5,.4,.12),YES)
        translation:@"本周活动照常举行，请查看集合安排。" sourceFrame:CGRectMake(160,300,320,72)];
    FYInlinePlacement *p=[engine initialPlacementForRequest:request viewport:CGRectMake(0,0,800,600)];
    NSView *content=[app inlineLongCardContentForTranslation:request.translation size:p.translationFrame.size selected:NO compact:NO placement:p];
    NSScrollView *scroll=BodyScroll(content);
    Check(((FYInlineLongCardView *)content).titleBarHeight==p.panelPadding,
        @"P1: newly created ordinary content cannot retain the old heading-sized drag region");
    Report[@"P1_ordinary_title_observation"]=@{@"title_band_height":@(p.titleBandHeight),
        @"visible_heading":@(HasVisibleLabel(content,@"中文译文")),@"body_top":@(NSMinY(scroll.frame)),@"padding":@(p.panelPadding)};
    Check(!HasVisibleLabel(content,@"中文译文") && p.titleBandHeight==0,
        @"P1: ordinary inline body cards show only translation, with no heading or reserved title band");
    Check(scroll && NSMinY(scroll.frame)==p.panelPadding && NSEqualRects(scroll.frame,p.bodyViewportFrame),
        @"P1: removing the heading moves native body to padding without a ghost title gap");
    Check(!p.scrollable && fabs(NSHeight(p.translationFrame)-(NSHeight(scroll.documentView.frame)+2*p.panelPadding))<=.5,
        @"P1: a short body card height equals actual rendered text plus its existing padding");
    for(NSDictionary *variant in [engine longCardVariantsForRequest:request viewport:CGRectMake(0,0,800,600)])
        Check([variant[@"titleBand"] doubleValue]==0,@"P1: ordinary cards cannot regain a heading in a narrower/lower-font variant");
    NSFont *font=[engine longBodyFont];
    CGFloat expectedMinimum=36+(ceil(font.ascender-font.descender+font.leading)+engine.longLineSpacing)*engine.minimumBodyLines;
    Check(fabs(engine.minimumCardHeight-expectedMinimum)<.5,@"P1: readable minimum excludes the removed title band");
    FYInlinePlacement *limited=[engine initialPlacementForRequest:request viewport:CGRectMake(0,0,800,expectedMinimum+24)];
    Check(!limited.compactEntry,@"P1: a viewport with room for padding and readable body must not fold because of a removed title");
    FYInlinePlacement *compat=[app inlinePlacementForLongCardFrame:CGRectMake(0,0,320,180) translation:request.translation];
    NSView *compatContent=[app inlineLongCardContentForTranslation:request.translation size:compat.translationFrame.size selected:NO compact:NO placement:compat];
    Check(compat.titleBandHeight==0 && !HasVisibleLabel(compatContent,@"中文译文") &&
        NSEqualRects(BodyScroll(compatContent).frame,compat.bodyViewportFrame),
        @"P1: explicitly sized ordinary cards use the same headerless rendering/measurement policy");
    LayoutPanelSink *sink=[LayoutPanelSink new];sink.frame=p.translationFrame;sink.contentView=content;
    [app wireInlinePanelDrag:(NSPanel *)sink placement:p];
    FYInlineLongCardView *card=(FYInlineLongCardView *)content;
    Check(card.titleBarHeight==p.panelPadding && [card pointIsInTitleBar:NSMakePoint(20,p.panelPadding/2)] &&
        ![card pointIsInTitleBar:NSMakePoint(20,p.panelPadding+10)],
        @"P1: top padding keeps card dragging while the body remains a distinct click/scroll region");
    FYInlinePlacement *reading=[app inlinePlacementForLongCardFrame:CGRectMake(0,0,320,240) translation:request.translation expandedReading:YES];
    reading.entryTitle=@"活动通知";
    NSView *readingContent=[app inlineLongCardContentForTranslation:request.translation size:reading.translationFrame.size selected:YES compact:NO placement:reading];
    Check(reading.expandedReading && reading.titleBandHeight==37 && HasVisibleLabel(readingContent,@"活动通知"),
        @"P1: explicitly expanded reading retains its own title and header space");
    NSScrollView *readingScroll=BodyScroll(readingContent);
    Check(NSEqualRects(readingScroll.frame,reading.bodyViewportFrame) &&
        fabs(NSHeight(readingScroll.documentView.frame)-reading.measuredContentHeight)<=.5,
        @"P1: expanded header/body/document use the same production measurements");
    [app updateInlineLongCard:(NSPanel *)sink translation:request.translation item:nil frame:reading.translationFrame compact:NO placement:reading];
    Check(HasVisibleLabel(sink.contentView,@"活动通知"),@"P1: reusing an ordinary panel as expanded reading adds the title");
    [app updateInlineLongCard:(NSPanel *)sink translation:request.translation item:nil frame:p.translationFrame compact:NO placement:p];
    Check(!HasVisibleLabel(sink.contentView,@"活动通知") && !HasVisibleLabel(sink.contentView,@"中文译文") &&
        NSEqualRects(BodyScroll(sink.contentView).frame,p.bodyViewportFrame),
        @"P1: returning to ordinary inline display removes stale title and header space");
    Report[@"P1_ordinary_title"]=@{@"status":@"passed",@"native_body_measurement":@YES,@"drag_regions":@YES};
}
static void P1(void) {
    P1OrdinaryTitlePolicy();
    for(NSString *name in @[@"sparse-menu",@"dense-menu",@"multiline"]) SceneRequests(LoadScene(name),0);
    LayoutHeadlessApp *app=[LayoutHeadlessApp new]; FYInlineLayoutEngine *engine=app.inlineLayoutEngine;
    CGRect viewport=CGRectMake(0,0,800,600);
    FYInlineLayoutRequest *r=[FYInlineLayoutRequest requestWithBlock:Block(@"合成段落。\n用于尺寸验证。",CGRectMake(.1,.4,.5,.2),YES)
        translation:@"这是一段合成的中文正文，用于检查更新前后换行宽度以及完整正文高度是否一致。" sourceFrame:CGRectMake(80,240,400,120)];
    FYInlinePlacement *p=[engine initialPlacementForRequest:r viewport:viewport];
    NSView *normal=[app inlineLongCardContentForTranslation:r.translation size:p.translationFrame.size selected:NO compact:NO placement:p];
    for(NSView *child in normal.subviews) if([child isKindOfClass:NSScrollView.class]) {
        NSScrollView *view=(NSScrollView *)child;
        Check(fabs(NSHeight(view.documentView.frame)-p.measuredContentHeight)<=.5,@"P1: predicted content height equals the production renderer document height");
        Check(NSEqualRects(view.frame,p.bodyViewportFrame),@"P1: predicted body viewport equals the production renderer viewport");
    }
    // Force a supported compact-chrome variant (12pt padding), without changing its font.
    p.panelPadding=12;p.titleBandHeight=0;p.translationFrame=CGRectMake(80,100,280,160);
    LayoutPanelSink *panel=[LayoutPanelSink new]; panel.frame=p.translationFrame;
    panel.contentView=[app inlineLongCardContentForTranslation:r.translation size:panel.frame.size selected:NO compact:NO placement:p];
    NSScrollView *scroll=nil;for(NSView *v in panel.contentView.subviews) if([v isKindOfClass:NSScrollView.class])scroll=(NSScrollView *)v;
    NSTextField *label=(NSTextField *)scroll.documentView;
    CGFloat beforeWidth=NSWidth(label.frame),beforeHeight=NSHeight(label.frame);
    Check(beforeWidth==256,@"P1: initial renderer uses layout padding (280 - 24 = 256)");
    [app updateInlineLongCard:(NSPanel *)panel translation:r.translation item:nil frame:panel.frame compact:NO placement:p];
    Report[@"P1_observation"]=@{@"initial_document_width":@(beforeWidth),@"updated_document_width":@(NSWidth(label.frame)),
        @"initial_document_height":@(beforeHeight),@"updated_document_height":@(NSHeight(label.frame)),@"expected_width":@256};
    Check(NSWidth(label.frame)==beforeWidth,@"P1: production reused card must keep the same document width as initial rendering");
    Check(NSHeight(label.frame)==beforeHeight,@"P1: production reused card must keep the same measured height for unchanged text/style");
    p.panelPadding=18;
    [app updateInlineLongCard:(NSPanel *)panel translation:r.translation item:nil frame:panel.frame compact:NO placement:p];
    Check(panel.contentView!=scroll.superview,@"P1: changing body padding at the same card size rebuilds stale body geometry");
    NSScrollView *updatedScroll=nil;for(NSView *v in panel.contentView.subviews) if([v isKindOfClass:NSScrollView.class])updatedScroll=(NSScrollView *)v;
    Check(NSWidth(updatedScroll.frame)==244 && NSWidth(updatedScroll.documentView.frame)==244,@"P1: padding changes keep body viewport/document width consistent");
    FYInlineLayoutRequest *shortRequest=[FYInlineLayoutRequest requestWithBlock:Block(@"設定",CGRectMake(.1,.8,.18,.036),NO) translation:@"设置与音量" sourceFrame:CGRectMake(80,480,144,22)];
    FYInlinePlacement *shortPlacement=[engine initialPlacementForRequest:shortRequest viewport:viewport];
    NSTextField *shortLabel=[app label:shortRequest.translation font:shortPlacement.font color:NSColor.blackColor];
    shortLabel.attributedStringValue=[app inlinePanelAttributedText:shortRequest.translation font:shortPlacement.font];
    shortLabel.frame=shortPlacement.labelFrame;
    NSSize cell=[shortLabel.cell cellSizeForBounds:NSMakeRect(0,0,NSWidth(shortLabel.bounds),CGFLOAT_MAX)];
    Check(cell.height<=NSHeight(shortLabel.frame)+.5,@"P1: measured short label has enough native NSCell height");
    Report[@"P1"]=@{@"status":@"passed",@"scope":@"real production view/NSCell/scroll-document creation and reuse, no NSWindow"};
}

static NSArray *Signature(FYInlineLayoutResult *result) {
    NSMutableArray *signature=[NSMutableArray array];
    for (FYInlinePlacement *p in result.placements) [signature addObject:@[p.blockID,FYLayoutDebugRect(p.translationFrame),@(p.mode),@(p.font.pointSize)]];
    return signature;
}
static void Legal(FYInlineLayoutResult *result, CGRect viewport) {
    for(FYInlinePlacement *p in result.visiblePlacements) {
        Check(CGRectContainsRect(viewport,p.translationFrame),@"P2: every visible frame lies in the viewport");
        for(FYInlinePlacement *other in result.visiblePlacements) if(other!=p)
            Check(!CGRectIntersectsRect(p.translationFrame,other.translationFrame),@"P2: no positive-area translation overlap");
        for(FYInlinePlacement *other in result.placements) if(other!=p)
            Check(!CGRectIntersectsRect(p.translationFrame,other.sourceFrame),@"P2: no unrelated source region is obscured");
        // A finite association envelope follows source/label geometry, not a symptom-tuned offset.
        Check(result.layoutPassCount<=12,@"P2: bounded layout rounds cannot loop forever");
        CGRect bounds=p.automaticOriginBounds;
        Check(NSMinX(p.translationFrame)>=NSMinX(bounds)-1e-6 && NSMinX(p.translationFrame)<=NSMaxX(bounds)+1e-6 &&
              NSMinY(p.translationFrame)>=NSMinY(bounds)-1e-6 && NSMinY(p.translationFrame)<=NSMaxY(bounds)+1e-6,
              @"P2: each final automatic origin satisfies its recorded displacement limits");
        CGFloat margin=8;
        Check(NSMinX(p.translationFrame)>=NSMinX(p.sourceFrame)-NSWidth(p.translationFrame)-margin &&
              NSMinX(p.translationFrame)<=NSMaxX(p.sourceFrame)+margin &&
              NSMinY(p.translationFrame)>=NSMinY(p.sourceFrame)-NSHeight(p.translationFrame)-margin &&
              NSMinY(p.translationFrame)<=NSMaxY(p.sourceFrame)+margin,@"P2: automatic labels cannot leave their source association envelope");
    }
}
static NSDictionary *LoadScene(NSString *name) {
    NSString *path=[@"tests/fixtures/layout" stringByAppendingPathComponent:[name stringByAppendingString:@".json"]];
    NSDictionary *scene=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:NULL];
    Check(scene!=nil,@"fixture is present");return scene;
}
static void ExportScene(NSDictionary *scene, NSArray *requests, FYInlineLayoutResult *result) {
    NSString *directory=[EvidenceOutput stringByAppendingPathComponent:scene[@"name"]];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    NSDictionary *control=@{@"session":NSUUID.UUID.UUIDString,@"issued_at":@(NSDate.date.timeIntervalSince1970-1),
        @"expires_at":@(NSDate.date.timeIntervalSince1970+120),@"overlay":@NO};
    NSString *controlPath=[directory stringByAppendingPathComponent:@"control.json"];
    [[NSJSONSerialization dataWithJSONObject:control options:0 error:NULL] writeToFile:controlPath atomically:YES];chmod(controlPath.fileSystemRepresentation,0600);
    FYInlineLayoutDebug *debug=[[FYInlineLayoutDebug alloc] initWithDirectory:directory];
    CGImageRef image=SyntheticImage(scene);
    NSDictionary *context=[debug beginFrameWithImage:image metadata:@{@"input_source":@0,@"scope":@[@0,@0,@1,@1]}];CGImageRelease(image);
    Check(context!=nil,@"explicit private synthetic diagnostic session accepts a supplied frame");
    NSMutableArray *raw=[NSMutableArray array];
    for(NSDictionary *line in scene[@"lines"]) { OCRTextItem *item=[OCRTextItem new];item.text=line[@"text"];item.boundingBox=R(line[@"box"]);[raw addObject:item]; }
    [debug recordItems:raw stage:@"vision_raw" context:context];
    [debug recordLayout:FYLayoutDebugSnapshot(result,nil,R(scene[@"viewport"]),@{},@"synthetic_fixed_input") context:context];
    NSDictionary *reuse=FYLayoutDebugSnapshot(result,result,R(scene[@"viewport"]),@{},@"cache_identical_input");
    Check(![reuse[@"changed"] boolValue] && [reuse[@"layout_pass_count"] unsignedIntegerValue]==0 && [reuse[@"layout_reused"] boolValue],
        @"cached diagnostic frames report zero new layout passes and zero changes");
    NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL];
    Check([files filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF ENDSWITH '.overlay.png'"]].count>0,@"diagnostic exports a rendered overlay PNG and structured JSON");
    [[NSFileManager defaultManager] removeItemAtPath:controlPath error:NULL];
    Check(!debug.isActive,@"stopping revokes the diagnostic session");
    NSUInteger before=files.count-1;
    [debug recordLayout:FYLayoutDebugSnapshot(result,nil,R(scene[@"viewport"]),@{},@"late_result") context:context];
    Check([[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL].count==before,@"late callback cannot save after stop");
    NSMutableDictionary *rotated=[control mutableCopy];rotated[@"session"]=NSUUID.UUID.UUIDString;
    [[NSJSONSerialization dataWithJSONObject:rotated options:0 error:NULL] writeToFile:controlPath atomically:YES];chmod(controlPath.fileSystemRepresentation,0600);
    [debug recordDecision:@"old_session_callback" context:context];
    Check([[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL].count==before+1,@"new session revokes callbacks from the previous one");
    chmod(controlPath.fileSystemRepresentation,0644);Check(!debug.isActive,@"public control file cannot enable image/text diagnostics");
    chmod(controlPath.fileSystemRepresentation,0600);rotated[@"expires_at"]=@(NSDate.date.timeIntervalSince1970-1);
    [[NSJSONSerialization dataWithJSONObject:rotated options:0 error:NULL] writeToFile:controlPath atomically:YES];chmod(controlPath.fileSystemRepresentation,0600);
    Check(!debug.isActive,@"expired session cannot continue diagnostics");
    [[NSFileManager defaultManager] removeItemAtPath:controlPath error:NULL];
}
static void P2RightBoundary(void) {
    NSDictionary *scene=LoadScene(@"right-boundary");CGRect viewport=R(scene[@"viewport"]);
    NSMutableArray *requests=[NSMutableArray array],*lines=[NSMutableArray array];
    for(NSDictionary *raw in scene[@"blocks"]) {
        CGRect frame=R(raw[@"source_frame"]);
        CGRect box=CGRectMake((NSMinX(frame)-NSMinX(viewport))/NSWidth(viewport),
            (NSMinY(frame)-NSMinY(viewport))/NSHeight(viewport),NSWidth(frame)/NSWidth(viewport),NSHeight(frame)/NSHeight(viewport));
        [requests addObject:[FYInlineLayoutRequest requestWithBlock:Block(raw[@"text"],box,[raw[@"long_body"] boolValue])
            translation:raw[@"translation"] sourceFrame:frame]];
        [lines addObject:@{@"text":raw[@"text"],@"box":FYLayoutDebugRect(box)}];
    }
    FYInlineLayoutEngine *engine=[FYInlineLayoutEngine defaultEngine];engine.collectsLayoutDiagnostics=YES;
    FYInlineLayoutResult *baseline=[engine layoutRequests:requests viewport:viewport previous:nil];
    FYInlinePlacement *body=[baseline placementForBlockID:((FYInlineLayoutRequest *)requests[0]).block.blockID];
    NSDictionary *right=nil;
    for(NSDictionary *candidate in body.candidateDiagnostics)
        if([candidate[@"anchor"] integerValue]==FYInlineAnchorRight && !candidate[@"stage"]) { right=candidate;break; }
    Report[@"P2_right_boundary_observation"]=@{@"right_candidate":right?:@{},@"final_frame":FYLayoutDebugRect(body.translationFrame),@"anchor":@(body.anchor)};
    Check(NSMaxX(body.sourceFrame)+engine.panelGap+NSWidth(body.translationFrame)>NSMaxX(viewport)-engine.viewportMargin,
        @"P2: right-edge fixture requires an inward adjustment, rather than already fitting");
    Check(right && ![right[@"hard_rejection"] boolValue] &&
        fabs(NSMaxX(R(right[@"frame"]))-(NSMaxX(viewport)-engine.viewportMargin))<.5,
        @"P2: a right candidate that fits after moving inward must survive the viewport boundary");
    Check(body.anchor==FYInlineAnchorRight && NSMinX(body.translationFrame)>=NSMinX(body.sourceFrame),
        @"P2: a usable right-side card stays by its source instead of crossing into the left menu");
    Legal(baseline,viewport);NSArray *signature=Signature(baseline);
    FYInlineLayoutResult *previous=baseline;
    for(NSUInteger n=0;n<100;n++) {
        FYInlineLayoutResult *fresh=[engine layoutRequests:requests viewport:viewport previous:nil];
        Check([Signature(fresh) isEqual:signature],@"P2: inward right-edge placement is deterministic for 100 fresh layouts");
        Legal(fresh,viewport);
        FYInlineLayoutResult *steady=[engine layoutRequests:requests viewport:viewport previous:previous];
        Check([Signature(steady) isEqual:signature] && !steady.changedFromPrevious,
            @"P2: inward right-edge placement stays fixed for 100 identical subsequent frames");previous=steady;
    }
    // Moving inward remains subject to production collision checks. The obstacle
    // covers the entire right candidate; accepting it would obscure another field.
    FYInlineTextBlock *obstacle=Block(@"独立字段",CGRectMake(.75,.5,.23,.39),NO);
    [requests addObject:[FYInlineLayoutRequest requestWithBlock:obstacle translation:@"独立字段" sourceFrame:CGRectMake(675,260,210,205)]];
    FYInlineLayoutResult *blocked=[engine layoutRequests:requests viewport:viewport previous:nil];Legal(blocked,viewport);
    FYInlinePlacement *blockedBody=[blocked placementForBlockID:body.sourceBlockID];
    Check(blockedBody.anchor!=FYInlineAnchorRight,@"P2: inward adjustment cannot bypass another source field");
    NSMutableDictionary *export=[scene mutableCopy];export[@"lines"]=lines;
    ExportScene(export,[requests subarrayWithRange:NSMakeRange(0,2)],baseline);
    Report[@"P2_right_boundary"]=@{@"status":@"passed",@"fresh_runs":@100,@"stationary_runs":@100,@"other_field_obstacle_checked":@YES};
}
static void P2(void) {
    P2RightBoundary();
    NSMutableArray *counts=[NSMutableArray array];
    for(NSString *name in @[@"sparse-menu",@"dense-menu",@"multiline"]) {
        NSDictionary *scene=LoadScene(name);NSArray *requests=SceneRequests(scene,0);CGRect viewport=R(scene[@"viewport"]);
        FYInlineLayoutEngine *engine=[FYInlineLayoutEngine defaultEngine];engine.collectsLayoutDiagnostics=YES;
        FYInlineLayoutResult *baseline=[engine layoutRequests:requests viewport:viewport previous:nil]; Legal(baseline,viewport);
        NSArray *signature=Signature(baseline);
        for(NSUInteger n=0;n<100;n++) {
            FYInlineLayoutResult *result=[engine layoutRequests:requests viewport:viewport previous:nil];
            Check([Signature(result) isEqual:signature],@"P2: 100 identical inputs with identical initial state produce identical layouts");Legal(result,viewport);
        }
        if ([name isEqual:@"dense-menu"]) Check(baseline.unplaceableBlockIDs.count+baseline.compactEntryBlockIDs.count>0,@"P2: physically crowded input explicitly degrades, keeping full translations");
        [counts addObject:@{@"sample":name,@"blocks":@(requests.count),@"visible":@(baseline.visiblePlacements.count),
            @"unplaceable":@(baseline.unplaceableBlockIDs.count),@"compact":@(baseline.compactEntryBlockIDs.count),@"runs":@100}];
        ExportScene(scene,requests,baseline);
    }
    Report[@"P2"]=@{@"status":@"passed",@"samples":counts};
}
static NSArray *StabilizedRequests(NSDictionary *scene, CGFloat noise, FYInlineOCRFrameStabilizer *stabilizer) {
    NSArray *requests=SceneRequests(scene,noise);NSMutableArray *items=[NSMutableArray array];
    for(FYInlineLayoutRequest *r in requests) {
        OCRTextItem *item=[OCRTextItem new];item.text=r.block.text;item.boundingBox=r.block.boundingBox;
        item.lineBoxes=r.block.lineBoxes;item.lineTexts=r.block.lineTexts;item.blockKind=(InlineBlockKind)r.block.kind;[items addObject:item];
    }
    NSArray *accepted=[stabilizer observeItems:items];NSMutableArray *out=[NSMutableArray array];
    for(OCRTextItem *item in accepted) {
        FYInlineTextBlock *b=Block(item.text,item.boundingBox,item.blockKind==InlineBlockKindLong);
        NSUInteger index=[items indexOfObjectPassingTest:^BOOL(OCRTextItem *value,NSUInteger idx,BOOL *stop) {return [value.text isEqual:item.text];}];
        if(index==NSNotFound) continue;
        [out addObject:[FYInlineLayoutRequest requestWithBlock:b translation:((FYInlineLayoutRequest *)requests[index]).translation
            sourceFrame:[FYGeometryManager frameForNormalizedBox:item.boundingBox inViewport:R(scene[@"viewport"])]]];
    }
    return out;
}
static void P3(void) {
    for(NSString *name in @[@"stationary",@"ocr-jitter",@"dense-menu",@"multiline"]) {
        NSDictionary *scene=LoadScene(name);CGRect viewport=R(scene[@"viewport"]);
        FYInlineLayoutEngine *engine=[FYInlineLayoutEngine defaultEngine];FYInlineOCRFrameStabilizer *stabilizer=[FYInlineOCRFrameStabilizer new];
        FYInlineLayoutResult *previous=nil;NSArray *baseline=nil;
        for(NSUInteger n=0;n<102;n++) {
            CGFloat noise=[scene[@"noise"] doubleValue]*(n%2?1:-1);
            NSArray *requests=StabilizedRequests(scene,noise,stabilizer);
            if(n==0) { Check(requests.count==0,@"P3: production startup requires confirmation");continue; }
            FYInlineLayoutResult *result=[engine layoutRequests:requests viewport:viewport previous:previous];
            if(!baseline) baseline=Signature(result);
            else Check([Signature(result) isEqual:baseline] && !result.changedFromPrevious,
                [NSString stringWithFormat:@"P3: %@ unchanged confirmed observations retain IDs/modes/frames",name]);
            previous=result;
        }
        if ([name isEqual:@"stationary"] || [name isEqual:@"ocr-jitter"]) ExportScene(scene,SceneRequests(scene,0),previous);
    }
    NSDictionary *scene=LoadScene(@"menu-switch");FYInlineOCRFrameStabilizer *stabilizer=[FYInlineOCRFrameStabilizer new];
    StabilizedRequests(scene,0,stabilizer);NSArray *a=StabilizedRequests(scene,0,stabilizer);
    NSMutableDictionary *next=[scene mutableCopy];next[@"lines"]=scene[@"next_lines"];next[@"expected_blocks"]=@2;next[@"image"]=scene[@"next_image"];
    StabilizedRequests(next,0,stabilizer);NSArray *b=StabilizedRequests(next,0,stabilizer);
    Check(a.count==3 && b.count==2,@"P3: menu switch requires two consistent frames and drops the previous scene");
    FYInlineLayoutEngine *engine=[FYInlineLayoutEngine defaultEngine];FYInlineLayoutResult *old=[engine layoutRequests:a viewport:R(scene[@"viewport"]) previous:nil];
    FYInlineLayoutResult *fresh=[engine layoutRequests:b viewport:R(scene[@"viewport"]) previous:old];
    for(FYInlinePlacement *p in fresh.placements) Check([old placementForBlockID:p.blockID]==nil,@"P3: a new scene does not reuse the old menu identity");
    ExportScene(next,b,fresh);
    // Queue an old result, then let geometry reflow establish the newer valid cache first.
    LayoutHeadlessApp *app=[LayoutHeadlessApp new];app.running=YES;app.translationGeneration=1;
    app.ocrGeometryGeneration=1;app.ocrDisplayTargetWindowID=100;app.geometryGeneration=1;
    [app handleInlineTranslationResult:@[@"旧译文"] forItems:@[] error:nil failureStatus:@"" successPrefix:@""];
    app.geometryGeneration=2;
    app.lastInlineLayoutResult=fresh;app.lastInlineTranslationKey=@"valid-current-geometry";
    __block BOOL drained=NO;dispatch_async(dispatch_get_main_queue(),^{drained=YES;});
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
    while(!drained && deadline.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    Check(drained,@"P3: queued stale callback executes within its test deadline");
    Report[@"P3_stale_geometry_observation"]=@{@"layout_preserved":@(app.lastInlineLayoutResult==fresh),
        @"identity_cache_preserved":@([app.lastInlineTranslationKey isEqual:@"valid-current-geometry"])};
    Check(app.lastInlineLayoutResult==fresh && [app.lastInlineTranslationKey isEqual:@"valid-current-geometry"],
        @"P3: a stale geometry callback cannot invalidate a newer layout or its identity cache");
    Report[@"P3"]=@{@"status":@"passed",@"scope":@"production field stabilizer + layout, 100+ stationary/jitter frames and confirmed switch"};
}

int main(int argc,const char **argv) { @autoreleasepool {
    NSString *output=argc>1?@(argv[1]):@".build/layout-debug/evidence";
    [[NSFileManager defaultManager] createDirectoryAtPath:output withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    chmod(output.fileSystemRepresentation,0700);
    EvidenceOutput=output;
    Report=[NSMutableDictionary dictionaryWithDictionary:@{@"schema_version":@1,@"headless":@YES,@"real_api_calls":@0,@"ui_windows_created":@0}];
    int code=0;
    @try {
        NSString *through=argc>2?@(argv[2]):@"P3";
        Stage=@"P0";P0();
        if(![through isEqual:@"P0"]) {Stage=@"P1";P1();}
        if([through isEqual:@"P2"] || [through isEqual:@"P3"]) {Stage=@"P2";P2();}
        if([through isEqual:@"P3"]) {Stage=@"P3";P3();}
    }
    @catch(NSException *error) { code=1;Report[Stage]=@{@"status":@"failed",@"failure":error.reason};NSLog(@"FAIL %@ %@",Stage,error.reason); }
    Report[@"assertions"]=@(Assertions);Report[@"outcome"]=code?@"failed":@"passed";
    NSString *path=[output stringByAppendingPathComponent:@"summary.json"];
    [[NSJSONSerialization dataWithJSONObject:Report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:path atomically:YES];chmod(path.fileSystemRepresentation,0600);
    NSLog(@"Layout gates %@ (%lu assertions); %@",Report[@"outcome"],(unsigned long)Assertions,path);return code;
} }
