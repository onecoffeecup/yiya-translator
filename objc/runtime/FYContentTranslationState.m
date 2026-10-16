#import "FYContentTranslationState.h"
#import "FYRuntimeDeliveryChecks.h"

@interface FYContentTranslationSnapshot ()
- (instancetype)initWithState:(FYContentTranslationState *)state;
@end
@implementation FYContentTranslationSnapshot
- (instancetype)initWithState:(FYContentTranslationState *)state {
    if ((self = [super init])) {
        _revision = state.revision; _operations = state.operations;
        _text = [state.text copy]; _mode = state.mode; _items = [state.items copy];
        _geometryGeneration = state.geometryGeneration; _displayTarget = state.displayTarget;
    }
    return self;
}
@end

@implementation FYContentTranslationState
- (FYContentTranslationSnapshot *)snapshot { return [[FYContentTranslationSnapshot alloc] initWithState:self]; }
- (void)invalidate { [self advanceRevision]; [self clearPending]; }
- (void)advanceRevision { self.revision += 1; }
- (void)clearPending {
    self.operations = 0;
    self.text = nil;
    self.items = nil;
}
- (NSUInteger)beginText:(NSString *)text mode:(NSInteger)mode {
    [self replacePendingText:text];
    self.mode = mode;
    return self.revision;
}
- (NSUInteger)replacePendingText:(NSString *)text {
    self.operations = 1;
    self.text = text;
    return self.revision;
}
- (void)updateGeometryGeneration:(NSInteger)geometry displayTarget:(uint32_t)target {
    self.geometryGeneration = geometry;
    self.displayTarget = target;
}
- (void)addOperation { self.operations += 1; }
- (void)finishRevision:(NSUInteger)revision {
    if (FYContentRevisionIsCurrent(revision, self.revision) && self.operations) {
        self.operations -= 1;
    }
}
- (BOOL)matchesText:(NSString *)text mode:(NSInteger)mode equivalent:(BOOL (^)(NSString *, NSString *))equivalent {
    if (!self.operations || mode != self.mode) { return NO; }
    return mode == FYContentModeUI ? [text isEqualToString:self.text] : equivalent(text, self.text);
}
- (BOOL)matchesItems:(NSArray<OCRTextItem *> *)items key:(NSString *(^)(OCRTextItem *))key {
    if (items.count != self.items.count) { return NO; }
    for (NSUInteger index = 0; index < items.count; index++) {
        if (![key(items[index]) isEqualToString:key(self.items[index])]) { return NO; }
    }
    return YES;
}
@end
