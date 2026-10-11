#import <Foundation/Foundation.h>

// Service catalog and form drafts, independent of AppKit, OCR and credentials.
FOUNDATION_EXPORT NSArray<NSDictionary *> *FYTranslationServicePresets(void);
FOUNDATION_EXPORT NSDictionary *FYTranslationServicePreset(NSString *identifier);
FOUNDATION_EXPORT NSString *FYTranslationModelFromSettings(NSDictionary *settings);

@interface FYTranslationServiceSettings : NSObject
@property(nonatomic, copy, readonly) NSString *mode;
@property(nonatomic, copy, readonly) NSString *provider;
@property(nonatomic, copy) NSString *baseURL;
@property(nonatomic, copy) NSString *model;
- (void)loadSettings:(NSDictionary *)settings;
- (NSDictionary *)settingsDictionary;
- (void)selectProvider:(NSString *)identifier;
- (void)switchToMode:(NSString *)mode seedFromPreset:(BOOL)seed;
@end
