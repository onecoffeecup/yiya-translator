#import "FYGeometryManager.h"
#import "FYOCRManager.h"
#import <math.h>

@interface LocateClockDate : NSDate
@property(nonatomic) NSTimeInterval relativeInterval;
@end
@implementation LocateClockDate
- (NSTimeInterval)timeIntervalSinceReferenceDate { return 0; }
- (NSTimeInterval)timeIntervalSinceNow { return self.relativeInterval; }
@end

// Deterministic injected clock without relying on NSDate accepting NaN timestamps.
@interface NonfiniteMappingDate : NSDate
@end
@implementation NonfiniteMappingDate
- (NSTimeInterval)timeIntervalSinceReferenceDate { return NAN; }
- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)date { return NAN; }
@end

static NSUInteger assertions;
static void Expect(BOOL condition, NSString *message) {
    assertions++;
    if (!condition) { NSLog(@"FAIL %@", message); exit(1); }
}
int main(void) {
    @autoreleasepool {
        Expect(FYGeometryDeliveryIsStale(1,2,10,10), @"geometry generation change rejects old placement");
        Expect(FYGeometryDeliveryIsStale(1,1,10,20), @"known display target change rejects placement");
        Expect(!FYGeometryDeliveryIsStale(1,1,0,20) && !FYGeometryDeliveryIsStale(1,1,10,10), @"unknown target skips target match and current geometry accepted");
        NSRect quartz = [FYGeometryManager appKitFrameForQuartzBounds:CGRectMake(-400, 100, 300, 200) mainScreenTop:900];
        Expect(NSEqualRects(quartz, NSMakeRect(-400, 600, 300, 200)), @"Quartz conversion preserves negative monitor coordinates");
        NSRect viewport = NSMakeRect(100, 200, 800, 600);
        CGRect box = CGRectMake(0.25, 0.10, 0.50, 0.20);
        Expect(NSEqualRects([FYGeometryManager frameForNormalizedBox:box inViewport:viewport], NSMakeRect(300, 260, 400, 120)), @"Vision bottom-left conversion");
        Expect(NSEqualRects([FYGeometryManager frameForTopLeftNormalizedBox:box inViewport:viewport], NSMakeRect(300, 620, 400, 120)), @"Top-left region slider conversion");
        CGRect selection = [FYGeometryManager quartzRectFromSelection:CGRectMake(10, 20, 30, 40) panelFrame:viewport mainScreenTop:1000];
        Expect(CGRectEqualToRect(selection, CGRectMake(110, 220, 30, 40)), @"Selection conversion uses explicit screen top");
        Expect(NSEqualRects([FYGeometryManager frameForNormalizedBox:CGRectMake(0, 0, 1, 1) inViewport:viewport], viewport), @"Full normalized viewport round trip");
        OCRTextItem *item = [OCRTextItem new]; item.text = @"日本語"; item.blockKind = InlineBlockKindLong; item.confidence = 0.8;
        Expect([item.text isEqualToString:@"日本語"] && item.blockKind == InlineBlockKindLong && fabs(item.confidence - 0.8) < 0.001, @"Shared OCR model preserves field semantics");
        NSDictionary *mapping=@{@"windowAspect":@2,@"videoAspect":@1.5,@"deviceID":@"A"};
        Expect(![FYGeometryManager captureMappingWindowReason:mapping windowFrame:NSMakeRect(-500,50,800,400)], @"moving and proportional scaling preserve mapping");
        Expect([[FYGeometryManager captureMappingWindowReason:mapping windowFrame:NSMakeRect(0,0,1,400)] isEqual:@"目标窗口尺寸无效，无法定位画面区域。"], @"invalid size reason preserved");
        Expect([[FYGeometryManager captureMappingWindowReason:mapping windowFrame:NSMakeRect(0,0,840,400)] isEqual:@"目标窗口比例已变化。"], @"changed window aspect rejected");
        Expect(![FYGeometryManager captureMappingInputReason:mapping frameSize:CGSizeZero hasFrameSize:NO deviceID:@"A"], @"unavailable frame size does not invent invalidation");
        Expect([[FYGeometryManager captureMappingInputReason:mapping frameSize:CGSizeMake(200,100) hasFrameSize:YES deviceID:@"B"] isEqual:@"采集画面比例已变化（可能换了输入源或设备）。"], @"video aspect reason precedes changed device");
        Expect([[FYGeometryManager captureMappingInputReason:mapping frameSize:CGSizeMake(150,100) hasFrameSize:YES deviceID:@"B"] isEqual:@"采集卡设备已变化。"], @"changed device rejected");
        Expect(![FYGeometryManager captureMappingInputReason:@{} frameSize:CGSizeZero hasFrameSize:NO deviceID:nil], @"missing calibrated device remains compatible");
        Expect([FYGeometryManager captureMappingScoreIsStale:-.5 unavailableValue:-2] && ![FYGeometryManager captureMappingScoreIsStale:-2 unavailableValue:-2], @"negative correlation stale but unavailable sentinel retained");
        Expect(![FYGeometryManager captureMappingScoreIsStale:.30 unavailableValue:-2] && [FYGeometryManager captureMappingScoreIsStale:.299 unavailableValue:-2], @"strict score threshold preserved");
        Expect(CGRectEqualToRect([FYGeometryManager pixelCropForTopLeftRegion:CGRectMake(.253,.107,.505,.208) imageWidth:100 imageHeight:100],CGRectMake(25,10,50,20)), @"crop floors top-left origin and size independently");
        Expect(CGRectEqualToRect([FYGeometryManager pixelCropForTopLeftRegion:CGRectMake(.2,.3,0,0) imageWidth:100 imageHeight:100],CGRectMake(20,30,1,1)), @"zero region retains minimum one-pixel dimensions");
        Expect(CGRectEqualToRect([FYGeometryManager pixelCropForTopLeftRegion:CGRectMake(.9,.8,.3,.4) imageWidth:100 imageHeight:100],CGRectMake(90,80,10,20)), @"crop clipped at right and bottom image edges");
        Expect(CGRectIsNull([FYGeometryManager pixelCropForTopLeftRegion:CGRectMake(2,2,.2,.2) imageWidth:100 imageHeight:100]), @"disjoint region remains null rather than fabricated valid crop");
        Expect(CGRectEqualToRect([FYGeometryManager pixelCropForTopLeftRegion:CGRectMake(0,0,1,1) imageWidth:2560 imageHeight:1440],CGRectMake(0,0,2560,1440)), @"full region preserves image pixels with no coordinate flip");
        NSRect frame=NSMakeRect(-400,100,800,400), calibrated=NSMakeRect(-200,150,400,200);
        NSDictionary *entry=[FYGeometryManager captureMappingForRect:calibrated windowFrame:frame videoAspect:0 deviceID:nil source:nil confidence:.75 version:2];
        Expect([entry isEqual:@{@"nx":@.25,@"ny":@.125,@"nw":@.5,@"nh":@.5,@"windowAspect":@2,@"videoAspect":@1,@"deviceID":@"",@"source":@"auto",@"confidence":@.75,@"mappingVersion":@2}], @"mapping fields and defaults preserve plist schema");
        Expect(NSEqualRects([FYGeometryManager captureMappingRect:entry windowFrame:frame],calibrated), @"negative-monitor mapping round trip");
        Expect(NSEqualRects([FYGeometryManager captureMappingRect:entry windowFrame:NSMakeRect(0,0,1600,800)],NSMakeRect(400,100,800,400)), @"moved and proportionally resized window reconstructs mapping");
        Expect(![FYGeometryManager captureMappingForRect:NSMakeRect(0,0,1,100) windowFrame:frame videoAspect:1 deviceID:nil source:nil confidence:0 version:2], @"invalid calibration does not produce entry");
        Expect(NSEqualRects([FYGeometryManager captureMappingRect:@{} windowFrame:frame],NSMakeRect(-400,100,0,0)), @"missing dimensions remain zero for coordinator rejection");
        double templ[]={1,2,3,4}, scene[]={11,12,13,14}; FYNormalizeSignature(templ,4);
        Expect(fabs(templ[0]+templ[1]+templ[2]+templ[3])<1e-9, @"signature zero mean");
        Expect(fabs((templ[0]*templ[0]+templ[1]*templ[1]+templ[2]*templ[2]+templ[3]*templ[3])/4-1)<1e-9, @"signature unit variance");
        Expect(fabs(FYSignatureCorrelation(scene,2,2,0,0,2,2,templ,2,2)-1)<1e-9, @"brightness shift retains perfect content correlation");
        double inverse[]={14,13,12,11}, uniform[]={10,10,10,10};
        Expect(fabs(FYSignatureCorrelation(inverse,2,2,0,0,2,2,templ,2,2)+1)<1e-9, @"inverted content returns negative correlation");
        Expect(FYSignatureCorrelation(uniform,2,2,0,0,2,2,templ,2,2)==-1, @"uniform candidate keeps legacy negative sentinel");
        Expect(FYSignatureCorrelation(scene,2,2,-1,0,2,2,templ,2,2)==-2 && FYSignatureCorrelation(scene,2,2,1,0,2,2,templ,2,2)==-2, @"invalid candidate bounds rejected");
        FYNormalizeSignature(uniform,4); Expect(uniform[0]==0 && uniform[3]==0, @"constant signature safely normalizes to zero");
        Expect(!FYGrayGridFromImage(NULL,4,4), @"missing image returns no allocated grid");
        double grid[16*16], signature[8*8];
        for(size_t j=0;j<16;j++) for(size_t i=0;i<16;i++) grid[j*16+i]=sin(i*.8+j*.31)*90+i*j;
        for(size_t j=0;j<8;j++) for(size_t i=0;i<8;i++) signature[j*8+i]=grid[(j+2)*16+i+4];
        FYNormalizeSignature(signature,64);
        NSDictionary *gridMapping=@{@"nx":@.25,@"ny":@.375,@"nw":@.5,@"nh":@.5};
        Expect(fabs(FYCaptureMappingScoreInGrids(gridMapping,grid,16,16,signature,8,8)-1)<1e-9, @"mapping bottom-left y converts to scene top row");
        Expect(FYCaptureMappingScoreInGrids(nil,grid,16,16,signature,8,8)==-99 && FYCaptureMappingScoreInGrids(gridMapping,NULL,16,16,signature,8,8)==-99, @"missing mapping/grid preserves unavailable sentinel");
        Expect(FYCaptureMappingScoreInGrids(gridMapping,grid,7,16,signature,8,8)==-99, @"undersized scene is unavailable not bad correlation");
        Expect(FYShouldPreferCaptureFit(.61,.60,NO) && !FYShouldPreferCaptureFit(.60,.60,NO), @"fit needs clear score advantage when search is not smaller");
        Expect(FYShouldPreferCaptureFit(.59,.60,YES) && !FYShouldPreferCaptureFit(.57,.60,YES), @"smaller duplicate allows near-equivalent fit but not worse content");
        Expect(FYShouldKeepCachedCaptureMapping(.6,.64) && !FYShouldKeepCachedCaptureMapping(.6,.66), @"cached mapping retained unless new candidate clearly better");
        Expect(!FYShouldKeepCachedCaptureMapping(.49,.4), @"weak cache does not suppress search result");
        double searchScene[64*64], searchTemplate[8*8]; memset(searchScene,0,sizeof searchScene); memset(searchTemplate,0,sizeof searchTemplate);
        for(size_t j=0;j<8;j++)for(size_t i=0;i<8;i++){searchTemplate[j*8+i]=(double)(i+j*3);searchScene[(20+j)*64+30+i]=searchTemplate[j*8+i];}
        FYNormalizeSignature(searchTemplate,64);
        NSRect found=NSZeroRect; double score=FYSearchCaptureGrid(searchScene,64,64,searchTemplate,8,8,1,&found);
        Expect(score>0 && found.size.width>=12 && found.origin.x>=0 && found.origin.y>=0, @"grid search returns bounded positive-scoring candidate");
        memset(searchScene,0,sizeof searchScene);
        Expect(FYSearchCaptureGrid(searchScene,64,64,searchTemplate,8,8,1,&found)==-1 && NSEqualRects(found,NSMakeRect(0,0,16,16)), @"uniform scene retains first candidate on score tie");
        CGColorSpaceRef colorSpace=CGColorSpaceCreateDeviceRGB();
        CGContextRef context=CGBitmapContextCreate(NULL,100,80,8,400,colorSpace,kCGImageAlphaPremultipliedLast);
        CGImageRef source=CGBitmapContextCreateImage(context);
        CGImageRef region=FYCopyCapturedRegion(source,CGRectMake(.2,.25,.5,.5));
        Expect(region && CGImageGetWidth(region)==50 && CGImageGetHeight(region)==40,@"normalized capture crop has expected pixel size");
        CGImageRelease(source);
        Expect(CGImageGetWidth(region)==50,@"returned crop survives caller releasing source");
        CGImageRelease(region);
        source=CGBitmapContextCreateImage(context);
        CGImageRef full=FYCopyCapturedRegion(source,CGRectMake(0,0,1,1));
        Expect(full && CGImageGetWidth(full)==100 && CGImageGetHeight(full)==80 && CGImageGetWidth(source)==100,@"full crop preserves size and borrowed source remains valid");
        Expect(!FYCopyCapturedRegion(NULL,CGRectMake(0,0,1,1)),@"missing captured image safely returns no crop");
        CGImageRelease(full);CGImageRelease(source);
        CGContextSetRGBFillColor(context,0,0,0,1);CGContextFillRect(context,CGRectMake(0,0,100,80));
        double *gridTemplate=NULL,*gridScene=NULL;size_t tw=0,th=0,ww=0,wh=0;CGFloat aspect=0;NSString *reason=nil;__block NSUInteger geometryCalls=0;
        BOOL uniformOK=FYBuildCaptureGrids(CGBitmapContextCreateImage(context),CGBitmapContextCreateImage(context),CGSizeMake(100,80),^NSRect {geometryCalls++;return NSMakeRect(0,0,100,80);},80,&gridTemplate,&tw,&th,&gridScene,&ww,&wh,&aspect,&reason);
        Expect(!uniformOK && [reason isEqual:@"采集卡画面没有可用细节"] && geometryCalls==1 && !gridTemplate && !gridScene,@"uniform capture grids reject detail and free both buffers");
        CGContextSetRGBFillColor(context,1,1,1,1);CGContextFillRect(context,CGRectMake(0,0,50,80));
        BOOL gridsOK=FYBuildCaptureGrids(CGBitmapContextCreateImage(context),CGBitmapContextCreateImage(context),CGSizeMake(100,80),^NSRect {return NSMakeRect(0,0,100,80);},80,&gridTemplate,&tw,&th,&gridScene,&ww,&wh,&aspect,&reason);
        Expect(gridsOK && gridTemplate && gridScene && tw==40 && th==32 && ww==80 && wh==64 && aspect==1.25,@"capture grid dimensions preserve aspect and caller-owned outputs");
        double sum=0;for(size_t i=0;i<tw*th;i++)sum+=gridTemplate[i];
        Expect(fabs(sum)<1e-6,@"prepared capture template is normalized");
        free(gridTemplate);free(gridScene);CGContextRelease(context);CGColorSpaceRelease(colorSpace);
        NSRect gridWindow=NSMakeRect(-400,100,800,600);
        NSRect upperGridRect=FYWindowRectFromCaptureGrid(NSMakeRect(10,10,20,10),80,60,gridWindow);
        Expect(fabs(upperGridRect.origin.x+300)<1e-9 && fabs(upperGridRect.origin.y-500)<1e-9 && fabs(upperGridRect.size.width-200)<1e-9 && fabs(upperGridRect.size.height-100)<1e-9,@"top grid row converts to upper AppKit window with negative screen x");
        Expect(NSEqualRects(FYWindowRectFromCaptureGrid(NSMakeRect(0,0,80,60),80,60,gridWindow),gridWindow),@"full grid maps to full window");
        NSRect outsideGridRect=FYWindowRectFromCaptureGrid(NSMakeRect(-8,60,8,6),80,60,gridWindow);
        Expect(fabs(outsideGridRect.origin.x+480)<1e-9 && fabs(outsideGridRect.origin.y-40)<1e-9 && fabs(outsideGridRect.size.width-80)<1e-9 && fabs(outsideGridRect.size.height-60)<1e-9,@"grid conversion preserves original out-of-bounds arithmetic not newly clamped");
        Expect(NSEqualRects(FYCaptureGridRectFromWindow(NSMakeRect(-300,500,200,100),gridWindow,80,60),NSMakeRect(10,10,20,10)),@"fit window rect rounds into flipped grid sample");
        Expect(NSEqualRects(FYCaptureGridRectFromWindow(gridWindow,gridWindow,80,60),NSMakeRect(0,0,80,60)),@"full fit uses full grid");
        Expect(NSEqualRects(FYCaptureGridRectFromWindow(NSMakeRect(1000,1000,1,1),gridWindow,80,60),NSMakeRect(72,0,8,6)),@"outlying tiny fit clamps origin and minimum grid dimensions");
        NSRect estimate=NSZeroRect;
        Expect(FYEstimatedCaptureDisplayRect(CGSizeMake(1600,900),NSMakeRect(-400,100,800,600),&estimate) && NSEqualRects(estimate,NSMakeRect(-400,175,800,450)),@"wide capture candidate centered vertically");
        Expect(FYEstimatedCaptureDisplayRect(CGSizeMake(400,800),NSMakeRect(0,0,800,600),&estimate) && NSEqualRects(estimate,NSMakeRect(250,0,300,600)),@"portrait capture candidate centered horizontally");
        estimate=NSMakeRect(1,2,3,4);
        Expect(!FYEstimatedCaptureDisplayRect(CGSizeMake(1,800),NSMakeRect(0,0,800,600),&estimate) && NSEqualRects(estimate,NSMakeRect(1,2,3,4)),@"undersized capture rejects without changing output");
        Expect(FYEstimatedCaptureDisplayRect(CGSizeMake(400,800),NSMakeRect(0,0,800,600),NULL),@"estimate supports optional output");
        FYMappingValidationSchedule *schedule=[FYMappingValidationSchedule new];
        NSDate *t0=[NSDate dateWithTimeIntervalSince1970:100];
        Expect([schedule beginValidationAt:t0] && schedule.lastValidationDate==t0,@"first mapping validation is due and records exact date");
        Expect(![schedule beginValidationAt:[NSDate dateWithTimeIntervalSince1970:101.99]],@"mapping validation remains throttled before two seconds");
        Expect([schedule beginValidationAt:[NSDate dateWithTimeIntervalSince1970:102]],@"mapping validation is due at two-second boundary");
        NSDate *lastValidated=schedule.lastValidationDate;
        Expect(![schedule beginValidationAt:t0] && schedule.lastValidationDate==lastValidated,@"backward clock does not validate or overwrite prior date");
        NonfiniteMappingDate *nonfinite=[NonfiniteMappingDate alloc];
        Expect(![schedule beginValidationAt:nonfinite] && schedule.lastValidationDate==lastValidated,@"nonfinite elapsed time preserves original positive due comparison");
        schedule.lastValidationDate=nil;
        Expect([schedule beginValidationAt:t0] && schedule.lastValidationDate==t0,@"explicitly cleared validation date permits immediate check");
        NSDictionary *manual=@{@"source":@"manual"}, *currentAuto=@{@"source":@"auto",@"mappingVersion":@2}, *oldAuto=@{@"source":@"auto",@"mappingVersion":@1};
        NSDictionary *saved=@{@"manual":manual,@"new":currentAuto,@"old":oldAuto,@"bad":@42};
        NSMutableDictionary *filtered=FYFilterCaptureMappings(saved,2);
        Expect(filtered.count==2 && filtered[@"manual"]==manual && filtered[@"new"]==currentAuto,@"saved mapping filter preserves manual/current entry identities");
        filtered[@"added"]=manual;
        Expect(saved.count==4 && filtered.count==3 && !filtered[@"old"] && !filtered[@"bad"],@"filter returns independent mutable container without rewriting saved map");
        Expect(FYFilterCaptureMappings(@{},2).count==0,@"empty saved mapping filter is safe");
        Expect(FYCaptureMappingVersion(manual,2)==FYCaptureMappingVersionNonAutomatic && FYCaptureMappingVersion(oldAuto,2)==FYCaptureMappingVersionStaleAutomatic && FYCaptureMappingVersion(currentAuto,2)==FYCaptureMappingVersionCurrentAutomatic,@"mapping version classifier preserves manual/stale/current categories");
        Expect(FYCaptureMappingVersion(@{},2)==FYCaptureMappingVersionNonAutomatic,@"missing source remains nonautomatic");
        FYCaptureMappingCache *cache=[FYCaptureMappingCache new];
        NSDictionary *cacheEntry=@{@"source":@"manual"};
        Expect(![cache entryForWindowID:7],@"mapping cache starts without implicit entry");
        [cache storeEntry:cacheEntry forWindowID:7];
        Expect([cache entryForWindowID:7]==cacheEntry && cache.entries.count==1,@"mapping cache preserves entry identity and string window key");
        [cache removeWindowID:7];Expect(![cache entryForWindowID:7] && cache.entries.count==0,@"mapping cache removes one window without replacing container");
        NSMutableDictionary *external=[NSMutableDictionary dictionaryWithObject:cacheEntry forKey:@"11"];
        cache.entries=external;
        Expect(cache.entries==external && [cache entryForWindowID:11]==cacheEntry,@"cache assignment retains external mutable container identity");
        external[@"12"]=currentAuto;
        Expect([cache entryForWindowID:12]==currentAuto,@"external mutation is visible to cache without snapshot copying");
        [cache removeWindowID:11];[cache storeEntry:manual forWindowID:13];
        Expect(!external[@"11"] && external[@"13"]==manual,@"cache mutations remain visible through external alias");
        cache.entries=nil;
        Expect(!cache.entries && external.count==2 && ![cache entryForWindowID:12],@"clearing cache container does not mutate previous external container");
        [cache storeEntry:cacheEntry forWindowID:14];
        Expect(cache.entries!=external && external.count==2 && cache.entries.count==1,@"store after nil creates new container and leaves prior alias intact");
        NSMutableArray *candidateEvents=[NSMutableArray array];
        FYCaptureCandidateResult selected=FYSelectCaptureCandidate(searchScene,64,64,searchTemplate,8,8,1,NSMakeRect(0,0,640,640),
            ^BOOL(NSRect *fit){[candidateEvents addObject:@"fit"];return NO;},
            ^NSDictionary *{[candidateEvents addObject:@"cache"];return nil;},2,NULL,NULL);
        Expect([candidateEvents isEqual:@[@"fit",@"cache"]] && selected.fitScore==-2 && !selected.keepExisting,@"candidate pipeline preserves fit-before-cache order and unavailable fit sentinel");
        Expect(selected.bestScore==-1 && NSEqualRects(selected.bestRect,NSMakeRect(0,0,16,16)),@"candidate pipeline preserves search result when no fit or cache available");
        double linearScene[64*64],linearTemplate[8*8];
        for(size_t j=0;j<64;j++)for(size_t i=0;i<64;i++)linearScene[j*64+i]=i+3*j;
        for(size_t j=0;j<8;j++)for(size_t i=0;i<8;i++)linearTemplate[j*8+i]=i+3*j;
        FYNormalizeSignature(linearTemplate,64);
        [candidateEvents removeAllObjects];
        NSDictionary *fullCache=@{@"source":@"auto",@"mappingVersion":@2,@"nx":@0,@"ny":@0,@"nw":@1,@"nh":@1};
        selected=FYSelectCaptureCandidate(linearScene,64,64,linearTemplate,8,8,1,NSMakeRect(0,0,640,640),
            ^BOOL(NSRect *fit){[candidateEvents addObject:@"fit"];*fit=NSMakeRect(0,0,640,640);return YES;},
            ^NSDictionary *{[candidateEvents addObject:@"cache"];return fullCache;},2,
            ^(double searchScore,double fitScore){[candidateEvents addObject:@"preferred"];},
            ^(double existingScore,double bestScore,double fitScore){[candidateEvents addObject:@"kept"];});
        Expect([candidateEvents isEqual:@[@"fit",@"preferred",@"cache",@"kept"]],@"fit preference observer precedes cache lookup and keep observer follows scoring");
        Expect(selected.keepExisting && selected.bestScore>.99 && selected.fitScore>.99 && NSEqualRects(selected.bestRect,NSMakeRect(0,0,64,64)),@"near-perfect full fit wins over duplicate smaller candidate and matching cache stays");
        selected=FYSelectCaptureCandidate(linearScene,64,64,linearTemplate,8,8,1,NSMakeRect(0,0,640,640),
            ^BOOL(NSRect *fit){return NO;},^NSDictionary *{return manual;},2,NULL,NULL);
        Expect(!selected.keepExisting && selected.fitScore==-2,@"manual cache never enters automatic cache retention branch");
        FYAutoLocateSchedule *locate=[FYAutoLocateSchedule new];
        Expect(![locate isThrottled],@"nil locate attempt never throttles");
        LocateClockDate *locateDate=[LocateClockDate alloc];locateDate.relativeInterval=-2.99;locate.lastAttemptDate=locateDate;
        Expect([locate isThrottled] && locate.lastAttemptDate==locateDate,@"locate throttles before three seconds without updating date");
        locateDate.relativeInterval=-3;Expect(![locate isThrottled],@"three-second locate boundary permits retry");
        locateDate.relativeInterval=NAN;Expect(![locate isThrottled],@"nonfinite locate delta preserves original less-than rejection");
        double *ownedScene=malloc(sizeof(double)*64),*ownedTemplate=malloc(sizeof(double)*64);
        for(size_t j=0;j<8;j++)for(size_t i=0;i<8;i++){ownedTemplate[j*8+i]=i+3*j;ownedScene[j*8+i]=-(double)(i+3*j);}
        FYNormalizeSignature(ownedTemplate,64);
        double consumedScore=FYConsumeCaptureMappingGrids(@{@"nx":@0,@"ny":@0,@"nw":@1,@"nh":@1},ownedScene,8,8,ownedTemplate,8,8);
        Expect(fabs(consumedScore+1)<1e-9,@"consuming grid score preserves negative correlation not unavailable sentinel");
        Expect(FYConsumeCaptureMappingGrids(nil,NULL,0,0,NULL,0,0)==-99,@"consuming unavailable grids safely returns original sentinel");
        NSLog(@"PASS GeometryManagerTests: %lu assertions, no AppDelegate or UI initialization", (unsigned long)assertions);
    }
    return 0;
}
