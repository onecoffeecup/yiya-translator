#pragma once
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *const SettingsKey;

@protocol FYSettingsPersistence <NSObject>
- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;
@end

// A frozen, credential-free copy of ordinary preferences.
@interface FYSettingsSnapshot : NSObject
@property(nonatomic, copy, readonly) NSDictionary *values;
- (instancetype)initWithValues:(NSDictionary *)values;
@end

// Ephemeral request configuration. The credential never enters preferences.
@interface FYTranslationConfiguration : NSObject
@property(nonatomic, copy, readonly) NSString *baseURL;
@property(nonatomic, copy, readonly) NSString *model;
@property(nonatomic, copy, readonly) NSString *learningModel;
@property(nonatomic, copy, readonly) NSString *apiKey;
- (instancetype)initWithBaseURL:(NSString *)baseURL model:(NSString *)model
                 learningModel:(NSString *)learningModel apiKey:(NSString *)apiKey;
@end

typedef NS_ENUM(NSInteger, FYSettingsSaveResult) {
    FYSettingsSaved, FYSettingsCredentialReadBlocked, FYSettingsCredentialWriteFailed
};

// Owns persistence, credential save status and the debounced save lifecycle.
// Controls/default values and runtime side effects remain in the host adapter.
@interface FYSettingsStore : NSObject
@property(nonatomic, copy) NSString *persistedAPIKey;
@property(nonatomic) BOOL credentialLoadFailed;
@property(nonatomic) BOOL loading;
@property(nonatomic, strong) NSTimer *saveTimer;
- (instancetype)initWithDefaults:(id<FYSettingsPersistence>)defaults;
- (FYSettingsSnapshot *)load;
- (FYSettingsSaveResult)saveSnapshot:(FYSettingsSnapshot *)snapshot apiKey:(NSString *)apiKey;
- (void)scheduleSave:(void (^)(void))save;
- (void)cancelScheduledSave;
@end
