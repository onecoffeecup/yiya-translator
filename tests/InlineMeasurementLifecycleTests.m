#import "FYInlineLayout.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
// Existing private selectors: the same fixture compiles with exact before and
// after production sources, and always executes the actual layout algorithm.
@interface FYInlineLayoutEngine (MeasurementTestAccess)
@property(nonatomic,strong) NSMutableDictionary<NSArray *,NSNumber *> *layoutHeightCache;
- (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
- (CGFloat)measuredHeightForText:(NSString *)text width:(CGFloat)width font:(NSFont *)font style:(NSParagraphStyle *)style;
@end
@interface GetterLayoutEngine : FYInlineLayoutEngine
@property(nonatomic) NSUInteger providerReads,cacheReads,cacheWrites;
@end
@implementation GetterLayoutEngine
- (NSFont * (^)(CGFloat,NSFontWeight))fontProvider{self.providerReads++;return [super fontProvider];}
- (NSMutableDictionary *)layoutHeightCache{self.cacheReads++;return [super layoutHeightCache];}
- (void)setLayoutHeightCache:(NSMutableDictionary *)value{self.cacheWrites++;[super setLayoutHeightCache:value];}
@end
static FYInlineLayoutRequest *Request(NSString *identity,NSString *source,NSString *translation,CGRect rect){FYInlineTextBlock *b=[FYInlineTextBlock new];b.blockID=identity;b.text=source;b.kind=FYInlineBlockKindShort;b.lineTexts=@[source];b.lineBoxes=@[@(rect)];return [FYInlineLayoutRequest requestWithBlock:b translation:translation sourceFrame:rect];}
int main(void){@autoreleasepool{
    GetterLayoutEngine *getter=[GetterLayoutEngine new];__block NSUInteger factoryCalls=0;
    getter.fontProvider=^NSFont *(CGFloat size,NSFontWeight weight){factoryCalls++;return [NSFont systemFontOfSize:size weight:weight];};
    NSFont *font=[getter fontOfSize:17.35 weight:NSFontWeightRegular];
    Check(font.pointSize==17.35&&factoryCalls==1&&getter.providerReads==2,@"actual concrete font-provider getter override retains two reads and one native factory call");
    NSParagraphStyle *style=[getter shortParagraphStyle];NSString *text=@"合成原生测量。Repeated English words preserve native metrics and wrapping.これは合成文です。";
    getter.cacheReads=0;
    CGFloat nativeHeight=ceil(NSHeight([text boundingRectWithSize:NSMakeSize(130,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:font,NSParagraphStyleAttributeName:style}]));
    Check([getter measuredHeightForText:text width:130 font:font style:style]==nativeHeight&&getter.cacheReads==1,@"concrete height getter override matches native uncached result and one read");
    NSMutableDictionary *cache=[NSMutableDictionary new];getter.layoutHeightCache=cache;getter.cacheReads=0;
    Check([getter measuredHeightForText:text width:130 font:font style:style]==nativeHeight&&getter.cacheReads==3&&cache.count==1,@"concrete cache getter sees original miss gate/read/write order");
    getter.cacheReads=0;Check([getter measuredHeightForText:text width:130 font:font style:style]==nativeHeight&&getter.cacheReads==2&&cache.count==1,@"concrete cache hit returns original value after two reads");
    getter.cacheReads=0;Check([getter measuredHeightForText:text width:4 font:font style:style]==0&&!getter.cacheReads,@"concrete width gate still precedes any state access");
    FYInlineLayoutEngine *engine=[FYInlineLayoutEngine defaultEngine];NSMutableDictionary<NSArray *,NSNumber *> *outside=[NSMutableDictionary dictionaryWithObject:@42 forKey:@[@"outside"]];engine.layoutHeightCache=outside;
    CGRect viewport=CGRectMake(0,0,800,600);FYInlineLayoutRequest *outer=Request(@"outer",@"外层合成标签",@"外层中文",CGRectMake(100,100,140,30)),*nested=Request(@"nested",@"内层合成标签",@"内层中文",CGRectMake(400,300,140,30));
    __weak FYInlineLayoutEngine *weakEngine=engine;__block BOOL entered=NO;__block BOOL restoredDuringReentry=NO;__block __weak NSMutableDictionary *completedScope;
    engine.fontProvider=^NSFont *(CGFloat size,NSFontWeight weight){
        if(!entered){
            entered=YES;FYInlineLayoutEngine *active=weakEngine;NSMutableDictionary *before=active.layoutHeightCache;completedScope=before;
            Check(before!=outside&&before!=nil,@"actual outer production layout uses a separate round cache");
            FYInlineLayoutResult *inner=[active layoutRequests:@[nested] viewport:viewport previous:nil];
            restoredDuringReentry=active.layoutHeightCache==before;
            Check(inner.placements.count==1&&[[inner.placements.firstObject blockID]isEqual:@"nested"]&&inner.visiblePlacements.count==1,@"reentrant native provider runs real production nested layout");
        }
        return [NSFont systemFontOfSize:size weight:weight];
    };
    @autoreleasepool {
        FYInlineLayoutResult *result=[engine layoutRequests:@[outer] viewport:viewport previous:nil];
        Check(entered&&restoredDuringReentry&&result.placements.count==1&&[[result.placements.firstObject blockID]isEqual:@"outer"],@"real outer layout completes after nested scope restores its cache");
        Check(engine.layoutHeightCache==outside&&outside.count==1&&outside[@[@"outside"]].integerValue==42,@"completed layout restores original mutable external cache without overwriting it");
        FYInlinePlacement *placement=result.placements.firstObject;
        Check(placement.font&&placement.paragraphStyle&&[placement.translation isEqual:@"外层中文"]&&placement.mode==FYInlineDisplayModeShortLabel,@"actual native measured style and original characters reach production placement");
    }
    Check(!completedScope,@"completed round cache releases after native return leases drain");
    engine.fontProvider=^NSFont *(CGFloat size,NSFontWeight weight){@throw [NSException exceptionWithName:@"SyntheticMeasurementException" reason:@"native factory boundary" userInfo:nil];};
    BOOL caught=NO;@try{[engine layoutRequests:@[outer] viewport:viewport previous:nil];}@catch(NSException *e){caught=[e.name isEqual:@"SyntheticMeasurementException"];}
    Check(caught&&engine.layoutHeightCache==outside&&outside.count==1,@"real native factory exception propagates and production finally restores external cache");
    engine.fontProvider=nil;@autoreleasepool{
        FYInlineLayoutResult *normal=[engine layoutRequests:@[outer] viewport:viewport previous:nil];
        Check(normal.visiblePlacements.count==1&&engine.layoutHeightCache==outside,@"same real engine recovers after native exception and restores scope again");
    }
    printf("PASS measurement lifecycle: %lu checks; real native/layout execution, concrete getter order, nested and exception scope restoration\n",(unsigned long)checks);
}return 0;}
