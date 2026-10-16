#import "presentation/FYInlineDisplayCoordinatorInternal.h"
#import "presentation/FYPresentationText.h"
#import "presentation/FYInlineManualPlacementCoordinator.h"
#import <objc/runtime.h>
#ifdef FY_DISPLAY_NATIVE_MEASUREMENT
#import "FYInlineLayout.h"
#endif
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
// Synthetic panel facts/actions replace the native UI boundary only. The
// production coordinator, canonical matcher and cache/commit algorithms run.
@interface PanelFact : NSObject
@property(nonatomic,copy) NSString *identity;
@property(nonatomic) BOOL longCard;
@property(nonatomic) NSUInteger closes,updates,wires;
@property(nonatomic) NSRect frame;
@end
@implementation PanelFact @end
@interface DisplayItem : OCRTextItem
@property(nonatomic) NSRect nativeFrame;
@end
@implementation DisplayItem @end
@interface DisplayProbe : FYInlineDisplayCoordinator <FYInlineDisplayNativeActions>
@property(nonatomic,weak) NSPanel *inlineDraggingPanel;
@property(nonatomic) BOOL inlineGeometryPending;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSValue *> *inlineManualOffsets;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *inlineManualOffsetAge;
@property(nonatomic,copy) NSString *lastDisplayGeometryToken;
@property(nonatomic,strong) FYInlineLayoutCalculator *configuration;
@property(nonatomic,strong) NSMutableArray<NSString *> *events;
@property(nonatomic) NSUInteger engineReads,blockReads,frameReads,badgeUpdates,expandedAdvances,visibilityRefreshes,rows,starts,overflowCount;
@property(nonatomic) BOOL failFactory,activeDiagnostics;
@property(nonatomic,copy) NSString *lastDebugReason;
@property(nonatomic,copy) NSDictionary *debugContext;
@property(nonatomic) NSUInteger debugReads;
@property(nonatomic,copy) void (^duringWire)(void);
@end
@implementation DisplayProbe
- (instancetype)init{if((self=[super init])){_events=[NSMutableArray new];_inlineManualOffsets=[NSMutableDictionary new];_inlineManualOffsetAge=[NSMutableDictionary new];_lastDisplayGeometryToken=@"native-token";_configuration=[FYInlineLayoutCalculator defaultCalculator];}return self;}
- (FYInlineLayoutCalculator *)inlineLayoutEngine{self.engineReads++;return self.configuration;}
- (NSDictionary *)currentInlineLayoutDebugContext{self.debugReads++;return self.debugContext;}
- (BOOL)inlineLayoutDiagnosticsActive{return self.activeDiagnostics;}
- (uint32_t)displayTargetWindowID{return 7;}
- (FYInlineTextBlock *)inlineLayoutBlockForItem:(OCRTextItem *)item order:(NSInteger)order{self.blockReads++;FYInlineTextBlock *b=[FYInlineTextBlock new];b.blockID=item.sourceBlockID;b.text=item.text;b.boundingBox=item.boundingBox;b.kind=item.blockKind==InlineBlockKindLong?FYInlineBlockKindLong:FYInlineBlockKindShort;b.lineTexts=item.lineTexts;return b;}
- (NSRect)appKitFrameForOCRItem:(OCRTextItem *)item inWindowFrame:(NSRect)frame{self.frameReads++;return ((DisplayItem *)item).nativeFrame;}
- (void)updateInlineLongCardSelectedBadgeForPanel:(NSPanel *)panel{self.badgeUpdates++;[self.events addObject:@"badge"];}
- (BOOL)inlinePanelHasLongCardContent:(NSPanel *)panel{return ((PanelFact *)panel).longCard;}
- (void)closeInlinePanel:(NSPanel *)panel{((PanelFact *)panel).closes++;[self.events addObject:@"close"];}
- (void)setInlinePanel:(NSPanel *)panel identifier:(NSString *)identity{((PanelFact *)panel).identity=identity;[self.events addObject:@"identifier"];}
- (NSPanel *)newPanelLong:(BOOL)longCard frame:(NSRect)frame{[self.events addObject:longCard?@"create_long":@"create_short"];if(self.failFactory)return nil;PanelFact *p=[PanelFact new];p.longCard=longCard;p.frame=frame;return (NSPanel *)p;}
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)placement{return [self newPanelLong:YES frame:frame];}
- (void)updateInlineLongCard:(NSPanel *)panel translation:(NSString *)translation item:(OCRTextItem *)item frame:(NSRect)frame compact:(BOOL)compact placement:(FYInlinePlacement *)placement{((PanelFact *)panel).updates++;((PanelFact *)panel).frame=frame;[self.events addObject:@"update_long"];}
- (InlinePanelLayout)inlinePanelLayoutFromPlacement:(FYInlinePlacement *)placement{[self.events addObject:@"short_layout"];InlinePanelLayout value={placement.translationFrame,placement.labelFrame,placement.font,placement.cornerRadius};return value;}
- (NSPanel *)inlinePanelForTranslation:(NSString *)translation sourceText:(NSString *)source sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout{return [self newPanelLong:NO frame:layout.frame];}
- (void)updateInlinePanel:(NSPanel *)panel translation:(NSString *)translation sourceText:(NSString *)source sourceFrame:(NSRect)sourceFrame windowFrame:(NSRect)windowFrame layout:(InlinePanelLayout)layout{((PanelFact *)panel).updates++;((PanelFact *)panel).frame=layout.frame;[self.events addObject:@"update_short"];}
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement{((PanelFact *)panel).wires++;[self.events addObject:@"wire"];if(self.duringWire)self.duringWire();}
- (NSValue *)inlineManualOffsetForText:(NSString *)text normalizedBox:(CGRect)box{return self.inlineManualOffsets[[self inlineManualOffsetKeyForText:text normalizedBox:box]];}
- (void)maintainInlineManualOffsetsForPlacements:(NSArray<FYInlinePlacement *> *)placements { FYInlineManualPlacementCoordinator *manual=[FYInlineManualPlacementCoordinator new];[manual maintainOffsetsForPlacements:placements stateSource:(id<FYInlineManualPlacementStateSource>)self]; }
- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box{return [NSString stringWithFormat:@"%@|%.2f",text,box.origin.x];}
- (void)recordInlineLayoutDebug:(FYInlineLayoutResult *)result previous:(FYInlineLayoutResult *)previous viewport:(NSRect)viewport reason:(NSString *)reason{self.lastDebugReason=reason;[self.events addObject:@"layout_debug"];}
- (void)recordInlineRenderInputCount:(NSUInteger)count{[self.events addObject:@"input_debug"];}
- (void)recordInlineUnplaceableDiagnosticForItem:(OCRTextItem *)item placement:(FYInlinePlacement *)p viewport:(NSRect)viewport{[self.events addObject:@"unplaceable"];}
- (void)recordInlinePlacedPanelDiagnostics:(NSPanel *)panel item:(OCRTextItem *)item placement:(FYInlinePlacement *)p{[self.events addObject:@"panel_debug"];}
- (void)recordInlineCardVariantDiagnostic:(FYInlinePlacement *)p{[self.events addObject:@"variant_debug"];}
- (void)advanceExpandedReadingState{self.expandedAdvances++;[self.events addObject:@"expanded"];}
- (void)refreshOverlayVisibility:(id)sender{self.visibilityRefreshes++;[self.events addObject:@"visibility"];}
- (void)refreshInlineTranslationList{self.rows++;[self.events addObject:@"rows"];}
- (void)startInlineModifierMonitorThroughHost{self.starts++;[self.events addObject:@"start_host"];}
- (void)updateInlineOverflowEntryThroughHostWithPlacements:(NSArray<FYInlinePlacement *> *)placements items:(NSDictionary<NSString *,OCRTextItem *> *)items viewport:(NSRect)viewport unplaceable:(NSUInteger)count{self.overflowCount=count;[self.events addObject:@"overflow_host"];}
@end
static DisplayItem *Item(NSString *identity,NSString *text,BOOL longCard){DisplayItem *i=[DisplayItem new];i.sourceBlockID=identity;i.text=text;i.boundingBox=CGRectMake(.0049,.2,.2,.04);i.nativeFrame=CGRectMake(100,200,160,30);i.blockKind=longCard?InlineBlockKindLong:InlineBlockKindShort;i.lineTexts=@[text];return i;}
static FYInlinePlacement *Placement(DisplayItem *item,NSString *stable){FYInlinePlacement *p=[FYInlinePlacement new];p.sourceBlockID=item.sourceBlockID;p.blockID=stable;p.block=[FYInlineTextBlock new];p.block.blockID=item.sourceBlockID;p.block.text=item.text;p.block.boundingBox=item.boundingBox;p.translation=@"合成译文";p.sourceFrame=item.nativeFrame;p.translationFrame=CGRectMake(100,250,160,40);p.mode=FYInlineDisplayModeShortLabel;return p;}
static FYInlineDisplayFrame *Frame(NSArray<FYInlinePlacement *> *placements,NSArray<DisplayItem *> *items){FYInlineLayoutResult *r=[FYInlineLayoutResult new];r.placements=placements;NSMutableDictionary *index=[NSMutableDictionary new];for(DisplayItem *i in items)index[i.sourceBlockID]=i;return [[FYInlineDisplayFrame alloc]initWithResult:r previous:nil viewport:CGRectMake(0,0,800,600) items:items itemsByBlockID:index identity:@"identity" contentKey:@"content" geometryKey:@"geometry" reason:@"fixture"] ;}
static NSString *GeometryKey(void){return @"|t=7|vp=0.0,0.0,800.0,600.0|style=16.0000,17.0000,19.0000,15.0000,14.0000,13.0000,360.0000,560.0000,330.0000";}
int main(void){@autoreleasepool{
    FYInlineDisplayCoordinator *cold=[FYInlineDisplayCoordinator new];unsigned int count=0;Ivar *ivars=class_copyIvarList(FYInlineDisplayCoordinator.class,&count);free(ivars);
    Check(count==16&&!cold.inlinePanelsByBlockID&&!cold.inlineTranslationPanels&&!cold.lastInlineLayoutResult,@"cold display owner has exactly16 zero state fields and no native work");
    Check([Trim(nil)isEqual:@""]&&[Trim(@" \n合成 \n")isEqual:@"合成"]&&[NormalizeForComparison(@"合 成　文\n")isEqual:@"合成文"]&&[Shorten(@" 合成文本 ",2)isEqual:@"合成..."]&&[Shorten(@"合成",2)isEqual:@"合成"],@"canonical original text helpers retain nil/whitespace/UTF16 limit behavior");
    DisplayProbe *p=[DisplayProbe new];DisplayItem *shortItem=Item(@"raw-short",@"合成短文",NO),*longItem=Item(@"raw-long",@"合成长文",YES);
    NSString *identity=[p inlineTranslationIdentityForTranslations:@[@" 译文 \n",@"unused"] forItems:@[shortItem]];
    Check([identity isEqual:@"合成短文\n译文\n0.00:0.20:0.20:0.04\n"]&&[[p inlineTranslationIdentityForTranslations:@[] forItems:@[shortItem]]isEqual:@""],@"identity retains min-count, canonical normalization and original two-decimal geometry");
    FYInlinePlacement *sp=Placement(shortItem,@"stable-short"),*lp=Placement(longItem,@"stable-long");lp.mode=FYInlineDisplayModeFullCard;
    FYInlineDisplayFrame *frame=Frame(@[sp,lp],@[shortItem,longItem]);Check(frame.result.placements.firstObject==sp&&frame.items.firstObject==shortItem&&frame.itemsByBlockID[shortItem.sourceBlockID]==shortItem&&frame.previous==nil,@"immutable frame retains original mutable element/index identity and nil previous");
    NSMutableArray *alias=[@[shortItem]mutableCopy];NSMutableString *key=[@"before"mutableCopy];FYInlineDisplayFrame *aliasFrame=[[FYInlineDisplayFrame alloc]initWithResult:frame.result previous:frame.result viewport:frame.viewport items:alias itemsByBlockID:frame.itemsByBlockID identity:key contentKey:key geometryKey:key reason:key];[alias addObject:longItem];[key appendString:@"after"];Check(aliasFrame.items==alias&&aliasFrame.items.count==2&&aliasFrame.identity==key&&[aliasFrame.contentKey isEqual:@"beforeafter"],@"frame does not introduce early copies of original synchronous aliases");
    [p applyInlineDisplayFrame:frame];PanelFact *shortPanel=(PanelFact *)p.inlinePanelsByBlockID[sp.blockID],*longPanel=(PanelFact *)p.inlinePanelsByBlockID[lp.blockID];
    Check(p.inlineTranslationPanels.count==1&&p.inlineLongCardPanels.count==1&&shortPanel&&!shortPanel.longCard&&longPanel.longCard,@"actual commit creates short and long native-boundary panels separately");
    Check([shortPanel.identity isEqual:sp.blockID]&&shortPanel.wires==1&&longPanel.wires==1,@"new panels get stable identity before drag binding");
    Check([p.events isEqual:@[@"short_layout",@"create_short",@"identifier",@"wire",@"panel_debug",@"create_long",@"identifier",@"wire",@"panel_debug",@"layout_debug",@"rows",@"start_host",@"overflow_host",@"expanded",@"visibility"]],@"panel commit preserves original factory/bind/debug/rows/host/expanded/visibility order");
    Check(p.lastInlineLayoutResult==frame.result&&[p.lastInlineTranslationKey isEqual:@"identity"]&&[p.lastInlineRenderGeometryToken isEqual:@"native-token"]&&p.lastInlineLayoutBoxes.count==2&&!p.inlineGeometryPending,@"commit stores canonical result,content/geometry/token and original item boxes");
    Check([p.inlineStableBlockIDs[shortItem.sourceBlockID]isEqual:sp.blockID]&&[p.inlineStableBlockIDs[longItem.sourceBlockID]isEqual:lp.blockID],@"source identities map to stable placement identities");
    NSMutableDictionary *oldMap=p.inlinePanelsByBlockID;[p.events removeAllObjects];[p applyInlineDisplayFrame:frame];
    Check(p.inlinePanelsByBlockID[sp.blockID]==(NSPanel *)shortPanel&&p.inlinePanelsByBlockID[lp.blockID]==(NSPanel *)longPanel&&shortPanel.updates==1&&longPanel.updates==1&&!shortPanel.closes&&!longPanel.closes,@"same stable identities update existing panels without close/recreate");
    Check(oldMap!=p.inlinePanelsByBlockID&&oldMap[sp.blockID]==(NSPanel *)shortPanel,@"registry replacement keeps external old dictionary alias and panel identity");
    shortItem.blockKind=InlineBlockKindLong;[p applyInlineDisplayFrame:Frame(@[sp],@[shortItem])];PanelFact *switched=(PanelFact *)p.inlinePanelsByBlockID[sp.blockID];
    Check(shortPanel.closes==1&&longPanel.closes==1&&switched!=shortPanel&&switched.longCard&&p.inlineTranslationPanels.count==0&&p.inlineLongCardPanels.count==1,@"type change rebuilds only changed block and removes extra old block");
    shortItem.blockKind=InlineBlockKindShort;sp.mode=FYInlineDisplayModeCompactEntry;[p applyInlineDisplayFrame:Frame(@[sp],@[shortItem])];
    Check(p.inlinePanelsByBlockID[sp.blockID]==(NSPanel *)switched&&p.lastInlineCompactEntryCount==1,@"compact mode always uses long-card semantics even for short OCR kind");
    sp.mode=FYInlineDisplayModeUnplaceable;[p applyInlineDisplayFrame:Frame(@[sp],@[shortItem])];
    Check(p.inlinePanelsByBlockID.count==0&&switched.closes==1&&p.lastInlineUnplaceableCount==1&&p.overflowCount==1,@"unplaceable keeps result/cause and routes original count to edge fallback");
    DisplayProbe *failed=[DisplayProbe new];failed.failFactory=YES;sp.mode=FYInlineDisplayModeShortLabel;[failed applyInlineDisplayFrame:Frame(@[sp],@[shortItem])];Check(failed.inlinePanelsByBlockID.count==0&&failed.starts==0&&failed.lastInlineUnplaceableCount==0,@"nil native factory does not fabricate a panel or unplaceable result");
    DisplayProbe *manual=[DisplayProbe new];sp.manuallyPlaced=YES;sp.translationFrame=CGRectMake(112,208,160,40);NSString *manualKey=[manual inlineManualOffsetKeyForText:sp.block.text normalizedBox:sp.block.boundingBox];manual.inlineManualOffsets[@"gone"]=@(NSMakeSize(1,2));manual.inlineManualOffsetAge[@"gone"]=@2;
    [manual applyInlineDisplayFrame:Frame(@[sp],@[shortItem])];Check(NSEqualSizes(manual.inlineManualOffsets[manualKey].sizeValue,NSMakeSize(12,8))&&[manual.inlineManualOffsetAge[manualKey]isEqual:@0]&&!manual.inlineManualOffsets[@"gone"]&&!manual.inlineManualOffsetAge[@"gone"],@"manual offset rekeys current anchor, resets age and expires after original two missing frames");
    manual.inlineManualOffsets[@"recent"]=@(NSMakeSize(1,2));manual.inlineManualOffsetAge[@"recent"]=@0;[manual applyInlineDisplayFrame:Frame(@[sp],@[shortItem])];Check(manual.inlineManualOffsets[@"recent"]&&[manual.inlineManualOffsetAge[@"recent"]isEqual:@1],@"one missing frame retains manual position");
    DisplayProbe *cache=[DisplayProbe new];shortItem.boundingBox=CGRectMake(.0049,.2,.2,.04);sp.manuallyPlaced=NO;sp.block.boundingBox=shortItem.boundingBox;sp.mode=FYInlineDisplayModeShortLabel;FYInlineLayoutResult *prior=[FYInlineLayoutResult new];prior.placements=@[sp];cache.lastInlineLayoutResult=prior;cache.lastInlineLayoutContentKey=@"1:1|合成短文\n译文\n";cache.lastInlineLayoutGeometryKey=GeometryKey();cache.lastInlineLayoutBoxes=@[@(shortItem.boundingBox)];
    Check([cache hasMinorOCRJitterForItems:@[shortItem] contentKey:cache.lastInlineLayoutContentKey geometryKey:GeometryKey()],@"actual jitter gate accepts same confirmed layout");
    shortItem.boundingBox=CGRectOffset(shortItem.boundingBox,.001,0);Check([cache hasMinorOCRJitterForItems:@[shortItem] contentKey:cache.lastInlineLayoutContentKey geometryKey:GeometryKey()],@"two-decimal bucket crossing remains minor jitter relative to actual last layout");
    shortItem.boundingBox=CGRectOffset(shortItem.boundingBox,.0021,0);Check(![cache hasMinorOCRJitterForItems:@[shortItem] contentKey:cache.lastInlineLayoutContentKey geometryKey:GeometryKey()],@"cumulative slow movement is compared to last actual layout instead of prior skipped frame");
    shortItem.boundingBox=CGRectMake(.0049,.2,.2031,.04);Check(![cache hasMinorOCRJitterForItems:@[shortItem] contentKey:cache.lastInlineLayoutContentKey geometryKey:GeometryKey()],@"width movement also rejects jitter beyond original bound");
    shortItem.boundingBox=CGRectMake(.0059,.2,.2,.04); // Independent key gates need otherwise-valid geometry.
    Check(![cache hasMinorOCRJitterForItems:@[shortItem] contentKey:@"changed" geometryKey:GeometryKey()]&&![cache hasMinorOCRJitterForItems:@[shortItem] contentKey:cache.lastInlineLayoutContentKey geometryKey:@"changed"]&&![cache hasMinorOCRJitterForItems:@[] contentKey:cache.lastInlineLayoutContentKey geometryKey:GeometryKey()],@"content/style/target/viewport keys and source count independently block jitter reuse");
    shortItem.boundingBox=CGRectMake(.0059,.2,.2,.04);cache.inlineLongCardPanels=[NSMutableArray arrayWithObject:(NSPanel *)switched];cache.inlineGeometryPending=YES;cache.debugContext=@{@"synthetic":@1};[cache.events removeAllObjects];
    [cache showInlineTranslations:@[@" 译文 "] forItems:@[shortItem] placementRect:CGRectMake(0,0,800,600)];
    Check([cache.lastDebugReason isEqual:@"cache_minor_ocr_jitter"]&&cache.lastInlineLayoutResult==prior&&cache.engineReads==1&&cache.badgeUpdates==1&&cache.blockReads==1&&cache.frameReads==1,@"real cache path uses original helper/config getters and stable-ID/badge update without layout/factory");
    Check([cache.events isEqual:@[@"badge",@"layout_debug",@"expanded",@"visibility"]]&&cache.debugReads==2&&[cache.lastInlineLayoutDebugContext isEqual:cache.debugContext],@"jitter cache retains debug-context two reads,expanded/visibility order and no panel recreation");
    Check(cache.lastInlineRenderedItems.firstObject==shortItem&&[cache.lastInlineRenderedTranslations isEqual:@[@" 译文 "]]&&NSEqualRects(cache.lastInlineLayoutBoxes.firstObject.rectValue,CGRectMake(.0049,.2,.2,.04))&&!cache.inlineGeometryPending,@"skipped frame remembers original new items but never advances actual-layout jitter baseline");
    cache.lastInlineTranslationKey=[[cache inlineTranslationIdentityForTranslations:@[@"译文"] forItems:@[shortItem]]stringByAppendingString:GeometryKey()];cache.lastInlineLayoutContentKey=@"force non-jitter";[cache.events removeAllObjects];[cache showInlineTranslations:@[@"译文"] forItems:@[shortItem] placementRect:CGRectMake(0,0,800,600)];Check([cache.lastDebugReason isEqual:@"cache_identical_input"]&&cache.badgeUpdates==1,@"exact identity cache remains independent of minor-jitter cache");
    NSUInteger before=cache.engineReads;cache.inlineDraggingPanel=(NSPanel *)switched;[cache showInlineTranslations:@[@"new"] forItems:@[shortItem] placementRect:CGRectMake(0,0,800,600)];Check(cache.engineReads==before&&[cache.lastInlineRenderedTranslations isEqual:@[@"译文"]],@"active drag guard precedes render snapshot and configuration work");cache.inlineDraggingPanel=nil;
    [cache showInlineTranslations:@[@"new"] forItems:@[shortItem] placementRect:CGRectMake(0,0,1,600)];Check(cache.engineReads==before,@"invalid viewport guard precedes all native/configuration calls");
    __weak FYInlineDisplayFrame *weakFrame;__weak DisplayItem *weakItem;@autoreleasepool{DisplayItem *owned=Item(@"owned",@"合成寿命",NO);weakItem=owned;FYInlineDisplayFrame *ownedFrame=Frame(@[],@[owned]);weakFrame=ownedFrame;Check(ownedFrame.items.firstObject==owned,@"frame holds original input for its synchronous operation");}Check(!weakFrame&&!weakItem,@"completed immutable frame releases source without idle context retention");
    __weak DisplayProbe *weakReceiver;FYInlineDisplayCoordinator *kept;@autoreleasepool{DisplayProbe *temporary=[DisplayProbe new];weakReceiver=temporary;kept=temporary;}Check(weakReceiver==kept,@"coordinator object is itself original receiver, without paired algorithm object");kept=nil;Check(!weakReceiver,@"idle coordinator/native boundary does not retain itself");
#ifdef FY_DISPLAY_NATIVE_MEASUREMENT
    DisplayProbe *native=[DisplayProbe new];native.configuration=[FYInlineLayoutEngine defaultEngine];DisplayItem *actual=Item(@"native",@"合成原生字段",NO);actual.boundingBox=CGRectMake(.2,.3,.2,.04);actual.nativeFrame=CGRectMake(200,200,160,30);
    [native showInlineTranslations:@[@"真实原生度量"] forItems:@[actual] placementRect:CGRectMake(0,0,800,600)];Check(native.lastInlineLayoutResult.placements.count==1&&native.inlinePanelsByBlockID.count==1&&native.engineReads==2,@"fresh production display pipeline invokes actual native calculator and retains original two engine getters");
    FYInlinePlacement *actualPlacement=native.lastInlineLayoutResult.placements.firstObject;Check(actualPlacement.font&&actualPlacement.paragraphStyle&&actualPlacement.measuredContentHeight>0&&CGRectContainsRect(CGRectMake(0,0,800,600),actualPlacement.translationFrame),@"actual native text/layout feeds valid measured placement,without fake glyph metrics");
    NSPanel *same=native.inlinePanelsByBlockID[actualPlacement.blockID];[native showInlineTranslations:@[@"真实原生度量"] forItems:@[actual] placementRect:CGRectMake(0,0,800,600)];Check(native.inlinePanelsByBlockID[actualPlacement.blockID]==same&&((PanelFact *)same).updates==0,@"native measured result is reused through production cache without rebuilding");
    [native showInlineTranslations:@[@"真实原生度量"] forItems:@[actual] placementRect:CGRectMake(10,0,800,600)];Check(native.inlinePanelsByBlockID.count==1&&native.engineReads==5&&[native.lastDebugReason isEqual:@"geometry_or_style_changed"],@"native viewport change rebuilds layout through actual calculator even with identical content");
#endif
    printf("PASS InlineDisplayCoordinatorTests: %lu checks; actual cache/commit/reuse decisions,canonical identities,state ownership,lifetime%s\n",(unsigned long)checks,
#ifdef FY_DISPLAY_NATIVE_MEASUREMENT
    " and real native calculation"
#else
    "; premeasured commit inputs,no layout/measurement replacement"
#endif
    );
}return 0;}
