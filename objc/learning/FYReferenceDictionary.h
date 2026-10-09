#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Read-only bundled reference data. User bookmarks and history remain in their own database.
@interface FYReferenceDictionary : NSObject
- (instancetype)initWithURL:(nullable NSURL *)url;
- (void)lookupWord:(NSString *)word reading:(nullable NSString *)reading
       completion:(void (^_Nullable)(NSArray<NSDictionary *> *records, NSError *_Nullable error))completion;
@end
NS_ASSUME_NONNULL_END
