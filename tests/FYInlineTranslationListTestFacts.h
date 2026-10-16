#pragma once
#import <AppKit/AppKit.h>
#import "inline/FYInlineTextModels.h"
#import "presentation/FYInlineBlockSnapshot.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
static FYInlinePlacement *ListPlacement(NSString *identifier,NSString *translation,FYInlineDisplayMode mode){FYInlinePlacement *p=[FYInlinePlacement new];p.block=[FYInlineTextBlock new];p.block.blockID=identifier;p.block.text=[@"source-" stringByAppendingString:identifier];p.blockID=identifier;p.translation=translation;p.mode=mode;return p;}
@interface ListConstraintFact : NSObject
@property(nonatomic) CGFloat constant;
@property(nonatomic) BOOL active;
@end
@implementation ListConstraintFact @end
@interface ListAnchorFact : NSObject
@property(nonatomic,strong) ListConstraintFact *constraint;
- (ListConstraintFact *)constraintEqualToConstant:(CGFloat)value;
@end
@implementation ListAnchorFact
- (ListConstraintFact *)constraintEqualToConstant:(CGFloat)value { self.constraint=[ListConstraintFact new];self.constraint.constant=value;return self.constraint; }
@end
@interface ListViewFact : NSObject
@property(nonatomic,getter=isHidden) BOOL hidden;
@property(nonatomic) BOOL selectable;
@property(nonatomic) CGFloat spacing;
@property(nonatomic) NSInteger maximumNumberOfLines,tag;
@property(nonatomic,copy) NSString *stringValue,*title;
@property(nonatomic,strong) NSFont *font;
@property(nonatomic,strong) NSColor *color;
@property(nonatomic) SEL action;
@property(nonatomic,weak) id target;
@property(nonatomic,strong) NSMutableArray *arrangedSubviews;
@property(nonatomic,strong) ListAnchorFact *heightAnchor;
@property(nonatomic,strong) id content;
@end
@implementation ListViewFact
- (instancetype)init{if((self=[super init])){self.arrangedSubviews=[NSMutableArray new];self.heightAnchor=[ListAnchorFact new];}return self;}
- (void)addArrangedSubview:(id)view { [self.arrangedSubviews addObject:view]; }
@end
@interface ListNativePeer : NSObject
@property(nonatomic,strong) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic,strong) FYInlineBlockSnapshot *opened;
@property(nonatomic,strong) NSMutableArray<FYInlineBlockSnapshot *> *createdSnapshots;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic,strong) ListViewFact *listScroll;
@property(nonatomic) NSUInteger clears,opens,pins;
@property(nonatomic,copy) void (^onButton)(void);
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSView *)spacer;
- (NSTextField *)mutedLabel:(NSString *)text;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSView *)cardWithStack:(NSStackView *)stack;
- (NSScrollView *)makePageScrollWithContent:(NSView *)view;
- (void)pinFullWidth:(NSView *)view toStack:(NSStackView *)stack;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block translation:(NSString *)translation stableBlockID:(NSString *)identifier;
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot;
@end
@implementation ListNativePeer
- (instancetype)init{if((self=[super init])){self.createdSnapshots=[NSMutableArray new];self.trace=[NSMutableArray new];}return self;}
- (NSColor *)uiInk{return NSColor.brownColor;}
- (NSColor *)uiMuted{return NSColor.grayColor;}
- (NSStackView *)verticalStack{[self.trace addObject:@"vertical"];return (NSStackView *)[ListViewFact new];}
- (NSStackView *)horizontalStack{[self.trace addObject:@"horizontal"];return (NSStackView *)[ListViewFact new];}
- (NSView *)spacer{[self.trace addObject:@"spacer"];return (NSView *)[ListViewFact new];}
- (NSTextField *)mutedLabel:(NSString *)text{ListViewFact *v=[ListViewFact new];v.stringValue=text;v.color=self.uiMuted;[self.trace addObject:@"muted"];return (NSTextField *)v;}
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color{ListViewFact *v=[ListViewFact new];v.stringValue=text;v.font=font;v.color=color;[self.trace addObject:[@"label:" stringByAppendingString:text]];return (NSTextField *)v;}
- (NSView *)cardWithStack:(NSStackView *)stack{ListViewFact *v=[ListViewFact new];v.content=stack;[self.trace addObject:@"card"];return (NSView *)v;}
- (NSScrollView *)makePageScrollWithContent:(NSView *)view{ListViewFact *v=[ListViewFact new];v.content=view;self.listScroll=v;[self.trace addObject:@"scroll"];return (NSScrollView *)v;}
- (void)pinFullWidth:(NSView *)view toStack:(NSStackView *)stack{self.pins++;[self.trace addObject:@"pin"];}
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary{ListViewFact *v=[ListViewFact new];v.title=title;v.action=action;v.target=self;[self.trace addObject:@"button"];if(self.onButton)self.onButton();return (NSButton *)v;}
- (void)clearArrangedSubviews:(NSStackView *)stack{self.clears++;[((ListViewFact *)stack).arrangedSubviews removeAllObjects];[self.trace addObject:@"clear"];}
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block translation:(NSString *)translation stableBlockID:(NSString *)identifier{FYInlineBlockSnapshot *s=[FYInlineBlockSnapshot new];s.blockID=identifier;s.sourceText=block.text;s.translation=translation;[self.createdSnapshots addObject:s];[self.trace addObject:[@"snapshot:" stringByAppendingString:identifier]];return s;}
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot{self.opened=snapshot;self.opens++;}
@end
// Same fixture runs original/new actual Main and standalone actual native renderer.
// Only native factories/properties and learning snapshot service are facts.
@protocol ListFixtureController <NSObject>
@property(nonatomic,strong) NSView *inlineTranslationListCard;
@property(nonatomic,strong) NSTextField *inlineTranslationListCount;
@property(nonatomic,strong) NSStackView *inlineTranslationListStack;
@property(nonatomic,copy) NSString *inlineTranslationListSignature;
@property(nonatomic,copy) NSArray<FYInlineBlockSnapshot *> *inlineTranslationListSnapshots;
- (NSView *)makeInlineTranslationListCard;
- (void)refreshInlineTranslationList;
- (void)openInlineTranslationRow:(NSButton *)sender;
@end
static void RunListNativeFixture(id<ListFixtureController> controller,ListNativePeer *peer){
    Check(NSApp==nil,@"list native fixture creates no application/view/control/window");
    [controller refreshInlineTranslationList];Check(!peer.clears&&!controller.inlineTranslationListCard,@"missing list resources returns before state/native work");
    ListViewFact *card=(ListViewFact *)[controller makeInlineTranslationListCard];ListViewFact *stack=(ListViewFact *)controller.inlineTranslationListStack;
    Check(card==((id)controller.inlineTranslationListCard)&&card.isHidden&&controller.inlineTranslationListSignature.length==0&&controller.inlineTranslationListSnapshots.count==0,@"native list construction installs hidden card and original empty state");
    Check(peer.listScroll.heightAnchor.constraint.constant==220&&peer.listScroll.heightAnchor.constraint.active&&stack.spacing==10,@"actual native constructor preserves220pt constraint and stack spacing10");Check(peer.pins==1,@"native scroll is pinned once to list card stack");
    FYInlinePlacement *a=ListPlacement(@"A",@"translation-A",FYInlineDisplayModeUnplaceable),*b=ListPlacement(@"B",@"translation-B",FYInlineDisplayModeCompactEntry);a.reason=@"合成原因";FYInlineLayoutResult *result=[FYInlineLayoutResult new];result.placements=@[a,ListPlacement(@"full",@"not listed",FYInlineDisplayModeFullCard),ListPlacement(@"blank",@" \n",FYInlineDisplayModeCompactEntry),b];peer.lastInlineLayoutResult=result;
    [peer.trace removeAllObjects];[controller refreshInlineTranslationList];Check(!card.isHidden&&stack.arrangedSubviews.count==2&&controller.inlineTranslationListSnapshots.count==2,@"actual native list builds only original unplaceable/compact rows");Check([controller.inlineTranslationListCount.stringValue isEqual:@"1 条暂不可放置 · 1 条用入口"],@"actual count native field keeps original mixed wording");
    ListViewFact *rowCard=stack.arrangedSubviews[0],*row=rowCard.content,*source=row.arrangedSubviews[0],*translation=row.arrangedSubviews[1],*footer=row.arrangedSubviews[2],*reason=footer.arrangedSubviews[0],*button=footer.arrangedSubviews[2];
    Check(row.spacing==6&&[source.stringValue isEqual:@"source-A"]&&source.font.pointSize==13&&source.maximumNumberOfLines==3&&[source.color isEqual:peer.uiMuted],@"actual original row source uses font13/three lines/muted with spacing6");Check([translation.stringValue isEqual:@"translation-A"]&&translation.font.pointSize==15&&translation.maximumNumberOfLines==6&&translation.selectable&&[translation.color isEqual:peer.uiInk],@"actual original translation uses font15/six lines/native selection/ink");Check([reason.stringValue isEqual:@"暂不可放置 · 原因：合成原因"]&&[button.title isEqual:@"查看原文和语法"]&&button.action==@selector(openInlineTranslationRow:)&&button.target==peer&&button.tag==0,@"original footer reason/Host target/selector and snapshot index retained");
    ListViewFact *row2=((ListViewFact *)stack.arrangedSubviews[1]).content,*button2=((ListViewFact *)row2.arrangedSubviews[2]).arrangedSubviews[2];Check(button2.tag==1&&[((ListViewFact *)((ListViewFact *)row2.arrangedSubviews[2]).arrangedSubviews[0]).stringValue isEqual:@"已改为「查看译文」入口 · 原因："],@"second compact row index and nil reason exact");
    NSArray *snapshots=controller.inlineTranslationListSnapshots;NSUInteger cleared=peer.clears;[controller refreshInlineTranslationList];Check(controller.inlineTranslationListSnapshots==snapshots&&peer.clears==cleared&&stack.arrangedSubviews[0]==rowCard,@"same signature preserves exact row and snapshot identity");a.block.text=@"new source";a.reason=@"different reason";a.translationFrame=CGRectMake(2,3,4,5);[controller refreshInlineTranslationList];Check(controller.inlineTranslationListSnapshots==snapshots&&stack.arrangedSubviews[0]==rowCard,@"source/reason/geometry alone do not replace saved rows");
    [controller openInlineTranslationRow:(NSButton *)button2];Check(peer.opened==snapshots[1]&&peer.opens==1,@"actual sender tag opens saved snapshot at clicked original row");button2.tag=-1;[controller openInlineTranslationRow:(NSButton *)button2];button2.tag=2;[controller openInlineTranslationRow:(NSButton *)button2];Check(peer.opens==1,@"actual negative/out-of-bounds sender tag returns");
    result.placements=@[];[controller refreshInlineTranslationList];Check(card.isHidden&&stack.arrangedSubviews.count==0&&controller.inlineTranslationListSnapshots.count==0&&controller.inlineTranslationListSignature.length==0,@"actual native empty clears state and rows");cleared=peer.clears;[controller refreshInlineTranslationList];Check(peer.clears==cleared,@"second empty keeps original early return");
    result.placements=@[b];[controller refreshInlineTranslationList];Check([controller.inlineTranslationListCount.stringValue isEqual:@"1 条改用「查看译文」入口"],@"actual compact-only count text preserved");
    result.placements=@[a];a.translation=@"before-button";a.block.text=@"before-source";__weak ListNativePeer *weakPeer=peer;peer.onButton=^{a.translation=@"after-button";a.block.text=@"after-source";FYInlineLayoutResult *next=[FYInlineLayoutResult new];next.placements=@[b];weakPeer.lastInlineLayoutResult=next;};[peer.trace removeAllObjects];[controller refreshInlineTranslationList];peer.onButton=nil;
    row=((ListViewFact *)stack.arrangedSubviews[0]).content;translation=row.arrangedSubviews[1];Check([translation.stringValue isEqual:@"before-button"]&&[controller.inlineTranslationListSnapshots[0].translation isEqual:@"after-button"]&&[controller.inlineTranslationListSnapshots[0].sourceText isEqual:@"after-source"],@"row reads text before native button factory, snapshot factory reads after it exactly as original");Check(peer.lastInlineLayoutResult.placements[0]==b&&[controller.inlineTranslationListSnapshots[0].blockID isEqual:@"A"],@"native factory changes current frame yet original held placement remains row snapshot input");
    NSUInteger pin=[peer.trace indexOfObject:@"pin"],snapshot=[peer.trace indexOfObject:@"snapshot:A"],factory=[peer.trace indexOfObject:@"button"];Check(factory!=NSNotFound&&pin>factory&&snapshot>pin,@"native button then row add/pin precedes snapshot factory");Check(NSApp==nil,@"all original/native list algorithms execute headless using only native boundary facts");
}
