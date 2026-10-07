#pragma once
#define FY_TEST_DISABLE_LEGACY_DIAGNOSTICS 1
#define FY_TEST_ISOLATED_CREDENTIAL_STORE 1
// Force-included in TEST builds only. Production scripts never include this file.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <sqlite3.h>

@interface FYTestDefaults : NSObject
+ (instancetype)standardUserDefaults;
- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
@end

@interface FYTestURLSession : NSObject
+ (instancetype)sharedSession;
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                          completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
@end

FOUNDATION_EXPORT NSString *FYTestTemporaryDirectory(void);
FOUNDATION_EXPORT NSUInteger FYTestCaptureCount(void);
// 让测试提供"目标窗口截图"的内容（传 NULL 恢复默认空白图）。仍会照常计数。
FOUNDATION_EXPORT void FYTestSetWindowImage(CGImageRef image);
FOUNDATION_EXPORT CGImageRef FYTestWindowImage(CGRect rect, CGWindowListOption options,
                                              CGWindowID window, CGWindowImageOption imageOptions);
FOUNDATION_EXPORT int FYTestSQLiteOpen(const char *path, sqlite3 **db);
FOUNDATION_EXPORT int FYTestSQLiteOpenV2(const char *path, sqlite3 **db, int flags, const char *vfs);

#define NSUserDefaults FYTestDefaults
#define NSURLSession FYTestURLSession
#define NSTemporaryDirectory FYTestTemporaryDirectory
#define CGWindowListCreateImage FYTestWindowImage
#define sqlite3_open FYTestSQLiteOpen
#define sqlite3_open_v2 FYTestSQLiteOpenV2
