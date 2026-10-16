#import "FYStudyChatRenderer.h"
#import "../learning/FYStudyChatView.h"
#import "../learning/FYStudyChatSession.h"
#import "../learning/FYStudyOverlayPanel.h"
#import "../learning/FYLearningViews.h"
#import "FYFlippedDocumentView.h"
#import "FYPresentationText.h"
#import <QuartzCore/QuartzCore.h>

@implementation FYStudyChatRenderer
+ (FYStudyChatView *)makeStudyChatViewForOverlay:(BOOL)overlay receiver:(id<FYStudyChatRenderSource>)receiver {
    [receiver ensureStudyChatSession];FYStudyChatView *view=[FYStudyChatView new];view.translatesAutoresizingMaskIntoConstraints=NO;
    __weak id<FYStudyChatRenderSource> weakSelf=receiver;
    view.onSend=^(NSString *text){[weakSelf sendStudyChat:text];};
    view.onLatest=^{[weakSelf referenceLatestStudySentence:nil];};
    // 从贴译学习卡进入 AI 时，返回动作走聊天组件自己的导航行回调。
    view.onReturn=^{[weakSelf returnFromStudyChatToInlineLearning:nil];};
    if(overlay){
        view.onClose=^{[weakSelf closeStudyOverlay:nil];};
    }else{
        // 主内容区右上角有唯一的显隐开关：侧栏内部不再放「收起」，避免两个入口状态不同步。
        [view setCloseVisible:NO];
    }
    return view;
}

+ (void)refreshStudyChatViewsWithReceiver:(id<FYStudyChatRenderSource>)receiver {
    for(FYStudyChatView *view in @[receiver.mainStudyChatView ?: (id)NSNull.null,receiver.overlayStudyChatView ?: (id)NSNull.null]){
        if(![view isKindOfClass:FYStudyChatView.class]){continue;}
        [view setContextText:receiver.studyChatSession.source label:receiver.chatResolvingSource?@"正在识别当前画面的对白…":@"当前讨论句 · 点击引用最新句可更新"];
        [view setMessages:receiver.studyChatSession.messages];[view setSending:receiver.studyChatSession.sending || receiver.chatResolvingSource];
    }
}

+ (void)configureStudyOverlay:(NSPanel *)panel receiver:(id<FYStudyChatRenderSource>)receiver {
    panel.hidesOnDeactivate=NO;panel.releasedWhenClosed=NO;panel.level=NSFloatingWindowLevel;
    panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.backgroundColor=receiver.uiSurface;panel.movableByWindowBackground=YES;
}

+ (void)updateInlineReturnButtonVisibilityWithReceiver:(id<FYStudyChatRenderSource>)receiver {
    BOOL hasReturn = receiver.inlineReturnSnapshot != nil && receiver.inlineReturnSnapshot.sourceText.length > 0;
    // 返回入口在聊天组件自己的导航行里；主窗口 AI 不显示该入口。
    [receiver.overlayStudyChatView setReturnVisible:hasReturn];
    receiver.inlineReturnButton = hasReturn ? receiver.overlayStudyChatView.returnButton : nil;
}
@end
