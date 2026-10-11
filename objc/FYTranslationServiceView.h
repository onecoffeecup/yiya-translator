#import <Cocoa/Cocoa.h>
#import "FYTranslationServiceSettings.h"
#import "learning/FYAdventureTheme.h"

// Rendering also accepts isolated test controls; it never starts a request.
@interface FYTranslationServiceTestPresentation : NSObject
@property(nonatomic, strong) NSButton *button;
@property(nonatomic, strong) NSImageView *icon;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *modelLabel;
@property(nonatomic, strong) NSTextField *messageLabel;
@property(nonatomic, strong) NSTextField *errorLabel;
@property(nonatomic, strong) NSTextField *resultLabel;
@property(nonatomic, strong) FYAdventurePanel *panel;
- (void)presentState:(NSString *)state error:(NSString *)error result:(NSString *)result;
@end

// Owns the service form. Host callbacks connect persistence and runtime actions.
@interface FYTranslationServiceView : NSObject <NSTextFieldDelegate>
@property(nonatomic, strong, readonly) NSView *view;
@property(nonatomic, strong, readonly) FYTranslationServiceSettings *settings;
@property(nonatomic, strong, readonly) NSTextField *baseURLField;
@property(nonatomic, strong, readonly) NSTextField *modelField;
@property(nonatomic, strong, readonly) NSSecureTextField *apiKeyField;
@property(nonatomic, strong, readonly) NSTextField *learningModelField;
@property(nonatomic, strong, readonly) FYTranslationServiceTestPresentation *testPresentation;
@property(nonatomic, copy) void (^onSettingsChanged)(void);
@property(nonatomic, copy) void (^onTextChanged)(NSNotification *);
@property(nonatomic, copy) void (^onEditingEnded)(NSNotification *);
@property(nonatomic, copy) void (^onTest)(void);
@property(nonatomic, copy) void (^onPasteKey)(void);
@property(nonatomic, copy) void (^onClearKey)(void);
@property(nonatomic, copy) void (^onShowLicenses)(void);
- (instancetype)initWithLicenseView:(NSView *)licenseView;
- (void)loadSettings:(NSDictionary *)settings;
- (NSDictionary *)settingsDictionary;
- (void)applyPreset:(NSString *)identifier model:(NSString *)model;
@end
