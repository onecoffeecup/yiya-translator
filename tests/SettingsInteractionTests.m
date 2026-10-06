#import "LearningAppTestSupport.h"

@interface SettingsTestApp : AppDelegate
@property(nonatomic,strong) NSURL *openedLicenseDirectory;
@end
@implementation SettingsTestApp
- (BOOL)translationTargetIsForeground { return NO; }
- (NSString *)bundledLicenseNotes {
    return [NSString stringWithContentsOfFile:@"resources/learning/LICENSE-NOTES.txt" encoding:NSUTF8StringEncoding error:NULL];
}
- (NSURL *)referenceResourceURL:(NSString *)file {
    return [NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:[@"resources/learning/reference" stringByAppendingPathComponent:file]]];
}
- (BOOL)openReferenceLicensesDirectory:(NSURL *)directory { self.openedLicenseDirectory=directory;return YES; }
@end

static NSView *Find(NSView *view, BOOL (^matches)(NSView *)) {
    if(matches(view)){return view;}
    for(NSView *child in view.subviews){NSView *found=Find(child,matches);if(found){return found;}}
    return nil;
}
static NSButton *Button(NSView *root,SEL action) {
    return (NSButton *)Find(root,^BOOL(NSView *view){return [view isKindOfClass:NSButton.class] && [(NSButton *)view action]==action;});
}
static void Snapshot(NSView *view,NSString *path) {
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    Require([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"screenshot save failed");
}

int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSString *output=argc>1?@(argv[1]):@".build/test-results/SettingsInteractionTests";
    FYLearningStore *store=Store([NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite"]]);
    FYGrammarCatalog *catalog=[FYGrammarCatalog new];SettingsTestApp *app=[SettingsTestApp new];app.learningStore=store;
    app.learningCoordinator=[[FYLearningCoordinator alloc] initWithStore:store analyzer:Analyzer(catalog) tokenizer:[FYJapaneseTokenizer new] catalog:catalog];
    [app createMainWindow];[app createCaptionWindow];
    [app.mainWindow makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    if(!app.mainStudyChatView.hidden){[app toggleMainStudyChat:nil];}
    [app selectPageAtIndex:4];[app.mainWindow.contentView layoutSubtreeIfNeeded];Tick();
    NSString *caption=app.captionTextLabel.stringValue;NSRect frame=app.captionPanel.frame;BOOL shown=app.captionPanelShownByUser;
    NSButton *preview=Button(app.pages[4],@selector(showCaptionAppearancePreview:));
    Require([preview.title isEqualToString:@"打开字幕预览"],@"appearance action clearly announces preview");
    [preview performClick:nil];Tick();
    Require(app.captionAppearancePreviewPanel.isVisible && !app.captionPanel.isVisible,@"settings opens a visible preview outside the game without raising the real caption");
    Require([app.captionAppearancePreviewPanel.title containsString:@"示例文字"] && [app.captionAppearancePreviewBrand.stringValue containsString:@"示例"],@"sample content is explicitly identified");
    Require(NSEqualRects(frame,app.captionPanel.frame),@"opening a sample does not move or resize the game caption");
    app.captionFontSizeSlider.doubleValue=56;app.captionThemeControl.selectedSegment=1;app.captionOpacitySlider.doubleValue=.85;
    [NSApp sendAction:app.captionFontSizeSlider.action to:app from:app.captionFontSizeSlider];Tick();
    Require(app.captionAppearancePreviewText.font.pointSize==56 && [app.captionAppearancePreviewText.textColor isEqual:[app captionTextColor]],@"style controls update preview immediately");
    [app.captionAppearancePreviewPanel.contentView layoutSubtreeIfNeeded];
    Require(NSMinY(app.captionAppearancePreviewText.frame)>=20 && NSMaxY(app.captionAppearancePreviewText.frame)<=NSMinY(app.captionAppearancePreviewBrand.frame),@"large text fits below the label and inside the preview");
    app.captionFontSizeSlider.doubleValue=30;app.captionThemeControl.selectedSegment=3;[app updateCaptionAppearance];Tick();
    Snapshot(app.captionAppearancePreviewPanel.contentView,[output stringByAppendingPathComponent:@"caption-preview.png"]);
    Require([app.captionTextLabel.stringValue isEqualToString:caption] && app.captionPanelShownByUser==shown,@"sample never replaces translation or changes its hide/show preference");
    [app selectPageAtIndex:5];Tick();Require(!app.captionAppearancePreviewPanel.isVisible,@"leaving appearance closes the preview");
    NSButton *disclosure=(NSButton *)Find(app.pages[5],^BOOL(NSView *view){return [view isKindOfClass:NSButton.class] && [[(NSButton *)view title] isEqualToString:@"资料来源与许可"];});
    Require(disclosure!=nil,@"source disclosure exists");[disclosure performClick:nil];[app.mainWindow.contentView layoutSubtreeIfNeeded];Tick();
    NSScrollView *notes=(NSScrollView *)Find(app.pages[5],^BOOL(NSView *view){return [view.identifier isEqualToString:@"reference-license-notes"];});
    NSTextView *text=(NSTextView *)notes.documentView;
    Require(![notes isHiddenOrHasHiddenAncestor] && text.selectable && !text.editable && [text.string containsString:@"JMdict"] && [text.string containsString:@"CC BY-SA 4.0"],@"expanded source has readable selectable real attribution");
    for(NSNumber *width in @[@1320,@980]){
        [app.mainWindow setContentSize:NSMakeSize(width.doubleValue,660)];[app.mainWindow.contentView layoutSubtreeIfNeeded];Tick();
        [text.layoutManager ensureLayoutForTextContainer:text.textContainer];
        Require(NSWidth(text.frame)>200 && fabs(NSWidth(text.frame)-NSWidth(notes.contentView.bounds))<3,@"source document fills normal and minimum-width viewports");
        Require([text.layoutManager usedRectForTextContainer:text.textContainer].size.height>100 && NSHeight(text.frame)>100,@"source glyphs have nonzero document geometry");
    }
    [notes scrollRectToVisible:notes.bounds];Tick();Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"license-disclosure.png"]);
    NSButton *finder=Button(app.pages[5],@selector(showReferenceLicenses:));Require([finder.title containsString:@"Finder"],@"external action explicitly names Finder");
    [finder performClick:nil];
    Require([app.openedLicenseDirectory.lastPathComponent isEqualToString:@"licenses"] && [NSFileManager.defaultManager fileExistsAtPath:[app.openedLicenseDirectory.path stringByAppendingPathComponent:@"CC-BY-SA-4.0.txt"]],@"external action selects actual licenses rather than the raw database folder");
    [disclosure performClick:nil];Require([notes isHiddenOrHasHiddenAncestor],@"source can collapse again");
    [app.mainWindow orderOut:nil];[app.captionAppearancePreviewPanel orderOut:nil];[app.captionPanel orderOut:nil];
    __block BOOL closed=NO;[store closeWithCompletion:^(NSError *error){Require(!error,@"close");closed=YES;}];Pump(^BOOL{return closed;});
    NSLog(@"PASS: visible caption preview, live styles, foreground isolation, source text geometry, narrow layout and explicit license folder action");
}return 0;}
