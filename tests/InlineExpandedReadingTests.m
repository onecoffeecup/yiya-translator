#import "presentation/FYInlineExpandedReadingController.h"
#import "FYInlineLayout.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface ReadingFooterFact : NSObject
@property(nonatomic,getter=isHidden) BOOL hidden;
@end
@implementation ReadingFooterFact @end
@interface ReadingLabelFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic) BOOL flipped,textField;
@property(nonatomic,copy) NSString *stringValue;
@end
@implementation ReadingLabelFact
- (BOOL)isFlipped{return self.flipped;}
- (BOOL)isKindOfClass:(Class)c{return c==NSTextField.class?self.textField:[super isKindOfClass:c];}
@end
@interface ReadingClipFact : NSObject
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGPoint scrolledPoint;
@end
@implementation ReadingClipFact
- (void)scrollToPoint:(CGPoint)p{self.scrolledPoint=p;_bounds.origin=p;}
@end
@interface ReadingScrollFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic,strong) ReadingLabelFact *documentView;
@property(nonatomic,strong) ReadingClipFact *contentView;
@property(nonatomic) NSUInteger reflects;
@end
@implementation ReadingScrollFact
- (BOOL)isKindOfClass:(Class)c{return c==NSScrollView.class?YES:[super isKindOfClass:c];}
- (void)reflectScrolledClipView:(id)clip{self.reflects++;}
@end
@interface ReadingCardFact : NSObject
@property(nonatomic,strong) NSArray *subviews;
@property(nonatomic,strong) ReadingFooterFact *expandedFooterLabel;
@property(nonatomic) BOOL longCard,needsDisplay;
@property(nonatomic,copy) void (^onCollapse)(void);
@property(nonatomic) NSUInteger installs;
@end
@implementation ReadingCardFact
- (BOOL)isKindOfClass:(Class)c{return c==FYInlineLongCardView.class?self.longCard:[super isKindOfClass:c];}
- (void)installCollapseControl{self.installs++;}
@end
@interface ReadingPanelFact : NSObject
@property(nonatomic,strong) ReadingCardFact *contentView;
@property(nonatomic) CGRect frame;
@property(nonatomic) BOOL display;
@property(nonatomic) NSUInteger frameWrites,closes,fronts;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@end
@implementation ReadingPanelFact
- (void)setFrame:(CGRect)f display:(BOOL)d{_frame=f;self.display=d;self.frameWrites++;[self.trace addObject:@"frame"];}
- (void)close{self.closes++;[self.trace addObject:@"panel-close"];}
- (void)orderFrontRegardless{self.fronts++;[self.trace addObject:@"front"];}
@end
@interface ReadingEventFact : NSObject
@property(nonatomic) unsigned short keyCode;
@end
@implementation ReadingEventFact @end
@interface ReadingFacts : NSObject <FYInlineExpandedReadingSource>
@property(nonatomic,strong) FYInlineExpandedReadingController *owner;
@property(nonatomic,strong) FYInlineLayoutEngine *inlineLayoutEngine;
@property(nonatomic,strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic,strong) ReadingPanelFact *factoryPanel;
@property(nonatomic,strong) FYInlinePlacement *lastMeasured;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic) CGRect viewport;
@property(nonatomic) CGFloat measuredHeight,appliedHeight;
@property(nonatomic) BOOL hasViewport,skipRefresh,restoreMonitor;
@property(nonatomic) NSUInteger measures,hidden,restored,monitors,removed,drags;
@property(nonatomic,copy) NSEvent *(^escape)(NSEvent *);
@end
@implementation ReadingFacts
@dynamic inlineExpandedReadingPanel,inlineExpandedReadingKeyMonitor,inlineExpandedReadingBlockID,inlineExpandedMissingFrames;
- (NSPanel *)inlineExpandedReadingPanel{return self.owner.inlineExpandedReadingPanel;}
- (void)setInlineExpandedReadingPanel:(NSPanel *)v{self.owner.inlineExpandedReadingPanel=v;}
- (id)inlineExpandedReadingKeyMonitor{return self.owner.inlineExpandedReadingKeyMonitor;}
- (void)setInlineExpandedReadingKeyMonitor:(id)v{self.owner.inlineExpandedReadingKeyMonitor=v;}
- (NSString *)inlineExpandedReadingBlockID{return self.owner.inlineExpandedReadingBlockID;}
- (void)setInlineExpandedReadingBlockID:(NSString *)v{self.owner.inlineExpandedReadingBlockID=v;}
- (NSUInteger)inlineExpandedMissingFrames{return self.owner.inlineExpandedMissingFrames;}
- (void)setInlineExpandedMissingFrames:(NSUInteger)v{self.owner.inlineExpandedMissingFrames=v;}
- (BOOL)inlinePlacementRect:(CGRect *)r reason:(NSString **)reason{Check(reason==NULL,@"open preserves NULL reason");if(r)*r=self.viewport;return self.hasViewport;}
- (CGSize)expandedInlineReadingSizeForTranslation:(NSString *)t viewport:(CGRect)v{return [self.owner expandedInlineReadingSizeForTranslation:t viewport:v source:self];}
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(CGRect)f translation:(NSString *)t expandedReading:(BOOL)e{
 Check(e,@"actual measured-placement boundary keeps expanded flag");self.measures++;FYInlinePlacement *p=[FYInlinePlacement new];p.translationFrame=f;p.measuredContentHeight=self.measuredHeight;p.panelPadding=18;p.titleBandHeight=24;p.bodyViewportFrame=CGRectMake(2,3,150,100);self.lastMeasured=p;return p;
}
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)t item:(OCRTextItem *)item frame:(CGRect)f placement:(FYInlinePlacement *)p{self.factoryPanel.frame=f;[self.trace addObject:@"factory"];return (NSPanel *)self.factoryPanel;}
- (void)hideOtherInlinePanelsForExpandedReading:(NSPanel *)p{self.hidden++;[self.trace addObject:@"hide"];}
- (void)refreshExpandedInlineReadingCardAppearanceInRect:(CGRect)v{[self.trace addObject:@"refresh"];if(!self.skipRefresh)[self.owner refreshExpandedInlineReadingCardAppearanceInRect:v source:self];}
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)p{self.drags++;[self.trace addObject:@"drag"];}
- (void)applyInlineLongCardBody:(NSString *)t toLabel:(NSTextField *)l cardWidth:(CGFloat)w placement:(FYInlinePlacement *)p{((ReadingLabelFact *)l).frame=CGRectMake(0,0,w,self.appliedHeight);[self.trace addObject:@"body"];}
- (void)closeExpandedInlineReadingCard{[self.owner closeExpandedInlineReadingCardWithSource:self];}
- (void)restoreOtherInlinePanelsAfterExpandedReading{self.restored++;[self.trace addObject:@"restore"];if(self.restoreMonitor)self.inlineExpandedReadingKeyMonitor=@"reentrant-monitor";}
- (id)installInlineExpandedReadingMonitorWithHandler:(NSEvent *(^)(NSEvent *))handler{self.monitors++;self.escape=handler;[self.trace addObject:@"monitor"];return [NSObject new];}
- (void)removeInlineExpandedReadingMonitor:(id)m{self.removed++;[self.trace addObject:@"remove"];self.escape=nil;}
@end
static ReadingFacts *Facts(void){ReadingFacts *f=[ReadingFacts new];f.owner=[FYInlineExpandedReadingController new];f.inlineLayoutEngine=[FYInlineLayoutEngine new];f.inlineLayoutEngine.cardMaxWidth=320;f.inlineLayoutEngine.cardMaxHeight=300;f.viewport=CGRectMake(0,0,600,500);f.hasViewport=YES;f.measuredHeight=180;f.appliedHeight=400;f.trace=[NSMutableArray new];f.lastInlineLayoutResult=[FYInlineLayoutResult new];ReadingPanelFact *p=[ReadingPanelFact new];p.trace=f.trace;p.contentView=[ReadingCardFact new];p.contentView.longCard=YES;p.contentView.expandedFooterLabel=[ReadingFooterFact new];p.contentView.expandedFooterLabel.hidden=YES;ReadingScrollFact *s=[ReadingScrollFact new];s.documentView=[ReadingLabelFact new];s.documentView.textField=YES;s.documentView.stringValue=@"synthetic";s.documentView.flipped=YES;s.documentView.frame=CGRectMake(0,0,200,300);s.contentView=[ReadingClipFact new];s.contentView.bounds=CGRectMake(0,30,150,80);p.contentView.subviews=@[s];f.factoryPanel=p;return f;}
static FYInlinePlacement *Known(NSString *identity,CGRect frame){FYInlinePlacement *p=[FYInlinePlacement new];p.blockID=identity;p.sourceFrame=frame;return p;}
int main(void){@autoreleasepool{
 Check(NSApp==nil,@"minimum expanded component tests create no application/view/window");ReadingFacts *f=Facts();unsigned int n=0;Ivar *v=class_copyIvarList(FYInlineExpandedReadingController.class,&n);free(v);Check(n==4&&!f.owner.inlineExpandedReadingPanel&&!f.owner.inlineExpandedReadingKeyMonitor&&!f.owner.inlineExpandedReadingBlockID&&!f.owner.inlineExpandedMissingFrames,@"cold component has exactly original four zero states and no saved source");
 CGSize size=[f expandedInlineReadingSizeForTranslation:@"synthetic" viewport:f.viewport];Check(CGSizeEqualToSize(size,CGSizeMake(320,256)),@"size uses original measured content/padding/title/footer sum and caps");f.inlineLayoutEngine.cardMaxWidth=160.9;f.inlineLayoutEngine.cardMaxHeight=199.9;size=[f expandedInlineReadingSizeForTranslation:@"synthetic" viewport:CGRectMake(0,0,100,90)];Check(CGSizeEqualToSize(size,CGSizeMake(76,66)),@"small viewport wins over160 minima and floors exact limits");f.inlineLayoutEngine.cardMaxWidth=320;f.inlineLayoutEngine.cardMaxHeight=300;
 f.inlineExpandedReadingPanel=(NSPanel *)f.factoryPanel;f.factoryPanel.frame=CGRectMake(100.25,150.5,200.5,200.5);f.factoryPanel.contentView.expandedFooterLabel.hidden=NO;[f.owner refreshExpandedInlineReadingCardAppearanceInRect:f.viewport source:f];ReadingScrollFact *scroll=f.factoryPanel.contentView.subviews[0];
 Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(41,95,320,256))&&!f.factoryPanel.display,@"appearance keeps round midpoint/top anchoring and display:NO");Check(CGRectEqualToRect(scroll.frame,CGRectMake(2,3,150,84))&&CGPointEqualToPoint(scroll.contentView.scrolledPoint,CGPointMake(0,30))&&scroll.reflects==1&&!f.factoryPanel.contentView.expandedFooterLabel.hidden&&f.factoryPanel.contentView.needsDisplay,@"appearance uses original body16pt/footer/scroll restoration and invalidation");NSUInteger writes=f.factoryPanel.frameWrites;[f.owner refreshExpandedInlineReadingCardAppearanceInRect:f.viewport source:f];Check(f.factoryPanel.frameWrites==writes,@"unchanged appearance target avoids frame update");
 scroll.documentView.flipped=NO;scroll.documentView.frame=CGRectMake(0,0,320,400);scroll.contentView.bounds=CGRectMake(0,30,150,80);f.appliedHeight=500;[f.owner refreshExpandedInlineReadingCardAppearanceInRect:f.viewport source:f];Check(scroll.contentView.scrolledPoint.y==130,@"unflipped body preserves actual distance from top after height changes");
 NSUInteger measures=f.measures;[f.owner refreshExpandedInlineReadingCardAppearanceInRect:CGRectMake(0,0,1,200) source:f];Check(f.measures==measures,@"invalid viewport refresh short-circuits before measuring");f.factoryPanel.contentView.longCard=NO;[f.owner refreshExpandedInlineReadingCardAppearanceInRect:f.viewport source:f];Check(f.measures==measures,@"non-card refresh returns before native scroll reads");f.factoryPanel.contentView.longCard=YES;scroll.documentView.textField=NO;[f.owner refreshExpandedInlineReadingCardAppearanceInRect:f.viewport source:f];Check(f.measures==measures,@"non-text document refresh returns before measuring");scroll.documentView.textField=YES;
 f.factoryPanel.frame=CGRectMake(-5.2,450.2,400.2,200.2);[f.owner repositionExpandedInlineReadingCardInRect:CGRectMake(10,20,300,200) source:f];Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(22,32,276,180))&&f.factoryPanel.display,@"reposition uses240/180 minima,12 inset,integral frame and display:YES");writes=f.factoryPanel.frameWrites;[f.owner repositionExpandedInlineReadingCardInRect:CGRectMake(10,20,300,200) source:f];Check(f.factoryPanel.frameWrites==writes,@"reposition compares target with second original frame read");
 f.skipRefresh=YES;f.lastInlineLayoutResult.placements=@[Known(@"stable",CGRectMake(70,350,180,30))];OCRTextItem *item=[OCRTextItem new];item.text=@"synthetic source";[f.trace removeAllObjects];[f.owner openFullInlineReadingCardForItem:item translation:@"synthetic" stableBlockID:@"stable" source:f];Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(70,86,320,256)),@"open matches stable original frame and prefers8pt below");Check([f.inlineExpandedReadingBlockID isEqual:@"stable"]&&!f.inlineExpandedMissingFrames&&f.factoryPanel.contentView.installs==1&&f.drags==1&&f.monitors==1&&f.factoryPanel.fronts==1,@"open sets original identity/state,collapse,drag,monitor/front");Check([[f.trace componentsJoinedByString:@","]isEqual:@"panel-close,restore,factory,hide,refresh,drag,front,monitor"],@"open preserves close/restore/factory/hide/refresh/drag/front/monitor order");
 ReadingEventFact *event=[ReadingEventFact new];event.keyCode=42;Check(f.escape((NSEvent *)event)==(NSEvent *)event,@"non-Esc event returned unchanged");event.keyCode=53;Check(f.escape((NSEvent *)event)==nil&&!f.inlineExpandedReadingPanel&&!f.inlineExpandedReadingKeyMonitor&&f.removed==1,@"Esc consumed and original monitor/panel lifecycle cleared");
 f.lastInlineLayoutResult.placements=@[Known(@"stable",CGRectMake(500,20,20,10))];[f.owner openFullInlineReadingCardForItem:item translation:@"synthetic" stableBlockID:@"stable" source:f];Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(268,38,320,256)),@"insufficient space below chooses above and clamps horizontal edge");f.factoryPanel.contentView.onCollapse();Check(!f.inlineExpandedReadingPanel,@"copied collapse invokes concrete source close");
 f.lastInlineLayoutResult.placements=@[Known(@"stable",CGRectMake(70,100,180,400))];[f.owner openFullInlineReadingCardForItem:item translation:@"synthetic" stableBlockID:@"stable" source:f];Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(70,122,320,256)),@"neither vertical side fits retains centered y while source x anchors");
 f.lastInlineLayoutResult.placements=@[Known(@"other",CGRectMake(70,350,180,30))];[f.owner openFullInlineReadingCardForItem:item translation:@"synthetic" stableBlockID:@"stable" source:f];Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(140,122,320,256)),@"other identity does not supply source anchor");
 f.inlineExpandedMissingFrames=9;f.lastInlineLayoutResult.placements=@[Known(@"stable",CGRectZero)];[f.owner advanceExpandedReadingStateWithSource:f];Check(f.inlineExpandedMissingFrames==0&&f.inlineExpandedReadingPanel,@"present identity resets missing count irrespective placement mode/frame");f.lastInlineLayoutResult.placements=@[];NSUInteger hidden=f.hidden;[f.owner advanceExpandedReadingStateWithSource:f];Check(f.inlineExpandedMissingFrames==1&&f.inlineExpandedReadingPanel&&f.hidden==hidden+1,@"first missing frame keeps expanded card and hides others");[f.owner advanceExpandedReadingStateWithSource:f];Check(!f.inlineExpandedReadingPanel&&!f.inlineExpandedMissingFrames,@"second missing frame closes and returns before further hide");
 f.inlineExpandedReadingPanel=(NSPanel *)f.factoryPanel;f.inlineExpandedReadingBlockID=@"";f.lastInlineLayoutResult.placements=@[Known(@"",CGRectZero)];[f.owner advanceExpandedReadingStateWithSource:f];Check(f.inlineExpandedMissingFrames==1,@"empty ID never treated as present even when an empty placement exists");
 f.inlineExpandedReadingKeyMonitor=@"synthetic-monitor";[f.trace removeAllObjects];[f closeExpandedInlineReadingCard];Check([[f.trace componentsJoinedByString:@","]isEqual:@"remove,panel-close,restore"]&&!f.inlineExpandedReadingBlockID&&!f.inlineExpandedReadingKeyMonitor&&!f.inlineExpandedMissingFrames,@"close keeps remove/nil/panel close/clear/current-frame restore order");
 f.hasViewport=NO;NSUInteger restored=f.restored;[f.owner openFullInlineReadingCardForItem:item translation:@"synthetic" stableBlockID:@"stable" source:f];Check(f.restored==restored,@"unavailable placement returns before close");f.hasViewport=YES;ReadingPanelFact *kept=f.factoryPanel;f.factoryPanel=nil;NSUInteger monitors=f.monitors;[f.owner openFullInlineReadingCardForItem:item translation:@"synthetic" stableBlockID:@"stable" source:f];Check(!f.inlineExpandedReadingPanel&&f.monitors==monitors,@"nil native factory creates no monitor or expanded state");f.factoryPanel=kept;
 f.restoreMonitor=YES;monitors=f.monitors;[f.owner openFullInlineReadingCardForItem:item translation:@"synthetic" stableBlockID:@"stable" source:f];Check(f.monitors==monitors&&[f.inlineExpandedReadingKeyMonitor isEqual:@"reentrant-monitor"],@"monitor guard preserves reentrantly installed monitor");f.restoreMonitor=NO;[f closeExpandedInlineReadingCard];
 NSMutableString *identity=[@"copied" mutableCopy];f.inlineExpandedReadingBlockID=identity;[identity appendString:@"changed"];Check([f.inlineExpandedReadingBlockID isEqual:@"copied"],@"sole state retains original copy ID semantics");
 __weak ReadingFacts *weakSource;ReadingCardFact *retainedCard;NSEvent *(^retainedEscape)(NSEvent *);@autoreleasepool{ReadingFacts *q=Facts();q.skipRefresh=YES;weakSource=q;[q.owner openFullInlineReadingCardForItem:item translation:@"synthetic" stableBlockID:@"stable" source:q];retainedCard=q.factoryPanel.contentView;retainedEscape=[q.escape copy];}Check(!weakSource,@"collapse and Esc copied callbacks do not retain concrete source");retainedCard.onCollapse();event.keyCode=53;Check(retainedEscape((NSEvent *)event)==nil,@"late Esc callback still consumes Esc safely after source release");
 ReadingFacts *lease=Facts();__weak ReadingPanelFact *weakPanel;__weak NSObject *weakMonitor;
 @autoreleasepool{lease.inlineExpandedReadingPanel=(NSPanel *)lease.factoryPanel;weakPanel=lease.factoryPanel;lease.factoryPanel=nil;NSObject *marker=[NSObject new];weakMonitor=marker;lease.inlineExpandedReadingKeyMonitor=marker;}
 @autoreleasepool{Check(weakPanel&&weakMonitor,@"sole owner strongly holds original panel and monitor leases");[lease closeExpandedInlineReadingCard];}
 Check(!weakPanel&&!weakMonitor,@"actual close releases panel and monitor after native call temporaries drain");
 Check(NSApp==nil,@"all production expanded algorithms remain headless with synthetic UI boundary facts");printf("PASS InlineExpandedReadingTests: %lu checks;real expanded algorithms,synthetic native facts,no UI objects\n",(unsigned long)checks);
}return 0;}
