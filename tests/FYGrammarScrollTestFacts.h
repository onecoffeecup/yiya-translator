#import <AppKit/AppKit.h>
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok, NSString *message) { checks++; if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);} }
@interface GrammarScrollNodeFact : NSObject
@property(nonatomic) NSRect frame,bounds;
@property(nonatomic) NSPoint lastPoint;
@property(nonatomic) NSUInteger scrollCalls,reflectCalls,removedCalls;
@property(nonatomic,strong) GrammarScrollNodeFact *contentView,*documentView,*window,*superview,*enclosingScrollView;
@property(nonatomic,strong) NSMutableArray *arrangedSubviews,*trace;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) void (^onLayout)(void);
- (void)layoutSubtreeIfNeeded;
- (void)scrollToPoint:(NSPoint)point;
- (void)reflectScrolledClipView:(id)clip;
- (void)removeArrangedSubview:(id)view;
- (void)addArrangedSubview:(id)view;
- (void)removeFromSuperview;
@end
@implementation GrammarScrollNodeFact
- (void)layoutSubtreeIfNeeded { [self.trace addObject:[self.name stringByAppendingString:@"-layout"]];if(self.onLayout)self.onLayout(); }
- (void)scrollToPoint:(NSPoint)p { self.lastPoint=p; self.scrollCalls++; [self.trace addObject:@"scroll"]; }
- (void)reflectScrolledClipView:(id)clip { Check(clip==self.contentView,@"reflect uses current clip object");self.reflectCalls++;[self.trace addObject:@"reflect"]; }
- (void)removeArrangedSubview:(id)view { [self.trace addObject:@"remove-arranged"];[self.arrangedSubviews removeObject:view]; }
- (void)addArrangedSubview:(id)view { [self.trace addObject:@"add-arranged"];[self.arrangedSubviews addObject:view]; }
- (void)removeFromSuperview { self.removedCalls++; [self.trace addObject:@"remove-view"]; }
@end
static GrammarScrollNodeFact *Node(NSString *name,NSMutableArray *trace){GrammarScrollNodeFact *n=[GrammarScrollNodeFact new];n.name=name;n.trace=trace;n.arrangedSubviews=[NSMutableArray new];return n;}
static GrammarScrollNodeFact *Scroll(NSMutableArray *t,CGFloat x,CGFloat y,CGFloat w,CGFloat h){
 GrammarScrollNodeFact *s=Node(@"scrollview",t);s.contentView=Node(@"clip",t);s.contentView.bounds=NSMakeRect(x,y,100,100);s.documentView=Node(@"doc",t);s.documentView.frame=NSMakeRect(0,0,w,h);s.superview=Node(@"super",t);s.window=Node(@"window",t);s.window.contentView=Node(@"window-content",t);return s;
}
@interface GrammarScrollFacts : NSObject
@property(nonatomic,strong) GrammarScrollNodeFact *main,*quick,*stack,*detail,*panel,*reviewButton,*quickReading,*replacementDetail;
@property(nonatomic,strong) NSObject *item;
@property(nonatomic,strong) NSMutableArray *trace;
@property(nonatomic) NSUInteger mainReads,quickReads,readingReads,factoryCalls;
@end
@implementation GrammarScrollFacts
- (NSScrollView *)mainStructureScrollView{self.mainReads++;return (NSScrollView *)self.main;}
- (NSScrollView *)quickStructureScrollView{self.quickReads++;return (NSScrollView *)self.quick;}
- (NSStackView *)quickGrammarStack{return (NSStackView *)self.stack;}
- (NSView *)quickGrammarDetailCard{return (NSView *)self.detail;}
- (void)setQuickGrammarDetailCard:(NSView *)v{[self.trace addObject:@"set-detail"];self.detail=(GrammarScrollNodeFact *)v;}
- (id)quickSentencePanel{return self.panel;}
- (NSButton *)grammarReviewButton{return (NSButton *)self.reviewButton;}
- (NSScrollView *)quickSentenceScrollView{self.readingReads++;[self.trace addObject:@"reading-get"];return (NSScrollView *)self.quickReading;}
- (id)grammarActionItemForQuick:(BOOL)quick{Check(quick,@"detail obtains quick selected item");return self.item;}
- (NSView *)quickGrammarDetailForItem:(id)item{Check(item==self.item,@"factory receives original item identity");self.factoryCalls++;[self.trace addObject:@"factory"];return (NSView *)self.replacementDetail;}
@end
@protocol GrammarScrollDriver <NSObject>
- (CGFloat)structureScrollOffsetForQuick:(BOOL)quick;
- (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick;
- (void)refreshQuickGrammarActionDetail;
- (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates;
@end
static void RunGrammarScrollFixture(id<GrammarScrollDriver> driver,GrammarScrollFacts *f){
 Check(NSApp==nil,@"native boundary fixture creates no application/view/window/control");
 f.main=Scroll(f.trace,12,42,500,500);f.quick=Scroll(f.trace,25,36,250,300);
 Check([driver structureScrollOffsetForQuick:NO]==12,@"main horizontal offset");Check([driver structureScrollOffsetForQuick:YES]==25,@"quick horizontal offset");f.quick=nil;Check([driver structureScrollOffsetForQuick:YES]==0,@"missing structure offset remains zero");
 NSUInteger reads=f.mainReads;[driver restoreStructureScrollOffset:0.5 quick:NO];[driver restoreStructureScrollOffset:-1 quick:NO];Check(f.mainReads==reads&&f.main.contentView.scrollCalls==0,@"threshold returns before querying native source");
 [driver restoreStructureScrollOffset:20 quick:YES];Check(!f.quick,@"missing scroll restoration safely returns");
 [f.trace removeAllObjects];GrammarScrollNodeFact *main=f.main;__weak GrammarScrollNodeFact *weakMain=main;main.documentView.frame=NSMakeRect(0,0,110,500);main.documentView.onLayout=^{weakMain.documentView.frame=NSMakeRect(0,0,500,500);};
 [driver restoreStructureScrollOffset:450 quick:NO];Check(NSEqualPoints(main.contentView.lastPoint,NSMakePoint(400,42)),@"width clamp reads post-layout document geometry and preserves vertical origin");Check([f.trace isEqual:@[@"doc-layout",@"scrollview-layout",@"scroll",@"reflect"]],@"structure document then scroll layout and immediate reflection order");Check(main.reflectCalls==1,@"structure restoration reflects once");
 main.documentView.onLayout=nil;main.documentView.frame=NSMakeRect(0,0,50,500);[driver restoreStructureScrollOffset:30 quick:NO];Check(main.contentView.lastPoint.x==0,@"narrow document clamps to zero");
 f.quick=Scroll(f.trace,1,17,350,350);NSUInteger prior=main.contentView.scrollCalls;[driver restoreStructureScrollOffset:180 quick:YES];Check(NSEqualPoints(f.quick.contentView.lastPoint,NSMakePoint(180,17))&&main.contentView.scrollCalls==prior,@"quick horizontal restore never scrolls main");
 GrammarScrollNodeFact *before=Scroll(f.trace,80,270,600,600),*after=Scroll(f.trace,1,2,1000,1000);f.quickReading=before;after.documentView.onLayout=^{after.documentView.frame=NSMakeRect(0,0,130,180);};[f.trace removeAllObjects];__block NSUInteger calls=0;[driver updateGrammarReviewDisplayForQuick:YES preservingPosition:^{calls++;[f.trace addObject:@"updates"];f.quickReading=after;}];
 Check(calls==1&&f.readingReads==2,@"updates runs once between fresh before and after source lookups");Check(NSEqualPoints(after.contentView.lastPoint,NSMakePoint(30,80)),@"review restores into new quick scroll with actual post-layout clamp");Check(before.contentView.scrollCalls==0,@"replaced old document is never scrolled");Check([f.trace isEqual:@[@"reading-get",@"updates",@"reading-get",@"window-content-layout",@"super-layout",@"doc-layout",@"scroll",@"reflect"]],@"review window/super/document layout order precedes geometry and scroll");after.documentView.onLayout=nil;
 f.reviewButton=Node(@"review",f.trace);GrammarScrollNodeFact *reading=Scroll(f.trace,-5,-9,70,80);f.reviewButton.enclosingScrollView=reading;[driver updateGrammarReviewDisplayForQuick:NO preservingPosition:^{calls++;}];Check(NSEqualPoints(reading.contentView.lastPoint,NSZeroPoint),@"main review clamps negative origins and small document to zero");
 reading.contentView.bounds=NSMakeRect(45,75,100,100);reading.documentView.frame=NSMakeRect(0,0,300,300);[driver updateGrammarReviewDisplayForQuick:NO preservingPosition:^{calls++;}];Check(NSEqualPoints(reading.contentView.lastPoint,NSMakePoint(45,75)),@"position captured at update time after reader moved while waiting");
 f.quickReading=nil;[f.trace removeAllObjects];NSUInteger previousAfter=after.contentView.scrollCalls;[driver updateGrammarReviewDisplayForQuick:YES preservingPosition:^{calls++;f.quickReading=after;}];Check(calls==4&&after.contentView.scrollCalls==previousAfter,@"nil before still performs update once but does not restore");Check([f.trace isEqual:@[@"reading-get",@"reading-get"]],@"nil before guard occurs after update and fresh after query");
 f.quickReading=before;[f.trace removeAllObjects];[driver updateGrammarReviewDisplayForQuick:YES preservingPosition:^{calls++;f.quickReading=nil;}];Check(calls==5&&before.contentView.scrollCalls==0,@"nil after still performs update and skips old scroll");
 f.item=nil;[f.trace removeAllObjects];[driver refreshQuickGrammarActionDetail];Check(f.factoryCalls==0&&f.trace.count==0,@"missing item skips detail replacement");f.item=[NSObject new];[driver refreshQuickGrammarActionDetail];Check(f.factoryCalls==0,@"missing stack skips factory");
 GrammarScrollNodeFact *stack=Node(@"stack",f.trace),*oldDetail=Node(@"detail",f.trace),*newDetail=Node(@"new",f.trace),*scroll=Scroll(f.trace,22,320,600,600);f.stack=stack;stack.enclosingScrollView=scroll;f.detail=oldDetail;[stack.arrangedSubviews addObject:oldDetail];f.replacementDetail=newDetail;f.panel=Node(@"panel",f.trace);f.panel.contentView=Node(@"panel-content",f.trace);__weak GrammarScrollNodeFact *weakScroll=scroll;f.panel.contentView.onLayout=^{weakScroll.documentView.frame=NSMakeRect(0,0,600,200);};[f.trace removeAllObjects];
 [driver refreshQuickGrammarActionDetail];Check(f.detail==newDetail&&f.factoryCalls==1&&oldDetail.removedCalls==1&&[stack.arrangedSubviews isEqual:@[newDetail]],@"detail replacement keeps exact item/factory/new card ownership");Check(NSEqualPoints(scroll.contentView.lastPoint,NSMakePoint(22,100)),@"quick detail clamps vertical origin after panel layout preserving horizontal origin");Check([f.trace isEqual:@[@"remove-arranged",@"remove-view",@"factory",@"set-detail",@"add-arranged",@"panel-content-layout",@"scroll",@"reflect"]],@"detail removal/factory/set/add/layout/restore order");f.panel.contentView.onLayout=nil;
 Check(NSApp==nil,@"actual native algorithms ran without UI construction, service, database or credentials");
}
