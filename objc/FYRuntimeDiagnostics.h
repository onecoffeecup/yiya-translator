#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Bounded, metadata-only flight recorder. No disk writes until the user exports.
@interface FYRuntimeDiagnostics : NSObject
+ (instancetype)shared;
- (instancetype)initWithClock:(NSTimeInterval (^)(void))clock capacity:(NSUInteger)capacity;
- (void)recordEvent:(NSString *)event fields:(NSDictionary *)fields;
- (NSArray<NSDictionary *> *)recentEvents;
+ (NSDictionary *)sanitizeSnapshot:(NSDictionary *)snapshot;
+ (NSArray<NSDictionary *> *)findingsForSnapshot:(NSDictionary *)snapshot events:(NSArray<NSDictionary *> *)events;
- (NSDictionary *)reportForSnapshot:(NSDictionary *)snapshot;
+ (BOOL)writeReport:(NSDictionary *)report toURL:(NSURL *)url error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
