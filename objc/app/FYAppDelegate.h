#pragma once
#import <Cocoa/Cocoa.h>

// Application lifecycle. Internal state remains private during staged extraction.
@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate, NSSharingServiceDelegate>
@end
