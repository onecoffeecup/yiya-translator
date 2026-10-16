#pragma once
#import "capture/FYCaptureSessionController.h"
NS_ASSUME_NONNULL_BEGIN
// Existing concrete input identity and native device/permission adapter.
// All session/queue/frame/state APIs remain inherited on this same receiver.
@interface FYCaptureCardInput : FYCaptureSessionController <FYCaptureDeviceAccess>
- (FYCaptureCardAvailability)availability;
- (void)requestAccessWithCompletion:(void (^)(FYCaptureCardAvailability availability))completion;
- (NSArray<FYCaptureCardDeviceInfo *> *)availableDevices;
@end
NS_ASSUME_NONNULL_END
