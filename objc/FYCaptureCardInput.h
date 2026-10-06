#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// 相机（视频采集）授权状态。译芽只读取授权，不在这里申请；申请必须由用户显式操作触发。
typedef NS_ENUM(NSInteger, FYCaptureCardAvailability) {
    FYCaptureCardAvailabilityNotDetermined = 0,
    FYCaptureCardAvailabilityAuthorized,
    FYCaptureCardAvailabilityDenied,
    FYCaptureCardAvailabilityRestricted,
};

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

/// 单一帧槽：采集卡是连续视频流，字幕只需要"最近一帧"。
/// 只保留一帧、按最短间隔限速、旧帧直接丢弃并计数，缓存因此天然有界，
/// 不会出现积压旧画面后按序补算的情况。
@interface FYCaptureCardFrameSlot : NSObject
/// 两次存帧之间的最短间隔（秒），默认 0.1。到期前的帧被丢弃并计入 skippedCount。
@property (nonatomic) NSTimeInterval minimumInterval;
/// 现在是否允许存帧（限速判断）。
- (BOOL)shouldStoreFrameAtTime:(NSTimeInterval)now;
/// 存入一帧并覆盖旧帧（内部 retain）。index 是流内的单调序号。
- (void)storeFrame:(CGImageRef)frame index:(uint64_t)index atTime:(NSTimeInterval)now;
/// 最近一帧的副本；调用方负责 CGImageRelease。没有帧时返回 NULL。
- (CGImageRef)copyLatestFrame CF_RETURNS_RETAINED;
/// 清空当前帧（新会话/停止时必须调用，避免继续用旧帧）。
- (void)clear;
- (void)resetCounters;
@property (nonatomic, readonly) uint64_t latestIndex;
@property (nonatomic, readonly) uint64_t storedCount;
@property (nonatomic, readonly) uint64_t skippedCount;
@property (nonatomic, readonly) BOOL hasFrame;
@end

/// 采集卡视频输入。只采视频、不采音频，只列外接采集设备，绝不回退到内置/手机摄像头。
///
/// 线程约定：`startWithDeviceUniqueID:` / `stop` / `availableDevices` / `availability` /
/// `requestAccessWithCompletion:` 在主线程调用；状态回调 `stateChangeHandler` 也在主队列触发。
/// `copyLatestFrame` 任何线程可用。
@interface FYCaptureCardInput : NSObject

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

- (FYCaptureCardAvailability)availability;
/// 申请相机权限。只在用户显式点击"申请相机权限"或开始采集时调用，不会自己弹窗。
- (void)requestAccessWithCompletion:(void (^)(FYCaptureCardAvailability availability))completion;
/// 可选的采集卡设备（外接视频输入，排除内置摄像头、手机接力相机、Desk View 与音频）。
- (NSArray<FYCaptureCardDeviceInfo *> *)availableDevices;
/// 用指定设备开始采集。缺少权限、设备不存在或被占用时返回 NO 并给出明确状态，不会改用其他设备。
- (BOOL)startWithDeviceUniqueID:(NSString *)uniqueID;
/// 停止并释放采集会话，同时作废当前帧。
- (void)stop;
- (CGImageRef)copyLatestFrame CF_RETURNS_RETAINED;
- (uint64_t)latestFrameIndex;
/// 最近一帧的像素尺寸。没有帧或尺寸无效时返回 NO（调用方据此判断"能否建立坐标映射"）。
- (BOOL)latestFrameSize:(CGSize *)outSize;

@end

NS_ASSUME_NONNULL_END
