#import "presentation/FYInlineSelectionCoordinator.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface SelectionProbe : NSObject <FYInlineSnapshotInputSource,FYInlineSelectionStateSource>
@property(nonatomic,strong) FYInlineSelectionCoordinator *policy;
@property(nonatomic,strong) FYInlineBlockSnapshot *inlineBlockSnapshot;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSString *> *inlineStableBlockIDs;
@property(nonatomic,strong) NSMutableArray<NSString *> *events;
@property(nonatomic) BOOL enabled,hostResult;
@property(nonatomic) NSUInteger epoch;
@property(nonatomic,copy) NSString *rawOverride,*hostStable;
@property(nonatomic,copy) void (^duringRaw)(void);
@end
@implementation SelectionProbe
- (instancetype)init{if((self=[super init])){_policy=[FYInlineSelectionCoordinator new];_events=[NSMutableArray new];_inlineStableBlockIDs=[NSMutableDictionary new];}return self;}
- (BOOL)captureCardInputEnabled{[self.events addObject:@"source"];return self.enabled;}
- (NSUInteger)inlineSnapshotInputEpoch{[self.events addObject:@"epoch"];return self.epoch;}
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item{[self.events addObject:@"raw"];if(self.duringRaw)self.duringRaw();return self.rawOverride?:[self.policy inlineBlockIdentityForItem:item];}
- (FYInlineBlockSnapshot *)inlineBlockSnapshot{[self.events addObject:@"current"];return _inlineBlockSnapshot;}
- (NSMutableDictionary *)inlineStableBlockIDs{[self.events addObject:@"map"];return _inlineStableBlockIDs;}
- (BOOL)inlineHostBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item{[self.events addObject:@"host"];self.hostStable=stableBlockID;return self.hostResult;}
@end
int main(void){@autoreleasepool{
    FYInlineSelectionCoordinator *policy=[FYInlineSelectionCoordinator new];unsigned int n=0;Ivar *ivars=class_copyIvarList(FYInlineSelectionCoordinator.class,&n);free(ivars);Check(n==0,@"selection policy owns no source/current snapshot/cache state");
    FYInlineBlockSnapshot *model=[FYInlineBlockSnapshot new];Check(!model.blockID&&!model.sourceText&&!model.translation&&!model.lineBoxes&&!model.sentenceID&&!model.inputSource&&!model.inputEpoch&&!model.version,@"canonical snapshot retains original nil/zero cold model");
    NSMutableString *text=[@"original"mutableCopy],*identity=[@"identity"mutableCopy],*sentence=[@"sentence"mutableCopy];NSMutableArray<NSValue *> *boxes=[NSMutableArray arrayWithObject:@(CGRectMake(.1,.2,.3,.4))];model.sourceText=text;model.translation=text;model.blockID=identity;model.sentenceID=sentence;model.lineBoxes=boxes;[text appendString:@" changed"];[identity appendString:@" changed"];[sentence appendString:@" changed"];[boxes addObject:@(CGRectZero)];
    Check([model.sourceText isEqual:@"original"]&&[model.translation isEqual:@"original"]&&[model.blockID isEqual:@"identity"]&&[model.sentenceID isEqual:@"sentence"]&&model.lineBoxes.count==1,@"original model copy fields freeze strings/outer boxes and keep no mutable-array alias");
    model.sentenceID=@"linked-db";model.version=42;Check([model.sentenceID isEqual:@"linked-db"]&&model.version==42,@"later database sentence/version binding remains writable");
    OCRTextItem *item=[OCRTextItem new];item.text=@" A　B \n";item.boundingBox=CGRectMake(.1234,.4564,.2,.03);item.lineBoxes=@[];
    Check([[policy inlineBlockIdentityForItem:item]isEqual:@"AB|0.123,0.456,0.200,0.030"],@"raw identity preserves normalized characters and exact three-decimal bbox fallback");
    NSValue *first=@(CGRectMake(.2,.3,.4,.05)),*second=@(CGRectMake(.2,.2,.4,.05));item.lineBoxes=@[first,second];NSString *lineKey=[policy inlineBlockIdentityForItem:item];Check([lineKey isEqual:@"AB|0.200,0.300,0.400,0.050|0.200,0.200,0.400,0.050"],@"line boxes take precedence and retain original order");
    item.lineBoxes=@[second,first];Check(![[policy inlineBlockIdentityForItem:item]isEqual:lineKey],@"identity does not reorder supplied source lines");
    item.lineBoxes=@[];item.boundingBox=CGRectZero;Check([[policy inlineBlockIdentityForItem:item]isEqual:@"AB"],@"zero-width source with no line boxes retains text-only identity");
    item.boundingBox=CGRectMake(.1,.2,.3,0);Check([[policy inlineBlockIdentityForItem:item]containsString:@"|0.100,0.200,0.300,0.000"],@"width-positive fallback deliberately includes zero height");
    SelectionProbe *source=[SelectionProbe new];source.policy=policy;source.enabled=NO;source.epoch=77;source.rawOverride=@"concrete-raw";NSMutableString *currentText=[@"原文"mutableCopy];item.text=currentText;item.lineBoxes=@[first];NSMutableString *translation=[@"译文"mutableCopy];[source.events removeAllObjects];
    FYInlineBlockSnapshot *snapshot=[policy inlineSnapshotForItem:item translation:translation stableBlockID:nil source:source];
    Check([source.events isEqual:@[@"source",@"epoch",@"raw"]]&&snapshot.inputSource==0&&snapshot.inputEpoch==77&&[snapshot.blockID isEqual:@"concrete-raw"],@"snapshot reads source then epoch even when disabled,then concrete raw helper");
    [currentText appendString:@"变更"];item.text=currentText;[translation appendString:@"变更"];Check([snapshot.sourceText isEqual:@"原文"]&&[snapshot.translation isEqual:@"译文"]&&snapshot.lineBoxes.firstObject==first,@"captured text/translation copy but source line element identity remains original");
    source.enabled=YES;NSMutableString *stable=[@"stable"mutableCopy];[source.events removeAllObjects];FYInlineBlockSnapshot *stableSnapshot=[policy inlineSnapshotForItem:item translation:translation stableBlockID:stable source:source];[stable appendString:@" changed"];Check([source.events isEqual:@[@"source",@"epoch"]]&&stableSnapshot.inputSource==1&&[stableSnapshot.blockID isEqual:@"stable"],@"stable override is copied and prevents raw helper access without skipping source/epoch");
    item.text=nil;item.lineBoxes=nil;item.boundingBox=CGRectZero;FYInlineBlockSnapshot *empty=[policy inlineSnapshotForItem:item translation:nil stableBlockID:@"" source:source];Check([empty.sourceText isEqual:@""]&&[empty.translation isEqual:@""]&&empty.lineBoxes.count==0&&[empty.blockID isEqual:@"concrete-raw"],@"nil source/translation and empty stable override preserve original fallbacks");
    FYInlineTextBlock *block=[FYInlineTextBlock new];block.text=@"标题";block.lineBoxes=@[first,second];[source.events removeAllObjects];FYInlineBlockSnapshot *blockSnapshot=[policy inlineSnapshotForBlock:block translation:@"译文" stableBlockID:nil source:source];Check([blockSnapshot.blockID isEqual:[FYInlineBlockMatcher blockIDForText:block.text lineBoxes:block.lineBoxes]]&&[source.events isEqual:@[@"source",@"epoch"]],@"block snapshot uses canonical matcher instead of native item identity helper");
    block.lineBoxes=nil;FYInlineBlockSnapshot *emptyBlock=[policy inlineSnapshotForBlock:block translation:nil stableBlockID:@"override" source:source];Check(emptyBlock.lineBoxes.count==0&&[emptyBlock.blockID isEqual:@"override"]&&[emptyBlock.translation isEqual:@""],@"block path retains empty boxes and explicit stable identity");
    source.inlineBlockSnapshot=nil;[source.events removeAllObjects];Check(![policy inlineBlockID:@"stable" isSelectedForItem:item stateSource:source]&&[source.events isEqual:@[@"current"]],@"selection early-rejects missing current snapshot without raw work");
    source.inlineBlockSnapshot=[FYInlineBlockSnapshot new];[source.events removeAllObjects];Check(![policy inlineBlockID:@"stable" isSelectedForItem:item stateSource:source]&&[source.events isEqual:@[@"current"]],@"empty current identity short-circuits selection");
    source.inlineBlockSnapshot=stableSnapshot;[source.events removeAllObjects];Check([policy inlineBlockID:@"stable" isSelectedForItem:item stateSource:source]&&[source.events isEqual:@[@"current"]],@"stable identity match returns before raw fallback");
    source.inlineBlockSnapshot=snapshot;[source.events removeAllObjects];Check([policy inlineBlockID:@"different" isSelectedForItem:item stateSource:source]&&[source.events isEqual:@[@"current",@"raw"]],@"different stable identity can still match original raw fallback");
    source.rawOverride=@"mismatch";Check(![policy inlineBlockID:nil isSelectedForItem:item stateSource:source],@"empty stable/raw mismatch remains unselected");
    source.rawOverride=@"concrete-raw";__weak SelectionProbe *weak=source;source.duringRaw=^{weak.inlineBlockSnapshot=stableSnapshot;};source.inlineBlockSnapshot=snapshot;Check([policy inlineBlockID:@"different" isSelectedForItem:item stateSource:source],@"selection keeps original strong current snapshot throughout raw helper reentry");source.duringRaw=nil;
    source.inlineStableBlockIDs=[NSMutableDictionary dictionaryWithObject:@"mapped-stable" forKey:@"concrete-raw"];source.inlineBlockSnapshot=nil;source.hostResult=YES;[source.events removeAllObjects];Check([policy inlineBlockIsSelectedForItem:item stateSource:source]&&[source.hostStable isEqual:@"mapped-stable"]&&[source.events isEqual:@[@"raw",@"map",@"host"]],@"mapped selection delegates actual host hook and does not substitute local current comparison");
    [source.inlineStableBlockIDs removeAllObjects];source.hostResult=NO;[source.events removeAllObjects];Check(![policy inlineBlockIsSelectedForItem:item stateSource:source]&&!source.hostStable&&[source.events isEqual:@[@"raw",@"map",@"host"]],@"missing stable map still routes nil to original host selection helper");
    __weak SelectionProbe *weakSource;@autoreleasepool{SelectionProbe *temporary=[SelectionProbe new];weakSource=temporary;[policy inlineSnapshotForItem:item translation:@"synthetic" stableBlockID:@"stable" source:temporary];}Check(!weakSource,@"snapshot/selection policy retains no idle source/context after completion");
    printf("PASS InlineSelectionTests: %lu checks;canonical pure model/identity/snapshot/selection,copy/getter order/host override/lifetime\n",(unsigned long)checks);
}return 0;}
