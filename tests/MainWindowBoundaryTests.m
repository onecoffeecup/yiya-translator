#import "presentation/FYMainWindowController.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface BoundaryNode : NSObject
@property(nonatomic,getter=isHidden) BOOL hidden;
@property(nonatomic) BOOL enabled,needsDisplay,active;
@property(nonatomic) NSInteger state;
@property(nonatomic) CGFloat constant,priority;
@property(nonatomic,copy) NSString *stringValue,*title,*toolTip,*draft;
@property(nonatomic,strong) id session;
@property(nonatomic,weak) id superview;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic,copy) NSString *name;
@property(nonatomic) NSUInteger layouts,orders;
@end
@implementation BoundaryNode
- (void)layoutSubtreeIfNeeded{self.layouts++;[self.trace addObject:@"layout"];}
- (void)orderOut:(id)sender{self.orders++;[self.trace addObject:@"preview-out"];}
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)value forOrientation:(NSLayoutConstraintOrientation)orientation{self.priority=value;[self.trace addObject:@"priority"];}
@end
@interface BoundaryWindow : NSObject
@property(nonatomic) NSSize contentMinSize;
@property(nonatomic,strong) BoundaryNode *contentView;
@end
@implementation BoundaryWindow @end
@interface BoundaryHost : NSObject
@property(nonatomic,strong) FYStudyChatView *mainStudyChatView;
@property(nonatomic,strong) NSPanel *captionAppearancePreviewPanel;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic) NSUInteger histories,vocabularies;
@end
@implementation BoundaryHost
- (void)refreshHistory{self.histories++;[self.trace addObject:@"history"];}
- (void)refreshVocabularyList{self.vocabularies++;[self.trace addObject:@"vocabulary"];}
@end
@interface BoundaryMain : FYMainWindowController
@property(nonatomic) NSUInteger heights;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@end
@implementation BoundaryMain
- (void)updateMainChatForWindowWidth{[self.trace addObject:@"chat"];[super updateMainChatForWindowWidth];}
- (void)updateLiveSourceReadingHeight{self.heights++;[self.trace addObject:@"height"];}
@end
int main(void){@autoreleasepool{
    Check(NSApp==nil,@"Main native boundary tests create no application/view/window/control");BoundaryHost *host=[BoundaryHost new];host.trace=[NSMutableArray new];BoundaryMain *main=[[BoundaryMain alloc]initWithHost:(id<FYMainWindowControllerHost>)host];main.trace=host.trace;
    BoundaryNode *chat=[BoundaryNode new];chat.session=[NSObject new];chat.draft=@"synthetic draft";id session=chat.session;host.mainStudyChatView=(FYStudyChatView *)chat;BoundaryNode *panel=[BoundaryNode new];panel.trace=host.trace;host.captionAppearancePreviewPanel=(NSPanel *)panel;
    BoundaryWindow *window=[BoundaryWindow new];window.contentMinSize=NSMakeSize(720,777);window.contentView=[BoundaryNode new];window.contentView.trace=host.trace;main.mainWindow=(NSWindow *)window;
    BoundaryNode *workspace=[BoundaryNode new],*chatWidth=[BoundaryNode new],*minimum=[BoundaryNode new],*toggle=[BoundaryNode new];main.workspaceWidth=(NSLayoutConstraint *)workspace;main.mainChatWidth=(NSLayoutConstraint *)chatWidth;main.mainWindowMinimumWidth=(NSLayoutConstraint *)minimum;main.mainChatToggle=(NSButton *)toggle;
    main.mainChatWantsVisible=YES;[main updateMainChatForWindowWidth];Check(!chat.isHidden&&chatWidth.active&&workspace.constant==-510&&minimum.constant==1100&&window.contentMinSize.width==1100&&window.contentMinSize.height==777,@"manual open uses original1100/-510, preserves content min height");Check([toggle.title isEqual:@"收起 AI 伙伴"]&&toggle.enabled,@"open toggle title/enabled original");
    main.mainChatWantsVisible=NO;[main updateMainChatForWindowWidth];Check(chat.isHidden&&!chatWidth.active&&workspace.constant==-190&&minimum.constant==720&&window.contentMinSize.width==720,@"manual collapse uses original720/-190 and releases chat constraint");Check([toggle.title isEqual:@"展开 AI 伙伴"]&&[toggle.toolTip isEqual:@"展开 AI 伙伴；空间不足时会放宽窗口"],@"collapsed toggle label/tooltip original");Check(chat.session==session&&[chat.draft isEqual:@"synthetic draft"]&&host.mainStudyChatView==(id)chat,@"manual layout retains identical chat/session/draft");
    [host.trace removeAllObjects];[main toggleMainStudyChat:nil];Check(main.mainChatWantsVisible&&!chat.isHidden&&window.contentView.layouts==1&&[[host.trace componentsJoinedByString:@","]isEqual:@"chat,layout"],@"manual toggle takes current hidden state then updates/layouts exactly");
    [host.trace removeAllObjects];[main windowDidResize:[NSNotification notificationWithName:@"synthetic resize" object:[BoundaryWindow new]]];Check(host.trace.count==0&&!main.heights,@"other window resize ignored before native actions");[main windowDidResize:[NSNotification notificationWithName:@"synthetic resize" object:window]];Check([[host.trace componentsJoinedByString:@","]isEqual:@"chat,layout,height"]&&main.heights==1&&main.mainChatWantsVisible&&!chat.isHidden,@"own resize preserves manual visibility and update/layout/height order");
    BoundaryNode *pageHost=[BoundaryNode new];main.learningPageHost=(NSView *)pageHost;NSMutableArray *pages=[NSMutableArray new],*buttons=[NSMutableArray new];for(NSUInteger i=0;i<6;i++){BoundaryNode *page=[BoundaryNode new];page.superview=pageHost;[pages addObject:page];[buttons addObject:[BoundaryNode new]];}main.pages=(NSArray *)pages;main.pageButtons=(NSArray *)buttons;BoundaryNode *title=[BoundaryNode new],*description=[BoundaryNode new],*currentWindow=[BoundaryNode new];description.trace=host.trace;main.headerTitleLabel=(NSTextField *)title;main.headerDescriptionLabel=(NSTextField *)description;main.currentWindowLabel=(NSTextField *)currentWindow;
    main.selectedPage=3;[host.trace removeAllObjects];[main selectPageAtIndex:-1];[main selectPageAtIndex:6];Check(main.selectedPage==3&&host.trace.count==0,@"invalid page indices return before any selected-page/native change");
    [main selectPageAtIndex:1];Check(main.selectedPage==1&&host.histories==1&&[title.stringValue isEqual:@"最近台词"]&&[description.stringValue isEqual:@"把之前没看懂的对白，再读一遍。"]&&currentWindow.isHidden&&description.priority==249,@"valid page changes original labels/priority/current-window visibility and history action");Check([[host.trace componentsJoinedByString:@","]isEqual:@"chat,preview-out,priority,history"],@"page chat/preview/header/history action ordering original");Check(!((BoundaryNode *)pages[1]).isHidden&&((BoundaryNode *)pages[0]).isHidden&&((BoundaryNode *)buttons[1]).state==NSControlStateValueOn&&((BoundaryNode *)buttons[1]).needsDisplay,@"actual canonical selected-page primitive runs on mounted native boundary facts");
    [host.trace removeAllObjects];NSUInteger outCount=panel.orders;[main selectPageAtIndex:4];Check(panel.orders==outCount&&main.selectedPage==4&&[[host.trace componentsJoinedByString:@","]isEqual:@"chat,priority"],@"appearance page alone preserves native preview visibility");[main selectPageAtIndex:2];Check(host.vocabularies==1&&[title.stringValue isEqual:@"单词学习"],@"vocabulary page refreshes original peer");[main selectPageAtIndex:0];Check(!currentWindow.isHidden&&[title.stringValue isEqual:@"实时翻译"]&&main.mainChatWantsVisible&&chat.session==session,@"navigation preserves user-selected sidebar and original chat identity");
    BoundaryNode *sender=[BoundaryNode new];sender.state=0; // sender tag is separate native input below.
    main.mainWindow=nil;workspace.constant=123;[main updateMainChatForWindowWidth];Check(workspace.constant==123,@"absent native window leaves original early-return layout contract");Check(NSApp==nil,@"actual Main/nav/chat/resize algorithms execute with native facts only; unmounted layout/full window UI compiled separately");printf("PASS MainWindowBoundaryTests: %lu checks; actual original/new Main algorithms and canonical mounted-page selections, no native UI objects\n",(unsigned long)checks);
}return 0;}
