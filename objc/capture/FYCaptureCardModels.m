#import "FYCaptureCardModels.h"
NSTimeInterval const FYCaptureCardPreviewFrameInterval = 1.0 / 30.0;

FYCapturePermissionAction FYCapturePermissionActionForAvailability(FYCaptureCardAvailability availability) {
    if (availability==FYCaptureCardAvailabilityAuthorized) return FYCapturePermissionActionContinue;
    if (availability==FYCaptureCardAvailabilityNotDetermined) return FYCapturePermissionActionRequest;
    return FYCapturePermissionActionReject;
}

NSString *FYCaptureCardStatusText(FYCaptureCardSessionState state, FYCaptureCardAvailability availability,
    NSString *deviceName, uint64_t receivedFrames, uint64_t skippedFrames, NSString *detail) {
    NSMutableString *text=[NSMutableString string];
    [text appendFormat:@"识别输入源：采集卡 · %@ · 相机权限：%@",FYCaptureCardSessionStateLabel(state),FYCaptureCardAvailabilityLabel(availability)];
    if (deviceName.length>0) [text appendFormat:@" · 设备：%@",deviceName];
    if (state==FYCaptureCardSessionStateRunning) [text appendFormat:@" · 已收帧 %llu（丢弃旧帧 %llu）",(unsigned long long)receivedFrames,(unsigned long long)skippedFrames];
    if (detail.length>0) [text appendFormat:@"\n%@",detail];
    return text;
}



NSString *FYCaptureCardAvailabilityLabel(FYCaptureCardAvailability value) {
    switch (value) {
        case FYCaptureCardAvailabilityAuthorized: return @"已授权";
        case FYCaptureCardAvailabilityDenied: return @"已拒绝";
        case FYCaptureCardAvailabilityRestricted: return @"受系统限制";
        default: return @"尚未授权";
    }
}

NSString *FYCaptureCardSessionStateLabel(FYCaptureCardSessionState state) {
    switch (state) {
        case FYCaptureCardSessionStateStarting: return @"正在连接采集卡";
        case FYCaptureCardSessionStateRunning: return @"采集卡采集中";
        case FYCaptureCardSessionStateStopped: return @"采集卡已停止";
        case FYCaptureCardSessionStatePermissionDenied: return @"相机权限被拒绝";
        case FYCaptureCardSessionStateNoDevice: return @"未找到所选采集卡";
        case FYCaptureCardSessionStateDeviceUnavailable: return @"采集卡不可用";
        case FYCaptureCardSessionStateDisconnected: return @"采集卡已断开";
        case FYCaptureCardSessionStateFailed: return @"采集卡出错";
        default: return @"采集卡未启动";
    }
}
@implementation FYCaptureCardDeviceInfo
@end
@implementation FYCaptureSessionSnapshot
- (instancetype)initWithState:(FYCaptureCardSessionState)state detail:(NSString *)detail
    deviceID:(NSString *)deviceID deviceName:(NSString *)deviceName epoch:(NSUInteger)epoch
    startToken:(NSUInteger)token released:(BOOL)released received:(uint64_t)received failures:(uint64_t)failures {
    if ((self=[super init])) { _state=state; _detail=[detail copy]?:@""; _deviceID=[deviceID copy]; _deviceName=[deviceName copy];
        _epoch=epoch; _startToken=token; _released=released; _receivedFrames=received; _conversionFailures=failures; }
    return self;
}
@end
