#import "FYCaptureMapping.h"
@implementation FYCaptureMappingCache
- (NSDictionary *)entryForWindowID:(uint32_t)windowID { return self.entries[[NSString stringWithFormat:@"%u",windowID]]; }
- (void)storeEntry:(NSDictionary *)entry forWindowID:(uint32_t)windowID {
    if (!self.entries) self.entries=[NSMutableDictionary dictionary];
    self.entries[[NSString stringWithFormat:@"%u",windowID]]=entry;
}
- (void)removeWindowID:(uint32_t)windowID { [self.entries removeObjectForKey:[NSString stringWithFormat:@"%u",windowID]]; }
@end

FYCaptureMappingVersionStatus FYCaptureMappingVersion(NSDictionary *entry, NSInteger currentVersion) {
    if (![entry[@"source"] isEqualToString:@"auto"]) return FYCaptureMappingVersionNonAutomatic;
    return [entry[@"mappingVersion"] integerValue]<currentVersion ? FYCaptureMappingVersionStaleAutomatic : FYCaptureMappingVersionCurrentAutomatic;
}

NSMutableDictionary *FYFilterCaptureMappings(NSDictionary *savedRects, NSInteger currentVersion) {
    NSMutableDictionary *kept=[NSMutableDictionary dictionary];
    for (id key in savedRects) {
        id entry=savedRects[key];
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        if (FYCaptureMappingVersion(entry,currentVersion)==FYCaptureMappingVersionStaleAutomatic) continue;
        kept[key]=entry;
    }
    return kept;
}

@implementation FYAutoLocateSchedule
- (BOOL)isThrottled { return self.lastAttemptDate && -[self.lastAttemptDate timeIntervalSinceNow]<3.0; }
@end

@implementation FYMappingValidationSchedule
- (BOOL)beginValidationAt:(NSDate *)now {
    BOOL due=!self.lastValidationDate || [now timeIntervalSinceDate:self.lastValidationDate]>=2.0;
    if (!due) return NO;
    self.lastValidationDate=now;
    return YES;
}
@end
