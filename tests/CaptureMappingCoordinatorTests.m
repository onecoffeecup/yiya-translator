#import "capture/FYCaptureMappingCoordinator.h"
static NSUInteger checks;
static void Check(BOOL ok, NSString *message) { checks++; if (!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(2); } }
static void Released(void *info, const void *bytes, size_t count) { (*(NSUInteger *)info)++; free((void *)bytes); }
static CGImageRef Image(NSUInteger *released) {
    size_t width=80,height=80; unsigned char *bytes=calloc(width*height,4);
    for(size_t y=0;y<height;y++)for(size_t x=0;x<width;x++) { unsigned char *p=bytes+4*(y*width+x); p[0]=p[1]=p[2]=(x*13+y*7)%256;p[3]=255; }
    CGDataProviderRef provider=CGDataProviderCreateWithData(released,bytes,width*height*4,Released);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGImageRef image=CGImageCreate(width,height,8,32,width*4,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast,provider,NULL,NO,kCGRenderingIntentDefault);
    CGColorSpaceRelease(space); CGDataProviderRelease(provider); return image;
}
@interface MappingInputs : NSObject <FYCaptureMappingOperations>
@property(nonatomic) BOOL present,hasSize,screen,hasFrame,hasWindow,buildOK,fitOK,enabled,negativeGrid;
@property(nonatomic) CGSize size;
@property(nonatomic) CGRect frame,fit;
@property(nonatomic) double score;
@property(nonatomic) NSUInteger resetCalls,storeCalls,frameReleases,windowReleases;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,weak) FYCaptureMappingCoordinator *coordinator;
@end
@implementation MappingInputs
- (instancetype)init {if((self=[super init])){_present=_hasSize=_screen=_hasFrame=_hasWindow=_buildOK=_fitOK=_enabled=YES;_size=CGSizeMake(80,80);_frame=_fit=CGRectMake(-100,20,640,640);_score=1;_events=[NSMutableArray new];}return self;}
- (BOOL)mappingWindowPresent {[self.events addObject:@"present"];return self.present;}
- (uint32_t)mappingWindowID {[self.events addObject:@"id"];return 7;}
- (CGRect)mappingWindowFrame {[self.events addObject:@"frame"];return self.frame;}
- (BOOL)mappingLatestFrameSize:(CGSize *)size {[self.events addObject:@"size"];*size=self.size;return self.hasSize;}
- (BOOL)mappingCanCaptureScreen {[self.events addObject:@"screen"];return self.screen;}
- (CGImageRef)copyMappingFrame {[self.events addObject:@"copyFrame"];return self.hasFrame?Image(&_frameReleases):NULL;}
- (CGImageRef)copyMappingWindow {[self.events addObject:@"copyWindow"];return self.hasWindow?Image(&_windowReleases):NULL;}
- (BOOL)mappingBuildGridsWithTemplate:(double **)t templateW:(size_t *)tw templateH:(size_t *)th scene:(double **)s sceneW:(size_t *)sw sceneH:(size_t *)sh aspect:(CGFloat *)aspect sceneWidth:(size_t)width reason:(NSString **)reason {
    [self.events addObject:@"build"];Check(width==320,@"native build receives unchanged grid width");
    if(!self.buildOK){if(reason)*reason=@"synthetic unavailable";return NO;}
    *tw=*th=8;*sw=*sh=64;*aspect=1;*t=malloc(64*sizeof(double));*s=malloc(4096*sizeof(double));
    for(size_t y=0;y<64;y++)for(size_t x=0;x<64;x++)(*s)[y*64+x]=(self.negativeGrid?-1:1)*(double)(x+3*y);
    for(size_t y=0;y<8;y++)for(size_t x=0;x<8;x++)(*t)[y*8+x]=x+3*y;
    FYNormalizeSignature(*t,64);return YES;
}
- (BOOL)mappingEstimatedRect:(CGRect *)rect {[self.events addObject:@"fit"];*rect=self.fit;return self.fitOK;}
- (double)mappingScoreForEntry:(NSDictionary *)entry {[self.events addObject:@"score"];return self.score;}
- (NSString *)mappingSelectedDeviceID {[self.events addObject:@"device"];return @"synthetic";}
- (BOOL)mappingCaptureCardEnabled {[self.events addObject:@"enabled"];return self.enabled;}
- (void)mappingStoreRect:(CGRect)rect windowFrame:(CGRect)frame aspect:(CGFloat)aspect deviceID:(NSString *)device source:(NSString *)source confidence:(CGFloat)confidence windowID:(uint32_t)windowID {
    [self.events addObject:@"store"];self.storeCalls++;
    [self.coordinator storeRect:rect windowFrame:frame aspect:aspect deviceID:device source:source confidence:confidence windowID:windowID operations:self];
}
- (void)mappingResetLayoutCache {[self.events addObject:@"reset"];self.resetCalls++;}
@end
static FYCaptureMappingCoordinator *New(void) {return [[FYCaptureMappingCoordinator alloc]initWithConfiguration:[[FYCaptureMappingConfiguration alloc]initWithVersion:3 scoreUnavailable:-99]];}
static NSDictionary *Entry(MappingInputs *inputs, NSString *source, NSInteger version) {return [FYCaptureMappingAlgorithms captureMappingForRect:inputs.frame windowFrame:inputs.frame videoAspect:1 deviceID:@"synthetic" source:source confidence:1 version:version];}
int main(void) {@autoreleasepool{
    FYCaptureMappingCoordinator *core=New();MappingInputs *inputs=[MappingInputs new];inputs.coordinator=core;
    Check(core.configuration.version==3&&core.configuration.scoreUnavailable==-99&&!core.captureMappingCache&&!core.autoLocateSchedule&&!core.mappingValidationSchedule,@"cold immutable configuration creates no lazy state or native resources");
    NSMutableDictionary *external=[NSMutableDictionary new];[core mappingCache].entries=external;
    Check(core.captureMappingCache.entries==external&&[core mappingCache]==core.captureMappingCache,@"one cache retains external mutable entries identity");
    core.captureMappingCache=nil;Check(!core.captureMappingCache&&[core mappingCache].entries==nil&&external.count==0,@"nil raw owner remains nil until original lazy helper access");
    core.autoLocateSchedule=nil;core.mappingValidationSchedule=nil;
    Check([core locateSchedule]==core.autoLocateSchedule&&[core validationSchedule]==core.mappingValidationSchedule,@"all lazy helper aliases use single owners");
    CGRect out=CGRectMake(1,2,3,4);NSString *reason=@"unchanged";
    inputs.present=NO;Check(![core displayRect:&out operations:inputs reason:&reason observer:NULL]&&CGRectEqualToRect(out,CGRectMake(1,2,3,4))&&[reason isEqual:@"未选择目标窗口。"]&&[inputs.events isEqual:@[@"present"]],@"missing window leaves output unchanged and short circuits native reads");
    inputs.present=YES;[inputs.events removeAllObjects];
    Check(![core displayRect:&out operations:inputs reason:NULL observer:NULL]&&[inputs.events isEqual:@[@"present",@"id",@"id"]],@"missing cache leaves output and reads only original window identity");
    inputs.hasSize=NO;double *t=(void *)1,*s=(void *)2;size_t tw=91,th=92,sw=93,sh=94;CGFloat aspect=95;
    [inputs.events removeAllObjects];Check(![core buildGridsWithTemplate:&t templateW:&tw templateH:&th scene:&s sceneW:&sw sceneH:&sh aspect:&aspect sceneWidth:80 operations:inputs reason:&reason]&&!t&&!s&&tw==91&&th==92&&sw==93&&sh==94&&aspect==95&&[inputs.events isEqual:@[@"size"]],@"no frame nulls only grid outputs and preserves dimensions/aspect");
    inputs.hasSize=YES;inputs.screen=NO;[inputs.events removeAllObjects];
    Check(![core buildGridsWithTemplate:&t templateW:&tw templateH:&th scene:&s sceneW:&sw sceneH:&sh aspect:&aspect sceneWidth:80 operations:inputs reason:&reason]&&[inputs.events isEqual:@[@"size",@"screen"]],@"screen permission gate precedes image acquisition");
    inputs.screen=YES;inputs.hasFrame=NO;[inputs.events removeAllObjects];
    Check(![core buildGridsWithTemplate:&t templateW:&tw templateH:&th scene:&s sceneW:&sw sceneH:&sh aspect:&aspect sceneWidth:80 operations:inputs reason:&reason]&&[inputs.events isEqual:@[@"size",@"screen",@"copyFrame"]],@"missing frame avoids window capture");
    inputs.hasFrame=YES;inputs.hasWindow=NO;
    Check(![core buildGridsWithTemplate:&t templateW:&tw templateH:&th scene:&s sceneW:&sw sceneH:&sh aspect:&aspect sceneWidth:80 operations:inputs reason:&reason]&&inputs.frameReleases==1&&!inputs.windowReleases&&[reason isEqual:@"无法读取目标窗口画面"],@"missing window image releases owned frame exactly once");
    inputs.hasWindow=YES;[inputs.events removeAllObjects];
    Check([core buildGridsWithTemplate:&t templateW:&tw templateH:&th scene:&s sceneW:&sw sceneH:&sh aspect:&aspect sceneWidth:80 operations:inputs reason:NULL]&&t&&s&&tw==80&&th==80&&sw==80&&sh==80&&aspect==1,@"real image pixels use canonical grid construction and native geometry");
    Check(inputs.frameReleases==2&&inputs.windowReleases==1&&[inputs.events isEqual:@[@"size",@"screen",@"copyFrame",@"copyWindow",@"frame"]],@"real CG providers released after exact image/geometry order");free(t);free(s);
    [inputs.events removeAllObjects];inputs.hasSize=NO;
    Check(![core estimatedRect:&out operations:inputs]&&[inputs.events isEqual:@[@"present",@"size"]],@"estimate missing frame avoids native geometry");
    inputs.hasSize=YES;inputs.size=CGSizeMake(1,80);[inputs.events removeAllObjects];
    Check(![core estimatedRect:&out operations:inputs]&&[inputs.events isEqual:@[@"present",@"size"]],@"minimum frame gate leaves estimated output unchanged");
    inputs.size=CGSizeMake(80,80);Check([core estimatedRect:&out operations:inputs]&&CGRectEqualToRect(out,inputs.frame),@"canonical aspect estimate preserves negative screen origin");
    inputs.storeCalls=inputs.resetCalls=0;
    [core storeRect:CGRectZero windowFrame:inputs.frame aspect:1 deviceID:@"synthetic" source:@"manual" confidence:1 windowID:7 operations:inputs];
    Check(![core mappingCache].entries&&!inputs.resetCalls&&!core.mappingValidationSchedule.lastValidationDate,@"invalid store leaves cache/date/native reset untouched");
    [core storeRect:inputs.frame windowFrame:inputs.frame aspect:1 deviceID:@"synthetic" source:@"manual" confidence:1 windowID:7 operations:inputs];
    Check([[[core mappingCache]entryForWindowID:7][@"source"]isEqual:@"manual"]&&inputs.resetCalls==1&&core.mappingValidationSchedule.lastValidationDate,@"store creates canonical mapping and starts validation grace before reset");
    [inputs.events removeAllObjects];reason=@"keep";
    Check([core displayRect:&out operations:inputs reason:&reason observer:NULL]&&CGRectEqualToRect(out,inputs.frame)&&[reason isEqual:@"keep"]&&![inputs.events containsObject:@"enabled"]&&![inputs.events containsObject:@"score"],@"manual mapping preserves reason and entirely skips automatic validation");
    [core clearWindowID:7];Check(![[core mappingCache]entryForWindowID:7]&&inputs.resetCalls==1,@"clear affects only one mapping without extra reset");
    [[core mappingCache]storeEntry:Entry(inputs,@"auto",2) forWindowID:7];core.autoLocateSchedule.lastAttemptDate=NSDate.date;
    __block FYCaptureMappingEvent event={0};[inputs.events removeAllObjects];
    Check(![core displayRect:&out operations:inputs reason:&reason observer:^(FYCaptureMappingEvent e){event=e;Check([inputs.events.lastObject isEqual:@"reset"],@"stale version observer follows original reset");}]&&event.kind==FYMappingStaleVersion&&event.windowID==7&&![[core mappingCache]entryForWindowID:7]&&!core.autoLocateSchedule.lastAttemptDate&&![inputs.events containsObject:@"size"],@"stale auto version invalidates before geometry and clears locate throttle");
    [[core mappingCache]storeEntry:Entry(inputs,@"auto",3) forWindowID:7];core.mappingValidationSchedule.lastValidationDate=NSDate.date;inputs.score=-1;[inputs.events removeAllObjects];
    Check([core displayRect:&out operations:inputs reason:NULL observer:NULL]&&![inputs.events containsObject:@"score"],@"fresh automatic mapping uses original two second grace");
    core.mappingValidationSchedule.lastValidationDate=nil;inputs.score=-99;
    Check([core displayRect:NULL operations:inputs reason:NULL observer:NULL]&&[[core mappingCache]entryForWindowID:7]&&core.mappingValidationSchedule.lastValidationDate,@"unavailable score keeps mapping and advances validation date");
    core.mappingValidationSchedule.lastValidationDate=nil;inputs.score=-1;core.autoLocateSchedule.lastAttemptDate=NSDate.date;
    Check(![core displayRect:&out operations:inputs reason:&reason observer:^(FYCaptureMappingEvent e){event=e;}]&&event.kind==FYMappingStalePicture&&event.score==-1&&![[core mappingCache]entryForWindowID:7]&&!core.autoLocateSchedule.lastAttemptDate&&[reason isEqual:@"游戏画面位置变了，正在重新定位"],@"negative correlation invalidates picture without conflating unavailable sentinel");
    [[core mappingCache]storeEntry:Entry(inputs,@"auto",3) forWindowID:7];inputs.enabled=NO;[inputs.events removeAllObjects];
    Check([core displayRect:NULL operations:inputs reason:NULL observer:NULL]&&![inputs.events containsObject:@"score"],@"disabled capture input avoids automatic scoring");inputs.enabled=YES;
    CGRect original=inputs.frame;inputs.frame=CGRectMake(0,0,1,1);[inputs.events removeAllObjects];
    Check(![core displayRect:NULL operations:inputs reason:NULL observer:NULL]&&![inputs.events containsObject:@"size"],@"invalid window geometry short circuits frame sampling");inputs.frame=original;
    inputs.size=CGSizeMake(160,80);[inputs.events removeAllObjects];
    Check(![core displayRect:NULL operations:inputs reason:NULL observer:NULL]&&![inputs.events containsObject:@"score"]&&[inputs.events containsObject:@"device"],@"changed input aspect retains original device read and avoids scoring");inputs.size=CGSizeMake(80,80);
    [core clearWindowID:7];core.autoLocateSchedule.lastAttemptDate=NSDate.date;[inputs.events removeAllObjects];
    Check(![core autoDetectWithOperations:inputs reason:NULL observer:NULL]&&[inputs.events isEqual:@[@"present"]],@"failed locate throttle precedes native geometry and grid capture");
    core.autoLocateSchedule.lastAttemptDate=nil;inputs.frame=CGRectMake(0,0,39,640);[inputs.events removeAllObjects];
    Check(![core autoDetectWithOperations:inputs reason:NULL observer:NULL]&&[inputs.events isEqual:@[@"present",@"frame"]],@"small window rejects before grid capture");inputs.frame=original;
    inputs.buildOK=NO;Check(![core autoDetectWithOperations:inputs reason:&reason observer:NULL]&&[reason isEqual:@"synthetic unavailable"]&&!core.autoLocateSchedule.lastAttemptDate,@"native grid failure preserves no-attempt-date policy");inputs.buildOK=YES;
    inputs.negativeGrid=YES;inputs.fitOK=NO;
    Check(![core autoDetectWithOperations:inputs reason:&reason observer:^(FYCaptureMappingEvent e){event=e;}]&&event.kind==FYMappingMiss&&event.score<.55&&core.autoLocateSchedule.lastAttemptDate&&!inputs.storeCalls,@"real negative grid search misses and timestamps failed attempt");
    core.autoLocateSchedule.lastAttemptDate=nil;inputs.negativeGrid=NO;inputs.fitOK=YES;[inputs.events removeAllObjects];
    Check([core autoDetectWithOperations:inputs reason:NULL observer:^(FYCaptureMappingEvent e){[inputs.events addObject:e.kind==FYMappingPreferFit?@"preferred":@"hit"];event=e;}]&&inputs.storeCalls==1&&event.kind==FYMappingHit&&event.score>.99&&CGRectEqualToRect(event.rect,inputs.frame)&&!core.autoLocateSchedule.lastAttemptDate,@"real grid fit stores through native action and clears failed-locate date");
    Check([inputs.events indexOfObject:@"fit"]<[inputs.events indexOfObject:@"preferred"]&&[inputs.events indexOfObject:@"preferred"]<[inputs.events indexOfObject:@"store"]&&[inputs.events indexOfObject:@"store"]<[inputs.events indexOfObject:@"reset"]&&[inputs.events.lastObject isEqual:@"hit"],@"fit observation/store/reset/hit retain original synchronous order");
    NSDate *validation=core.mappingValidationSchedule.lastValidationDate;[inputs.events removeAllObjects];reason=@"unchanged";
    Check(![core autoDetectWithOperations:inputs reason:&reason observer:^(FYCaptureMappingEvent e){event=e;}]&&event.kind==FYMappingKeepCache&&inputs.storeCalls==1&&core.mappingValidationSchedule.lastValidationDate==validation&&!core.autoLocateSchedule.lastAttemptDate&&[reason isEqual:@"unchanged"],@"matching real-grid cache retention leaves dates/reason and native store untouched");
    Check([core scoreForEntry:[[core mappingCache]entryForWindowID:7] operations:inputs]>.99,@"score consumes real native owned grids using same canonical implementation");
    inputs.buildOK=NO;Check([core scoreForEntry:Entry(inputs,@"auto",3) operations:inputs]==-99,@"failed native grid sampling returns exact sentinel");
    [inputs.events removeAllObjects];Check([core scoreForEntry:nil operations:inputs]==-99&&[inputs.events isEqual:@[@"present"]],@"nil score entry avoids owned grid acquisition");
    __weak MappingInputs *released;
    @autoreleasepool { MappingInputs *temporary=[MappingInputs new];released=temporary;temporary.coordinator=core;[core estimatedRect:&out operations:temporary]; }
    Check(!released,@"idle coordinator keeps no synchronous operations provider");
    printf("PASS mapping coordinator: %lu checks; Foundation/CG, native action order, single lazy state, image leases, canonical search/validation\n",(unsigned long)checks);
}return 0;}
