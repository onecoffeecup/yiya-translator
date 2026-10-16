#import <FYCaptureCardInput.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
@interface FYCaptureCardInput (ProbePrivate)
- (AVCaptureDevice *)deviceForUniqueID:(NSString *)identifier;
- (BOOL)isSelectableCaptureCard:(AVCaptureDevice *)device;
@end
@interface Device : NSObject
- (NSString *)uniqueID;
- (NSString *)localizedName;
- (BOOL)isInUseByAnotherApplication;
@end
@implementation Device
- (NSString *)uniqueID{return @"fixture";}
- (NSString *)localizedName{return @"synthetic";}
- (BOOL)isInUseByAnotherApplication{return NO;}
@end
@interface Probe : FYCaptureCardInput @end
@implementation Probe
- (FYCaptureCardAvailability)availability{return FYCaptureCardAvailabilityAuthorized;}
- (AVCaptureDevice *)deviceForUniqueID:(NSString *)identifier{return (id)[Device new];}
- (BOOL)isSelectableCaptureCard:(AVCaptureDevice *)device{return YES;}
@end
int main(void){@autoreleasepool{Probe *p=[Probe new];dispatch_queue_t q=(dispatch_queue_t)object_getIvar(p,class_getInstanceVariable(FYCaptureCardInput.class,"_sessionQueue"));dispatch_semaphore_t gate=dispatch_semaphore_create(0),entered=dispatch_semaphore_create(0);dispatch_async(q,^{dispatch_semaphore_signal(entered);dispatch_semaphore_wait(gate,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC));});if(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)))return 3;
 BOOL accepted=[p startWithDeviceUniqueID:@"fixture"];BOOL pending=[p valueForKey:@"pendingDevice"]!=nil;dispatch_semaphore_signal(gate);dispatch_sync(q,^{});printf("accepted=%d pending_before_drain=%d pending_after_drain=%d state=%ld released=%d\n",accepted,pending,[p valueForKey:@"pendingDevice"]!=nil,(long)p.state,p.sessionReleased);BOOL success=p.state==FYCaptureCardSessionStateRunning;[p stop];dispatch_sync(q,^{});return success?0:2;}}
