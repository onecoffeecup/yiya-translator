#pragma once
#import "FYRealtimeRecognitionHost.h"
#import "../ocr/FYOCRRefinementSession.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
@protocol FYRealtimeRecognitionRuntime <NSObject>
- (FYRecognitionCycleScheduler *)recognitionScheduler;
- (FYOCRRefinementSession *)refinementSession;
- (FYOCRRecognitionWorker *)ocrWorker;
- (FYRecognitionCycleLease *)recognitionLeaseForHost:(id)host;
- (FYOCRRecognitionOperationLease *)ocrOperationsForHost:(id)host layoutDebug:(NSDictionary *)layoutDebug;
- (FYOCRWorkerObserver)ocrObserverForTrace:(NSDictionary *)trace layoutDebug:(NSDictionary *)layoutDebug
    windowID:(uint32_t)windowID generation:(NSInteger)generation frameIndex:(uint64_t)frameIndex language:(NSInteger)language fastOCR:(BOOL)fastOCR;
- (void)processRecognizedRealtimeText:(NSString *)text items:(NSArray<OCRTextItem *> *)items modalItems:(NSArray<OCRTextItem *> *)modalItems
    duration:(NSTimeInterval)duration frame:(FYRealtimeRecognitionFrame *)frame trace:(NSDictionary *)trace layoutDebug:(NSDictionary *)layoutDebug host:(id)host;
@end

// Stateless stage. Existing owners retain every mutable state field.
@interface FYRealtimeRecognitionWorkflow : NSObject
- (void)tick:(NSTimer *)timer runtime:(id<FYRealtimeRecognitionRuntime>)runtime host:(id<FYRealtimeRecognitionHost>)runtimeHost;
@end
#pragma clang diagnostic pop
