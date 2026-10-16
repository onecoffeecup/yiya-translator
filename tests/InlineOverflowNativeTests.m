#import "FYInlineOverflowTestFacts.h"
#import "presentation/FYInlineOverflowController.h"
#import "presentation/FYFlippedDocumentView.h"
#import "FYInlineLayout.h"
@interface OverflowLabelFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic,copy) NSString *stringValue;
@end
@implementation OverflowLabelFact
- (BOOL)isKindOfClass:(Class)c{return c==NSTextField.class?YES:[super isKindOfClass:c];}
@end
@interface OverflowCardFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic) CGFloat titleBarHeight;
@property(nonatomic,strong) NSArray *subviews;
@property(nonatomic,copy) void (^onClick)(void);
@end
@implementation OverflowCardFact
- (BOOL)isKindOfClass:(Class)c{return c==FYInlineLongCardView.class?YES:[super isKindOfClass:c];}
@end
@interface OverflowPanelFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic,getter=isVisible) BOOL visible;
@property(nonatomic) BOOL ignoresMouseEvents,display;
@property(nonatomic) NSUInteger writes,closes,displays;
@property(nonatomic,strong) OverflowCardFact *contentView;
@property(nonatomic,strong) NSMutableArray *trace;
@end
@implementation OverflowPanelFact
- (void)setFrame:(CGRect)f display:(BOOL)d{_frame=f;self.display=d;self.writes++;}
- (void)displayIfNeeded{self.displays++;}
- (void)close{self.closes++;[self.trace addObject:@"panel-close"];}
@end
@interface OverflowMeasuredEngineFact : NSObject
@property(nonatomic) CGFloat viewportMargin;
@property(nonatomic) CGSize measuredSize;
@property(nonatomic,copy) NSString *lastTitle;
@end
@implementation OverflowMeasuredEngineFact
- (CGSize)foldedEntrySizeForViewport:(CGRect)v title:(NSString *)t hint:(NSString *)h action:(NSString *)a{Check(h.length==0&&a.length==0,@"native entry requests original single-line measurement without hint/action");self.lastTitle=t;return self.measuredSize;}
@end
@interface OverflowNativeFacts : OverflowPolicyFacts <FYInlineOverflowNativeSource>
@property(nonatomic,strong) OverflowMeasuredEngineFact *measurement;
@property(nonatomic,strong) OverflowPanelFact *factoryPanel;
@property(nonatomic,strong) FYInlinePlacement *factoryPlacement;
@property(nonatomic,strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic,strong) NSPanel *captionPanel;
@property(nonatomic,strong) NSArray<NSPanel *> *panels;
@property(nonatomic) NSUInteger removed;
@end
@implementation OverflowNativeFacts
- (instancetype)init{if((self=[super init])){self.owner=[FYInlineOverflowController new];self.measurement=[OverflowMeasuredEngineFact new];self.measurement.measuredSize=CGSizeMake(200,44);self.lastInlineLayoutResult=[FYInlineLayoutResult new];self.panels=@[];self.factoryPanel=[OverflowPanelFact new];self.factoryPanel.trace=self.trace;self.factoryPanel.contentView=[OverflowCardFact new];OverflowLabelFact *label=[OverflowLabelFact new];label.frame=CGRectMake(10,12,180,20);self.factoryPanel.contentView.subviews=@[label];}return self;}
- (NSPanel *)inlineOverflowPanel{return ((FYInlineOverflowController *)self.owner).inlineOverflowPanel;}
- (void)setInlineOverflowPanel:(NSPanel *)p{((FYInlineOverflowController *)self.owner).inlineOverflowPanel=p;}
- (NSPanel *)inlineOverflowChoicePanel{return ((FYInlineOverflowController *)self.owner).inlineOverflowChoicePanel;}
- (void)setInlineOverflowChoicePanel:(NSPanel *)p{((FYInlineOverflowController *)self.owner).inlineOverflowChoicePanel=p;}
- (id)inlineOverflowChoiceKeyMonitor{return ((FYInlineOverflowController *)self.owner).inlineOverflowChoiceKeyMonitor;}
- (void)setInlineOverflowChoiceKeyMonitor:(id)p{((FYInlineOverflowController *)self.owner).inlineOverflowChoiceKeyMonitor=p;}
- (FYInlineLayoutEngine *)inlineLayoutEngine{return (FYInlineLayoutEngine *)self.measurement;}
- (NSArray<NSPanel *> *)allInlineOverlayPanels{return self.panels;}
- (BOOL)inlinePlacementRect:(NSRect *)r reason:(NSString **)reason{if(r)*r=CGRectMake(0,0,400,300);return YES;}
- (NSTextField *)label:(NSString *)t font:(NSFont *)f color:(NSColor *)c{return nil;}
- (NSTextField *)mutedLabel:(NSString *)t{return nil;}
- (void)applyInlineChromeToContent:(NSView *)v cornerRadius:(CGFloat)r{}
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)t item:(OCRTextItem *)item frame:(NSRect)frame placement:(FYInlinePlacement *)p{Check(t.length==0&&item==nil,@"entry factory keeps empty translation/nil item");self.factoryPlacement=p;self.factoryPanel.frame=frame;return (NSPanel *)self.factoryPanel;}
- (id)inlineOverflowActionTarget{return nil;}
- (NSString *)overflowRowTitleForEntry:(NSDictionary *)entry{return [self.owner overflowRowTitleForEntry:entry];}
- (void)showInlineOverflowChooser{[self.owner showInlineOverflowChooserWithSource:self];}
- (NSColor *)inlineOverflowChooserInkColor{return nil;}
- (NSColor *)inlineOverflowChooserCreamColor{return nil;}
- (NSColor *)inlineOverflowChooserLineColor{return nil;}
- (id)installInlineOverflowMonitorWithHandler:(NSEvent *(^)(NSEvent *))h{Check(NO,@"native >1 UI construction is never executed in headless facts");return nil;}
- (void)removeInlineOverflowMonitor:(id)m{self.removed++;[self.trace addObject:@"remove"];}
- (void)closeInlineOverflowChoice{[(FYInlineOverflowController *)self.owner closeInlineOverflowChoiceWithSource:self];}
@end
int main(void){@autoreleasepool{
 Check(NSApp==nil,@"native facts tests create no application/window/view/control");OverflowNativeFacts *f=[OverflowNativeFacts new];FYInlineOverflowController *native=(FYInlineOverflowController *)f.owner;unsigned int n=0;Ivar *ivars=class_copyIvarList(FYInlineOverflowController.class,&n);free(ivars);Check(n==3&&!native.inlineOverflowPanel&&!native.inlineOverflowChoicePanel&&!native.inlineOverflowChoiceKeyMonitor,@"native owner adds exactly original three zero resource fields to pure policy");
 f.inlineOverflowPanel=(NSPanel *)f.factoryPanel;f.factoryPanel.frame=CGRectMake(0,0,200,44);[native positionInlineOverflowEntryInViewport:CGRectMake(0,0,400,300) source:f];Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(8,8,200,44))&&!f.factoryPanel.display&&f.factoryPanel.writes==1,@"first zero-overlap corner selected with8pt margin/display:NO");[native positionInlineOverflowEntryInViewport:CGRectMake(0,0,400,300) source:f];Check(f.factoryPanel.writes==1,@"same native position avoids frame write");OverflowPanelFact *obstacle=[OverflowPanelFact new];obstacle.visible=YES;obstacle.frame=CGRectMake(8,8,200,44);f.panels=@[(NSPanel *)f.factoryPanel,(NSPanel *)obstacle];[native positionInlineOverflowEntryInViewport:CGRectMake(0,0,400,300) source:f];Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(8,248,200,44)),@"candidate ordering evaluates bottom-right overlap then top-left clear");obstacle.visible=NO;[native positionInlineOverflowEntryInViewport:CGRectMake(0,0,400,300) source:f];Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(8,8,200,44)),@"invisible panel excluded and self panel ignored");NSUInteger writes=f.factoryPanel.writes;[native positionInlineOverflowEntryInViewport:CGRectMake(0,0,1,300) source:f];Check(f.factoryPanel.writes==writes,@"narrow viewport returns before reposition");
 f.panels=@[];FYInlinePlacement *p=[FYInlinePlacement new];p.translationFrame=CGRectMake(8,8,200,44);p.sourceFrame=CGRectMake(192,8,200,44);f.lastInlineLayoutResult.placements=@[p];[native positionInlineOverflowEntryInViewport:CGRectMake(0,0,400,300) source:f];Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(8,248,200,44)),@"both current translation/source rectangles remain native obstacles");f.lastInlineLayoutResult.placements=@[];f.factoryPanel.frame=CGRectMake(0,0,200.3,44.3);[native positionInlineOverflowEntryInViewport:CGRectMake(.2,.2,400.1,300.1) source:f];Check(CGRectEqualToRect(f.factoryPanel.frame,CGRectMake(8,8,201,45)),@"candidate uses original NSIntegralRect outward rounding");
 f.inlineOverflowCount=0;[native buildInlineOverflowEntryForViewport:CGRectMake(0,0,400,300) source:f];Check([f.measurement.lastTitle isEqual:@"还有 1 条译文 · 查看"]&&native.inlineOverflowPanel==(NSPanel *)f.factoryPanel&&!f.factoryPanel.ignoresMouseEvents&&f.factoryPanel.contentView.titleBarHeight==0&&f.factoryPanel.contentView.onClick,@"native build preserves minimum title/compact entry/no drag/weak click");Check(f.factoryPlacement.mode==FYInlineDisplayModeCompactEntry&&f.factoryPlacement.compactEntry&&f.factoryPlacement.panelPadding==10&&f.factoryPlacement.cornerRadius==8&&[f.factoryPlacement.entryHint isEqual:@""]&&[f.factoryPlacement.entryAction isEqual:@""],@"entry placement keeps original mode/padding/radius/empty optional lines");
 OCRTextItem *item=[OCRTextItem new];item.text=@"synthetic";f.inlineOverflowEntries=@[@{@"item":item,@"translation":@"translation",@"blockID":@"stable"}];f.factoryPanel.contentView.onClick();Check(f.openedItem==item&&[f.openedID isEqual:@"stable"],@"real weak entry click delegates actual single-entry policy");
 f.measurement.measuredSize=CGSizeMake(220,48);[native resizeInlineOverflowEntryWithTitle:@"title" viewport:CGRectMake(0,0,400,300) source:f];OverflowLabelFact *label=f.factoryPanel.contentView.subviews[0];Check(CGSizeEqualToSize(f.factoryPanel.frame.size,CGSizeMake(220,48))&&!f.factoryPanel.display&&CGRectEqualToRect(f.factoryPanel.contentView.frame,CGRectMake(0,0,220,48))&&CGRectEqualToRect(label.frame,CGRectMake(10,12,200,20))&&[label.stringValue isEqual:@"title"]&&f.factoryPanel.displays==1,@"real native resize preserves measured frame/card/label/title/display order");
 OverflowPanelFact *choice=[OverflowPanelFact new];choice.trace=f.trace;f.inlineOverflowChoicePanel=(NSPanel *)choice;f.inlineOverflowChoiceKeyMonitor=[NSObject new];[f.trace removeAllObjects];[native closeInlineOverflowChoiceWithSource:f];Check([[f.trace componentsJoinedByString:@","]isEqual:@"remove,panel-close"]&&f.removed==1&&!f.inlineOverflowChoicePanel&&!f.inlineOverflowChoiceKeyMonitor&&choice.closes==1,@"native choice close removes monitor before panel close and clears sole fields");[native closeInlineOverflowChoiceWithSource:f];Check(f.removed==1&&choice.closes==1,@"empty repeated choice close has no monitor/panel actions");
 __weak OverflowNativeFacts *weakSource;OverflowCardFact *kept;@autoreleasepool{OverflowNativeFacts *q=[OverflowNativeFacts new];weakSource=q;[(FYInlineOverflowController *)q.owner buildInlineOverflowEntryForViewport:CGRectMake(0,0,400,300) source:q];kept=q.factoryPanel.contentView;}Check(!weakSource,@"native copied entry callback does not retain concrete source");kept.onClick();
 OverflowNativeFacts *lease=[OverflowNativeFacts new];__weak OverflowPanelFact *weakChoice;__weak NSObject *weakMonitor;@autoreleasepool{OverflowPanelFact *q=[OverflowPanelFact new];q.trace=lease.trace;weakChoice=q;lease.inlineOverflowChoicePanel=(NSPanel *)q;NSObject *marker=[NSObject new];weakMonitor=marker;lease.inlineOverflowChoiceKeyMonitor=marker;}@autoreleasepool{Check(weakChoice&&weakMonitor,@"sole native owner keeps strong choice panel/monitor leases");[(FYInlineOverflowController *)lease.owner closeInlineOverflowChoiceWithSource:lease];}Check(!weakChoice&&!weakMonitor,@"native close releases both resource leases after call temporaries drain");
 Method flipped=class_getInstanceMethod(FlippedDocumentView.class,@selector(isFlipped));BOOL (*isFlipped)(id,SEL)=(void *)method_getImplementation(flipped);Check(isFlipped(nil,@selector(isFlipped)),@"original shared flipped primitive returns YES without view construction");Check(NSApp==nil,@"all native checks remain headless; >1 chooser/events only compiled");printf("PASS InlineOverflowNativeTests: %lu checks;real native positioning/build/resize/close,premeasured boundary facts,no UI objects\n",(unsigned long)checks);
}return 0;}
