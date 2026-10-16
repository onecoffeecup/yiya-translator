#pragma once
#import <Cocoa/Cocoa.h>

// Receives metadata snapshots and owns report/export/mail presentation state.
// The host supplies permission/window/camera facts, never images or content.
@interface FYDiagnosticsController : NSObject <NSSharingServiceDelegate>
@property(nonatomic, strong) NSTextField *resultLabel;
@property(nonatomic, strong) NSDate *lastCheckDate;
@property(nonatomic) BOOL exporting;
@property(nonatomic, strong) NSSharingService *mailService;
@property(nonatomic, copy) void (^statusHandler)(NSString *);
+ (NSDictionary *)snapshotForWindowInfos:(NSArray<NSDictionary *> *)infos
                                context:(NSDictionary *)context quickTimeRunning:(BOOL)quickTimeRunning;
- (NSArray<NSDictionary *> *)updateWithSnapshot:(NSDictionary *)snapshot;
- (void)showMailFallback;
- (void)composeEmailForURL:(NSURL *)url service:(NSSharingService *)service;
- (void)saveSnapshot:(NSDictionary *)snapshot forWindow:(NSWindow *)window email:(BOOL)email
            compose:(void (^)(NSURL *))compose;
@end
