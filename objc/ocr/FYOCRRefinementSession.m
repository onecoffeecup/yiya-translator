#import "FYOCRRefinementSession.h"

@implementation FYOCRRefinementIdentity
- (instancetype)initWithGeneration:(NSInteger)generation windowID:(uint32_t)windowID
    captureCard:(BOOL)captureCard inputEpoch:(NSUInteger)epoch language:(NSInteger)language
    scopeSignature:(NSString *)scope width:(NSUInteger)width height:(NSUInteger)height {
    if ((self = [super init])) {
        _generation = generation; _windowID = windowID; _captureCard = captureCard;
        _inputEpoch = epoch; _language = language; _scopeSignature = [scope copy];
        _width = width; _height = height;
        _legacyRepresentation = @{@"generation": @(generation), @"window": @(windowID),
            @"source": @(captureCard), @"epoch": @(epoch), @"language": @(language),
            @"scope": _scopeSignature, @"width": @(width), @"height": @(height)};
    }
    return self;
}
@end

@implementation FYOCRRefinementSession
- (FYOCRRefinementStabilizer *)stateForIdentity:(FYOCRRefinementIdentity *)identity {
    if (![self.legacyContext isEqual:identity.legacyRepresentation]) {
        self.legacyContext = identity.legacyRepresentation;
        self.stabilizer = [FYOCRRefinementStabilizer new];
    }
    return self.stabilizer;
}
@end
