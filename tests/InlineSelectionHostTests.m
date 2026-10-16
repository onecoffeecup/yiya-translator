#import "presentation/FYInlineOverlayController.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface EpochFact : NSObject
@property(nonatomic) NSUInteger sessionEpoch,reads;
@end
@implementation EpochFact
- (NSUInteger)sessionEpoch{self.reads++;return _sessionEpoch;}
@end
@interface SelectionHostPeer : NSObject
@property(nonatomic,strong) FYInlineBlockSnapshot *inlineBlockSnapshot;
@property(nonatomic,strong) EpochFact *captureCardInput;
@property(nonatomic) BOOL enabled,hostSelection;
@property(nonatomic) NSUInteger sourceReads;
@property(nonatomic,copy) NSString *selectedStable;
@end
@implementation SelectionHostPeer
- (BOOL)captureCardInputEnabled{self.sourceReads++;return self.enabled;}
- (BOOL)inlineBlockID:(NSString *)stable isSelectedForItem:(OCRTextItem *)item{self.selectedStable=stable;return self.hostSelection;}
@end
@interface HostBorderFact : NSObject
@property(nonatomic) CGFloat borderWidth;
@end
@implementation HostBorderFact @end
@interface HostActionCardFact : NSObject
@property(nonatomic) BOOL compactEntry;
@property(nonatomic,copy) NSString *stableBlockID,*toolTip;
@property(nonatomic,strong) HostBorderFact *layer;
@property(nonatomic,copy) void (^onClick)(void);
@property(nonatomic,copy) void (^onHover)(BOOL);
@end
@implementation HostActionCardFact
- (BOOL)isKindOfClass:(Class)cls{if(cls==FYInlineLongCardView.class)return YES;return [super isKindOfClass:cls];}
@end
@interface HostActionPanelFact : NSObject
@property(nonatomic,strong) HostActionCardFact *contentView;
@end
@implementation HostActionPanelFact @end
@interface SelectionHostProbe : FYInlineOverlayController
@property(nonatomic,strong) FYInlineBlockSnapshot *learned;
@property(nonatomic,strong) OCRTextItem *openedItem;
@property(nonatomic,strong) NSString *openedTranslation,*openedStable;
@property(nonatomic) NSUInteger opens,closes,learns;
@end
@implementation SelectionHostProbe
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot{self.learned=snapshot;self.learns++;}
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)stable{self.opens++;self.openedItem=item;self.openedTranslation=translation;self.openedStable=stable;}
- (void)closeExpandedInlineReadingCard{self.closes++;self.inlineExpandedReadingPanel=nil;}
@end
static HostActionPanelFact *Panel(void){HostActionPanelFact *p=[HostActionPanelFact new];p.contentView=[HostActionCardFact new];p.contentView.layer=[HostBorderFact new];return p;}
int main(void){@autoreleasepool{
    Check(NSApp==nil,@"original/extracted host selection fixture starts without UI objects");SelectionHostPeer *peer=[SelectionHostPeer new];peer.captureCardInput=[EpochFact new];peer.captureCardInput.sessionEpoch=71;SelectionHostProbe *p=[[SelectionHostProbe alloc]initWithHost:(id<FYInlineOverlayControllerHost>)peer];
    OCRTextItem *item=[OCRTextItem new];NSMutableString *currentText=[@" A　B \n"mutableCopy];item.text=currentText;item.boundingBox=CGRectMake(.1234,.4564,.2,.03);item.lineBoxes=@[];Check([[p inlineBlockIdentityForItem:item]isEqual:@"AB|0.123,0.456,0.200,0.030"],@"actual native raw identity retains canonical three-decimal bbox");
    NSMutableString *translation=[@"original translation"mutableCopy];FYInlineBlockSnapshot *raw=[p inlineSnapshotForItem:item translation:translation];Check(raw.inputSource==0&&raw.inputEpoch==71&&peer.sourceReads==1&&peer.captureCardInput.reads==1&&[raw.blockID isEqual:[p inlineBlockIdentityForItem:item]],@"disabled native source still reads actual input epoch after source check");
    peer.enabled=YES;FYInlineBlockSnapshot *stable=[p inlineSnapshotForItem:item translation:translation stableBlockID:@"stable"];Check(stable.inputSource==1&&stable.inputEpoch==71&&[stable.blockID isEqual:@"stable"],@"native stable snapshot preserves actual input metadata");
    [currentText appendString:@" changed"];item.text=currentText;[translation appendString:@" changed"];Check([stable.sourceText isEqual:@" A　B \n"]&&[stable.translation isEqual:@"original translation"],@"native snapshot freezes original copy fields");
    stable.sentenceID=@"later-db";stable.version=4;Check([stable.sentenceID isEqual:@"later-db"]&&stable.version==4,@"actual later database binding remains writable");
    peer.inlineBlockSnapshot=stable;Check([p inlineBlockID:@"stable" isSelectedForItem:item],@"actual native selection reads single peer-owned current snapshot");peer.inlineBlockSnapshot=raw;item.text=@" A　B \n";Check([p inlineBlockID:@"other" isSelectedForItem:item],@"actual native stable mismatch retains raw fallback");
    p.inlineStableBlockIDs=[NSMutableDictionary dictionaryWithObject:@"mapped" forKey:[p inlineBlockIdentityForItem:item]];peer.hostSelection=YES;Check([p inlineBlockIsSelectedForItem:item]&&[peer.selectedStable isEqual:@"mapped"],@"actual native mapped path preserves host-directed selection hook");
    FYInlineTextBlock *block=[FYInlineTextBlock new];block.text=@"标题";block.lineBoxes=@[@(CGRectMake(.1,.2,.3,.04))];FYInlineBlockSnapshot *bs=[p inlineSnapshotForBlock:block translation:@"译文" stableBlockID:nil];Check([bs.blockID isEqual:[FYInlineBlockMatcher blockIDForText:block.text lineBoxes:block.lineBoxes]],@"actual native block snapshot uses canonical matcher identity");
    HostActionPanelFact *panel=Panel();NSMutableString *capturedStable=[@"stable"mutableCopy];[p wireInlineLongCardPanel:(NSPanel *)panel item:item translation:translation frame:CGRectZero stableBlockID:capturedStable];Check([panel.contentView.stableBlockID isEqual:@"stable"]&&panel.contentView.onClick&&panel.contentView.onHover,@"actual native binding sets stableID and both copied callbacks");
    panel.contentView.onClick();Check(p.learns==1&&p.learned.inputEpoch==71&&[p.learned.blockID isEqual:@"stable"],@"actual ordinary click opens captured native snapshot");panel.contentView.onHover(YES);Check(panel.contentView.layer.borderWidth==2&&[panel.contentView.toolTip isEqual:@"点击查看原文和语法"],@"actual native hover updates synthetic border/tooltip facts");panel.contentView.onHover(NO);Check(panel.contentView.layer.borderWidth==1&&!panel.contentView.toolTip,@"actual native hover leave resets facts");
    panel.contentView.compactEntry=YES;panel.contentView.onClick();Check(p.opens==1&&p.openedItem==item&&p.openedTranslation==translation&&p.openedStable==capturedStable,@"actual compact click preserves original strong payload aliases");
    p.inlineExpandedReadingPanel=(NSPanel *)panel;p.inlineExpandedReadingBlockID=@"stable";panel.contentView.onClick();Check(p.closes==1&&p.opens==1&&!p.inlineExpandedReadingPanel,@"actual compact same-identity click toggles close");
    [capturedStable appendString:@" changed"];p.inlineExpandedReadingPanel=(NSPanel *)panel;p.inlineExpandedReadingBlockID=@"stable changed";panel.contentView.onClick();Check(p.closes==2&&[panel.contentView.stableBlockID isEqual:@"stable"],@"actual callback retains mutable stable alias distinct from copied card ID");
    __weak FYInlineOverlayController *weakSource;HostActionCardFact *kept;@autoreleasepool{SelectionHostProbe *temporary=[[SelectionHostProbe alloc]initWithHost:nil];HostActionPanelFact *q=Panel();kept=q.contentView;weakSource=temporary;[temporary wireInlineLongCardPanel:(NSPanel *)q item:item translation:translation frame:CGRectZero stableBlockID:nil];}Check(!weakSource,@"actual native card callbacks retain no concrete controller");kept.onClick();kept.onHover(YES);Check(kept.layer.borderWidth==2&&NSApp==nil,@"late native callbacks remain safe and headless after source release");
    printf("PASS InlineSelectionHostTests: %lu checks;actual original/extracted native model/selection/snapshot/callback behavior,no UI objects\n",(unsigned long)checks);
}return 0;}
