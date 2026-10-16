#import "FYReferenceQueryCoordinator.h"

@implementation FYReferenceQueryCoordinator
- (void)lookupWord:(NSString *)word reading:(NSString *)reading receiver:(id<FYReferenceQuerySource>)receiver {
    if(![receiver hasReferenceStack]){return;}
    [receiver setReferenceSearchText:word];
    [receiver clearReferenceRows];
    [receiver showReferenceLoadingWord:word];
    NSInteger generation=++receiver.referenceRequestGeneration;
    receiver.referenceRecords=@[]; receiver.referenceActiveWord=word;
    if(!receiver.referenceDictionary){receiver.referenceDictionary=[receiver makeReferenceDictionary];}
    [receiver.referenceDictionary lookupWord:word reading:reading completion:^(NSArray<NSDictionary *> *records,NSError *error){
        if(generation!=receiver.referenceRequestGeneration){return;}
        receiver.referenceRecords=records;
        [receiver clearReferenceRows];
        if(error || !records.count){
            [receiver showReferenceEmptyWord:word error:error]; return;
        }
        [receiver renderReferenceRecords:records];
    }];
}

@end
