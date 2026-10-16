#pragma once
#import <Foundation/Foundation.h>

#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared cadence for the latest-frame slot and capture-card preview (30 Hz).
FOUNDATION_EXPORT NSTimeInterval const FYCaptureCardPreviewFrameInterval;
FOUNDATION_EXPORT BOOL FYCaptureFrameNeedsRecognition(uint64_t latestIndex, uint64_t lastRecognizedIndex);

/// 相机（视频采集）授权状态。译芽只读取授权，不在这里申请；申请必须由用户显式操作触发。
typedef NS_ENUM(NSInteger, FYCaptureCardAvailability) {
    FYCaptureCardAvailabilityNotDetermined = 0,
    FYCaptureCardAvailabilityAuthorized,
    FYCaptureCardAvailabilityDenied,
    FYCaptureCardAvailabilityRestricted,
};

typedef NS_ENUM(NSInteger, FYCapturePermissionAction) {
    FYCapturePermissionActionContinue,
    FYCapturePermissionActionRequest,
    FYCapturePermissionActionReject,
};
FOUNDATION_EXPORT FYCapturePermissionAction FYCapturePermissionActionForAvailability(FYCaptureCardAvailability availability);

/// 采集会话状态。任何非 Running 的状态都表示"没有可用新帧"。
typedef NS_ENUM(NSInteger, FYCaptureCardSessionState) {
    FYCaptureCardSessionStateIdle = 0,
    FYCaptureCardSessionStateStarting,
    FYCaptureCardSessionStateRunning,
    FYCaptureCardSessionStateStopped,
    FYCaptureCardSessionStatePermissionDenied,
    FYCaptureCardSessionStateNoDevice,
    FYCaptureCardSessionStateDeviceUnavailable,
    FYCaptureCardSessionStateDisconnected,
    FYCaptureCardSessionStateFailed,
};

FOUNDATION_EXPORT NSString *FYCaptureCardStatusText(FYCaptureCardSessionState state, FYCaptureCardAvailability availability,
    NSString *deviceName, uint64_t receivedFrames, uint64_t skippedFrames, NSString *detail);
FOUNDATION_EXPORT NSString *FYCaptureCardAvailabilityLabel(FYCaptureCardAvailability value);
FOUNDATION_EXPORT NSString *FYCaptureCardSessionStateLabel(FYCaptureCardSessionState state);

/// 一个**外接视频采集设备**（采集卡）的公开信息。
/// 刻意不含 uniqueID 之外的序列号/型号：状态行只显示名称，日志不记录硬件标识。
@interface FYCaptureCardDeviceInfo : NSObject
@property (nonatomic, copy) NSString *uniqueID;
@property (nonatomic, copy) NSString *displayName;
/// 设备已被其他进程打开。采集卡通常可共享，只作提示，不阻止打开。
@property (nonatomic) BOOL inUseByAnotherApplication;
@end

// A coherent immutable view of the existing session fields, on explicit read.
@interface FYCaptureSessionSnapshot : NSObject
@property(nonatomic, readonly) FYCaptureCardSessionState state;
@property(nonatomic, copy, readonly) NSString *detail;
@property(nonatomic, copy, readonly, nullable) NSString *deviceID;
@property(nonatomic, copy, readonly, nullable) NSString *deviceName;
@property(nonatomic, readonly) NSUInteger epoch, startToken;
@property(nonatomic, readonly) BOOL released;
@property(nonatomic, readonly) uint64_t receivedFrames, conversionFailures;
- (instancetype)initWithState:(FYCaptureCardSessionState)state detail:(NSString *)detail
    deviceID:(nullable NSString *)deviceID deviceName:(nullable NSString *)deviceName
    epoch:(NSUInteger)epoch startToken:(NSUInteger)token released:(BOOL)released
    received:(uint64_t)received failures:(uint64_t)failures;
@end

NS_ASSUME_NONNULL_END
