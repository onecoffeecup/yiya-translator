#import <Cocoa/Cocoa.h>

typedef struct {
    NSRect bestRect;
    double bestScore, fitScore;
    BOOL keepExisting;
} FYCaptureCandidateResult;
// Borrowed grids; synchronous callbacks preserve search -> fit -> observer -> cache order.
FOUNDATION_EXPORT FYCaptureCandidateResult FYSelectCaptureCandidate(const double *scene, size_t width, size_t height,
    const double *templ, size_t templateWidth, size_t templateHeight, CGFloat videoAspect, NSRect windowFrame,
    BOOL (^estimateFit)(NSRect *), NSDictionary *(^existingEntry)(void), NSInteger version,
    void (^preferredFit)(double searchScore, double fitScore), void (^keptCache)(double existingScore, double bestScore, double fitScore));

typedef NS_ENUM(NSInteger, FYCaptureMappingVersionStatus) {
    FYCaptureMappingVersionNonAutomatic,
    FYCaptureMappingVersionStaleAutomatic,
    FYCaptureMappingVersionCurrentAutomatic,
};
FOUNDATION_EXPORT FYCaptureMappingVersionStatus FYCaptureMappingVersion(NSDictionary *entry, NSInteger currentVersion);
FOUNDATION_EXPORT NSMutableDictionary *FYFilterCaptureMappings(NSDictionary *savedRects, NSInteger currentVersion);

@interface FYCaptureMappingCache : NSObject
// Retain the caller's mutable container, not a copied snapshot.
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *entries;
- (NSDictionary *)entryForWindowID:(uint32_t)windowID;
- (void)storeEntry:(NSDictionary *)entry forWindowID:(uint32_t)windowID;
- (void)removeWindowID:(uint32_t)windowID;
@end

@interface FYAutoLocateSchedule : NSObject
@property(nonatomic, strong) NSDate *lastAttemptDate;
- (BOOL)isThrottled;
@end

@interface FYMappingValidationSchedule : NSObject
@property(nonatomic, strong) NSDate *lastValidationDate;
- (BOOL)beginValidationAt:(NSDate *)now;
@end

// Estimate only, not evidence of a calibrated mapping; output unchanged on failure.
FOUNDATION_EXPORT BOOL FYEstimatedCaptureDisplayRect(CGSize frameSize, NSRect windowFrame, NSRect *outRect);

// Consumes both caller-owned images; successful non-NULL grid outputs are caller-owned.
FOUNDATION_EXPORT BOOL FYBuildCaptureGrids(CGImageRef frameImage, CGImageRef windowImage, CGSize frameSize,
    NSRect (^windowFrame)(void), size_t sceneWidth, double **outTempl, size_t *outTW, size_t *outTH,
    double **outScene, size_t *outWW, size_t *outWH, CGFloat *outAspect, NSString **outReason);

// Source is borrowed; returned crop is caller-owned, including full-image crops.
FOUNDATION_EXPORT CGImageRef FYCopyCapturedRegion(CGImageRef image, CGRect topLeftRegion) CF_RETURNS_RETAINED;

// Grid dimensions must be positive; grid rect uses top-row origin, no extra clipping.
// Requires grid width >= 8 and height >= 6; preserves rounding and minimum sample size.
FOUNDATION_EXPORT NSRect FYCaptureGridRectFromWindow(NSRect fitRect, NSRect windowFrame, size_t width, size_t height);
FOUNDATION_EXPORT NSRect FYWindowRectFromCaptureGrid(NSRect gridRect, size_t width, size_t height, NSRect windowFrame);

// Stateless coordinate conversions; display height and viewport are explicit inputs.
FOUNDATION_EXPORT BOOL FYGeometryDeliveryIsStale(NSInteger generation, NSInteger currentGeneration,
    uint32_t targetID, uint32_t currentTargetID);
// Borrows image; returns a newly malloc-allocated gridW*gridH double buffer, or NULL on failure.
// Caller owns the returned buffer: free() exactly once, or transfer to FYConsumeCaptureMappingGrids.
// CF_RETURNS_RETAINED expresses an owned return only; this is NOT a CF object: never CFRelease().
FOUNDATION_EXPORT double *FYGrayGridFromImage(CGImageRef image, size_t gridW, size_t gridH) CF_RETURNS_RETAINED;
FOUNDATION_EXPORT void FYNormalizeSignature(double *values, size_t count);
FOUNDATION_EXPORT double FYSignatureCorrelation(const double *scene, size_t sw, size_t sh, NSInteger x, NSInteger y,
    size_t cw, size_t ch, const double *templ, size_t tw, size_t th);
// Grid inputs must be valid/nonempty, template normalized. Rect uses top-row origin.
FOUNDATION_EXPORT double FYSearchCaptureGrid(const double *scene, size_t width, size_t height,
    const double *templ, size_t templateWidth, size_t templateHeight, CGFloat videoAspect, NSRect *outRect);
FOUNDATION_EXPORT BOOL FYShouldPreferCaptureFit(double fitScore, double searchScore, BOOL clearlySmaller);
FOUNDATION_EXPORT BOOL FYShouldKeepCachedCaptureMapping(double existingScore, double bestScore);
// Consumes both malloc-owned grids, including on unavailable score; do not alias buffers.
FOUNDATION_EXPORT double FYConsumeCaptureMappingGrids(NSDictionary *entry, double *scene, size_t width, size_t height,
    double *templ, size_t templateWidth, size_t templateHeight);
FOUNDATION_EXPORT double FYCaptureMappingScoreInGrids(NSDictionary *entry, const double *scene, size_t width, size_t height,
    const double *templ, size_t templateWidth, size_t templateHeight);
@interface FYGeometryManager : NSObject
+ (NSDictionary *)captureMappingForRect:(NSRect)rect windowFrame:(NSRect)frame videoAspect:(CGFloat)aspect
                                deviceID:(NSString *)deviceID source:(NSString *)source
                              confidence:(CGFloat)confidence version:(NSInteger)version;
// Unrounded reconstruction; coordinator retains size validation and integral rounding.
+ (NSRect)captureMappingRect:(NSDictionary *)entry windowFrame:(NSRect)frame;
// Capture mapping policy only; nil reason means valid. No device/frame acquisition.
+ (NSString *)captureMappingWindowReason:(NSDictionary *)entry windowFrame:(NSRect)frame;
+ (NSString *)captureMappingInputReason:(NSDictionary *)entry frameSize:(CGSize)size
                         hasFrameSize:(BOOL)hasSize deviceID:(NSString *)deviceID;
+ (BOOL)captureMappingScoreIsStale:(double)score unavailableValue:(double)unavailable;
// Top-left normalized capture region, floor/minimum-one/intersection semantics.
+ (CGRect)pixelCropForTopLeftRegion:(CGRect)region imageWidth:(size_t)width imageHeight:(size_t)height;
+ (NSRect)appKitFrameForQuartzBounds:(CGRect)bounds mainScreenTop:(CGFloat)top;
+ (NSRect)frameForNormalizedBox:(CGRect)box inViewport:(NSRect)viewport;
+ (NSRect)frameForTopLeftNormalizedBox:(CGRect)box inViewport:(NSRect)viewport;
+ (CGRect)quartzRectFromSelection:(CGRect)selection panelFrame:(NSRect)panelFrame mainScreenTop:(CGFloat)top;
@end
