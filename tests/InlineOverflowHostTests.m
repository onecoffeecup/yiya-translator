#import "presentation/FYInlineOverlayController.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface OverflowHostLabelFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic,copy) NSString *stringValue;
@end
@implementation OverflowHostLabelFact
- (BOOL)isKindOfClass:(Class)c{return c==NSTextField.class?YES:[super isKindOfClass:c];}
@end
@interface OverflowHostCardFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic,strong) NSArray *subviews;
@end
@implementation OverflowHostCardFact @end
@interface OverflowHostPanelFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic,getter=isVisible) BOOL visible;
@property(nonatomic) BOOL ignoresMouseEvents;
@property(nonatomic,strong) OverflowHostCardFact *contentView;
@property(nonatomic) NSUInteger closes,fronts,writes;
@end
@implementation OverflowHostPanelFact
- (void)close{self.closes++;}
- (void)orderOut:(id)sender{self.visible=NO;}
- (void)orderFrontRegardless{self.visible=YES;self.fronts++;}
- (void)setFrame:(CGRect)f display:(BOOL)d{_frame=f;self.writes++;}
- (void)displayIfNeeded{}
@end
@interface OverflowHostMeasurement : NSObject
@property(nonatomic) CGFloat viewportMargin;
@property(nonatomic,copy) NSString *foldedEntryFallbackTitle;
@end
@implementation OverflowHostMeasurement
- (CGSize)foldedEntrySizeForViewport:(CGRect)v title:(NSString *)t hint:(NSString *)h action:(NSString *)a{return CGSizeMake(200,44);}
@end
@class OverflowHostProbe;
@interface OverflowHostPeer : NSObject
@property(nonatomic,weak) OverflowHostProbe *controller;
@property(nonatomic) NSUInteger expires;
@property(nonatomic,strong) NSPanel *captionPanel;
@end
@interface OverflowHostProbe : FYInlineOverlayController
@property(nonatomic,strong) OverflowHostMeasurement *measurement;
@property(nonatomic,strong) OverflowHostPanelFact *factoryPanel;
@property(nonatomic,strong) OCRTextItem *opened;
@property(nonatomic,strong) NSString *translation,*identity;
@property(nonatomic) NSUInteger builds,opens;
@end
@implementation OverflowHostPeer
- (void)expireInlineOverflowEntryIfNeeded{self.expires++;[self.controller expireInlineOverflowEntryIfNeeded];}
@end
@implementation OverflowHostProbe
- (FYInlineLayoutEngine *)inlineLayoutEngine{return (FYInlineLayoutEngine *)self.measurement;}
- (void)buildInlineOverflowEntryForViewport:(NSRect)v{self.builds++;self.inlineOverflowPanel=(NSPanel *)self.factoryPanel;}
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)t stableBlockID:(NSString *)identity{self.opens++;self.opened=item;self.translation=t;self.identity=identity;}
@end
@interface OverflowHostRowFact : NSObject
@property(nonatomic) NSInteger tag;
@end
@implementation OverflowHostRowFact @end
static FYInlinePlacement *Placement(NSString *identity,NSString *translation){FYInlinePlacement *p=[FYInlinePlacement new];p.blockID=identity;p.sourceBlockID=identity;p.mode=FYInlineDisplayModeUnplaceable;p.block=[FYInlineTextBlock new];p.block.text=identity;p.translation=translation;return p;}
int main(void){@autoreleasepool{
 Check(NSApp==nil,@"exact original/extracted overflow host is headless");OverflowHostPeer *peer=[OverflowHostPeer new];OverflowHostProbe *p=[[OverflowHostProbe alloc]initWithHost:(id<FYInlineOverlayControllerHost>)peer];peer.controller=p;p.measurement=[OverflowHostMeasurement new];p.factoryPanel=[OverflowHostPanelFact new];p.factoryPanel.frame=CGRectMake(0,0,200,44);p.factoryPanel.contentView=[OverflowHostCardFact new];OverflowHostLabelFact *label=[OverflowHostLabelFact new];label.frame=CGRectMake(10,12,180,20);p.factoryPanel.contentView.subviews=@[label];p.inlineTranslationPanels=[NSMutableArray new];p.inlineLongCardPanels=[NSMutableArray new];p.lastInlineLayoutResult=[FYInlineLayoutResult new];
 FYInlinePlacement *a=Placement(@"a",@"translation-a"),*b=Placement(@"b",@"translation-b");OCRTextItem *item=[OCRTextItem new];item.text=@"synthetic";NSRect viewport=CGRectMake(0,0,400,300);
 [p updateInlineOverflowEntryWithPlacements:@[a,b] items:@{@"a":item} viewport:viewport unplaceable:2];Check(p.builds==1&&p.inlineOverflowCount==2&&p.inlineOverflowPanelCount==2&&p.factoryPanel.visible&&!p.factoryPanel.ignoresMouseEvents,@"actual host builds/shows two-entry stable overflow");Check(p.inlineOverflowEntries[0][@"item"]==item&&p.inlineOverflowEntries[1][@"item"]==NSNull.null,@"actual host preserves source identity and original item/NSNull");Check(CGRectEqualToRect(p.factoryPanel.frame,CGRectMake(8,8,200,44)),@"actual host native geometry uses original first8pt corner");
 NSArray *old=p.inlineOverflowEntries;[p updateInlineOverflowEntryWithPlacements:@[a] items:@{} viewport:viewport unplaceable:1];Check(p.inlineOverflowEntries==old&&p.inlineOverflowCount==2&&p.inlineOverflowCandidateFrames==1,@"actual first count-change retains original list/count");[p updateInlineOverflowEntryWithPlacements:@[a] items:@{} viewport:viewport unplaceable:1];Check(p.inlineOverflowCount==1&&p.inlineOverflowPanelCount==1&&!p.inlineOverflowCandidateFrames&&[label.stringValue isEqual:@"还有 1 条译文 · 查看"],@"actual second frame adopts and updates real native resize/title algorithm");
 old=p.inlineOverflowEntries;p.inlineOverflowChoicePanel=(NSPanel *)[NSObject new];[p updateInlineOverflowEntryWithPlacements:@[a,b] items:@{} viewport:viewport unplaceable:2];Check(p.inlineOverflowEntries==old&&p.inlineOverflowCount==1,@"actual open chooser freezes original row list");p.inlineOverflowChoicePanel=nil;p.inlineExpandedReadingPanel=(NSPanel *)[NSObject new];[p updateInlineOverflowEntryWithPlacements:@[a,b] items:@{} viewport:viewport unplaceable:2];Check(p.inlineOverflowEntries==old&&!p.factoryPanel.visible&&p.factoryPanel.ignoresMouseEvents,@"actual expanded reading hides overflow without adopting entries");p.inlineExpandedReadingPanel=nil;
 [p updateInlineOverflowEntryWithPlacements:@[] items:@{} viewport:viewport unplaceable:0];NSTimeInterval since=p.inlineOverflowEmptySince;Check(since>0&&peer.expires==1&&p.inlineOverflowPanel,@"actual empty input records time and Host-directed expiry");[p updateInlineOverflowEntryWithPlacements:@[] items:@{} viewport:viewport unplaceable:0];Check(p.inlineOverflowEmptySince==since&&peer.expires==2,@"actual empty update keeps first timestamp");p.inlineOverflowEmptySince=[NSDate timeIntervalSinceReferenceDate]-2;[p expireInlineOverflowEntryIfNeeded];Check(!p.inlineOverflowPanel&&!p.inlineOverflowCount&&!p.inlineOverflowPanelCount&&!p.inlineOverflowCandidateFrames&&!p.inlineOverflowEmptySince&&p.inlineOverflowCandidateCount==1&&p.factoryPanel.closes==1,@"actual elapsed expiry clears original fields but leaves candidate count");
 Check([[p overflowRowTitleForEntry:@{@"title":@"title",@"source":@"first\nsecond"}]isEqual:@"title　（first）"],@"actual original/extracted title format/canonical shorten");p.inlineOverflowEntries=@[];[p showInlineOverflowChooser];Check(!p.opens,@"actual empty chooser closes then returns without UI");p.inlineOverflowEntries=@[@{@"item":item,@"translation":@"synthetic translation",@"blockID":@"stable"}];[p showInlineOverflowChooser];Check(p.opened==item&&[p.translation isEqual:@"synthetic translation"]&&[p.identity isEqual:@"stable"],@"actual single chooser opens original item/stable identity");
 p.inlineOverflowEntries=@[@{@"source":@"fallback source",@"translation":@"row",@"blockID":@"row-id"}];OverflowHostRowFact *row=[OverflowHostRowFact new];row.tag=-1;NSUInteger opens=p.opens;[p openInlineOverflowRow:(NSButton *)row];Check(p.opens==opens,@"actual negative tag guard");row.tag=1;[p openInlineOverflowRow:(NSButton *)row];Check(p.opens==opens,@"actual out-of-range tag guard");row.tag=0;[p openInlineOverflowRow:(NSButton *)row];Check([p.opened.text isEqual:@"fallback source"]&&p.opened.blockKind==InlineBlockKindLong&&CGRectEqualToRect(p.opened.boundingBox,CGRectZero)&&p.opened.lineBoxes.count==0&&[p.identity isEqual:@"row-id"],@"actual row fallback keeps synthetic item fields and identity");
 OverflowHostPanelFact *choice=[OverflowHostPanelFact new];p.inlineOverflowChoicePanel=(NSPanel *)choice;[p closeInlineOverflowChoice];Check(!p.inlineOverflowChoicePanel&&choice.closes==1,@"actual native choice close releases same panel with absent monitor");NSMutableArray *alias=[NSMutableArray arrayWithObjects:@{},nil];p.inlineOverflowEntries=alias;[alias addObject:@{}];Check(p.inlineOverflowEntries==alias&&p.inlineOverflowEntries.count==2,@"actual strong entries retain original mutable alias");Check(NSApp==nil,@"actual original/extracted host remains headless; >1 chooser/UI/monitors only compiled");printf("PASS InlineOverflowHostTests: %lu checks;exact original/extracted controller,real policy/native resize/position,no UI objects\n",(unsigned long)checks);
}return 0;}
