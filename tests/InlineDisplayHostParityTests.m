#import "presentation/FYInlineOverlayController.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
// Native UI facts only: neither object is a view/window and no event is posted.
// The exact original/extracted controller, matcher and native calculator run.
@interface NativeContentFact : NSObject
@property(nonatomic) BOOL longCard,showsSelectedBadge;
@end
@implementation NativeContentFact
- (BOOL)isKindOfClass:(Class)cls{if(cls==FYInlineLongCardView.class)return self.longCard;return [super isKindOfClass:cls];}
@end
@interface NativePanelFact : NSObject
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic) NSRect frame;
@property(nonatomic,strong) NativeContentFact *contentView;
@property(nonatomic) NSUInteger closes,updates,wires;
@property(nonatomic) BOOL ignoresMouseEvents;
@end
@implementation NativePanelFact
- (void)close{self.closes++;}
@end
@interface NativeDisplayPeer : NSObject
@property(nonatomic) BOOL inlineGeometryPending;
@property(nonatomic,copy) NSString *lastDisplayGeometryToken,*inlineOCRPendingText;
@property(nonatomic) NSInteger inlineOCRPendingCount;
@property(nonatomic,strong) FYInlineBlockSnapshot *inlineBlockSnapshot;
@property(nonatomic,strong) FYInlineOCRFrameStabilizer *inlineFrameStabilizer;
@property(nonatomic) NSUInteger starts,overflow;
@end
@implementation NativeDisplayPeer
- (void)startInlineModifierMonitor{self.starts++;}
- (void)updateInlineOverflowEntryWithPlacements:(NSArray *)placements items:(NSDictionary *)items viewport:(NSRect)viewport unplaceable:(NSUInteger)unplaceable{self.overflow=unplaceable;}
@end
@interface NativeHostProbe : FYInlineOverlayController
@property(nonatomic,strong) FYInlineLayoutEngine *actualEngine;
@property(nonatomic) NSUInteger engineReads,expanded,visibility,rows;
@property(nonatomic,copy) NSString *reason;
@end
@implementation NativeHostProbe
- (FYInlineLayoutEngine *)inlineLayoutEngine{self.engineReads++;return self.actualEngine;}
- (uint32_t)displayTargetWindowID{return 7;}
- (FYInlineTextBlock *)inlineLayoutBlockForItem:(OCRTextItem *)item order:(NSInteger)order{FYInlineTextBlock *b=[FYInlineTextBlock new];b.blockID=item.sourceBlockID;b.text=item.text;b.boundingBox=item.boundingBox;b.kind=item.blockKind==InlineBlockKindLong?FYInlineBlockKindLong:FYInlineBlockKindShort;b.lineTexts=item.lineTexts;return b;}
- (NSRect)appKitFrameForOCRItem:(OCRTextItem *)item inWindowFrame:(NSRect)viewport{return CGRectMake(NSMinX(viewport)+item.boundingBox.origin.x*NSWidth(viewport),NSMinY(viewport)+item.boundingBox.origin.y*NSHeight(viewport),item.boundingBox.size.width*NSWidth(viewport),item.boundingBox.size.height*NSHeight(viewport));}
- (NSPanel *)panelLong:(BOOL)longCard frame:(NSRect)frame{NativePanelFact *p=[NativePanelFact new];p.frame=frame;p.contentView=[NativeContentFact new];p.contentView.longCard=longCard;return (NSPanel *)p;}
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)text item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement{return [self panelLong:YES frame:frame];}
- (NSPanel *)inlinePanelForTranslation:(NSString *)text sourceText:(NSString *)source sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout{return [self panelLong:NO frame:layout.frame];}
- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)text item:(OCRTextItem *)item frame:(NSRect)frame compact:(BOOL)compact placement:(FYInlinePlacement *)placement{((NativePanelFact *)panel).frame=frame;((NativePanelFact *)panel).updates++;}
- (void)updateInlinePanel:(NSPanel *)panel translation:(NSString *)text sourceText:(NSString *)source sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout{((NativePanelFact *)panel).frame=layout.frame;((NativePanelFact *)panel).updates++;}
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement{((NativePanelFact *)panel).wires++;}
- (void)recordInlineLayoutDebug:(FYInlineLayoutResult *)result previous:(FYInlineLayoutResult *)previous viewport:(NSRect)viewport reason:(NSString *)reason{self.reason=reason;}
- (void)advanceExpandedReadingState{self.expanded++;}
- (void)refreshOverlayVisibility:(id)sender{self.visibility++;}
- (void)refreshInlineTranslationList{self.rows++;}
@end
static OCRTextItem *Item(NSString *identity,NSString *text,CGRect rect,BOOL longCard){OCRTextItem *i=[OCRTextItem new];i.sourceBlockID=identity;i.text=text;i.boundingBox=rect;i.blockKind=longCard?InlineBlockKindLong:InlineBlockKindShort;i.lineTexts=@[text];return i;}
int main(void){@autoreleasepool{
    Check(NSApp==nil,@"headless before/after host fixture starts without application/window");
    NativeDisplayPeer *peer=[NativeDisplayPeer new];peer.lastDisplayGeometryToken=@"peer-token";NativeHostProbe *p=[[NativeHostProbe alloc]initWithHost:(id<FYInlineOverlayControllerHost>)peer];p.actualEngine=[FYInlineLayoutEngine defaultEngine];p.actualEngine.fontProvider=^NSFont *(CGFloat size,NSFontWeight weight){return [NSFont systemFontOfSize:size weight:weight];};p.inlineTranslationPanels=[NSMutableArray new];p.inlineLongCardPanels=[NSMutableArray new];p.inlineManualOffsets=[NSMutableDictionary new];p.inlineManualOffsetAge=[NSMutableDictionary new];p.inlineStableBlockIDs=[NSMutableDictionary new];p.inlinePanelsByBlockID=[NSMutableDictionary new];
    OCRTextItem *item=Item(@"source",@"合成字段",CGRectMake(.2,.3,.2,.05),NO);NSRect viewport=CGRectMake(0,0,800,600);
    [p showInlineTranslations:@[@"合成原生译文"] forItems:@[item] placementRect:viewport];FYInlinePlacement *placement=p.lastInlineLayoutResult.placements.firstObject;NativePanelFact *first=(NativePanelFact *)p.inlinePanelsByBlockID[placement.blockID];
    Check(p.lastInlineLayoutResult.placements.count==1&&first&&p.inlineTranslationPanels.count==1&&p.engineReads==2,@"fresh exact production host calculates and creates one native-boundary panel");
    Check(placement.font&&placement.paragraphStyle&&placement.measuredContentHeight>0&&[first.identifier isEqual:placement.blockID]&&first.wires==1,@"native calculator supplies actual font/style/measurement and stable binding");
    Check([p.reason isEqual:@"initial"]&&peer.starts==1&&p.expanded==1&&p.visibility==1&&[p.lastInlineRenderGeometryToken isEqual:@"peer-token"],@"initial commit retains debug/host/expanded/visibility/token semantics");
    [p showInlineTranslations:@[@"合成原生译文"] forItems:@[item] placementRect:viewport];Check(p.inlinePanelsByBlockID[placement.blockID]==(NSPanel *)first&&!first.updates&&!first.closes&&p.engineReads==3&&p.expanded==2&&p.visibility==2,@"identical input retains same panel without update/close and still advances reading");
    item.boundingBox=CGRectOffset(item.boundingBox,.001,0);[p showInlineTranslations:@[@"合成原生译文"] forItems:@[item] placementRect:viewport];Check([p.reason isEqual:@"cache_minor_ocr_jitter"]&&p.inlinePanelsByBlockID[placement.blockID]==(NSPanel *)first&&!first.updates,@"actual original/extracted jitter path preserves same measured panel");
    [p showInlineTranslations:@[@"合成原生译文"] forItems:@[item] placementRect:CGRectOffset(viewport,10,0)];Check(p.inlinePanelsByBlockID[placement.blockID]==(NSPanel *)first&&first.updates==1&&[p.reason isEqual:@"geometry_or_style_changed"],@"real native viewport change reflows stable existing panel");
    item.blockKind=InlineBlockKindLong;[p showInlineTranslations:@[@"合成原生译文"] forItems:@[item] placementRect:CGRectOffset(viewport,10,0)];
    // Kind alone is deliberately absent from the old content fingerprint.
    Check(p.inlinePanelsByBlockID[placement.blockID]==(NSPanel *)first&&!first.closes,@"unchanged text/geometry retains original kind-only cache behavior");
    [p showInlineTranslations:@[@"另一段合成原生译文。保留实际字体与换行。"] forItems:@[item] placementRect:CGRectOffset(viewport,10,0)];NativePanelFact *longPanel=(NativePanelFact *)p.inlineLongCardPanels.firstObject;
    Check(longPanel&&longPanel!=first&&longPanel.contentView.longCard&&first.closes==1&&p.inlineTranslationPanels.count==0,@"actual content change rebuilds only type-changed panel");
    peer.inlineBlockSnapshot=[FYInlineBlockSnapshot new];peer.inlineBlockSnapshot.blockID=longPanel.identifier;[p showInlineTranslations:@[@"另一段合成原生译文。保留实际字体与换行。"] forItems:@[item] placementRect:CGRectOffset(viewport,10,0)];Check(longPanel.contentView.showsSelectedBadge,@"actual native badge action observes original peer snapshot and panel identifier");
    NSUInteger before=p.engineReads;p.inlineDraggingPanel=(NSPanel *)longPanel;[p showInlineTranslations:@[@"guard"] forItems:@[item] placementRect:viewport];Check(p.engineReads==before,@"actual active drag guard avoids layout and snapshot work");p.inlineDraggingPanel=nil;
    [p clearInlineTranslationPanels];Check(longPanel.closes==1&&p.inlinePanelsByBlockID.count==0&&p.inlineTranslationPanels.count==0&&p.inlineLongCardPanels.count==0&&!p.lastInlineLayoutResult&&!p.lastInlineRenderedItems&&!p.lastInlineRenderedTranslations&&!p.lastInlineTranslationKey,@"original native clear releases all inherited/current scene caches and panels");
    Check(p.host==(id)peer&&NSApp==nil,@"headless native pipeline preserves weak peer without creating any UI object");
    printf("PASS InlineDisplayHostParityTests: %lu checks; exact production host/canonical native layout,same source before/after,no UI objects\n",(unsigned long)checks);
}return 0;}
