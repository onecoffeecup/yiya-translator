#import "FYInlineLayout.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface FYInlineLayoutEngine (ReceiverTestAccess)
- (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight;
- (NSArray<NSNumber *> *)cardWidthCandidatesForSource:(CGRect)source viewport:(CGRect)viewport;
- (void)applyFoldedEntryCopyToPlacement:(FYInlinePlacement *)placement crowded:(BOOL)crowded;
@end
@interface ReceiverEngine : FYInlineLayoutEngine
@property(nonatomic) NSUInteger bodyCalls,paragraphCalls,widthCalls;
@end
@implementation ReceiverEngine
+ (NSString *)shortTitleForBlockText:(NSString *)text { return @"subclass override"; }
- (NSFont *)fontOfSize:(CGFloat)size weight:(NSFontWeight)weight { self.bodyCalls++;return [super fontOfSize:size weight:weight]; }
- (NSParagraphStyle *)shortParagraphStyle { self.paragraphCalls++;return [super shortParagraphStyle]; }
- (NSArray<NSNumber *> *)cardWidthCandidatesForSource:(CGRect)source viewport:(CGRect)viewport {
    self.widthCalls++;return [super cardWidthCandidatesForSource:source viewport:viewport];
}
@end
int main(void){@autoreleasepool{
    FYInlineLayoutEngine *factory=[ReceiverEngine defaultEngine];
    Check(factory.class==FYInlineLayoutEngine.class,@"original named-class defaultEngine factory does not instantiate receiver subclass");
    ReceiverEngine *engine=[ReceiverEngine new];
    engine.shortFontSize=factory.shortFontSize;engine.coverFontSize=factory.coverFontSize;engine.longBodyFontSize=factory.longBodyFontSize;engine.minimumLongBodyFontSize=factory.minimumLongBodyFontSize;engine.minimumCardWidth=factory.minimumCardWidth;engine.cardMaxWidth=factory.cardMaxWidth;engine.cardWidthFraction=factory.cardWidthFraction;engine.cardWideFraction=factory.cardWideFraction;engine.viewportMargin=factory.viewportMargin;engine.panelGap=factory.panelGap;engine.shortWidthFraction=factory.shortWidthFraction;engine.shortMaxWidth=factory.shortMaxWidth;
    FYInlineTextBlock *block=[FYInlineTextBlock new];block.blockID=@"native";block.text=@"原生合成字段";block.kind=FYInlineBlockKindShort;block.lineTexts=@[block.text];
    FYInlineLayoutRequest *request=[FYInlineLayoutRequest requestWithBlock:block translation:@"保留原生度量" sourceFrame:CGRectMake(200,200,160,30)];
    FYInlineLayoutResult *result=[engine layoutRequests:@[request] viewport:CGRectMake(0,0,800,600) previous:nil];
    Check(result.placements.count==1&&engine.bodyCalls&&engine.paragraphCalls,@"actual native layout keeps concrete short font/style helper overrides");
    FYInlinePlacement *placement=result.placements.firstObject;
    CGFloat actual=ceil(NSHeight([placement.translation boundingRectWithSize:NSMakeSize(MAX((CGFloat)80,130-placement.panelPadding*2),CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:placement.font,NSParagraphStyleAttributeName:placement.paragraphStyle}]));
    Check([engine measuredBodyHeight:placement.translation placement:placement width:130]==actual,@"facade measurement still uses actual native font and paragraph on placement");
    [engine longCardVariantsForRequest:request viewport:CGRectMake(0,0,800,600)];Check(engine.widthCalls>0,@"inherited variant algorithm dispatches width helper to concrete subclass");
    placement.block.text=@"合成标题\n合成正文";[engine applyFoldedEntryCopyToPlacement:placement crowded:NO];
    Check([placement.entryTitle isEqual:[FYInlineLayoutEngine shortTitleForBlockText:placement.block.text]]&&![placement.entryTitle isEqual:@"subclass override"],@"folded title preserves original literal native class call despite subclass class-method override");
    __weak ReceiverEngine *weak;
    @autoreleasepool { ReceiverEngine *temporary=[ReceiverEngine new];weak=temporary;temporary.fontProvider=^NSFont *(CGFloat size,NSFontWeight weight){return [NSFont systemFontOfSize:size weight:weight];};[temporary shortBodyFontForCover:NO]; }
    Check(!weak,@"native action lifetime retains no idle calculator source or receiver lease");
    printf("PASS InlineLayoutReceiverTests: %lu checks; same concrete native receiver/helper/class dispatch\n",(unsigned long)checks);
}return 0;}
