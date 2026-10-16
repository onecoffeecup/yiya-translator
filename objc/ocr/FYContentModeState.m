#import "FYContentModeState.h"

@implementation FYContentModeStability
- (NSInteger)observeMode:(NSInteger)detected {
    if (detected==self.detectedMode) { self.candidateMode=detected;self.candidateHits=0;return self.detectedMode; }
    if (self.candidateMode==detected) self.candidateHits+=1;
    else { self.candidateMode=detected;self.candidateHits=1; }
    if (self.candidateHits>=2) { self.detectedMode=detected;self.candidateHits=0; }
    return self.detectedMode;
}
@end


@implementation FYContentModeDecision
- (instancetype)initWithMode:(NSInteger)mode reason:(NSString *)reason {
    if ((self = [super init])) { _mode = mode; _reason = [reason copy]; }
    return self;
}
@end
@implementation FYContentModeCoordinator
- (instancetype)init { if ((self = [super init])) _stability = [FYContentModeStability new]; return self; }
- (NSInteger)observeLocked:(BOOL)locked classifier:(FYContentModeDecision *(^)(NSInteger fallback))classifier {
    if (locked) {
        self.lastDecision = [[FYContentModeDecision alloc] initWithMode:self.stability.detectedMode reason:@"mode_locked"];
        return self.stability.detectedMode;
    }
    self.lastDecision = classifier(self.stability.detectedMode);
    return [self.stability observeMode:self.lastDecision.mode];
}
@end
