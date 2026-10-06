#import "LearningAppTestSupport.h"
@interface FYChatPresentationApp : AppDelegate
@end
@implementation FYChatPresentationApp
- (BOOL)translationTargetIsForeground{return YES;}
@end
static NSString *VisibleText(NSView *view){NSMutableString *text=[NSMutableString new];if([view isKindOfClass:NSTextField.class]){[text appendString:[(NSTextField *)view stringValue]];}for(NSView *child in view.subviews){[text appendString:VisibleText(child)];}return text;}
static NSView *IdentifiedView(NSView *view,NSString *identifier){if([view.identifier isEqualToString:identifier]){return view;}for(NSView *child in view.subviews){NSView *found=IdentifiedView(child,identifier);if(found){return found;}}return nil;}
int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];FYLearningStore *store=Store([NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]);FYGrammarCatalog *catalog=[FYGrammarCatalog new];AppDelegate *app=App(store,Analyzer(catalog),catalog);
    [app.learningCoordinator recordText:@"雨が降った。" kind:FYSentenceKindDialogue];Drain(store);
    FYStudyChatSession *session=app.studyChatSession;session.analyzer.baseURL=@"https://example.invalid/v1";session.analyzer.apiKey=@"test-only";session.analyzer.model=@"mock-model";
    __block void (^pending)(NSData *,NSURLResponse *,NSError *);__block NSDictionary *payload;
    session.analyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){pending=[done copy];payload=[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];};
    [session referenceSource:@"前の台詞です。" translation:@"上一句"];[session send:@"旧问题"];pending(Envelope(@"旧回复"),Response(),nil);Pump(^BOOL{return !session.sending;});
    Require(session.messages.count==2,@"fixture has both old question and answer");
    [app referenceLatestStudySentence:nil];Pump(^BOOL{return [session.source isEqualToString:@"雨が降った。"];});
    Require(session.messages.count==0 && ![VisibleText(app.mainStudyChatView) containsString:@"旧回复"] && ![VisibleText(app.mainStudyChatView) containsString:@"旧问题"],@"referencing latest clears sent question and answer from shared session and view");
    [session send:@"新问题"];Require([payload[@"messages"] count]==2 && ![[payload description] containsString:@"旧问题"],@"new reference excludes old conversation from next request");
    void (^late)(NSData *,NSURLResponse *,NSError *)=[pending copy];[app referenceLatestStudySentence:nil];
    Require(session.messages.count==0 && !session.sending,@"same-sentence reference also clears pending question and cancels request");late(Envelope(@"迟到回复"),Response(),nil);Tick();Require(session.messages.count==0,@"late old reply cannot return after reset");
    NSArray *messages=@[@{@"role":@"user",@"content":@"为什么用 **でも**？"},@{@"role":@"assistant",@"content":@"## 用法\n**でも** 表示让步。\n- `得意でも`：即使擅长。\n[来源](https://example.invalid/reference)"}];
    for(FYStudyChatView *view in @[app.mainStudyChatView]){
        [view setMessages:messages];Tick();NSString *text=VisibleText(view);
        Require([text containsString:@"でも 表示让步。"] && [text containsString:@"• 得意でも"] && [text containsString:@"来源（https://example.invalid/reference）"],@"assistant markdown markers display as ordinary text without losing content and links");
        Require([text containsString:@"为什么用 **でも**？"],@"user input is displayed verbatim");
        Require(IdentifiedView(view,@"chat-user-bubble") && IdentifiedView(view,@"chat-assistant-bubble"),@"both speakers have dialogue bubbles");
    }
    if(argc>1){[app.mainWindow.contentView layoutSubtreeIfNeeded];NSView *root=app.mainWindow.contentView;NSBitmapImageRep *bitmap=[root bitmapImageRepForCachingDisplayInRect:root.bounds];[root cacheDisplayInRect:root.bounds toBitmapImageRep:bitmap];NSString *path=[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"chat-bubbles.png"];Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"bubble screenshot saved");}
    [app.mainWindow orderOut:nil];
    NSLog(@"PASS: latest-reference reset, fresh request context, cancellation/late replies, ordinary-text dialogue bubbles");
}return 0;}
