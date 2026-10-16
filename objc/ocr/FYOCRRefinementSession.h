#pragma once
#import "FYOCRRefinement.h"
NS_ASSUME_NONNULL_BEGIN

// Identity only, with the original formatted scope signature. Do not replace
// that signature with stricter floating-point equality during a refactor.
@interface FYOCRRefinementIdentity : NSObject
- (instancetype)initWithGeneration:(NSInteger)generation windowID:(uint32_t)windowID
    captureCard:(BOOL)captureCard inputEpoch:(NSUInteger)epoch language:(NSInteger)language
    scopeSignature:(NSString *)scope width:(NSUInteger)width height:(NSUInteger)height;
@property(nonatomic, readonly) NSInteger generation;
@property(nonatomic, readonly) uint32_t windowID;
@property(nonatomic, readonly) BOOL captureCard;
@property(nonatomic, readonly) NSUInteger inputEpoch;
@property(nonatomic, readonly) NSInteger language;
@property(nonatomic, copy, readonly) NSString *scopeSignature;
@property(nonatomic, readonly) NSUInteger width;
@property(nonatomic, readonly) NSUInteger height;
@property(nonatomic, copy, readonly) NSDictionary *legacyRepresentation;
@end

// Identity selection is main-thread work. Each returned stabilizer belongs to
// one serial OCR context; an older worker keeps its own instance until finished.
// Compatibility setters preserve original separate assignments, including nil.
@interface FYOCRRefinementSession : NSObject
@property(nonatomic, copy, nullable) NSDictionary *legacyContext;
@property(nonatomic, strong, nullable) FYOCRRefinementStabilizer *stabilizer;
- (nullable FYOCRRefinementStabilizer *)stateForIdentity:(FYOCRRefinementIdentity *)identity;
@end
NS_ASSUME_NONNULL_END
