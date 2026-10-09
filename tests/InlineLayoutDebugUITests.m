// Scheduled desktop slot only. Fictional source pixels, no capture, DB or HTTP.
#import "LearningAppTestSupport.h"
#import <sys/stat.h>
int main(int argc,const char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *output=argc>1?@(argv[1]):FYTestTemporaryDirectory();
    NSString *directory=[FYTestTemporaryDirectory() stringByAppendingPathComponent:@"layout-overlay"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    NSString *controlPath=[directory stringByAppendingPathComponent:@"control.json"];
    NSDictionary *control=@{@"session":NSUUID.UUID.UUIDString,@"issued_at":@(NSDate.date.timeIntervalSince1970-1),
        @"expires_at":@(NSDate.date.timeIntervalSince1970+120),@"overlay":@YES};
    [[NSJSONSerialization dataWithJSONObject:control options:0 error:NULL] writeToFile:controlPath atomically:YES];chmod(controlPath.fileSystemRepresentation,0600);
    FYInlineLayoutDebug *debug=[[FYInlineLayoutDebug alloc] initWithDirectory:directory];
    NSImage *source=[[NSImage alloc] initWithContentsOfFile:@"tests/fixtures/layout/assets/sparse-menu.png"];
    CGImageRef pixels=[source CGImageForProposedRect:NULL context:nil hints:nil];
    NSDictionary *context=[debug beginFrameWithImage:pixels metadata:@{}];Require(context!=nil,@"explicit synthetic image diagnostic context");
    CGRect viewport=CGRectMake(80,120,800,600),box=CGRectMake(.1,.8,.18,.036);
    OCRTextItem *raw=[OCRTextItem new];raw.text=@"設定";raw.boundingBox=box;
    [debug recordItems:@[raw] stage:@"vision_raw" context:context];
    FYInlineTextBlock *block=[FYInlineTextBlock new];block.text=raw.text;block.boundingBox=box;block.lineTexts=@[raw.text];block.lineBoxes=@[[NSValue valueWithRect:box]];
    block.blockID=[FYInlineBlockMatcher blockIDForText:block.text lineBoxes:block.lineBoxes];
    FYInlineTextBlock *obstacle=[FYInlineTextBlock new];obstacle.text=@"合成障碍";obstacle.boundingBox=CGRectMake(.08,.72,.4,.07);
    obstacle.lineTexts=@[obstacle.text];obstacle.lineBoxes=@[[NSValue valueWithRect:obstacle.boundingBox]];
    obstacle.blockID=[FYInlineBlockMatcher blockIDForText:obstacle.text lineBoxes:obstacle.lineBoxes];
    FYInlineLayoutRequest *reserve=[FYInlineLayoutRequest requestWithBlock:obstacle translation:@"" sourceFrame:[FYGeometryManager frameForNormalizedBox:obstacle.boundingBox inViewport:viewport]];
    FYInlineLayoutEngine *engine=[FYInlineLayoutEngine defaultEngine];
    FYInlineLayoutResult *result=[engine layoutRequests:@[[FYInlineLayoutRequest requestWithBlock:block translation:@"设置" sourceFrame:[FYGeometryManager frameForNormalizedBox:box inViewport:viewport]],reserve] viewport:viewport previous:nil];
    [debug recordLayout:FYLayoutDebugSnapshot(result,nil,viewport,@{},@"scheduled_synthetic_ui") context:context];
    [debug refreshVisible:YES level:NSFloatingWindowLevel];
    NSPanel *panel=[debug valueForKey:@"overlay"];
    Require(panel!=nil && panel.isVisible,@"debug overlay is visible");
    Require(NSEqualRects(panel.frame,viewport),@"overlay uses exact AppKit viewport points");
    Require(panel.ignoresMouseEvents && !panel.isOpaque && !panel.hasShadow,@"debug overlay stays transparent and does not intercept game clicks");
    [panel.contentView displayIfNeeded];
    NSBitmapImageRep *image=[panel.contentView bitmapImageRepForCachingDisplayInRect:panel.contentView.bounds];
    [panel.contentView cacheDisplayInRect:panel.contentView.bounds toBitmapImageRep:image];
    NSString *png=[output stringByAppendingPathComponent:@"layout-debug-overlay-native.png"];
    [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:png atomically:YES];chmod(png.fileSystemRepresentation,0600);
    NSUInteger colors[4]={0,0,0,0}; CGFloat maximumGreenCoverage=0;
    for(NSInteger y=0;y<image.pixelsHigh;y++) for(NSInteger x=0;x<image.pixelsWide;x++) {
        NSColor *c=[[image colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        if(c.alphaComponent<.2) continue;
        // Classify chromatic dominance: display caching, antialiasing and
        // color conversion can mix outline colors with background channels.
        if(c.greenComponent>c.redComponent+.2 && c.greenComponent>c.blueComponent+.2) { colors[0]++; maximumGreenCoverage=MAX(maximumGreenCoverage,c.greenComponent); }
        if(c.greenComponent>.7 && c.redComponent>.7 && c.blueComponent<.4)colors[1]++;
        if(c.blueComponent>.7 && c.redComponent<.4 && c.greenComponent<.4)colors[2]++;
        if(c.redComponent>.7 && c.greenComponent<.4 && c.blueComponent<.4)colors[3]++;
    }
    NSLog(@"native diagnostic color pixels: green=%lu yellow=%lu blue=%lu red=%lu; maximum green coverage=%.3f",(unsigned long)colors[0],(unsigned long)colors[1],(unsigned long)colors[2],(unsigned long)colors[3],maximumGreenCoverage);
    Require(colors[0]>0 && colors[1]>0 && colors[2]>0 && colors[3]>0,@"native overlay draws all four diagnostic colors");
    [debug refreshVisible:NO level:NSFloatingWindowLevel];Require(!panel.isVisible,@"foreground hide is respected");
    [[NSFileManager defaultManager] removeItemAtPath:controlPath error:NULL];
    Pump(^BOOL{return [debug valueForKey:@"overlay"]==nil;});
    Require([debug valueForKey:@"overlay"]==nil,@"stop closes the overlay without requiring a new OCR frame");
    NSLog(@"PASS InlineLayoutDebugUITests: scheduled synthetic desktop overlay, no capture/network");return 0;
} }
