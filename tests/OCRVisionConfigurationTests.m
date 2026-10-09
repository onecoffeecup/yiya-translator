#import "FYOCRManager.h"
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL %@", message); exit(1); } }
int main(void) { @autoreleasepool {
    NSUInteger __block observed = 0;
    FYOCRManager *manager = [FYOCRManager new];
    for (NSNumber *heightValue in @[@512, @1024]) {
        size_t height = heightValue.unsignedIntegerValue;
        CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, 640, height, 8, 0, colors, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(colors); Check(context != NULL, @"make synthetic blank OCR frame");
        CGImageRef image = CGBitmapContextCreateImage(context); CGContextRelease(context);
        for (NSNumber *fastValue in @[@NO, @YES]) {
            BOOL fast = fastValue.boolValue;
            manager.configurationObserver = ^(BOOL configuredFast, NSInteger language, size_t width, size_t imageHeight, CGFloat minimum) {
                observed++;
                Check(configuredFast == fast && language == 0 && width == 640 && imageHeight == height, @"Vision uses the submitted OCR options and dimensions");
                CGFloat expected = (fast ? 32.0 : 48.0) / height;
                Check(fabs(minimum - expected) < .000001, @"real Vision request preserves adaptive 32/48 pixel text threshold");
            };
            NSError *error = nil;
            [manager recognizeTextItemsInImage:image fastOCR:fast languageSegment:0 error:&error];
            Check(!error, @"synthetic Vision request executes without UI or capture");
        }
        CGImageRelease(image);
    }
    Check(observed == 4, @"configuration guard actually executes for both modes and image sizes");
    NSLog(@"PASS OCRVisionConfigurationTests: actual request settings, synthetic pixels, no UI/device/network");
} return 0; }
