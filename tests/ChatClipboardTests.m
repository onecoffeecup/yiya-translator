#import "LearningAppTestSupport.h"
// Throw inside the clipboard scope so the finally block restores every item even on failure.
#define Require(condition,message) do { if(!(condition)){@throw [NSException exceptionWithName:@"ClipboardTestFailure" reason:(message) userInfo:nil];} } while(0)
@interface FYClipboardTestApp : AppDelegate
@end
@implementation FYClipboardTestApp
- (BOOL)translationTargetIsForeground{return YES;}
@end
static NSEvent *Shortcut(NSString *key,NSEventModifierFlags flags,NSWindow *window){return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:window.windowNumber context:nil characters:key charactersIgnoringModifiers:key isARepeat:NO keyCode:0];}
static BOOL SelectableReply(NSView *view){if([view isKindOfClass:NSTextField.class] && [[(NSTextField *)view stringValue] isEqualToString:@"例文です。"]){return [(NSTextField *)view isSelectable];}for(NSView *child in view.subviews){if(SelectableReply(child)){return YES;}}return NO;}
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];AppDelegate *app=[FYClipboardTestApp new];[app createApplicationMenu];[app createMainWindow];[app createCaptionWindow];
    NSPasteboard *clipboard=NSPasteboard.generalPasteboard;NSMutableArray *backup=[NSMutableArray new];
    for(NSPasteboardItem *original in clipboard.pasteboardItems){NSPasteboardItem *item=[NSPasteboardItem new];for(NSPasteboardType type in original.types){NSData *data=[original dataForType:type];if(data){[item setData:data forType:type];}}[backup addObject:item];}
    @try {
        for(NSWindow *window in @[app.mainWindow]){
            [window makeKeyAndOrderFront:nil];[app.mainStudyChatView focusInput];NSTextView *input=[app.mainStudyChatView valueForKey:@"input"];
            Require(window.firstResponder==input,@"main AI input receives editing focus");
            input.string=@"相談の使い方";input.selectedRange=NSMakeRange(0,input.string.length);
            Require([[NSApp.mainMenu itemAtIndex:1].submenu itemWithTitle:@"复制"].action==@selector(copy:),@"edit menu exposes responder-chain copy");
            Require([input performKeyEquivalent:Shortcut(@"c",NSEventModifierFlagCommand,window)],@"focused input handles command-copy");
            Require([[clipboard stringForType:NSPasteboardTypeString] isEqualToString:@"相談の使い方"],@"command-copy stores selected sentence");
            input.string=@"";Require([input performKeyEquivalent:Shortcut(@"v",NSEventModifierFlagCommand,window)] && [input.string isEqualToString:@"相談の使い方"],@"command-v pastes into AI input");
            input.selectedRange=NSMakeRange(0,input.string.length);Require([input performKeyEquivalent:Shortcut(@"c",NSEventModifierFlagControl,window)],@"control-copy alias handled");input.string=@"";
            Require([input performKeyEquivalent:Shortcut(@"v",NSEventModifierFlagControl,window)] && [input.string isEqualToString:@"相談の使い方"],@"control-v alias pastes into AI input");
        }
        [app showStudyChatOverlay:nil];[app.studyChatPanel makeKeyAndOrderFront:nil];[app.overlayStudyChatView focusInput];NSTextView *input=[app.overlayStudyChatView valueForKey:@"input"];
        Require(input!=nil && app.studyChatPanel.firstResponder==input,@"independent AI input receives editing focus");
        Tick();[app.overlayStudyChatView focusInput];input.string=@"質問：";[clipboard clearContents];[clipboard setString:@"相談の使い方" forType:NSPasteboardTypeString];input.selectedRange=NSMakeRange(input.string.length,0);
        BOOL handled=[input performKeyEquivalent:Shortcut(@"v",NSEventModifierFlagCommand,app.studyChatPanel)];
        Require(handled && [input.string isEqualToString:@"質問：相談の使い方"],@"floating AI command-paste appends at insertion point");
        Require([input performKeyEquivalent:Shortcut(@"a",NSEventModifierFlagCommand,app.studyChatPanel)] && input.selectedRange.length==input.string.length,@"floating AI select-all works");
        Require([input performKeyEquivalent:Shortcut(@"x",NSEventModifierFlagCommand,app.studyChatPanel)] && input.string.length==0,@"floating AI cut works");
        // —— 当前对白 → 系统剪贴板 → AI 输入框（用户报的路径）——
        NSString *dialogue=@"カレンさんでーす！\n初メールしました！";
        NSTextView *source=[app learningSourceTextView];
        source.string=dialogue;   // 直接放入对白文本（复制路径与此无关，本套件没有学习库）
        Require(source.selectable && !source.editable,@"当前对白 must stay selectable but read-only");
        [source setSelectedRange:NSMakeRange(0,5)];
        Require(source.selectedRange.length==5,@"当前对白 keeps the user's selection");
        [clipboard clearContents];
        [source copy:nil];
        NSString *copied=[clipboard stringForType:NSPasteboardTypeString];
        Require([copied isEqualToString:@"カレンさん"],@"copying 当前对白 must reach the system clipboard");
        // 复制到的内容再贴进 AI 输入框（含已有草稿，插在光标处）
        [app.mainStudyChatView focusInput];NSTextView *mainInput=[app.mainStudyChatView valueForKey:@"input"];
        Require(app.mainWindow.firstResponder==mainInput,@"main AI input holds focus before pasting");
        mainInput.string=@"草稿：";mainInput.selectedRange=NSMakeRange(mainInput.string.length,0);
        BOOL pasted=[mainInput performKeyEquivalent:Shortcut(@"v",NSEventModifierFlagCommand,app.mainWindow)];
        Require(pasted && [mainInput.string isEqualToString:@"草稿：カレンさん"],@"pasting 当前对白 text into the AI input inserts at the caret");
        // 选中一段后粘贴要替换选区（不追加）
        mainInput.string=@"草稿：旧内容";mainInput.selectedRange=NSMakeRange(3,3);
        [mainInput performKeyEquivalent:Shortcut(@"v",NSEventModifierFlagCommand,app.mainWindow)];
        Require([mainInput.string isEqualToString:@"草稿：カレンさん"],@"pasting replaces the selected range instead of appending");
        // 多行日文：换行与标点保留
        NSString *multiline=@"初メールしました！\nこれからメールでも\nヨロシクね❤";
        [clipboard clearContents];[clipboard setString:multiline forType:NSPasteboardTypeString];
        mainInput.string=@"";mainInput.selectedRange=NSMakeRange(0,0);
        [mainInput performKeyEquivalent:Shortcut(@"v",NSEventModifierFlagCommand,app.mainWindow)];
        Require([mainInput.string isEqualToString:multiline],@"multi-line Japanese pastes with newlines and punctuation intact");
        // 点击输入框必须真的命中文本框；粘贴动作必须沿响应链落到它身上（没有被菜单或快捷键拦截）
        NSPoint inputCentre=[mainInput convertPoint:NSMakePoint(NSMidX(mainInput.bounds),NSMidY(mainInput.bounds)) toView:nil];
        Require([app.mainWindow.contentView hitTest:inputCentre]==mainInput,
                @"a click inside the AI input shell must land on the text view so it can take focus");
        // 无头测试进程没有 key window，targetForAction: 解析不了；改为断言菜单本身没有写死 target，
        // 即 paste: 走响应链而不是被菜单/全局快捷键截走。
        NSMenuItem *editPaste=[[NSApp.mainMenu itemAtIndex:1].submenu itemWithTitle:@"粘贴"];
        Require(editPaste!=nil && editPaste.action==@selector(paste:) && editPaste.target==nil,
                @"the Edit menu's 粘贴 must stay responder-chain routed (no hard-wired target intercepting paste:)");
        NSEvent *rightClick=[NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:inputCentre modifierFlags:0 timestamp:0 windowNumber:app.mainWindow.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
        NSMenu *contextMenu=[mainInput menuForEvent:rightClick];
        BOOL hasPaste=NO;
        // 标准右键菜单项标题跟随系统语言，按 action 判定更可靠。
        for(NSMenuItem *item in contextMenu.itemArray){if(item.action==@selector(paste:)){hasPaste=YES;}}
        Require(hasPaste,@"the AI input context menu offers paste:");
        NSTextField *context=[app.mainStudyChatView valueForKey:@"contextText"];Require(context.selectable,@"referenced source can be selected for copying");
        [app.mainStudyChatView setMessages:@[@{@"role":@"assistant",@"content":@"例文です。"}]];
        NSStackView *messages=[app.mainStudyChatView valueForKey:@"messagesStack"];
        Require(SelectableReply(messages),@"AI reply text supports selection and copying");
    } @finally {[clipboard clearContents];if(backup.count){[clipboard writeObjects:backup];}}
    [app closeStudyOverlay:nil];[app.mainWindow orderOut:nil];NSLog(@"PASS: 当前对白 copy → system clipboard → AI input paste (caret/replace/multi-line), editing menu, main/floating AI clipboard shortcuts and selectable source/replies; clipboard restored");
}return 0;}
