#import "presentation/FYInlineOverlayController.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface ExpandedHostPanelFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic) NSUInteger closes,writes;
@property(nonatomic) BOOL display;
@end
@implementation ExpandedHostPanelFact
- (void)close{self.closes++;}
- (void)setFrame:(CGRect)f display:(BOOL)d{_frame=f;self.display=d;self.writes++;}
@end
@interface ExpandedHostProbe : FYInlineOverlayController
@property(nonatomic,strong) FYInlineLayoutEngine *limits;
@property(nonatomic) CGFloat measuredHeight;
@property(nonatomic) NSUInteger measures,hidden,restored;
@property(nonatomic) BOOL expanded;
@end
@implementation ExpandedHostProbe
- (FYInlineLayoutEngine *)inlineLayoutEngine{return self.limits;}
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(NSRect)frame translation:(NSString *)t expandedReading:(BOOL)e{self.measures++;self.expanded=e;FYInlinePlacement *p=[FYInlinePlacement new];p.translationFrame=frame;p.measuredContentHeight=self.measuredHeight;p.panelPadding=18;p.titleBandHeight=24;return p;}
- (void)hideOtherInlinePanelsForExpandedReading:(NSPanel *)panel{self.hidden++;}
- (void)restoreOtherInlinePanelsAfterExpandedReading{self.restored++;}
@end
int main(void){@autoreleasepool{
 Check(NSApp==nil,@"original/extracted actual expanded host creates no UI or application");ExpandedHostProbe *p=[[ExpandedHostProbe alloc]initWithHost:nil];p.limits=[FYInlineLayoutEngine new];p.limits.cardMaxWidth=320;p.limits.cardMaxHeight=300;p.measuredHeight=180;
 NSSize size=[p expandedInlineReadingSizeForTranslation:@"synthetic" viewport:CGRectMake(0,0,600,500)];Check(NSEqualSizes(size,NSMakeSize(320,256))&&p.expanded&&p.measures==1,@"actual host uses original native placement helper and natural height");p.limits.cardMaxWidth=160.9;p.limits.cardMaxHeight=199.9;size=[p expandedInlineReadingSizeForTranslation:@"synthetic" viewport:CGRectMake(0,0,100,90)];Check(NSEqualSizes(size,NSMakeSize(76,66)),@"actual original/extracted host preserves viewport-first cap and floor");
 ExpandedHostPanelFact *panel=[ExpandedHostPanelFact new];panel.frame=CGRectMake(-5.2,450.2,400.2,200.2);p.inlineExpandedReadingPanel=(NSPanel *)panel;[p repositionExpandedInlineReadingCardInRect:CGRectMake(10,20,300,200)];Check(CGRectEqualToRect(panel.frame,CGRectMake(22,32,276,180))&&panel.display&&panel.writes==1,@"actual host preserves native reposition geometry/integral/display");[p repositionExpandedInlineReadingCardInRect:CGRectMake(10,20,300,200)];Check(panel.writes==1,@"actual unchanged target avoids second native write");[p repositionExpandedInlineReadingCardInRect:CGRectMake(0,0,1,200)];Check(panel.writes==1,@"actual narrow viewport early return preserves panel frame");
 p.inlineExpandedReadingBlockID=@"stable";p.inlineExpandedMissingFrames=7;p.lastInlineLayoutResult=[FYInlineLayoutResult new];FYInlinePlacement *known=[FYInlinePlacement new];known.blockID=@"stable";known.mode=FYInlineDisplayModeUnplaceable;p.lastInlineLayoutResult.placements=@[known];[p advanceExpandedReadingState];Check(p.inlineExpandedMissingFrames==0&&p.hidden==1&&p.inlineExpandedReadingPanel==(NSPanel *)panel,@"actual present ID resets history even in unplaceable result");
 p.lastInlineLayoutResult.placements=@[];[p advanceExpandedReadingState];Check(p.inlineExpandedMissingFrames==1&&p.hidden==2&&!panel.closes,@"actual first missing keeps panel and hides others");[p advanceExpandedReadingState];Check(!p.inlineExpandedReadingPanel&&!p.inlineExpandedReadingBlockID&&!p.inlineExpandedMissingFrames&&panel.closes==1&&p.restored==1&&p.hidden==2,@"actual second missing closes,resets,restores and returns");[p advanceExpandedReadingState];Check(p.restored==1&&p.hidden==2,@"actual absent panel advances no state or callbacks");
 p.inlineExpandedReadingPanel=(NSPanel *)panel;p.inlineExpandedReadingBlockID=@"";known.blockID=@"";p.lastInlineLayoutResult.placements=@[known];[p advanceExpandedReadingState];Check(p.inlineExpandedMissingFrames==1,@"actual empty current ID is not present even with empty known ID");[p closeExpandedInlineReadingCard];Check(panel.closes==2&&p.restored==2&&!p.inlineExpandedReadingPanel&&!p.inlineExpandedReadingBlockID&&!p.inlineExpandedMissingFrames,@"actual native close releases panel/ID/history before current-frame restoration");[p closeExpandedInlineReadingCard];Check(p.restored==3&&panel.closes==2,@"actual repeated close preserves restoration callback even without panel");
 NSMutableString *identity=[@"copied" mutableCopy];p.inlineExpandedReadingBlockID=identity;[identity appendString:@"changed"];Check([p.inlineExpandedReadingBlockID isEqual:@"copied"],@"actual compatibility keeps original copy block identity");
 Check(NSApp==nil,@"actual original/extracted expanded host stays headless;monitor and native UI separately compiled");printf("PASS InlineExpandedReadingHostTests: %lu checks;actual original/extracted native host,same fixture,no UI objects\n",(unsigned long)checks);
}return 0;}
