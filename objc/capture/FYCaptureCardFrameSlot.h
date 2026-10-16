#pragma once
#import "FYCaptureCardModels.h"
NS_ASSUME_NONNULL_BEGIN
/// 单一帧槽：采集卡是连续视频流，字幕只需要"最近一帧"。
/// 只保留一帧、按最短间隔限速、旧帧直接丢弃并计数，缓存因此天然有界，
/// 不会出现积压旧画面后按序补算的情况。
@interface FYCaptureCardFrameSlot : NSObject
/// 两次存帧之间的最短间隔（秒），默认 1/30；允许最多 1 ms 调度抖动。到期前的帧被丢弃并计入 skippedCount。
@property (nonatomic) NSTimeInterval minimumInterval;
/// 现在是否允许存帧（限速判断）。
- (BOOL)shouldStoreFrameAtTime:(NSTimeInterval)now;
/// 存入一帧并覆盖旧帧（内部 retain）。index 是流内的单调序号。
- (void)storeFrame:(CGImageRef)frame index:(uint64_t)index atTime:(NSTimeInterval)now;
/// 最近一帧的副本；调用方负责 CGImageRelease。没有帧时返回 NULL。
- (CGImageRef)copyLatestFrame CF_RETURNS_RETAINED;
/// Atomically retain pixels and their sequence number from the same frame slot.
- (CGImageRef)copyLatestFrameWithIndex:(uint64_t * _Nullable)index CF_RETURNS_RETAINED;
/// 清空当前帧（新会话/停止时必须调用，避免继续用旧帧）。
- (void)clear;
- (void)resetCounters;
@property (nonatomic, readonly) uint64_t latestIndex;
@property (nonatomic, readonly) uint64_t storedCount;
@property (nonatomic, readonly) uint64_t skippedCount;
@property (nonatomic, readonly) BOOL hasFrame;
@end

NS_ASSUME_NONNULL_END
