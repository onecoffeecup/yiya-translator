#pragma once
#import <Foundation/Foundation.h>
#import "../FYTranslationManager.h"

typedef void (^FYServiceTestTransport)(NSString *, void (^)(NSString *, NSError *));
typedef void (^FYServiceTestPresentationHandler)(NSString *, NSString *, NSString *);

// Service tests have their own task/epoch, independent of live translation.
@interface FYServiceTestController : NSObject
@property(nonatomic) NSInteger generation;
@property(nonatomic, strong) FYTranslationTaskOwner *taskOwner;
@property(nonatomic) BOOL pending;
- (void)invalidateWhileRunning:(BOOL)running status:(void (^)(NSString *))status;
- (void)testSample:(NSString *)sample transport:(FYServiceTestTransport)transport
         isRunning:(BOOL (^)(void))isRunning status:(void (^)(NSString *))status
           present:(FYServiceTestPresentationHandler)present
          sanitize:(NSString *(^)(NSString *, NSString *))sanitize;
@end
