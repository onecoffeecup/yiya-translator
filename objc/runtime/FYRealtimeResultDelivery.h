#pragma once
#import "FYRealtimeResultHost.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
@protocol FYRealtimeResultRuntime <FYInlinePlacementDeliverySource>
- (FYContentTranslationState *)contentState;
@end

// Stateless delivery; tickets read the original runtime lazily.
@interface FYRealtimeResultDelivery : NSObject
- (void)deliverInline:(NSArray<NSString *> *)translations error:(NSError *)translationError items:(NSArray<OCRTextItem *> *)uiItemsForRender identities:(NSArray<FYRequestIdentity *> *)uiIdentities normalized:(NSString *)normalized started:(NSDate *)uiTranslateStart revision:(NSUInteger)contentRevision serial:(NSUInteger)inlineSerial ticket:(FYRealtimeDeliveryTicket *)deliveryTicket captureCard:(BOOL)captureCard inputEpoch:(NSUInteger)inputEpoch trace:(NSDictionary *)uiTrace layoutDebug:(NSDictionary *)layoutDebug runtime:(id<FYRealtimeResultRuntime>)runtime host:(id<FYRealtimeResultHost>)runtimeHost;
- (void)deliverOptions:(NSArray<NSString *> *)translations error:(NSError *)translationError items:(NSArray<OCRTextItem *> *)optionsToRender identities:(NSArray<FYRequestIdentity *> *)optionIdentities revision:(NSUInteger)contentRevision ticket:(FYRealtimeDeliveryTicket *)deliveryTicket inputEpoch:(NSUInteger)inputEpoch trace:(NSDictionary *)optionTrace layoutDebug:(NSDictionary *)layoutDebug runtime:(id<FYRealtimeResultRuntime>)runtime host:(id<FYRealtimeResultHost>)runtimeHost;
- (void)deliverDialogue:(NSString *)translated error:(NSError *)translationError text:(NSString *)dialogueText identity:(FYRequestIdentity *)dialogueIdentity normalized:(NSString *)normalized started:(NSDate *)translationStart duration:(NSTimeInterval)ocrDuration revision:(NSUInteger)contentRevision ticket:(FYRealtimeDeliveryTicket *)deliveryTicket generation:(NSInteger)cycleGeneration windowID:(uint32_t)windowID inputEpoch:(NSUInteger)inputEpoch cycleStart:(NSDate *)cycleStart trace:(NSDictionary *)dialogueTrace runtime:(id<FYRealtimeResultRuntime>)runtime host:(id<FYRealtimeResultHost>)runtimeHost;
- (void)handleInlineTranslationResult:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items error:(NSError *)translationError failureStatus:(NSString *)failureStatus successPrefix:(NSString *)successPrefix runtime:(id<FYRealtimeResultRuntime>)runtime host:(id<FYRealtimeResultHost>)runtimeHost;
@end
#pragma clang diagnostic pop
