#import "LearningAppTestSupport.h"
static NSView *FindServiceView(NSView *root, NSString *identifier) {
    if([root.identifier isEqual:identifier]) return root;
    for(NSView *child in root.subviews) { NSView *match=FindServiceView(child,identifier); if(match) return match; }
    return nil;
}
static CGFloat ServiceBrightness(NSColor *color) {
    NSColor *rgb=[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return .2126*rgb.redComponent+.7152*rgb.greenComponent+.0722*rgb.blueComponent;
}
static void ServiceSnapshot(NSView *view,NSString *path) {
    [view layoutSubtreeIfNeeded]; NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    Require([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"native service screenshot saved");
}
static void ServiceResize(AppDelegate *app,CGFloat width) {
    // Exercise the live-resize delegates as well as AppKit's layout pressure;
    // setContentSize alone skips the boundary that releases the idle width lock.
    NSLayoutConstraint *drag=[app.mainWindow.contentView.widthAnchor constraintEqualToConstant:width];
    drag.priority=NSLayoutPriorityDragThatCanResizeWindow;
    [app windowWillStartLiveResize:[NSNotification notificationWithName:NSWindowWillStartLiveResizeNotification object:app.mainWindow]];
    drag.active=YES;
    Tick(); [app.mainWindow.contentView layoutSubtreeIfNeeded]; Tick();
    NSLog(@"SERVICE_RESIZE desired=%.0f actual=%.0f preferred=%.0f",width,NSWidth(app.mainWindow.contentView.bounds),app.mainWindowContentWidth.constant);
    Require(fabs(NSWidth(app.mainWindow.contentView.bounds)-width)<2,@"service controls allow the native drag-priority window width");
    [app windowDidEndLiveResize:[NSNotification notificationWithName:NSWindowDidEndLiveResizeNotification object:app.mainWindow]];
    drag.active=NO;
    Tick(); [app.mainWindow.contentView layoutSubtreeIfNeeded]; Tick();
    NSLog(@"SERVICE_WINDOW requested=%.0f actual=%.0f",width,NSWidth(app.mainWindow.contentView.bounds));
    Require(fabs(NSWidth(app.mainWindow.contentView.bounds)-width)<2,@"service controls preserve the chosen native window width");
}
int main(int argc,const char *argv[]) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *output=argc>1 ? @(argv[1]) : @".build/test-results/TranslationServiceViewTests";
    AppDelegate *app=[AppDelegate new]; [app createMainWindow]; [app loadSettings];
    [app selectPageAtIndex:5]; [app.mainWindow makeKeyAndOrderFront:nil]; Tick();
    NSView *service=app.translationServiceView.view;
    Require(service && app.baseURLField==app.translationServiceView.baseURLField && app.modelField.delegate==app.translationServiceView,@"service component owns its fields and input handling");
    for(NSString *identifier in @[@"service-mode-preset",@"service-mode-custom"]) {
        NSButton *button=(NSButton *)FindServiceView(service,identifier);
        Require(button.image && button.imagePosition==NSImageLeft,@"both mode buttons retain the list/link icons shown in the approved preview");
    }
    Require([app.modelField isMemberOfClass:NSTextField.class] && app.modelField.editable && app.modelField.selectable,@"preset model is an ordinary editable native text field");
    for(NSTextField *field in @[app.baseURLField,app.modelField,app.apiKeyField])
        Require(ServiceBrightness(field.backgroundColor)>.8,@"cream form uses readable light input backgrounds instead of an unknown theme token");
    for(NSDictionary *preset in FYTranslationServicePresets()) Require(FindServiceView(service,preset[@"id"])!=nil,@"all ten provider cards exist");
    NSButton *claude=(NSButton *)FindServiceView(service,@"claude"); [claude performClick:nil]; Tick();
    Require([app.baseURLField.stringValue isEqual:@"https://api.anthropic.com/v1"] && !app.baseURLField.editable && app.modelField.editable,@"preset URL is filled and model remains editable");
    app.modelField.stringValue=@"typed-claude-model";
    [app.translationServiceView controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:app.modelField]];
    NSPopUpButton *models=(NSPopUpButton *)FindServiceView(service,@"service-common-models");
    [models selectItemAtIndex:2]; [NSApp sendAction:models.action to:models.target from:models];
    Require([app.modelField.stringValue isEqual:@"claude-haiku-5-5"] && models.indexOfSelectedItem==0 && app.modelField.editable,@"common model copies into editable field and resets its picker");
    app.modelField.stringValue=@"manual-claude-model"; [app.translationServiceView controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:app.modelField]];
    [(NSButton *)FindServiceView(service,@"glm") performClick:nil]; [claude performClick:nil];
    Require([app.modelField.stringValue isEqual:@"manual-claude-model"],@"manual preset model survives provider changes");
    [(NSButton *)FindServiceView(service,@"service-mode-custom") performClick:nil];
    Require(app.baseURLField.editable && app.modelField.editable && [models isHiddenOrHasHiddenAncestor],@"custom mode has editable URL and model without a model picker");
    app.baseURLField.stringValue=@"http://localhost:1234/v1"; app.modelField.stringValue=@"local-model"; app.apiKeyField.stringValue=@"synthetic-key";
    [app.translationServiceView controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:app.modelField]];
    [app saveSettings:nil]; NSDictionary *saved=[NSUserDefaults.standardUserDefaults objectForKey:SettingsKey];
    Require([saved[@"model"] isEqual:@"local-model"] && [saved[@"serviceMode"] isEqual:@"custom"] && !saved[@"apiKey"],@"component drafts integrate with settings without storing Key in preferences");
    [app loadSettings]; Require([app.modelField.stringValue isEqual:@"local-model"] && [app.baseURLField.stringValue isEqual:@"http://localhost:1234/v1"],@"saved custom model and URL restore through application load");
    for(NSNumber *width in @[@720,@960,@1024,@1320,@1600]) {
        ServiceResize(app,width.doubleValue);
        NSScrollView *page=(NSScrollView *)app.pages[5]; NSView *content=page.documentView;
        for(NSView *control in @[app.baseURLField,app.modelField,app.apiKeyField]) {
            NSRect rect=[control convertRect:control.bounds toView:content];
            Require(NSMinX(rect)>=-1 && NSMaxX(rect)<=NSWidth(content.bounds)+1 && NSWidth(rect)>100,@"native service inputs fit narrow and wide windows");
        }
        if(width.integerValue==960) Require(((NSStackView *)app.modelField.superview).orientation==NSUserInterfaceLayoutOrientationVertical,@"compact service form moves the model picker below the editable field while AI remains visible");
        if(width.integerValue==1320) ServiceSnapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"service-custom-native.png"]);
    }
    [(NSButton *)FindServiceView(service,@"service-mode-preset") performClick:nil]; [(NSButton *)FindServiceView(service,@"deepseek") performClick:nil];
    ServiceResize(app,1600);
    for(NSDictionary *preset in FYTranslationServicePresets()) {
        NSButton *button=(NSButton *)FindServiceView(service,preset[@"id"]); NSRect rect=[button convertRect:button.bounds toView:service];
        Require(NSWidth(rect)>100 && NSMinX(rect)>=-1 && NSMaxX(rect)<=NSWidth(service.bounds)+1,@"preset cards reflow inside the native service width");
        NSBitmapImageRep *rep=[button bitmapImageRepForCachingDisplayInRect:button.bounds]; [button cacheDisplayInRect:button.bounds toBitmapImageRep:rep];
        NSColor *fill=[rep colorAtX:rep.pixelsWide-18 y:rep.pixelsHigh-18];
        Require(ServiceBrightness(fill)>.8,@"selected and unselected provider cards render light cream or green interiors");
    }
    Require(NSWidth(app.serviceTestButton.frame)<250,@"test action keeps a compact width beside its status");
    [app.mainWindow makeFirstResponder:nil];
    ServiceSnapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"service-presets-native.png"]);
    ServiceResize(app,720);
    for(NSDictionary *preset in FYTranslationServicePresets()) {
        NSButton *button=(NSButton *)FindServiceView(service,preset[@"id"]); NSRect rect=[button convertRect:button.bounds toView:service];
        Require(NSWidth(rect)>100 && NSMinX(rect)>=-1 && NSMaxX(rect)<=NSWidth(service.bounds)+1,@"preset cards fit the minimum-width native window");
    }
    NSView *content=((NSScrollView *)app.pages[5]).documentView;
    for(NSView *control in @[app.baseURLField,app.modelField,app.apiKeyField]) {
        NSRect rect=[control convertRect:control.bounds toView:content];
        Require(NSMinX(rect)>=-1 && NSMaxX(rect)<=NSWidth(content.bounds)+1 && NSWidth(rect)>100,@"preset fields remain editable and inside the narrow scroll document");
    }
    ServiceSnapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"service-presets-narrow-native.png"]);
    [app clearAPIKey:nil]; Require(FYTestLocalAPIKeyValue==nil,@"existing clear action still removes the isolated credential");
    [app.mainWindow orderOut:nil]; [app.saveTimer invalidate];
    NSLog(@"PASS: native service ownership, presets, typing, common models, custom drafts, migration, Key actions and layout (isolated inputs, no service calls)");
} return 0; }
