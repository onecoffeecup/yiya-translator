#pragma once
#import "FYCaptureCardFrameSlot.h"
@class AVCaptureDevice, AVCaptureDeviceInput, AVCaptureSession, AVCaptureVideoDataOutput, CIContext;
NS_ASSUME_NONNULL_BEGIN
// Session-only device hooks, synchronously dispatched to the concrete subclass.
@protocol FYCaptureDeviceAccess <NSObject>
- (FYCaptureCardAvailability)availability;
- (nullable AVCaptureDevice *)deviceForUniqueID:(NSString *)uniqueID;
- (BOOL)isSelectableCaptureCard:(AVCaptureDevice *)device;
@end
/// 采集卡视频输入。只采视频、不采音频，只列外接采集设备，绝不回退到内置/手机摄像头。
///
/// 线程约定：`startWithDeviceUniqueID:` / `stop` / `availableDevices` / `availability` /
/// `requestAccessWithCompletion:` 在主线程调用；状态回调 `stateChangeHandler` 也在主队列触发。
/// `copyLatestFrame` 任何线程可用。
@interface FYCaptureSessionController : NSObject
/// Visible preview: 30 Hz; OCR-only background input: 10 Hz.
@property(nonatomic) BOOL previewActive;

@property (nonatomic, readonly) FYCaptureCardSessionState state;
/// 给用户看的状态说明（中文），说明失败原因与下一步动作。
@property (nonatomic, readonly, copy) NSString *stateDetail;
@property (nonatomic, readonly, copy, nullable) NSString *activeDeviceUniqueID;
@property (nonatomic, readonly, copy, nullable) NSString *activeDeviceName;
/// 会话代次：每次开始/停止/断开/运行错误都会自增。
/// 调用方在采集一帧时记下它，回调返回时再比对，代次不同就丢弃迟到结果。
@property (nonatomic, readonly) NSUInteger sessionEpoch;
/// 会话是否已真正释放（stopRunning + 移除输入输出完成）。断开/停止后可据此确认设备已放手。
@property (nonatomic, readonly) BOOL sessionReleased;
@property (nonatomic, readonly) uint64_t receivedFrameCount;
@property (nonatomic, readonly) uint64_t conversionFailureCount;
/// 已存入帧槽的帧数（有界缓存只保留最后一帧）。
@property (nonatomic, readonly) uint64_t storedFrameCount;
/// 因限速被丢弃的帧数。持续增长说明读帧快于识别，缓存没有积压。
@property (nonatomic, readonly) uint64_t skippedFrameCount;
/// 状态或帧统计变化时在主队列回调（可空）。
@property (nonatomic, copy, nullable) void (^stateChangeHandler)(void);




/// 用指定设备开始采集。缺少权限、设备不存在或被占用时返回 NO 并给出明确状态，不会改用其他设备。
- (BOOL)startWithDeviceUniqueID:(NSString *)uniqueID;
/// 停止并释放采集会话，同时作废当前帧。
- (void)stop;
- (CGImageRef)copyLatestFrame CF_RETURNS_RETAINED;
/// Atomically retain pixels and their sequence number from the same frame slot.
- (CGImageRef)copyLatestFrameWithIndex:(uint64_t * _Nullable)index CF_RETURNS_RETAINED;
- (uint64_t)latestFrameIndex;
/// 最近一帧的像素尺寸。没有帧或尺寸无效时返回 NO（调用方据此判断"能否建立坐标映射"）。
- (BOOL)latestFrameSize:(CGSize *)outSize;

- (FYCaptureSessionSnapshot *)sessionSnapshot;
@end

NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN
// Required native device adapters are implemented by FYCaptureCardInput;
// isolated session consumers provide the same three operations.
@interface FYCaptureSessionController (DeviceAccess) <FYCaptureDeviceAccess>
@end
// Exact construction boundary: tests replace native resources, not lifecycle algorithms.
@interface FYCaptureSessionController (NativeFactories)
- (nullable AVCaptureDeviceInput *)deviceInputForDevice:(AVCaptureDevice *)device error:(NSError * _Nullable * _Nullable)error;
- (AVCaptureSession *)newCaptureSession;
- (AVCaptureVideoDataOutput *)newVideoOutput;
- (CIContext *)captureImageContext;
@end
NS_ASSUME_NONNULL_END
