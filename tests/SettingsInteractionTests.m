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
static void CheckShortPreview(FYSubtitleAppearancePreview *sample) {
    [sample layoutSubtreeIfNeeded];
    for(NSView *surface in [sample.translationSurfaces subarrayWithRange:NSMakeRange(0,2)]){
        NSTextField *label=(NSTextField *)Find(surface,^BOOL(NSView *view){return [view isKindOfClass:NSTextField.class];});
        NSSize natural=label.cell.cellSize;
        NSSize fitted=[label.cell cellSizeForBounds:label.bounds];
        Require(label.selectable && fitted.height<=natural.height+1 && NSHeight(label.frame)>=natural.height-1,
            @"short preview translations fit one complete selectable line");
    }
}

int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSString *output=argc>1?@(argv[1]):@".build/test-results/SettingsInteractionTests";
    FYLearningStore *store=Store([NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite"]]);
    FYGrammarCatalog *catalog=[FYGrammarCatalog new];SettingsTestApp *app=[SettingsTestApp new];app.learningStore=store;
    app.learningCoordinator=[[FYLearningCoordinator alloc] initWithStore:store analyzer:Analyzer(catalog) tokenizer:[FYJapaneseTokenizer new] catalog:catalog];
    [app createMainWindow];[app createCaptionWindow];
    [app.mainWindow makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    [app.mainWindow setContentSize:NSMakeSize(720,700)];[app selectPageAtIndex:4];Tick();
    NSScrollView *narrowAppearance=(NSScrollView *)app.pages[4];
    Require(fabs(NSWidth(app.mainWindow.contentView.bounds)-720)<2 && app.mainStudyChatView.hidden &&
            !app.mainChatToggle.enabled && NSWidth(narrowAppearance.frame)>500,@"narrow window keeps its requested width and releases AI space for readable settings");
    Require(app.appearanceModeControl.selectedSegment==1 && app.appearanceEditors[0].hidden && !app.appearanceEditors[1].hidden,@"concentrated settings start with inline appearance without the other editor taking space");
    for(NSButton *choice in app.batchThemeSwatches){
        NSRect themeFrame=[choice convertRect:choice.bounds toView:narrowAppearance.contentView];
        Require(NSMinX(themeFrame)>=0 && NSMaxX(themeFrame)<=NSWidth(narrowAppearance.contentView.bounds)+1 && NSWidth(themeFrame)>80,@"all four inline palette cards remain usable inside narrow settings");
    }
    CheckShortPreview(app.appearanceSamples[1]);
    Snapshot(app.appearanceSamples[1],[output stringByAppendingPathComponent:@"appearance-inline-concentrated-narrow.png"]);
    Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"appearance-narrow-with-ai-auto-collapsed.png"]);
    [app.mainWindow setContentSize:NSMakeSize(1320,800)];Tick();
    Require(fabs(NSWidth(app.mainWindow.contentView.bounds)-1320)<2 && !app.mainStudyChatView.hidden && app.mainChatToggle.enabled,@"window regains its requested width and AI sidebar returns");
    if(!app.mainStudyChatView.hidden){[app toggleMainStudyChat:nil];}
    [app.mainWindow setContentSize:NSMakeSize(720,700)];Tick();
    [app.mainWindow setContentSize:NSMakeSize(1320,800)];Tick();
    Require(app.mainStudyChatView.hidden,@"manual AI collapse remains the user's choice after a narrow/wide resize");
    [app selectPageAtIndex:4];[app.mainWindow.contentView layoutSubtreeIfNeeded];Tick();
    FYLearningColumnsView *workbench=(FYLearningColumnsView *)Find(app.pages[4],^BOOL(NSView *view){return [view.identifier isEqualToString:@"appearance-inline-columns"];});
    CGFloat controlsWidth=NSWidth(workbench.arrangedSubviews[0].frame), previewWidth=NSWidth(workbench.arrangedSubviews[1].frame);
    NSDictionary *metrics=@{@"workbench_width":@(NSWidth(workbench.frame)),@"controls_width":@(controlsWidth),@"preview_width":@(previewWidth),@"controls_fraction":@(controlsWidth/(controlsWidth+previewWidth)),@"inline_body_font":@(app.appearanceSamples[1].translationLabel.font.pointSize)};
    [[NSJSONSerialization dataWithJSONObject:metrics options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[output stringByAppendingPathComponent:@"appearance-fidelity-metrics.json"] atomically:YES];
    NSLog(@"APPEARANCE_FIDELITY %@",metrics);
    Require(fabs(controlsWidth/(controlsWidth+previewWidth)-1.0/3)<.02,@"approved preview keeps settings and preview columns at one to two");
    Require(app.appearanceSamples[1].translationLabel.font.pointSize==16,@"approved inline preview uses the selected 16 pt without an extra size offset");
    FYSubtitleAppearancePreview *inlineSample=app.appearanceSamples[1];
    Require(inlineSample.sourcePanels.count==2 && inlineSample.translationSurfaces[0].superview==inlineSample.sourcePanels[0] && inlineSample.translationSurfaces[2].superview==inlineSample.sourcePanels[1],@"approved sample retains two separate source panels instead of a fixed sidebar");
    Require(fabs(NSWidth(inlineSample.sourcePanels[1].frame)/NSWidth(inlineSample.sourcePanels[0].frame)-1.2)<.02,@"source panel proportions follow the approved one to 1.2 grid");
    Require(fabs(NSWidth(inlineSample.translationSurfaces[2].frame)/(NSWidth(inlineSample.sourcePanels[1].frame)-24)-.8667)<.01,@"default card width follows the approved range mapping inside the right source panel");
    NSParagraphStyle *sampleParagraph=[inlineSample.translationLabel.attributedStringValue attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    Require(fabs(sampleParagraph.minimumLineHeight-24.8)<.01 && [inlineSample.translationLabel.font.fontName containsString:@"Regular"],@"approved inline demo uses regular 16 pt with 1.55 line height");
    NSView *opacityCard=Find(app.pages[4],^BOOL(NSView *view){return [view.identifier isEqualToString:@"appearance-opacity-row"];});
    NSRect sliderAlignment=[app.captionOpacitySlider alignmentRectForFrame:app.captionOpacitySlider.frame];
    NSLog(@"OPACITY_FIDELITY card=%@ slider_alignment=%@",NSStringFromRect(opacityCard.frame),NSStringFromRect(sliderAlignment));
    Require(NSHeight(opacityCard.frame)<=74 && NSWidth(sliderAlignment)<=261 && NSHeight(sliderAlignment)==22,@"shared opacity remains a compact horizontal strip with a bounded slider alignment rect");
    Require([app.captionOpacitySlider.accessibilityLabel isEqualToString:@"背景不透明度"],@"shared opacity slider preserves its native accessibility name");
    Require(NSEqualSizes(app.batchTextColorWell.frame.size,NSMakeSize(48,32)) && NSHeight(app.appearanceModeButtons[0].frame)==40,@"color swatch and mode buttons match approved sizes");
    NSButton *follow=Button(app.appearanceEditors[1],@selector(resetBatchTextColor:));
    Require(fabs(NSWidth(follow.frame)-70)<1,@"follow-style button keeps its compact width when the control column grows");
    CheckShortPreview(app.appearanceSamples[1]);
    Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"appearance-inline-concentrated-wide.png"]);
    // Same 836 pt settings width as the approved 1028 px HTML screenshot.
    [app.mainWindow setContentSize:NSMakeSize(1058,900)];Tick();
    NSLog(@"REFERENCE_WINDOW frame=%@ content=%@ editor=%@ width_lock=%g",NSStringFromRect(app.mainWindow.frame),NSStringFromRect(app.mainWindow.contentView.bounds),NSStringFromRect(app.appearanceEditors[1].frame),app.mainWindowContentWidth.constant);
    Require(fabs(NSWidth(app.mainWindow.contentView.bounds)-1058)<2 && fabs(NSWidth(app.appearanceEditors[1].frame)-836)<2,@"reference screenshot uses the approved 836 pt settings width");
    Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"appearance-inline-reference-width.png"]);
    Snapshot(app.appearanceEditors[1],[output stringByAppendingPathComponent:@"appearance-inline-editor-reference-width.png"]);
    [app.mainWindow setContentSize:NSMakeSize(1320,900)];Tick();
    NSButton *inlineDimensions=(NSButton *)Find(app.appearanceEditors[1],^BOOL(NSView *view){return [view isKindOfClass:FYSubtitleDisclosureButton.class];});
    [inlineDimensions performClick:nil];Tick();
    for(NSNumber *windowWidth in @[@1320,@720]){
        [app.mainWindow setContentSize:NSMakeSize(windowWidth.doubleValue,900)];Tick();
        for(NSNumber *fontSize in @[@13,@16,@30]){
            app.batchFontSizeSlider.doubleValue=fontSize.doubleValue;
            [NSApp sendAction:app.batchFontSizeSlider.action to:app from:app.batchFontSizeSlider];Tick();
            app.batchHeightSlider.doubleValue=160;
            [NSApp sendAction:app.batchHeightSlider.action to:app from:app.batchHeightSlider];Tick();
            CGFloat smallHeight=NSHeight(inlineSample.translationSurfaces.lastObject.frame);
            app.batchHeightSlider.doubleValue=500;
            [NSApp sendAction:app.batchHeightSlider.action to:app from:app.batchHeightSlider];Tick();
            CGFloat largeHeight=NSHeight(inlineSample.translationSurfaces.lastObject.frame);
            NSLog(@"HEIGHT_PREVIEW width=%@ font=%@ small=%g large=%g",windowWidth,fontSize,smallHeight,largeHeight);
            Require(fabs(smallHeight-160*.46)<1 && fabs(largeHeight-500*.46)<1,
                @"expanded dimensions use a long example so both height limits visibly resize the native card");
            NSScrollView *heightScroll=(NSScrollView *)Find(inlineSample.translationSurfaces.lastObject,^BOOL(NSView *view){return [view isKindOfClass:NSScrollView.class];});
            Require(inlineSample.translationLabel.selectable && NSHeight(inlineSample.translationLabel.frame)>NSHeight(heightScroll.contentView.bounds),
                @"height demo keeps the complete selectable text in a scrollable viewport");
            CGFloat topOrigin=inlineSample.translationLabel.isFlipped?0:NSHeight(inlineSample.translationLabel.frame)-NSHeight(heightScroll.contentView.bounds);
            Require(fabs(NSMinY(heightScroll.contentView.bounds)-topOrigin)<1,
                @"resized height example starts at its first sentence instead of the bottom of the document");
        }
    }
    app.batchFontSizeSlider.doubleValue=16;app.batchHeightSlider.doubleValue=330;
    [NSApp sendAction:app.batchHeightSlider.action to:app from:app.batchHeightSlider];Tick();
    [app.mainWindow setContentSize:NSMakeSize(1320,900)];Tick();
    Snapshot(inlineSample,[output stringByAppendingPathComponent:@"appearance-inline-height-limit.png"]);
    [inlineDimensions performClick:nil];Tick();
    Require([inlineSample.translationLabel.stringValue isEqualToString:@"放学后去图书馆吧。\n上次借的书，也该还了。"] && NSHeight(inlineSample.translationSurfaces.lastObject.frame)<330*.46,
        @"closing dimensions restores the approved short example and its natural height");
    app.batchFontSizeSlider.doubleValue=30;[app controlValueChanged:app.batchFontSizeSlider];Tick();
    CheckShortPreview(app.appearanceSamples[1]);
    Snapshot(app.appearanceSamples[1],[output stringByAppendingPathComponent:@"appearance-inline-large-font.png"]);
    app.batchFontSizeSlider.doubleValue=16;[app controlValueChanged:app.batchFontSizeSlider];Tick();
    for(NSButton *choice in app.batchThemeSwatches){
        [choice performClick:nil];Tick();
        Require([app inlineThemeIndex]==choice.tag && choice.state==NSControlStateValueOn &&
                [app.appearanceSamples[1].subtitleInk isEqual:[app inlinePanelTextColor]],@"inline palette choice updates the selected card and native sample immediately");
        Require(app.appearanceSamples[1].translationLabel.selectable && app.appearanceSamples[1].translationSurfaces.count==3,@"inline sample shows selectable short patches and a long translation card");
        Snapshot(app.appearanceSamples[1],[output stringByAppendingPathComponent:[NSString stringWithFormat:@"appearance-inline-palette-%ld.png",choice.tag]]);
    }
    [app.appearanceModeButtons[0] performClick:nil];Tick();
    Require(!app.appearanceEditors[0].hidden && app.appearanceEditors[1].hidden,@"switching types shows one complete editor at a time");
    Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"appearance-dialogue-concentrated-wide.png"]);
    NSString *caption=app.captionTextLabel.stringValue;NSRect frame=app.captionPanel.frame;BOOL shown=app.captionPanelShownByUser;
    NSButton *preview=Button(app.pages[4],@selector(showCaptionAppearancePreview:));
    Require([preview.title isEqualToString:@"打开字幕预览"],@"appearance action clearly announces preview");
    NSButton *dimensions=(NSButton *)Find(app.appearanceEditors[0],^BOOL(NSView *view){return [view isKindOfClass:FYSubtitleDisclosureButton.class];});
    Require([preview isHiddenOrHasHiddenAncestor],@"standalone caption preview lives inside the collapsed dimensions section");
    [dimensions performClick:nil];Tick();Require(![preview isHiddenOrHasHiddenAncestor],@"native disclosure reveals standalone caption preview");
    [preview performClick:nil];Tick();
    Require(app.captionAppearancePreviewPanel.isVisible && !app.captionPanel.isVisible,@"settings opens a visible preview outside the game without raising the real caption");
    Require([app.captionAppearancePreviewPanel.title containsString:@"示例文字"] && [app.captionAppearancePreviewBrand.stringValue containsString:@"示例"],@"sample content is explicitly identified");
    Require(NSEqualRects(frame,app.captionPanel.frame),@"opening a sample does not move or resize the game caption");
    app.captionFontSizeSlider.doubleValue=56;app.captionThemeControl.selectedSegment=1;app.captionOpacitySlider.doubleValue=.85;
    [NSApp sendAction:app.captionFontSizeSlider.action to:app from:app.captionFontSizeSlider];Tick();
    Require(app.captionAppearancePreviewText.font.pointSize==56 && [app.captionAppearancePreviewText.textColor isEqual:[app captionTextColor]],@"style controls update preview immediately");
    app.captionWidthSlider.doubleValue=640;
    app.captionTextColorWell.color=[NSColor colorWithSRGBRed:0.42 green:0.21 blue:0.12 alpha:1];
    [app controlValueChanged:app.captionTextColorWell];Tick();
    Require(fabs(NSWidth(app.captionPanel.frame)-640)<2 && fabs(NSWidth(app.captionAppearancePreviewPanel.frame)-640)<2,@"single caption width controls both real and preview windows");
    Require(app.captionTextColorCustomized && [app.captionTextLabel.textColor isEqual:app.captionTextColorWell.color] && [app.captionAppearancePreviewText.textColor isEqual:app.captionTextColorWell.color],@"selected caption color reaches real and preview text");
    app.batchFontSizeSlider.doubleValue=22;app.batchWidthSlider.doubleValue=480;app.batchHeightSlider.doubleValue=280;
    app.batchTextColorWell.color=[NSColor colorWithSRGBRed:0.31 green:0.19 blue:0.13 alpha:1];
    [app controlValueChanged:app.batchTextColorWell];
    Require(app.inlineLayoutEngine.shortFontSize==22 && app.inlineLayoutEngine.cardMaxWidth==480 && app.inlineLayoutEngine.cardMaxHeight==280,@"batch controls update measured subtitle geometry");
    Require([[app inlinePanelTextColor] isEqual:app.batchTextColorWell.color] && ![[app inlinePanelTextColor] isEqual:[app captionTextColor]],@"batch color is independent from selected caption color");
    [app resetCaptionTextColor:nil];
    Require(!app.captionTextColorCustomized && [[app captionTextColor] isEqual:[app captionThemeTextColor]],@"selected caption color can follow the chosen theme again");
    [app.captionAppearancePreviewPanel.contentView layoutSubtreeIfNeeded];
    Require(NSMinY(app.captionAppearancePreviewText.frame)>=20 && NSMaxY(app.captionAppearancePreviewText.frame)<=NSMinY(app.captionAppearancePreviewBrand.frame),@"large text fits below the label and inside the preview");
    app.captionFontSizeSlider.doubleValue=30;app.captionThemeControl.selectedSegment=3;app.captionWidthSlider.doubleValue=900;[app updateCaptionAppearance];Tick();
    Snapshot(app.captionAppearancePreviewPanel.contentView,[output stringByAppendingPathComponent:@"caption-preview.png"]);
    Require([app.captionTextLabel.stringValue isEqualToString:caption] && app.captionPanelShownByUser==shown,@"sample never replaces translation or changes its hide/show preference");
    [app selectPageAtIndex:5];Tick();Require(!app.captionAppearancePreviewPanel.isVisible,@"leaving appearance closes the preview");
    NSView *servicePage=app.pages[5];
    NSButton *testButton=Button(servicePage,@selector(testTranslation:));
    Require(testButton && app.serviceStatusLabel.superview==testButton.superview &&
            [app.serviceStatusLabel isDescendantOf:servicePage],@"service test status is next to its button on the service page");
    Require([testButton isKindOfClass:FYWorkspaceButton.class] && ((FYWorkspaceButton *)testButton).primary &&
        testButton.image && testButton.imagePosition==NSImageLeft && app.serviceStatusIcon.superview==testButton.superview,
        @"service test uses the leaf-green native button with a play icon and adjacent status icon");
    NSView *modelIcon=Find(servicePage,^BOOL(NSView *view){return [view.identifier isEqualToString:@"service-test-model-icon"];});
    Require(modelIcon && [app.serviceTestModelLabel.stringValue containsString:@"与实时字幕一致"],@"model information has a vector icon and explains shared realtime configuration");
    Require(![app respondsToSelector:@selector(realtimeModelField)] &&
            [app.modelField.accessibilityLabel isEqualToString:@"翻译模型"],@"settings exposes one translation model field");
    Require([app.learningModelField isHiddenOrHasHiddenAncestor],@"optional learning model starts inside collapsed advanced options");
    NSButton *advanced=(NSButton *)Find(servicePage,^BOOL(NSView *view){return [view isKindOfClass:NSButton.class] && [[(NSButton *)view title] isEqualToString:@"高级选项"];});
    Require(advanced!=nil,@"advanced options exist");[advanced performClick:nil];Tick();
    Require(![app.learningModelField isHiddenOrHasHiddenAncestor] && app.learningModelField.editable,@"advanced options reveal the editable optional learning model");
    [advanced performClick:nil];Tick();
    Require(app.serviceStatusLabel.selectable && app.serviceErrorLabel.selectable && app.serviceTestResultLabel.selectable &&
            app.serviceErrorLabel.maximumNumberOfLines==0,@"test status, errors and sample results can be selected and long errors are not truncated");
    [app presentServiceTestState:@"error" error:@"未找到翻译模型。请核对服务商提供的模型名称及访问权限，再点击测试翻译。" result:nil];
    Require([app.serviceStatusIcon.identifier isEqualToString:@"service-test-error"] && !app.serviceErrorLabel.hidden &&
        app.serviceTestResultLabel.hidden && [app.serviceTestResultPanel.fillColor isEqual:FYAdventureColor(@"serviceErrorSoft")],@"failure displays its icon and tinted error card");
    for(NSNumber *width in @[@720,@1320]){
        [app.mainWindow setContentSize:NSMakeSize(width.doubleValue,800)];[app.mainWindow.contentView layoutSubtreeIfNeeded];Tick();
        NSRect buttonFrame=[testButton convertRect:testButton.bounds toView:servicePage];
        NSRect statusFrame=[app.serviceStatusLabel convertRect:app.serviceStatusLabel.bounds toView:servicePage];
        NSRect iconFrame=[app.serviceStatusIcon convertRect:app.serviceStatusIcon.bounds toView:servicePage];
        Require(NSMaxX(buttonFrame)<=NSMinX(statusFrame)+1 && NSMaxX(statusFrame)<=NSWidth(servicePage.bounds)+1,
            @"test button and result remain beside each other inside wide and narrow service pages");
        Require(NSMaxX(buttonFrame)<=NSMinX(iconFrame)+1 && NSMaxX(iconFrame)<=NSMinX(statusFrame)+1 && NSWidth(iconFrame)>=18,
            @"status icon remains visible between the test button and text at both widths");
        Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:[NSString stringWithFormat:@"service-failure-%@.png",width]]);
    }
    [app.mainWindow setContentSize:NSMakeSize(980,800)];
    app.modelField.stringValue=@"synthetic-translation-model";[app updateServiceTestModelLabel];
    [app presentServiceTestState:@"success" error:nil result:@"测试原文：今日は一緒に帰りませんか？\n译文：今天要不要一起回家？"];
    Require([app.serviceStatusIcon.identifier isEqualToString:@"service-test-success"] && app.serviceErrorLabel.hidden &&
        !app.serviceTestResultLabel.hidden && [app.serviceTestResultPanel.fillColor isEqual:FYAdventureColor(@"serviceSuccessSoft")],@"success displays its check icon and tinted selectable translation card");
    Tick();Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"service-success.png"]);
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
