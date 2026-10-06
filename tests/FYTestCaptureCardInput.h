#pragma once
// 仅测试构建使用：采集卡输入的测试替身。
// 它不创建 AVCaptureSession、不查询真实权限、不打开任何设备，
// 因此可以在不占用桌面、不接硬件的条件下验证会话生命周期与代次规则。
#import "FYCaptureCardInput.h"

@interface FYTestCaptureCardDevice : NSObject
@property (nonatomic, copy) NSString *uniqueID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic) BOOL inUseByAnotherApplication;
@end

@interface FYTestCaptureCardInput : FYCaptureCardInput

// —— 配置 ——
@property (nonatomic, copy) NSArray<FYTestCaptureCardDevice *> *testDevices;
@property (nonatomic) FYCaptureCardAvailability testAvailability;
/// requestAccessWithCompletion: 之后返回的授权状态。
@property (nonatomic) FYCaptureCardAvailability testAvailabilityAfterRequest;
/// 是否记录"确实收到了权限申请"。
@property (nonatomic, readonly) NSInteger accessRequestCount;
/// 单帧槽，使用真实生产类，可设置 minimumInterval 验证限速与有界缓存。
@property (nonatomic, readonly) FYCaptureCardFrameSlot *frameSlot;

// —— 观测 ——
/// 每次 startWithDeviceUniqueID: 收到的设备标识（含失败）。
@property (nonatomic, readonly) NSMutableArray<NSString *> *startAttempts;
/// 真正开始采集的会话设备标识。权限被拒或设备缺失时必须保持为空。
@property (nonatomic, readonly) NSMutableArray<NSString *> *startedSessions;
@property (nonatomic, readonly) NSInteger stopCallCount;
@property (nonatomic, readonly) NSInteger teardownCount;

// —— 模拟 ——
- (BOOL)testEnqueueFrameIndex:(uint64_t)index pixelSize:(size_t)pixelSize;
- (BOOL)testEnqueueFrameIndex:(uint64_t)index pixelWidth:(size_t)width pixelHeight:(size_t)height;
- (BOOL)testStoreFrame:(CGImageRef)image index:(uint64_t)index;
- (void)testDisconnectActiveDevice;
- (void)testSimulateRuntimeFailure;
- (void)testSetState:(FYCaptureCardSessionState)state detail:(NSString *)detail;

@end
