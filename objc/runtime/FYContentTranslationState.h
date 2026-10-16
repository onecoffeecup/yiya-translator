#pragma once
#import <Foundation/Foundation.h>
#import "../FYContentRouter.h"

NS_ASSUME_NONNULL_BEGIN
@class OCRTextItem;
@class FYContentTranslationState;

// Copies the containers/text while preserving each original observation identity.
@interface FYContentTranslationSnapshot : NSObject
@property(nonatomic, readonly) NSUInteger revision;
@property(nonatomic, readonly) NSUInteger operations;
@property(nonatomic, readonly) NSInteger mode;
@property(nonatomic, copy, readonly, nullable) NSString *text;
@property(nonatomic, copy, readonly, nullable) NSArray<OCRTextItem *> *items;
@property(nonatomic, readonly) NSInteger geometryGeneration;
@property(nonatomic, readonly) uint32_t displayTarget;
@end

// Main-thread content lease state. No host, UI, requests, timers or observers.
@interface FYContentTranslationState : NSObject
// Explicit mutable aliases preserve the existing application/test facade.
@property(nonatomic) NSUInteger revision;
@property(nonatomic) NSUInteger operations;
@property(nonatomic) NSInteger mode;
@property(nonatomic, copy, nullable) NSString *text;
@property(nonatomic, copy, nullable) NSArray<OCRTextItem *> *items;
@property(nonatomic) NSInteger geometryGeneration;
@property(nonatomic) uint32_t displayTarget;
- (FYContentTranslationSnapshot *)snapshot;
- (void)invalidate;
// Two explicit phases let the adapter preserve the existing request cleanup order.
- (void)advanceRevision;
- (void)clearPending;
// Caller first performs the existing cancellation through its native host seam.
- (NSUInteger)beginText:(nullable NSString *)text mode:(NSInteger)mode;
// Retained long batch replaces its UI plan without creating a new transport revision.
- (NSUInteger)replacePendingText:(nullable NSString *)text;
- (void)updateGeometryGeneration:(NSInteger)geometry displayTarget:(uint32_t)target;
- (void)addOperation;
- (void)finishRevision:(NSUInteger)revision;
- (BOOL)matchesText:(nullable NSString *)text mode:(NSInteger)mode
    equivalent:(BOOL (^)(NSString * _Nullable, NSString * _Nullable))equivalent;
- (BOOL)matchesItems:(nullable NSArray<OCRTextItem *> *)items
    key:(NSString * _Nullable (^)(OCRTextItem *))key;
@end
NS_ASSUME_NONNULL_END
