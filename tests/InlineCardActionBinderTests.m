#import "presentation/FYInlineCardActionBinder.h"
#import "inline/FYInlineOverlayViews.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface BorderFact : NSObject
@property(nonatomic) CGFloat borderWidth;
@end
@implementation BorderFact @end
@interface ActionCardFact : NSObject
@property(nonatomic) BOOL longCard,compactEntry;
@property(nonatomic,copy) NSString *stableBlockID,*toolTip;
@property(nonatomic,strong) BorderFact *layer;
@property(nonatomic,copy) void (^onClick)(void);
@property(nonatomic,copy) void (^onHover)(BOOL);
@end
@implementation ActionCardFact
- (BOOL)isKindOfClass:(Class)cls{if(cls==FYInlineLongCardView.class)return self.longCard;return [super isKindOfClass:cls];}
@end
@interface ActionPanelFact : NSObject
@property(nonatomic,strong) ActionCardFact *contentView;
@end
@implementation ActionPanelFact @end
@interface ActionProbe : NSObject <FYInlineCardActionSource,FYInlineSnapshotInputSource>
@property(nonatomic,strong) FYInlineSelectionCoordinator *policy;
@property(nonatomic,copy) NSString *inlineExpandedReadingBlockID;
@property(nonatomic,strong) NSPanel *inlineExpandedReadingPanel;
@property(nonatomic,strong) FYInlineBlockSnapshot *learnedSnapshot;
@property(nonatomic,strong) OCRTextItem *openedItem;
@property(nonatomic,strong) NSString *openedTranslation,*openedStable;
@property(nonatomic) NSUInteger snapshotCalls,opens,closes,learns;
@end
@implementation ActionProbe
- (instancetype)init{if((self=[super init]))_policy=[FYInlineSelectionCoordinator new];return self;}
- (BOOL)captureCardInputEnabled{return YES;}
- (NSUInteger)inlineSnapshotInputEpoch{return 9;}
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item{return [self.policy inlineBlockIdentityForItem:item];}
- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID{self.snapshotCalls++;return [self.policy inlineSnapshotForItem:item translation:translation stableBlockID:stableBlockID source:self];}
- (void)closeExpandedInlineReadingCard{self.closes++;self.inlineExpandedReadingPanel=nil;}
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID{self.opens++;self.openedItem=item;self.openedTranslation=translation;self.openedStable=stableBlockID;}
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot{self.learns++;self.learnedSnapshot=snapshot;}
@end
static ActionPanelFact *Panel(BOOL longCard){ActionPanelFact *p=[ActionPanelFact new];p.contentView=[ActionCardFact new];p.contentView.longCard=longCard;p.contentView.layer=[BorderFact new];return p;}
int main(void){@autoreleasepool{
    Check(NSApp==nil,@"native card-binding fixture creates no UI objects");FYInlineCardActionBinder *binder=[FYInlineCardActionBinder new];unsigned int n=0;Ivar *ivars=class_copyIvarList(FYInlineCardActionBinder.class,&n);free(ivars);Check(n==0,@"native binder stores no source/card/current state");
    ActionProbe *source=[ActionProbe new];OCRTextItem *item=[OCRTextItem new];NSMutableString *currentText=[@"original source"mutableCopy];item.text=currentText;item.boundingBox=CGRectMake(.1,.2,.3,.04);NSMutableString *translation=[@"original translation"mutableCopy],*stable=[@"stable"mutableCopy];ActionPanelFact *panel=Panel(NO);
    [binder wireInlineLongCardPanel:(NSPanel *)panel item:item translation:translation frame:CGRectZero stableBlockID:stable source:source];Check(!panel.contentView.onClick&&!source.snapshotCalls,@"wrong native content type returns before snapshot or callback binding");
    panel.contentView.longCard=YES;[binder wireInlineLongCardPanel:(NSPanel *)panel item:item translation:translation frame:CGRectZero stableBlockID:stable source:source];Check(source.snapshotCalls==1&&[panel.contentView.stableBlockID isEqual:@"stable"]&&panel.contentView.onClick&&panel.contentView.onHover,@"binding captures one snapshot,sets copied stableID and both callbacks");
    [currentText appendString:@" changed"];item.text=currentText;[translation appendString:@" changed"];panel.contentView.onClick();Check(source.learns==1&&source.opens==0&&source.learnedSnapshot.inputEpoch==9&&[source.learnedSnapshot.sourceText isEqual:@"original source"]&&[source.learnedSnapshot.translation isEqual:@"original translation"],@"ordinary click opens original copied snapshot despite later source/translation changes");
    panel.contentView.onClick();Check(source.learns==2&&source.snapshotCalls==1,@"repeat click reuses captured snapshot rather than rebuilding it");
    panel.contentView.onHover(YES);Check(panel.contentView.layer.borderWidth==2&&[panel.contentView.toolTip isEqual:@"点击查看原文和语法"],@"actual hover callback keeps original native border/tooltip updates");panel.contentView.onHover(NO);Check(panel.contentView.layer.borderWidth==1&&!panel.contentView.toolTip,@"hover leave resets native border/tooltip");
    panel.contentView.compactEntry=YES;panel.contentView.onClick();Check(source.opens==1&&source.openedItem==item&&source.openedTranslation==translation&&source.openedStable==stable&&source.learns==2,@"compact click uses strong original item/translation/stable aliases instead of copied snapshot contents");
    source.inlineExpandedReadingPanel=(NSPanel *)panel;source.inlineExpandedReadingBlockID=@"stable";panel.contentView.onClick();Check(source.closes==1&&source.opens==1&&!source.inlineExpandedReadingPanel,@"same expanded stable identity toggles close before opening");
    source.inlineExpandedReadingPanel=(NSPanel *)panel;source.inlineExpandedReadingBlockID=@"different";panel.contentView.onClick();Check(source.opens==2&&source.closes==1,@"different expanded identity opens requested original block");
    [stable appendString:@" mutated"];source.inlineExpandedReadingPanel=(NSPanel *)panel;source.inlineExpandedReadingBlockID=@"stable mutated";panel.contentView.onClick();Check(source.closes==2&&[panel.contentView.stableBlockID isEqual:@"stable"]&&[source.learnedSnapshot.blockID isEqual:@"stable"],@"closure keeps original mutable stableID alias while card and snapshot keep their old copies");
    ActionPanelFact *rawPanel=Panel(YES);rawPanel.contentView.compactEntry=YES;[binder wireInlineLongCardPanel:(NSPanel *)rawPanel item:item translation:translation frame:CGRectZero stableBlockID:nil source:source];NSString *raw=[source inlineBlockIdentityForItem:item];source.inlineExpandedReadingPanel=(NSPanel *)rawPanel;source.inlineExpandedReadingBlockID=raw;rawPanel.contentView.onClick();Check(source.closes==3,@"nil stable argument toggles using captured snapshot raw identity");
    __weak OCRTextItem *heldItem;__weak NSString *heldTranslation;__weak NSString *heldStable;@autoreleasepool{ActionCardFact *leaseCard;@autoreleasepool{ActionPanelFact *p=Panel(YES);leaseCard=p.contentView;OCRTextItem *i=[OCRTextItem new];i.text=@"lease";NSMutableString *t=[@"lease translation"mutableCopy],*s=[@"lease stable"mutableCopy];heldItem=i;heldTranslation=t;heldStable=s;[binder wireInlineLongCardPanel:(NSPanel *)p item:i translation:t frame:CGRectZero stableBlockID:s source:source];}
    @autoreleasepool{Check(heldItem&&heldTranslation&&heldStable,@"copied card callback retains original payload leases even before compact click");}leaseCard.onClick=nil;leaseCard.onHover=nil;leaseCard=nil;}
    @autoreleasepool{}Check(!heldItem&&!heldTranslation&&!heldStable,@"removing callbacks releases original payload leases");
    __weak ActionProbe *weakSource;__weak ActionCardFact *weakCard;@autoreleasepool{ActionCardFact *keptCard;@autoreleasepool{ActionProbe *temporary=[ActionProbe new];weakSource=temporary;ActionPanelFact *p=Panel(YES);keptCard=p.contentView;weakCard=keptCard;[binder wireInlineLongCardPanel:(NSPanel *)p item:item translation:translation frame:CGRectZero stableBlockID:nil source:temporary];}@autoreleasepool{Check(!weakSource&&weakCard==keptCard,@"callbacks preserve weak concrete source while external owner holds card");}keptCard.onClick();keptCard.onHover(YES);Check(keptCard.layer.borderWidth==2,@"late hover uses weak card after source release and click safely messages nil source");keptCard=nil;}
    @autoreleasepool{}Check(!weakCard,@"callback does not make card retain itself through hover/click");
    Check(NSApp==nil,@"actual native binder checks remain headless using synthetic native facts only");
    printf("PASS InlineCardActionBinderTests: %lu checks;actual weak native card/source binding,original payload/snapshot leases,compact toggle and hover\n",(unsigned long)checks);
}return 0;}
