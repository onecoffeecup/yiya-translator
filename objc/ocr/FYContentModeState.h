#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, FYContentMode) {
    FYContentModeDialogue = 0,
    FYContentModeUI = 1,
};

// Per-run mode evidence. Kept public for existing replay/state adapters.
@interface FYContentModeStability : NSObject
@property(nonatomic) NSInteger detectedMode;
@property(nonatomic) NSInteger candidateMode;
@property(nonatomic) NSInteger candidateHits;
- (NSInteger)observeMode:(NSInteger)detected;
@end

@interface FYContentModeDecision : NSObject
- (instancetype)initWithMode:(NSInteger)mode reason:(NSString *)reason;
@property(nonatomic, readonly) NSInteger mode;
@property(nonatomic, copy, readonly) NSString *reason;
@end

// Owns mode evidence and last immutable decision; classifier is synchronous
// and never retained. Locking bypasses classification and preserves candidates.
@interface FYContentModeCoordinator : NSObject
@property(nonatomic, strong) FYContentModeStability *stability;
@property(nonatomic, strong) FYContentModeDecision *lastDecision;
- (NSInteger)observeLocked:(BOOL)locked classifier:(FYContentModeDecision *(^)(NSInteger fallback))classifier;
@end
