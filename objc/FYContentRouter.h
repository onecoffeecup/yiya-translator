#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class OCRTextItem;
@class FYOCRStabilityOwner;

#import "ocr/FYContentModeState.h"
#import "ocr/FYDialogueStability.h"

#import "ocr/FYContentPolicy.h"

// Content policy only: no capture, Vision request, windows, cache, HTTP or keys.
// The caller preserves pipeline ordering, observes on one serial context and
// supplies explicit language/mapping/interaction state. Classification still
// precedes text filtering; extraction does not change the UI-first policy.
@interface FYContentRouter : FYContentPolicy
@property(nonatomic, strong, readonly) FYContentModeCoordinator *modeCoordinator;
@property(nonatomic, strong, readonly) FYContentModeStability *modeStability;
@property(nonatomic, strong, readonly) FYContentModeDecision *lastModeDecision;
- (NSInteger)observeModeForItems:(NSArray<OCRTextItem *> *)items locked:(BOOL)locked;

@end
