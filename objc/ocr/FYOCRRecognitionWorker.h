#pragma once
#import "FYOCRImageGeometry.h"
#import "FYOCRRefinement.h"
@interface FYOCRRecognitionSettings : NSObject
- (instancetype)initWithManual:(BOOL)manual language:(NSInteger)language fastOCR:(BOOL)fast autoFit:(BOOL)autoFit scope:(CGRect)scope exclusions:(NSArray<NSValue *> *)exclusions;
@property(nonatomic, readonly) BOOL manual, fastOCR, autoFit;
@property(nonatomic, readonly) NSInteger language;
@property(nonatomic, readonly) CGRect scope;
@property(nonatomic, copy, readonly) NSArray<NSValue *> *exclusions;
@end
// Consumes the caller's +1 image; finish is explicit and repeat-safe.
@interface FYOCRRecognitionImageLease : NSObject
- (instancetype)initWithOwnedImage:(CGImageRef)image;
@property(nonatomic, readonly) CGImageRef image;
- (void)finishImage;
@end
// Only recognition actions for this cycle. No controls, settings lookup or host
// context; implementations may preserve original native receiver overrides.
@protocol FYOCRRecognitionOperations <NSObject>
- (NSString *)recognizeBlocks:(CGImageRef)image settings:(FYOCRRecognitionSettings *)settings blocks:(NSArray<OCRTextItem *> **)blocks error:(NSError **)error;
- (NSArray<OCRTextItem *> *)recognizeItems:(CGImageRef)image settings:(FYOCRRecognitionSettings *)settings error:(NSError **)error;
- (NSString *)recognizeEnlarged:(CGImageRef)image region:(CGRect)region settings:(FYOCRRecognitionSettings *)settings blocks:(NSArray<OCRTextItem *> **)blocks error:(NSError **)error;
- (NSString *)sourceTextForItems:(NSArray<OCRTextItem *> *)items blocks:(NSArray<OCRTextItem *> **)blocks;
- (NSArray<OCRTextItem *> *)markSpeakerItems:(NSArray<OCRTextItem *> *)items image:(CGImageRef)image;
- (NSArray<OCRTextItem *> *)modalItems:(NSArray<OCRTextItem *> *)items image:(CGImageRef)image exclusions:(NSArray<NSValue *> *)exclusions;
- (void)performManualPass1:(void (^)(void))work;
@end
// Bounded strong native action lease, retained by the queued cycle only.
@interface FYOCRRecognitionOperationLease : NSObject <FYOCRRecognitionOperations>
- (instancetype)initWithBlocks:(NSString *(^)(CGImageRef,FYOCRRecognitionSettings *,NSArray<OCRTextItem *> **,NSError **))blocks
 items:(NSArray<OCRTextItem *> *(^)(CGImageRef,FYOCRRecognitionSettings *,NSError **))items
 enlarged:(NSString *(^)(CGImageRef,CGRect,FYOCRRecognitionSettings *,NSArray<OCRTextItem *> **,NSError **))enlarged
 sourceText:(NSString *(^)(NSArray<OCRTextItem *> *,NSArray<OCRTextItem *> **))sourceText
 speakers:(NSArray<OCRTextItem *> *(^)(NSArray<OCRTextItem *> *,CGImageRef))speakers
 modal:(NSArray<OCRTextItem *> *(^)(NSArray<OCRTextItem *> *,CGImageRef,NSArray<NSValue *> *))modal
 manualPass1:(void (^)(void (^)(void)))manualPass1;
@end

typedef NS_ENUM(NSInteger,FYOCRWorkerStage) {
 FYOCRWorkerBegin, FYOCRWorkerDiagnosticImage, FYOCRWorkerRawCrop, FYOCRWorkerMappedPass1,
 FYOCRWorkerPass1Complete, FYOCRWorkerRefinementSelection, FYOCRWorkerRefinementPerformance,
 FYOCRWorkerModalPerformance, FYOCRWorkerMerged, FYOCRWorkerReleasedImage,
};
// Immutable OCR-only observation. Pixel callbacks happen while the lease is
// valid; ReleasedImage is emitted with NULL image, before any result delivery.
@interface FYOCRWorkerProgress : NSObject
@property(nonatomic, copy, readonly) NSArray<OCRTextItem *> *items, *modalItems;
@property(nonatomic, strong, readonly) NSError *error;
@property(nonatomic, readonly) NSTimeInterval elapsed, pass1, pass2;
@property(nonatomic, readonly) NSUInteger fallbackCount;
@end
typedef void (^FYOCRWorkerObserver)(FYOCRWorkerStage stage,FYOCRWorkerProgress *progress,CGImageRef image);
@interface FYOCRRecognitionResult : NSObject
@property(nonatomic, copy, readonly) NSString *text;
@property(nonatomic, copy, readonly) NSArray<OCRTextItem *> *items, *modalItems;
@property(nonatomic, strong, readonly) NSError *error;
@property(nonatomic, readonly) NSTimeInterval duration;
@end
// Synchronous background work. No state/host/lease is stored by this component;
// scheduling, cancellation, GUI and diagnostics persistence remain adapters.
@interface FYOCRRecognitionWorker : NSObject
- (FYOCRRecognitionResult *)recognizeImageLease:(FYOCRRecognitionImageLease *)imageLease
 settings:(FYOCRRecognitionSettings *)settings refinement:(FYOCRRefinementStabilizer *)refinement
 operations:(id<FYOCRRecognitionOperations>)operations cropScope:(FYOCRCropScopePerform)cropScope
 observer:(FYOCRWorkerObserver)observer;
@end
