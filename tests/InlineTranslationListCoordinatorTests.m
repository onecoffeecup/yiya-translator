#import "presentation/FYInlineTranslationListCoordinator.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok, NSString *message) { checks++; if (!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(2); } }
static FYInlinePlacement *Placement(NSString *identifier, NSString *text, FYInlineDisplayMode mode) {
    FYInlinePlacement *p=[FYInlinePlacement new];p.block=[FYInlineTextBlock new];p.block.blockID=identifier;p.block.text=[@"source-" stringByAppendingString:identifier];p.blockID=identifier;p.translation=text;p.mode=mode;return p;
}
@interface ListSourceFact : NSObject <FYInlineTranslationListSource>
@property(nonatomic,strong) FYInlineTranslationListCoordinator *owner;
@property(nonatomic,strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic) BOOL ready,hidden,changeFrameDuringRow;
@property(nonatomic,strong) NSString *countText;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic,strong) NSMutableArray<FYInlinePlacement *> *rows;
@property(nonatomic,strong) NSMutableArray<NSNumber *> *rowIndices;
@property(nonatomic,strong) FYInlineBlockSnapshot *opened;
@property(nonatomic) NSUInteger clears,opens,inputReads;
@end
@implementation ListSourceFact
@dynamic inlineTranslationListSignature,inlineTranslationListSnapshots;
- (instancetype)init { if((self=[super init])){self.owner=[FYInlineTranslationListCoordinator new];self.ready=YES;self.trace=[NSMutableArray new];self.rows=[NSMutableArray new];self.rowIndices=[NSMutableArray new];}return self; }
- (NSString *)inlineTranslationListSignature { return self.owner.inlineTranslationListSignature; }
- (void)setInlineTranslationListSignature:(NSString *)v { self.owner.inlineTranslationListSignature=v;[self.trace addObject:@"signature"]; }
- (NSArray *)inlineTranslationListSnapshots { return self.owner.inlineTranslationListSnapshots; }
- (void)setInlineTranslationListSnapshots:(NSArray *)v { self.owner.inlineTranslationListSnapshots=v;[self.trace addObject:@"snapshots"]; }
- (BOOL)isInlineTranslationListReady { [self.trace addObject:@"ready"];return self.ready; }
- (void)setInlineTranslationListHidden:(BOOL)v { self.hidden=v;[self.trace addObject:@"hidden"]; }
- (void)clearInlineTranslationListRows { self.clears++;[self.rows removeAllObjects];[self.rowIndices removeAllObjects];[self.trace addObject:@"clear"]; }
- (void)updateInlineTranslationListCountText:(NSString *)v { self.countText=v;[self.trace addObject:@"count"]; }
- (void)appendInlineTranslationListRowForPlacement:(FYInlinePlacement *)p currentSnapshots:(NSArray *)s {
    [self.rows addObject:p];[self.rowIndices addObject:@(s.count)];[self.trace addObject:[@"row:" stringByAppendingString:p.blockID]];
    if(self.changeFrameDuringRow){FYInlineLayoutResult *next=[FYInlineLayoutResult new];next.placements=@[Placement(@"new-frame",@"new",FYInlineDisplayModeUnplaceable)];self.lastInlineLayoutResult=next;}
}
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block translation:(NSString *)translation stableBlockID:(NSString *)identifier {
    [self.trace addObject:[@"snapshot:" stringByAppendingString:identifier]];FYInlineBlockSnapshot *s=[FYInlineBlockSnapshot new];s.blockID=identifier;s.sourceText=block.text;s.translation=translation;return s;
}
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)s { self.opens++;self.opened=s; }
@end
int main(void) { @autoreleasepool {
    Check(NSClassFromString(@"NSPanel")==Nil,@"list business uses Foundation/CG/model only, no AppKit");ListSourceFact *s=[ListSourceFact new];unsigned int n=0;Ivar *v=class_copyIvarList(FYInlineTranslationListCoordinator.class,&n);free(v);Check(n==2&&!class_getInstanceVariable(FYInlineTranslationListCoordinator.class,"_receiver"),@"original two copy fields sole owned, no idle receiver/cache");
    Check(s.inlineTranslationListSignature==nil&&s.inlineTranslationListSnapshots==nil,@"cold model retains original nil state until native card setup");s.ready=NO;[s.owner refreshWithReceiver:s];Check([[s.trace componentsJoinedByString:@","]isEqual:@"ready"]&&!s.clears,@"missing native list returns before input/state/native work");s.ready=YES;[s.trace removeAllObjects];[s.owner refreshWithReceiver:s];Check(s.hidden&&!s.clears&&[[s.trace componentsJoinedByString:@","]isEqual:@"ready,hidden"],@"empty with old empty signature hides before early return, no state replacement");
    FYInlinePlacement *a=Placement(@"A",@" 译文A ",FYInlineDisplayModeUnplaceable),*b=Placement(@"B",@"译文B",FYInlineDisplayModeCompactEntry);FYInlineLayoutResult *result=[FYInlineLayoutResult new];result.placements=@[Placement(@"short",@"text",FYInlineDisplayModeShortLabel),a,Placement(@"full",@"text",FYInlineDisplayModeFullCard),Placement(@"scroll",@"text",FYInlineDisplayModeScrollingCard),Placement(@"blank",@" \n\t",FYInlineDisplayModeUnplaceable),b];s.lastInlineLayoutResult=result;[s.trace removeAllObjects];[s.owner refreshWithReceiver:s];
    Check(s.rows.count==2&&s.rows[0]==a&&s.rows[1]==b,@"only nonempty canonical Trim unplaceable/compact survive in original placement order");Check(!s.hidden&&[s.countText isEqual:@"1 条暂不可放置 · 1 条用入口"],@"original separate unplaceable/compact count wording preserved");Check([s.inlineTranslationListSignature isEqual:@"A|4| 译文A \nB|3|译文B\n"],@"signature uses original raw translation, ID/mode/newline exactly");Check([s.rowIndices isEqual:@[@0,@1]]&&s.inlineTranslationListSnapshots.count==2,@"rows read local snapshot count then factory appends each exact index");Check([s.inlineTranslationListSnapshots[0].sourceText isEqual:@"source-A"]&&[s.inlineTranslationListSnapshots[0].translation isEqual:@" 译文A "],@"snapshot boundary receives original block/translation/id unchanged");Check([[s.trace componentsJoinedByString:@","]isEqual:@"ready,hidden,signature,clear,count,row:A,snapshot:A,row:B,snapshot:B,snapshots"],@"signature clear count row factory and final copy assignment order exact");
    NSArray *oldSnapshots=s.inlineTranslationListSnapshots;NSUInteger clears=s.clears;[s.trace removeAllObjects];[s.owner refreshWithReceiver:s];Check(s.inlineTranslationListSnapshots==oldSnapshots&&s.clears==clears&&[[s.trace componentsJoinedByString:@","]isEqual:@"ready,hidden"],@"same signature still hides/unhides first but does not rebuild/replace snapshots");a.reason=@"reason changed";a.block.text=@"new source";a.translationFrame=CGRectMake(20,30,40,50);[s.owner refreshWithReceiver:s];Check(s.inlineTranslationListSnapshots==oldSnapshots&&s.clears==clears,@"source/reason/geometry-only changes preserve old snapshots per original signature contract");
    [s.owner openRowAtIndex:-1 receiver:s];[s.owner openRowAtIndex:2 receiver:s];Check(!s.opens,@"negative and equal-count row indices rejected");[s.owner openRowAtIndex:1 receiver:s];Check(s.opens==1&&s.opened==oldSnapshots[1],@"row learning opens exact saved snapshot, not newest frame");a.translation=@"changed translation";[s.owner refreshWithReceiver:s];Check(s.clears==clears+1&&s.inlineTranslationListSnapshots!=oldSnapshots&&[s.inlineTranslationListSnapshots[0].translation isEqual:@"changed translation"],@"translation change rebuilds/copies current snapshot array");
    result.placements=@[b];[s.owner refreshWithReceiver:s];Check([s.countText isEqual:@"1 条改用「查看译文」入口"]&&[s.rowIndices isEqual:@[@0]],@"compact-only count/reset index wording unchanged");result.placements=@[];[s.trace removeAllObjects];[s.owner refreshWithReceiver:s];Check(s.hidden&&s.inlineTranslationListSignature.length==0&&s.inlineTranslationListSnapshots.count==0&&s.rows.count==0,@"nonempty-to-empty clears both fields and native rows");Check([[s.trace componentsJoinedByString:@","]isEqual:@"ready,hidden,signature,snapshots,clear"],@"empty clear order retains state before native rows");clears=s.clears;oldSnapshots=s.inlineTranslationListSnapshots;[s.owner refreshWithReceiver:s];Check(s.clears==clears&&s.inlineTranslationListSnapshots==oldSnapshots,@"repeated empty does not replace array or clear again");
    NSMutableString *alias=[@"signature" mutableCopy];s.inlineTranslationListSignature=alias;[alias appendString:@"-changed"];Check([s.inlineTranslationListSignature isEqual:@"signature"],@"signature property preserves original copy");NSMutableArray *array=[NSMutableArray arrayWithObject:s.opened];s.inlineTranslationListSnapshots=array;[array removeAllObjects];Check(s.inlineTranslationListSnapshots.count==1&&s.inlineTranslationListSnapshots[0]==s.opened,@"snapshot array copy preserves element identity and isolates mutable array");
    result.placements=@[a,b];s.lastInlineLayoutResult=result;s.changeFrameDuringRow=YES;[s.owner refreshWithReceiver:s];Check(s.rows.count==2&&s.rows[0]==a&&s.rows[1]==b&&[s.inlineTranslationListSnapshots[1].blockID isEqual:@"B"],@"mid-row input replacement does not change original held degraded array or factory order");Check([s.lastInlineLayoutResult.placements[0].blockID isEqual:@"new-frame"],@"input boundary actually changed during row construction");
    __weak ListSourceFact *weak;FYInlineTranslationListCoordinator *kept;@autoreleasepool{ListSourceFact *temporary=[ListSourceFact new];weak=temporary;kept=temporary.owner;[kept refreshWithReceiver:temporary];}Check(!weak&&kept,@"coordinator owns only original fields, releases borrowed receiver");Check(NSClassFromString(@"NSPanel")==Nil,@"all production list business executed without native UI/device/service initialization");printf("PASS InlineTranslationListCoordinatorTests: %lu checks; actual filtering/signature/order/copy/row snapshots, no UI\n",(unsigned long)checks);
}return 0; }
