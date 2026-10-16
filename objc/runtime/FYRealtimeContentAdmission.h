#pragma once
#import "FYRealtimeContentAdmissionHost.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

// Stateless stage. Existing owners retain every mutable state field.
@interface FYRealtimeContentAdmission : NSObject
- (BOOL)admitContent:(FYPreparedRealtimeContent *)prepared rawText:(NSString *)ocrText items:(NSArray<OCRTextItem *> *)ocrBlocks duration:(NSTimeInterval)ocrDuration trace:(NSDictionary *)trace layoutDebug:(NSDictionary *)layoutDebug host:(id<FYRealtimeContentAdmissionHost>)runtimeHost;
@end
#pragma clang diagnostic pop
