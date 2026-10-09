#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#import "FYLocalFont.h"
#import "FYInlineLayout.h"
#import "learning/FYAdventureTheme.h"

static NSUInteger failures, missingLookups;
static NSString * const missingFontName = @"FY-Regression-Font-That-Is-Not-Installed";
static IMP originalLookup;
static NSFont *ObserveLookup(id receiver, SEL selector, NSString *name, CGFloat size) {
    if ([name isEqualToString:missingFontName]) {
        missingLookups++;
        // Do not ask the OS to look up an absent font during an isolated test.
        return nil;
    }
    return ((NSFont *(*)(id, SEL, NSString *, CGFloat))originalLookup)(receiver, selector, name, size);
}
static void Check(BOOL ok, NSString *message) {
    if (!ok) { failures++; NSLog(@"FAIL %@", message); }
}
int main(void) { @autoreleasepool {
    NSArray *available = CFBridgingRelease(CTFontManagerCopyAvailablePostScriptNames());
    Check(![available containsObject:missingFontName], @"missing-font fixture is absent locally");
    Method lookup = class_getClassMethod(NSFont.class, @selector(fontWithName:size:));
    originalLookup = method_setImplementation(lookup, (IMP)ObserveLookup);
    Check(FYLocalFontNamed(missingFontName, 19) == nil, @"absent local font returns nil for system fallback");
    Check(missingLookups == 0, @"absent font never reaches NSFont name matching or download");
    method_setImplementation(lookup, originalLookup);

    NSString *installed = [available containsObject:@"Helvetica"] ? @"Helvetica" : available.firstObject;
    NSFont *font = FYLocalFontNamed(installed, 19);
    Check([font.fontName isEqualToString:installed] && font.pointSize == 19,
          @"an available font keeps its face and requested size");
    for (NSNumber *value in @[@(NSFontWeightRegular), @(NSFontWeightSemibold)]) {
        NSFontWeight weight = value.doubleValue;
        NSString *preferred = weight >= NSFontWeightSemibold ? @"STYuanti-SC-Bold" : @"STYuanti-SC-Regular";
        NSFont *expected = [available containsObject:preferred] ? FYLocalFontNamed(preferred, 19) :
            [NSFont systemFontOfSize:19 weight:weight];
        Check([FYUIFont(19, weight).fontName isEqualToString:expected.fontName],
              @"the actual theme preserves installed round faces and falls back when unavailable");
    }
    FYInlineLayoutEngine *engine = [FYInlineLayoutEngine defaultEngine];
    Check([engine.longBodyFont.fontName isEqualToString:FYUIFont(engine.longBodyFontSize, NSFontWeightRegular).fontName],
          @"inline measurement and the UI theme choose the same locally available body font");
    NSFont *japanese = FYJapaneseFont(19);
    Check(japanese != nil && japanese.pointSize == 19, @"the Japanese font chain completes without downloading");
    NSLog(@"LocalFontTests: %lu failures", (unsigned long)failures);
    return failures ? 1 : 0;
} }
