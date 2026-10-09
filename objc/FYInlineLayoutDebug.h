#pragma once
#import <Cocoa/Cocoa.h>
#import "FYInlineLayout.h"
@class OCRTextItem;
FOUNDATION_EXPORT NSDictionary *FYCurrentLayoutDebug(void);
FOUNDATION_EXPORT void FYLayoutDebugPerform(NSDictionary *context, void (^work)(void));
// The actual crop used by OCR, composed with any outer crop. No guessed scope.
FOUNDATION_EXPORT void FYLayoutDebugPerformCrop(CGRect crop, CGSize imageSize, void (^work)(void));
FOUNDATION_EXPORT NSArray *FYLayoutDebugRect(CGRect rect);
FOUNDATION_EXPORT NSDictionary *FYLayoutDebugSnapshot(FYInlineLayoutResult *result,
    FYInlineLayoutResult *previous, CGRect viewport, NSDictionary *rendered, NSString *reason);

// No screenshots, user defaults, credentials, network or window acquisition here.
// Only an explicitly armed private control file permits saving the image supplied by capture.
@interface FYInlineLayoutDebug : NSObject
+ (instancetype)shared;
+ (NSString *)defaultDirectory;
- (instancetype)initWithDirectory:(NSString *)directory;
- (BOOL)isActive;
- (NSDictionary *)beginFrameWithImage:(CGImageRef)image metadata:(NSDictionary *)metadata;
- (void)recordItems:(NSArray<OCRTextItem *> *)items stage:(NSString *)stage context:(NSDictionary *)context;
- (void)recordLayout:(NSDictionary *)snapshot context:(NSDictionary *)context;
- (void)recordLayout:(NSDictionary *)snapshot context:(NSDictionary *)context renderedImages:(NSDictionary<NSString *, NSData *> *)images;
- (void)recordDecision:(NSString *)reason context:(NSDictionary *)context;
- (void)showSnapshot:(NSDictionary *)snapshot viewport:(CGRect)viewport;
- (void)refreshVisible:(BOOL)visible level:(NSInteger)level;
- (void)clearOverlay;
@end
