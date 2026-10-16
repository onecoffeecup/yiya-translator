#import "FYCaptureCardInput.h"
#import <AVFoundation/AVFoundation.h>
static NSArray<AVCaptureDeviceType> *FYExternalVideoDeviceTypes(void) {
    if (@available(macOS 14.0, *)) {
        return @[AVCaptureDeviceTypeExternal];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return @[AVCaptureDeviceTypeExternalUnknown];
#pragma clang diagnostic pop
}

// 明确要排除的"摄像头"类设备。实测本机 macOS 26/27 的外接枚举里会出现
// 「“iPhone (96)”的相机」，因此除了类型判断，再用型号/名称兜底。
static NSArray<AVCaptureDeviceType> *FYCameraLikeDeviceTypes(void) {
    NSMutableArray<AVCaptureDeviceType> *types = [NSMutableArray array];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [types addObject:AVCaptureDeviceTypeBuiltInWideAngleCamera];
#pragma clang diagnostic pop
    if (@available(macOS 14.0, *)) {
        [types addObject:AVCaptureDeviceTypeContinuityCamera];
        [types addObject:AVCaptureDeviceTypeDeskViewCamera];
    }
    return types;
}

static NSArray<AVCaptureDevice *> *FYDevicesOfTypes(NSArray<AVCaptureDeviceType> *types) {
    AVCaptureDeviceDiscoverySession *session =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:types
                                                               mediaType:AVMediaTypeVideo
                                                                position:AVCaptureDevicePositionUnspecified];
    return session.devices ?: @[];
}

static BOOL FYLooksLikePhoneOrComputerCamera(AVCaptureDevice *device) {
    NSArray<NSString *> *markers = @[@"iPhone", @"iPad", @"Continuity", @"Desk View", @"DeskView"];
    NSString *name = device.localizedName ?: @"";
    NSString *model = device.modelID ?: @"";
    for (NSString *marker in markers) {
        if ([name rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) { return YES; }
        if ([model rangeOfString:marker options:NSCaseInsensitiveSearch].location != NSNotFound) { return YES; }
    }
    for (NSString *prefix in @[@"iPhone", @"iPad"]) {
        if ([model hasPrefix:prefix]) { return YES; }
    }
    return NO;
}

static FYCaptureCardAvailability FYAvailabilityFromAV(AVAuthorizationStatus status) {
    switch (status) {
        case AVAuthorizationStatusAuthorized: return FYCaptureCardAvailabilityAuthorized;
        case AVAuthorizationStatusDenied: return FYCaptureCardAvailabilityDenied;
        case AVAuthorizationStatusRestricted: return FYCaptureCardAvailabilityRestricted;
        default: return FYCaptureCardAvailabilityNotDetermined;
    }
}


@implementation FYCaptureCardInput
- (FYCaptureCardAvailability)availability {
    return FYAvailabilityFromAV([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]);
}

- (void)requestAccessWithCompletion:(void (^)(FYCaptureCardAvailability))completion {
    if (!completion) { return; }
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        FYCaptureCardAvailability availability = granted ? FYCaptureCardAvailabilityAuthorized
                                                        : FYCaptureCardAvailabilityDenied;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(availability); });
    }];
}

- (NSArray<FYCaptureCardDeviceInfo *> *)availableDevices {
    NSMutableSet<NSString *> *excluded = [NSMutableSet set];
    for (AVCaptureDevice *camera in FYDevicesOfTypes(FYCameraLikeDeviceTypes())) {
        if (camera.uniqueID) { [excluded addObject:camera.uniqueID]; }
    }

    NSMutableArray<FYCaptureCardDeviceInfo *> *result = [NSMutableArray array];
    for (AVCaptureDevice *device in FYDevicesOfTypes(FYExternalVideoDeviceTypes())) {
        if (!device.isConnected) { continue; }
        if (device.uniqueID && [excluded containsObject:device.uniqueID]) { continue; }
        if (FYLooksLikePhoneOrComputerCamera(device)) { continue; }
        FYCaptureCardDeviceInfo *info = [FYCaptureCardDeviceInfo new];
        info.uniqueID = device.uniqueID ?: @"";
        info.displayName = device.localizedName ?: @"外接采集设备";
        info.inUseByAnotherApplication = device.isInUseByAnotherApplication;
        [result addObject:info];
    }
    [result sortUsingComparator:^NSComparisonResult(FYCaptureCardDeviceInfo *left, FYCaptureCardDeviceInfo *right) {
        return [left.displayName localizedCaseInsensitiveCompare:right.displayName];
    }];
    return result;
}

- (nullable AVCaptureDevice *)deviceForUniqueID:(NSString *)uniqueID {
    for (AVCaptureDevice *device in FYDevicesOfTypes(FYExternalVideoDeviceTypes())) {
        if ([device.uniqueID isEqualToString:uniqueID] && device.isConnected) { return device; }
    }
    return nil;
}

- (BOOL)isSelectableCaptureCard:(AVCaptureDevice *)device {
    for (AVCaptureDevice *camera in FYDevicesOfTypes(FYCameraLikeDeviceTypes())) {
        if (camera.uniqueID && [camera.uniqueID isEqualToString:device.uniqueID]) { return NO; }
    }
    return !FYLooksLikePhoneOrComputerCamera(device);
}
@end
