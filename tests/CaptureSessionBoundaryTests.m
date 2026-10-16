#import "capture/FYCaptureSessionController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *s){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",s.UTF8String);exit(2);}}
@interface FYCaptureSessionController (TestNativeEvents)
- (BOOL)isCurrentStartToken:(NSUInteger)token;
- (void)handleDeviceDisconnected;
- (void)handleRuntimeFailure:(NSError *)error;
- (void)handleSessionInterrupted:(NSDictionary *)info;
- (void)handleSessionInterruptionEnded;
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sample fromConnection:(AVCaptureConnection *)connection;
@end
@interface FakeDevice : NSObject
@property(copy) NSString *uniqueID,*localizedName;
@property(getter=isInUseByAnotherApplication) BOOL inUseByAnotherApplication;
@end
@implementation FakeDevice @end
@interface FakeSession : NSObject
@property(strong) NSMutableArray *events;
@property BOOL allowInput,allowOutput,willRun,isRunning;
- (BOOL)canAddInput:(id)value;
- (BOOL)canAddOutput:(id)value;
- (void)addInput:(id)value;
- (void)addOutput:(id)value;
- (void)removeInput:(id)value;
- (void)removeOutput:(id)value;
- (void)startRunning;
- (void)stopRunning;
@end
@implementation FakeSession
- (BOOL)canAddInput:(id)value{[self.events addObject:@"canInput"];return self.allowInput;}
- (BOOL)canAddOutput:(id)value{[self.events addObject:@"canOutput"];return self.allowOutput;}
- (void)addInput:(id)value{[self.events addObject:@"addInput"];}
- (void)addOutput:(id)value{[self.events addObject:@"addOutput"];}
- (void)removeInput:(id)value{[self.events addObject:@"removeInput"];}
- (void)removeOutput:(id)value{[self.events addObject:@"removeOutput"];}
- (void)startRunning{[self.events addObject:@"start"];self.isRunning=self.willRun;}
- (void)stopRunning{[self.events addObject:@"stop"];self.isRunning=NO;}
@end
@interface FakeOutput : NSObject
@property BOOL alwaysDiscardsLateVideoFrames;
@property(copy) NSDictionary *videoSettings;
@property(weak) id delegate;
@property(strong) dispatch_queue_t queue;
@property(strong) NSMutableArray *events;
- (void)setSampleBufferDelegate:(id)value queue:(dispatch_queue_t)queue;
@end
@implementation FakeOutput
- (void)setSampleBufferDelegate:(id)value queue:(dispatch_queue_t)queue{self.delegate=value;self.queue=queue;[self.events addObject:value?@"delegateSet":@"delegateClear"];}
@end
@interface SessionProbe : FYCaptureSessionController <FYCaptureDeviceAccess>
@property FYCaptureCardAvailability permission;
@property(strong) FakeDevice *device;
@property BOOL supported,inputFails,allowInput,allowOutput,willRun;
@property(strong) NSMutableArray *events;
@property(strong) FakeSession *nativeSession;
@property(strong) FakeOutput *nativeOutput;
@property(strong) dispatch_semaphore_t entered,gate;
@property NSUInteger permissionReads,deviceReads,selectorReads;
@end
@implementation SessionProbe
- (instancetype)init{if((self=[super init])){_permission=FYCaptureCardAvailabilityAuthorized;_supported=_allowInput=_allowOutput=_willRun=YES;_device=[FakeDevice new];_device.uniqueID=@"fixture";_device.localizedName=@"synthetic capture";_events=[NSMutableArray array];}return self;}
- (FYCaptureCardAvailability)availability{self.permissionReads++;dispatch_sync((dispatch_queue_t)object_getIvar(self,class_getInstanceVariable(FYCaptureSessionController.class,"_sessionQueue")),^{});return self.permission;}
- (AVCaptureDevice *)deviceForUniqueID:(NSString *)identifier{self.deviceReads++;return [identifier isEqual:@"fixture"]?(id)self.device:nil;}
- (BOOL)isSelectableCaptureCard:(AVCaptureDevice *)device{self.selectorReads++;return self.supported;}
- (AVCaptureDeviceInput *)deviceInputForDevice:(AVCaptureDevice *)device error:(NSError **)error{[self.events addObject:@"deviceInput"];if(self.inputFails){if(error)*error=[NSError errorWithDomain:@"synthetic" code:1 userInfo:nil];return nil;}return (id)[NSObject new];}
- (AVCaptureSession *)newCaptureSession{if(self.entered)dispatch_semaphore_signal(self.entered);if(self.gate)dispatch_semaphore_wait(self.gate,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));[self.events addObject:@"session"];self.nativeSession=[FakeSession new];self.nativeSession.events=self.events;self.nativeSession.allowInput=self.allowInput;self.nativeSession.allowOutput=self.allowOutput;self.nativeSession.willRun=self.willRun;return (id)self.nativeSession;}
- (AVCaptureVideoDataOutput *)newVideoOutput{[self.events addObject:@"output"];self.nativeOutput=[FakeOutput new];self.nativeOutput.events=self.events;return (id)self.nativeOutput;}
- (CIContext *)captureImageContext{[self.events addObject:@"context"];return [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@YES}];}
@end
static dispatch_queue_t Queue(FYCaptureSessionController *p,const char *name){return (dispatch_queue_t)object_getIvar(p,class_getInstanceVariable(FYCaptureSessionController.class,name));}
static void Flush(SessionProbe *p){dispatch_sync(Queue(p,"_sessionQueue"),^{});}
static void Pump(void){for(int n=0;n<8;n++)[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];}
int main(void){@autoreleasepool{
 SessionProbe *p=[SessionProbe new];FYCaptureSessionSnapshot *cold=[p sessionSnapshot];
 Check(cold.state==FYCaptureCardSessionStateIdle&&cold.released&&!cold.epoch&&!cold.startToken&&!cold.receivedFrames&&!cold.conversionFailures,@"cold canonical session has original idle state");
 Check(!p.permissionReads&&!p.deviceReads&&!p.events.count&&!p.nativeSession&&!p.nativeOutput,@"cold session creates no native resource or permission/device queries");Check(Queue(p,"_sessionQueue")&&Queue(p,"_frameQueue")&&Queue(p,"_sessionQueue")!=Queue(p,"_frameQueue"),@"session and frame queues remain separate original owners");
 Check(![p startWithDeviceUniqueID:@""]&&!p.sessionEpoch&&p.state==FYCaptureCardSessionStateNoDevice&&!p.permissionReads,@"empty selection rejects before epoch or native device access");
 p.permission=FYCaptureCardAvailabilityDenied;Check(![p startWithDeviceUniqueID:@"fixture"]&&p.sessionEpoch==1&&p.state==FYCaptureCardSessionStatePermissionDenied&&p.sessionReleased&&!p.deviceReads,@"permission gate preserves original epoch and short circuit");Flush(p);Check(!p.events.count,@"rejected authorization constructs no native capture resource");
 p.permission=FYCaptureCardAvailabilityAuthorized;Check(![p startWithDeviceUniqueID:@"missing"]&&p.state==FYCaptureCardSessionStateNoDevice&&!p.selectorReads,@"missing chosen device never selects another device");Flush(p);
 p.supported=NO;Check(![p startWithDeviceUniqueID:@"fixture"]&&p.state==FYCaptureCardSessionStateDeviceUnavailable&&!p.events.count,@"unsupported device rejected before constructors");Flush(p);p.supported=YES;
 __block NSUInteger notifications=0;__block BOOL allMain=YES;p.stateChangeHandler=^{notifications++;allMain&=NSThread.isMainThread;};
 NSUInteger before=p.sessionEpoch;Check([p startWithDeviceUniqueID:@"fixture"],@"supported device starts real canonical lifecycle");Flush(p);Pump();FYCaptureSessionSnapshot *running=[p sessionSnapshot];
 Check(p.state==FYCaptureCardSessionStateRunning&&!p.sessionReleased&&p.sessionEpoch==before+1&&[running.deviceID isEqual:@"fixture"]&&[running.deviceName isEqual:@"synthetic capture"],@"configuration produces original running state and immutable device identity");
 Check([p.events isEqual:@[@"deviceInput",@"session",@"canInput",@"addInput",@"output",@"delegateSet",@"canOutput",@"addOutput",@"context",@"start"]],@"canonical configuration preserves native construction/delegate/input/output/start order");
 Check(p.nativeOutput.alwaysDiscardsLateVideoFrames&&[p.nativeOutput.videoSettings[(id)kCVPixelBufferPixelFormatTypeKey] unsignedIntValue]==kCVPixelFormatType_32BGRA,@"capture remains late-frame dropping and BGRA video only");Check(p.nativeOutput.delegate==p&&p.nativeOutput.queue==Queue(p,"_frameQueue"),@"actual concrete self remains delegate on separate frame queue");
 Check([p isCurrentStartToken:running.startToken]&&![p isCurrentStartToken:running.startToken-1],@"old start token rejected by actual session gate");Check(notifications>=2&&allMain,@"original state notifications deliver asynchronously on main queue");
 Check(!p.previewActive,@"session starts with OCR-only cadence");p.previewActive=YES;FYCaptureCardFrameSlot *slot=object_getIvar(p,class_getInstanceVariable(FYCaptureSessionController.class,"_slot"));Check(fabs(slot.minimumInterval-1.0/30)<1e-10&&p.previewActive,@"preview switches the same canonical slot to 30Hz");p.previewActive=NO;Check(slot.minimumInterval==.1,@"hiding preview restores original 10Hz slot");
 CVPixelBufferRef pixels=NULL;Check(CVPixelBufferCreate(kCFAllocatorDefault,8,8,kCVPixelFormatType_32BGRA,NULL,&pixels)==kCVReturnSuccess,@"synthetic pixel buffer created without device");CVPixelBufferLockBaseAddress(pixels,0);memset(CVPixelBufferGetBaseAddress(pixels),255,CVPixelBufferGetDataSize(pixels));CVPixelBufferUnlockBaseAddress(pixels,0);
 CMVideoFormatDescriptionRef format=NULL;CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,pixels,&format);CMSampleTimingInfo timing={CMTimeMake(1,30),CMTimeMake(1,30),kCMTimeInvalid};CMSampleBufferRef sample=NULL;CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,pixels,format,&timing,&sample);
 dispatch_sync(Queue(p,"_frameQueue"),^{[p captureOutput:nil didOutputSampleBuffer:sample fromConnection:nil];});CFRelease(sample);CFRelease(format);CVPixelBufferRelease(pixels);
 uint64_t index=0;CGImageRef image=[p copyLatestFrameWithIndex:&index];Check(p.receivedFrameCount==1&&p.storedFrameCount==1&&!p.conversionFailureCount&&index==1&&image&&CGImageGetWidth(image)==8,@"actual sample callback and real CoreImage produce a coherent frame/index");CGImageRelease(image);
 NSUInteger epoch=p.sessionEpoch;FakeOutput *output=p.nativeOutput;[p.events removeAllObjects];
 dispatch_semaphore_t stopEntered=dispatch_semaphore_create(0),stopGate=dispatch_semaphore_create(0);
 dispatch_async(Queue(p,"_sessionQueue"),^{dispatch_semaphore_signal(stopEntered);dispatch_semaphore_wait(stopGate,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));});
 Check(dispatch_semaphore_wait(stopEntered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0,@"teardown is held to verify immediate frame cancellation");[p stop];Check(p.state==FYCaptureCardSessionStateStopped&&p.sessionEpoch==epoch+1&&!p.latestFrameIndex,@"stop immediately invalidates epoch and clears old slot");dispatch_semaphore_signal(stopGate);Flush(p);Pump();Check(p.sessionReleased&&!output.delegate&&!output.queue,@"actual teardown clears delegate/queue and publishes released state");
 Check([p.events isEqual:@[@"delegateClear",@"stop",@"removeOutput",@"removeInput"]],@"teardown preserves clear-delegate/stop/remove-output/remove-input order");Check([running.deviceID isEqual:@"fixture"]&&running.state==FYCaptureCardSessionStateRunning&&!running.released,@"captured immutable snapshot does not change after stop");
 [p.events removeAllObjects];Check([p startWithDeviceUniqueID:@"fixture"],@"session can restart");Flush(p);epoch=p.sessionEpoch;[p handleSessionInterrupted:@{}];Check(p.state==FYCaptureCardSessionStateDeviceUnavailable&&p.sessionEpoch==epoch,@"interruption retains original epoch policy");[p handleSessionInterruptionEnded];Check(p.state==FYCaptureCardSessionStateRunning,@"interruption ended restores original running state");
 [p handleDeviceDisconnected];Check(p.state==FYCaptureCardSessionStateDisconnected&&p.sessionEpoch==epoch+1,@"disconnect advances epoch through canonical handler");Flush(p);Check(p.sessionReleased,@"disconnect releases native resources");
 [p startWithDeviceUniqueID:@"fixture"];Flush(p);epoch=p.sessionEpoch;[p handleRuntimeFailure:[NSError errorWithDomain:@"fictional" code:7 userInfo:nil]];Check(p.state==FYCaptureCardSessionStateFailed&&p.sessionEpoch==epoch+1,@"runtime failure has original state and epoch cancellation");Flush(p);Check(p.sessionReleased,@"runtime failure teardown completes");
 for(NSUInteger variant=0;variant<4;variant++){SessionProbe *f=[SessionProbe new];f.inputFails=variant==0;f.allowInput=variant!=1;f.allowOutput=variant!=2;f.willRun=variant!=3;Check([f startWithDeviceUniqueID:@"fixture"],@"failure transport enters same asynchronous configure algorithm");Flush(f);Check(f.sessionReleased&&f.state==(variant==3?FYCaptureCardSessionStateFailed:FYCaptureCardSessionStateDeviceUnavailable),@"all original native construction/configuration failures release session and retain failure state");[f stop];Flush(f);}
 SessionProbe *late=[SessionProbe new];late.entered=dispatch_semaphore_create(0);late.gate=dispatch_semaphore_create(0);
 Check([late startWithDeviceUniqueID:@"fixture"],@"late-start fixture enters canonical native configure");
 Check(dispatch_semaphore_wait(late.entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0,@"late native construction boundary is reached");[late stop];dispatch_semaphore_signal(late.gate);Flush(late);
 Check(late.state==FYCaptureCardSessionStateStopped&&late.sessionReleased,@"old native start token cannot publish running after stop");
 dispatch_semaphore_t entered=dispatch_semaphore_create(0),gate=dispatch_semaphore_create(0);__weak SessionProbe *leased;
 @autoreleasepool{SessionProbe *q=[SessionProbe new];q.entered=entered;q.gate=gate;leased=q;Check([q startWithDeviceUniqueID:@"fixture"],@"held native constructor is accepted");Check(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0,@"actual session task reaches held native boundary");}
 Check(leased!=nil,@"original strong self survives while native task is in flight");dispatch_semaphore_signal(gate);for(int n=0;n<100&&leased;n++)usleep(10000);Check(!leased,@"native task completion releases self and weak observers");
 p.stateChangeHandler=nil;[p stop];Flush(p);
 printf("PASS session boundary: %lu checks; actual configure/teardown/sample algorithms, fake native transport, no permission/devices/UI\n",(unsigned long)checks);
 }return 0;}
