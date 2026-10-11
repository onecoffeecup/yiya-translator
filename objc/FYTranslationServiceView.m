#import "FYTranslationServiceView.h"
#import "learning/FYLearningViews.h"

// Outline list/link marks from the service preview, drawn locally so the
// component does not depend on a web icon library or the main controller.
static NSImage *FYServiceModeIcon(BOOL custom) {
    return [NSImage imageWithSize:NSMakeSize(20,20) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [FYAdventureColor(@"ink") setStroke];
        NSBezierPath *path=[NSBezierPath bezierPath];
        path.lineWidth=1.7; path.lineCapStyle=NSLineCapStyleRound; path.lineJoinStyle=NSLineJoinStyleRound;
        if(custom) {
            [path moveToPoint:NSMakePoint(10.5,14.5)]; [path lineToPoint:NSMakePoint(12,16)];
            [path curveToPoint:NSMakePoint(17,16) controlPoint1:NSMakePoint(13.4,17.4) controlPoint2:NSMakePoint(15.6,17.4)];
            [path curveToPoint:NSMakePoint(17,11) controlPoint1:NSMakePoint(18.4,14.6) controlPoint2:NSMakePoint(18.4,12.4)];
            [path lineToPoint:NSMakePoint(14,8)];
            [path curveToPoint:NSMakePoint(9,8) controlPoint1:NSMakePoint(12.6,6.6) controlPoint2:NSMakePoint(10.4,6.6)];
            [path moveToPoint:NSMakePoint(9.5,5.5)]; [path lineToPoint:NSMakePoint(8,4)];
            [path curveToPoint:NSMakePoint(3,4) controlPoint1:NSMakePoint(6.6,2.6) controlPoint2:NSMakePoint(4.4,2.6)];
            [path curveToPoint:NSMakePoint(3,9) controlPoint1:NSMakePoint(1.6,5.4) controlPoint2:NSMakePoint(1.6,7.6)];
            [path lineToPoint:NSMakePoint(6,12)];
            [path curveToPoint:NSMakePoint(11,12) controlPoint1:NSMakePoint(7.4,13.4) controlPoint2:NSMakePoint(9.6,13.4)];
        } else {
            for(CGFloat y=5;y<=15;y+=5) {
                [path moveToPoint:NSMakePoint(3,y)]; [path lineToPoint:NSMakePoint(3.1,y)];
                [path moveToPoint:NSMakePoint(7,y)]; [path lineToPoint:NSMakePoint(17,y)];
            }
        }
        [path stroke]; return YES;
    }];
}

@implementation FYTranslationServiceTestPresentation
- (void)presentState:(NSString *)state error:(NSString *)error result:(NSString *)result {
    BOOL pending=[state isEqual:@"pending"], success=[state isEqual:@"success"];
    BOOL failure=[state isEqual:@"error"] || error.length>0;
    NSString *status=pending ? @"正在测试服务" : success ? @"服务测试成功" : [state isEqual:@"error"] ? @"服务测试失败" : @"服务未测试";
    NSColor *color=FYAdventureColor(failure ? @"serviceError" : success ? @"serviceSuccess" : @"muted");
    NSColor *fill=FYAdventureColor(failure ? @"serviceErrorSoft" : success ? @"serviceSuccessSoft" : @"canvas");
    self.statusLabel.stringValue=status; self.statusLabel.textColor=color;
    self.icon.image=FYAdventureSymbolImage(failure ? @"error" : success ? @"success" : pending ? @"pending" : @"untested",color);
    self.icon.accessibilityLabel=status;
    self.icon.identifier=failure ? @"service-test-error" : success ? @"service-test-success" : pending ? @"service-test-pending" : @"service-test-untested";
    self.button.title=pending ? @"测试中…" : @"测试翻译"; self.button.enabled=!pending;
    self.messageLabel.stringValue=pending ? @"正在等待翻译模型返回译文…" : success ? @"翻译模型已返回有效译文。" : failure ? @"请检查服务配置后重新测试。" : @"点击「测试翻译」，检查当前翻译模型能否返回译文。";
    self.messageLabel.textColor=color;
    self.errorLabel.stringValue=error ?: @""; self.errorLabel.hidden=!error.length;
    self.resultLabel.stringValue=result ?: @""; self.resultLabel.hidden=!result.length;
    self.panel.fillColor=fill;
    self.panel.edgeColor=failure || success ? [fill blendedColorWithFraction:.22 ofColor:color] : FYAdventureColor(@"rim");
}
@end

@interface FYServicePresetButton : FYWorkspaceButton
@property(nonatomic, strong) NSDictionary *preset;
@end
@implementation FYServicePresetButton
- (BOOL)isFlipped { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(120,64); }
- (void)drawRect:(NSRect)dirtyRect {
    BOOL selected=self.state==NSControlStateValueOn;
    NSBezierPath *shape=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:11 yRadius:11];
    [FYAdventureColor(selected ? @"mint" : @"paper") setFill]; [shape fill];
    [FYAdventureColor(selected ? @"teal" : @"line") setStroke]; [shape stroke];
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new]; paragraph.lineBreakMode=NSLineBreakByTruncatingTail;
    [self.preset[@"name"] drawInRect:NSMakeRect(12,10,MAX(1,NSWidth(self.bounds)-40),22) withAttributes:@{NSFontAttributeName:FYUIFont(13,NSFontWeightSemibold),NSForegroundColorAttributeName:FYAdventureColor(@"ink"),NSParagraphStyleAttributeName:paragraph}];
    [self.preset[@"subtitle"] drawInRect:NSMakeRect(12,35,MAX(1,NSWidth(self.bounds)-24),20) withAttributes:@{NSFontAttributeName:FYUIFont(11,NSFontWeightRegular),NSForegroundColorAttributeName:FYAdventureColor(@"muted"),NSParagraphStyleAttributeName:paragraph}];
    [FYAdventureSymbolImage(selected ? @"success" : @"untested",FYAdventureColor(selected ? @"serviceSuccess" : @"muted")) drawInRect:NSMakeRect(NSWidth(self.bounds)-27,12,15,15) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    if (self.highlighted) { [[FYAdventureColor(@"ink") colorWithAlphaComponent:.06] setFill]; [shape fill]; }
    if (self.window.firstResponder==self) { [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); [shape fill]; [NSGraphicsContext restoreGraphicsState]; }
}
@end

@interface FYServicePresetGrid : NSView
@property(nonatomic, copy) NSArray<NSButton *> *buttons;
@end
@implementation FYServicePresetGrid
- (BOOL)isFlipped { return YES; }
- (NSUInteger)columns { return NSWidth(self.bounds)>=680 ? 4 : NSWidth(self.bounds)>=460 ? 3 : NSWidth(self.bounds)>=290 ? 2 : 1; }
- (NSSize)intrinsicContentSize { NSUInteger columns=[self columns]; return NSMakeSize(NSViewNoIntrinsicMetric,ceil(self.buttons.count/(double)columns)*73-9); }
- (void)setFrameSize:(NSSize)size { CGFloat previous=NSWidth(self.bounds); [super setFrameSize:size]; if(fabs(previous-size.width)>.5) [self invalidateIntrinsicContentSize]; }
- (void)layout { [super layout]; NSUInteger columns=[self columns]; CGFloat width=MAX(1,(NSWidth(self.bounds)-(columns-1)*9)/columns); for(NSUInteger i=0;i<self.buttons.count;i++) self.buttons[i].frame=NSMakeRect((i%columns)*(width+9),(i/columns)*73,width,64); }
@end

@interface FYServiceFormStack : FYLearningStackView
@property(nonatomic, strong) NSStackView *modelRow;
@property(nonatomic, strong) NSStackView *keyRow;
@property(nonatomic, copy) NSArray<NSLayoutConstraint *> *compactFieldWidths;
@end
@implementation FYServiceFormStack
- (void)layout {
    BOOL compact=NSWidth(self.bounds)<430;
    for(NSLayoutConstraint *constraint in self.compactFieldWidths) constraint.active=compact;
    for(NSStackView *row in @[self.modelRow,self.keyRow]) {
        NSUserInterfaceLayoutOrientation orientation=compact ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
        if(row.orientation!=orientation) { row.orientation=orientation; row.alignment=compact ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY; }
    }
    [super layout];
}
@end

@interface FYTranslationServiceView ()
@property(nonatomic, strong, readwrite) NSView *view;
@property(nonatomic, strong, readwrite) FYTranslationServiceSettings *settings;
@property(nonatomic, strong, readwrite) NSTextField *baseURLField;
@property(nonatomic, strong, readwrite) NSTextField *modelField;
@property(nonatomic, strong, readwrite) NSSecureTextField *apiKeyField;
@property(nonatomic, strong, readwrite) NSTextField *learningModelField;
@property(nonatomic, strong, readwrite) FYTranslationServiceTestPresentation *testPresentation;
@property(nonatomic, strong) NSStackView *presetSection;
@property(nonatomic, strong) NSTextField *customHelp;
@property(nonatomic, strong) NSTextField *urlNote;
@property(nonatomic, strong) NSTextField *keyNote;
@property(nonatomic, strong) NSButton *presetModeButton;
@property(nonatomic, strong) NSButton *customModeButton;
@property(nonatomic, strong) NSButton *customizeButton;
@property(nonatomic, strong) NSButton *platformButton;
@property(nonatomic, strong) NSPopUpButton *modelPicker;
@property(nonatomic, strong) NSArray<NSButton *> *providerButtons;
@end
@implementation FYTranslationServiceView
- (NSStackView *)stack:(BOOL)horizontal {
    NSStackView *stack=horizontal ? [NSStackView new] : [FYLearningStackView new];
    stack.orientation=horizontal ? NSUserInterfaceLayoutOrientationHorizontal : NSUserInterfaceLayoutOrientationVertical;
    stack.alignment=horizontal ? NSLayoutAttributeCenterY : NSLayoutAttributeLeading;
    stack.spacing=horizontal ? 9 : 12; stack.distribution=NSStackViewDistributionFill; return stack;
}
- (NSTextField *)label:(NSString *)text size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *field=[NSTextField labelWithString:text ?: @""]; field.font=FYUIFont(size,bold ? NSFontWeightSemibold : NSFontWeightRegular);
    field.textColor=FYAdventureColor(bold ? @"ink" : @"muted"); field.maximumNumberOfLines=0; field.lineBreakMode=NSLineBreakByWordWrapping;
    field.selectable=YES; [field setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal]; return field;
}
- (NSButton *)button:(NSString *)title action:(SEL)action primary:(BOOL)primary {
    FYWorkspaceButton *button=[FYWorkspaceButton buttonWithTitle:title target:self action:action]; button.bordered=NO; button.primary=primary;
    [button setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    button.font=FYUIFont(12,primary ? NSFontWeightSemibold : NSFontWeightRegular); [button.heightAnchor constraintEqualToConstant:36].active=YES; return button;
}
- (NSTextField *)field:(NSString *)label secure:(BOOL)secure {
    NSTextField *field=secure ? [NSSecureTextField new] : [NSTextField new]; field.font=FYUIFont(13,NSFontWeightRegular);
    field.textColor=FYAdventureColor(@"ink"); field.backgroundColor=FYAdventureColor(@"paper"); field.delegate=self;
    field.accessibilityLabel=label;
    [field setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [field setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:30].active=YES; return field;
}
- (NSView *)fieldRow:(NSString *)label view:(NSView *)view {
    NSStackView *row=[self stack:NO]; row.spacing=6; [row addArrangedSubview:[self label:label size:13 bold:YES]]; [row addArrangedSubview:view]; return row;
}
- (NSView *)disclosure:(NSString *)title content:(NSView *)content {
    NSStackView *row=[self stack:NO]; NSButton *button=[self button:title action:@selector(toggleDisclosure:) primary:NO];
    [button setButtonType:NSButtonTypePushOnPushOff]; button.identifier=[title isEqual:@"高级选项"] ? @"service-advanced" : @"service-licenses";
    [row addArrangedSubview:button]; [row addArrangedSubview:content]; content.hidden=YES; return row;
}
- (void)toggleDisclosure:(NSButton *)sender { NSStackView *row=(NSStackView *)sender.superview; row.arrangedSubviews.lastObject.hidden=sender.state!=NSControlStateValueOn; }
- (instancetype)initWithLicenseView:(NSView *)licenseView {
    if(!(self=[super init])) return nil;
    _settings=[FYTranslationServiceSettings new]; _testPresentation=[FYTranslationServiceTestPresentation new];
    FYServiceFormStack *root=[FYServiceFormStack new]; root.orientation=NSUserInterfaceLayoutOrientationVertical; root.alignment=NSLayoutAttributeLeading; root.spacing=14;
    root.identifier=@"translation-service-settings"; _view=root;
    NSStackView *modes=[self stack:YES]; modes.distribution=NSStackViewDistributionFillEqually;
    self.presetModeButton=[self button:@"选择预设" action:@selector(selectPresetMode:) primary:YES]; self.presetModeButton.identifier=@"service-mode-preset";
    self.customModeButton=[self button:@"自定义 URL" action:@selector(selectCustomMode:) primary:NO]; self.customModeButton.identifier=@"service-mode-custom";
    self.presetModeButton.image=FYServiceModeIcon(NO); self.presetModeButton.imagePosition=NSImageLeft;
    self.customModeButton.image=FYServiceModeIcon(YES); self.customModeButton.imagePosition=NSImageLeft;
    // Mode choices fill the page width; their intrinsic titles must not pull
    // the Auto Layout window back to the form's fitting size.
    [self.presetModeButton setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.customModeButton setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [modes addArrangedSubview:self.presetModeButton]; [modes addArrangedSubview:self.customModeButton]; [root addArrangedSubview:modes];
    self.presetSection=[self stack:NO]; [self.presetSection addArrangedSubview:[self label:@"选择一个服务，自动填入地址和默认模型，再填写该服务的 API Key。" size:12 bold:NO]];
    NSMutableArray *all=[NSMutableArray new];
    for(NSNumber *aggregate in @[@NO,@YES]) {
        NSUInteger count=0;
        for(NSDictionary *preset in FYTranslationServicePresets()) if([preset[@"aggregate"] boolValue]==aggregate.boolValue) count++;
        NSString *heading=[NSString stringWithFormat:@"%@ · %lu 个预设",aggregate.boolValue ? @"多模型平台" : @"官方服务",(unsigned long)count];
        [self.presetSection addArrangedSubview:[self label:heading size:13 bold:YES]];
        FYServicePresetGrid *grid=[FYServicePresetGrid new]; NSMutableArray *buttons=[NSMutableArray new];
        for(NSDictionary *preset in FYTranslationServicePresets()) {
            if([preset[@"aggregate"] boolValue]!=aggregate.boolValue) continue;
            FYServicePresetButton *button=[FYServicePresetButton buttonWithTitle:preset[@"name"] target:self action:@selector(selectProvider:)];
            button.preset=preset; button.identifier=preset[@"id"]; button.bordered=NO; [button setButtonType:NSButtonTypePushOnPushOff];
            button.accessibilityLabel=[NSString stringWithFormat:@"%@，%@",preset[@"name"],preset[@"subtitle"]];
            [grid addSubview:button]; [buttons addObject:button]; [all addObject:button];
        }
        grid.buttons=buttons; [self.presetSection addArrangedSubview:grid];
    }
    self.providerButtons=all; [self.presetSection addArrangedSubview:[self label:@"通过多模型平台使用模型时，请填写平台提供的 API Key。" size:12 bold:NO]]; [root addArrangedSubview:self.presetSection];
    self.customHelp=[self label:@"填写你使用的服务地址与模型，也可以接入代理或本机服务。" size:12 bold:NO]; [root addArrangedSubview:self.customHelp];
    self.baseURLField=[self field:@"服务地址 Base URL" secure:NO]; self.baseURLField.identifier=@"service-base-url";
    NSStackView *urlGroup=[self stack:NO]; NSStackView *urlLabel=[self stack:YES]; [urlLabel addArrangedSubview:[self label:@"服务地址 Base URL" size:13 bold:YES]];
    self.customizeButton=[self button:@"改为自定义" action:@selector(customize:) primary:NO]; [urlLabel addArrangedSubview:self.customizeButton];
    [urlGroup addArrangedSubview:urlLabel]; [urlGroup addArrangedSubview:self.baseURLField]; self.urlNote=[self label:@"" size:12 bold:NO]; [urlGroup addArrangedSubview:self.urlNote]; [root addArrangedSubview:urlGroup];
    self.modelField=[self field:@"翻译模型" secure:NO]; self.modelField.identifier=@"service-model";
    self.modelPicker=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; self.modelPicker.identifier=@"service-common-models"; self.modelPicker.accessibilityLabel=@"选择常用模型";
    self.modelPicker.font=FYUIFont(12,NSFontWeightRegular); self.modelPicker.target=self; self.modelPicker.action=@selector(selectCommonModel:);
    [self.modelPicker.widthAnchor constraintLessThanOrEqualToConstant:180].active=YES;
    root.modelRow=[self stack:YES]; [root.modelRow addArrangedSubview:self.modelField]; [root.modelRow addArrangedSubview:self.modelPicker];
    [root addArrangedSubview:[self fieldRow:@"翻译模型" view:root.modelRow]]; [root addArrangedSubview:[self label:@"可直接输入、粘贴或修改模型名。实时字幕、翻译当前界面和测试翻译使用同一个模型。" size:12 bold:NO]];
    self.apiKeyField=(NSSecureTextField *)[self field:@"API Key" secure:YES]; self.apiKeyField.placeholderString=@"API Key";
    root.keyRow=[self stack:YES]; [root.keyRow addArrangedSubview:self.apiKeyField]; [root.keyRow addArrangedSubview:[self button:@"从剪贴板粘贴" action:@selector(pasteAPIKeyFromClipboard:) primary:NO]]; [root.keyRow addArrangedSubview:[self button:@"清空" action:@selector(clearAPIKey:) primary:NO]];
    root.compactFieldWidths=@[[self.modelField.widthAnchor constraintEqualToAnchor:root.modelRow.widthAnchor],
        [self.apiKeyField.widthAnchor constraintEqualToAnchor:root.keyRow.widthAnchor]];
    [root addArrangedSubview:[self fieldRow:@"API Key" view:root.keyRow]];
    self.keyNote=[self label:@"" size:12 bold:NO]; [root addArrangedSubview:self.keyNote]; self.platformButton=[self button:@"前往服务平台 ↗" action:@selector(openPlatform:) primary:NO]; [root addArrangedSubview:self.platformButton];
    NSBox *separator=[NSBox new]; separator.boxType=NSBoxSeparator; [root addArrangedSubview:separator];
    NSStackView *test=[self stack:NO]; NSStackView *testRow=[self stack:YES];
    self.testPresentation.button=[self button:@"测试翻译" action:@selector(testTranslation:) primary:YES]; self.testPresentation.button.image=FYAdventureSymbolImage(@"play",FYAdventureColor(@"ink")); self.testPresentation.button.imagePosition=NSImageLeft; [testRow addArrangedSubview:self.testPresentation.button];
    self.testPresentation.icon=[NSImageView new]; [self.testPresentation.icon.widthAnchor constraintEqualToConstant:20].active=YES; [self.testPresentation.icon.heightAnchor constraintEqualToConstant:20].active=YES; [testRow addArrangedSubview:self.testPresentation.icon];
    self.testPresentation.statusLabel=[self label:@"服务未测试" size:13 bold:YES]; [testRow addArrangedSubview:self.testPresentation.statusLabel]; [test addArrangedSubview:testRow];
    NSStackView *modelLabelRow=[self stack:YES]; NSImageView *modelIcon=[NSImageView new]; modelIcon.image=FYAdventureSymbolImage(@"model",FYAdventureColor(@"muted")); modelIcon.identifier=@"service-test-model-icon"; modelIcon.accessibilityElement=NO;
    [modelIcon.widthAnchor constraintEqualToConstant:18].active=YES; [modelIcon.heightAnchor constraintEqualToConstant:18].active=YES; [modelLabelRow addArrangedSubview:modelIcon]; self.testPresentation.modelLabel=[self label:@"测试模型：—" size:12 bold:NO]; [modelLabelRow addArrangedSubview:self.testPresentation.modelLabel]; [test addArrangedSubview:modelLabelRow];
    NSStackView *result=[self stack:NO]; result.spacing=7; self.testPresentation.messageLabel=[self label:@"" size:13 bold:YES]; self.testPresentation.errorLabel=[self label:@"" size:12 bold:NO]; self.testPresentation.resultLabel=[self label:@"" size:13 bold:NO]; self.testPresentation.resultLabel.textColor=FYAdventureColor(@"ink");
    [result addArrangedSubview:self.testPresentation.messageLabel]; [result addArrangedSubview:self.testPresentation.errorLabel]; [result addArrangedSubview:self.testPresentation.resultLabel];
    self.testPresentation.panel=[FYAdventurePanel new]; [self.testPresentation.panel addSubview:result]; result.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[[result.leadingAnchor constraintEqualToAnchor:self.testPresentation.panel.leadingAnchor constant:14],[result.trailingAnchor constraintEqualToAnchor:self.testPresentation.panel.trailingAnchor constant:-14],[result.topAnchor constraintEqualToAnchor:self.testPresentation.panel.topAnchor constant:14],[result.bottomAnchor constraintEqualToAnchor:self.testPresentation.panel.bottomAnchor constant:-14]]];
    [test addArrangedSubview:self.testPresentation.panel]; [root addArrangedSubview:test];
    self.learningModelField=[self field:@"学习模型（可选）" secure:NO]; self.learningModelField.placeholderString=@"留空复用翻译模型";
    NSStackView *advanced=[self stack:NO]; [advanced addArrangedSubview:[self fieldRow:@"学习模型（可选）" view:self.learningModelField]]; [advanced addArrangedSubview:[self label:@"用于语法分析和 AI 学习伙伴，留空复用翻译模型。" size:12 bold:NO]]; [root addArrangedSubview:[self disclosure:@"高级选项" content:advanced]];
    [root addArrangedSubview:[self label:@"API Key 保存在本机应用数据文件；重开、重装和跨版本更新均自动读取。" size:12 bold:NO]];
    NSBox *offlineSeparator=[NSBox new]; offlineSeparator.boxType=NSBoxSeparator; [root addArrangedSubview:offlineSeparator]; [root addArrangedSubview:[self label:@"离线学习资料" size:17 bold:YES]]; [root addArrangedSubview:[self label:@"词义来自 JMdict，日文例句来自 Tatoeba，参考等级来自 OpenJLPT。" size:12 bold:NO]];
    NSStackView *licenses=[self stack:NO]; if(licenseView) [licenses addArrangedSubview:licenseView]; [licenses addArrangedSubview:[self button:@"在 Finder 查看完整许可文件 ↗" action:@selector(showReferenceLicenses:) primary:NO]]; [root addArrangedSubview:[self disclosure:@"资料来源与许可" content:licenses]];
    [self render]; [self.testPresentation presentState:@"untested" error:nil result:nil]; return self;
}
- (void)synchronizeFields { self.settings.baseURL=self.baseURLField.stringValue; self.settings.model=self.modelField.stringValue; }
- (void)render {
    NSDictionary *p=FYTranslationServicePreset(self.settings.provider); BOOL preset=[self.settings.mode isEqual:@"preset"];
    ((FYWorkspaceButton *)self.presetModeButton).primary=preset; ((FYWorkspaceButton *)self.customModeButton).primary=!preset;
    self.presetModeButton.state=preset; self.customModeButton.state=!preset;
    self.presetSection.hidden=!preset; self.customHelp.hidden=preset; self.customizeButton.hidden=!preset;
    self.baseURLField.editable=!preset; self.baseURLField.stringValue=self.settings.baseURL; self.modelField.stringValue=self.settings.model;
    self.urlNote.stringValue=preset ? p[@"note"] : @"填写基础地址即可；本机服务可使用 http://localhost:端口/v1。";
    self.modelField.placeholderString=preset && [p[@"placeholder"] length] ? p[@"placeholder"] : @"填写服务提供的模型名";
    for(NSButton *button in self.providerButtons) button.state=[button.identifier isEqual:self.settings.provider] ? NSControlStateValueOn : NSControlStateValueOff;
    [self.modelPicker removeAllItems]; [self.modelPicker addItemWithTitle:@"常用模型"]; [self.modelPicker addItemsWithTitles:p[@"models"]]; self.modelPicker.hidden=!preset || [p[@"models"] count]<2;
    self.platformButton.hidden=!preset; self.keyNote.stringValue=preset ? [NSString stringWithFormat:@"请使用 %@ 服务平台提供的 API Key。",p[@"name"]] : @"请填写当前服务提供的 API Key。";
}
- (void)loadSettings:(NSDictionary *)settings { [self.settings loadSettings:settings]; self.learningModelField.stringValue=[settings[@"learningModel"] isKindOfClass:NSString.class] ? settings[@"learningModel"] : @""; [self render]; }
- (NSDictionary *)settingsDictionary { [self synchronizeFields]; NSMutableDictionary *settings=[[self.settings settingsDictionary] mutableCopy]; settings[@"learningModel"]=self.learningModelField.stringValue; return settings; }
- (void)changed { [self render]; if(self.onSettingsChanged) self.onSettingsChanged(); }
- (void)selectProvider:(NSButton *)sender { [self synchronizeFields]; [self.settings selectProvider:sender.identifier]; [self changed]; }
- (void)selectPresetMode:(id)sender { [self synchronizeFields]; [self.settings switchToMode:@"preset" seedFromPreset:NO]; [self changed]; }
- (void)selectCustomMode:(id)sender { [self synchronizeFields]; [self.settings switchToMode:@"custom" seedFromPreset:NO]; [self changed]; }
- (void)customize:(id)sender { [self synchronizeFields]; [self.settings switchToMode:@"custom" seedFromPreset:YES]; [self changed]; }
- (void)selectCommonModel:(NSPopUpButton *)sender { if(sender.indexOfSelectedItem<1) return; self.modelField.stringValue=sender.titleOfSelectedItem; [self synchronizeFields]; [sender selectItemAtIndex:0]; if(self.onSettingsChanged) self.onSettingsChanged(); [self.modelField.window makeFirstResponder:self.modelField]; }
- (void)applyPreset:(NSString *)identifier model:(NSString *)model { [self synchronizeFields]; [self.settings selectProvider:identifier]; if(model) self.settings.model=model; [self changed]; }
- (void)controlTextDidChange:(NSNotification *)notification { [self synchronizeFields]; if(self.onTextChanged) self.onTextChanged(notification); }
- (void)controlTextDidEndEditing:(NSNotification *)notification { [self synchronizeFields]; if(self.onEditingEnded) self.onEditingEnded(notification); }
- (void)testTranslation:(id)sender { if(self.onTest) self.onTest(); }
- (void)pasteAPIKeyFromClipboard:(id)sender { if(self.onPasteKey) self.onPasteKey(); }
- (void)clearAPIKey:(id)sender { if(self.onClearKey) self.onClearKey(); }
- (void)showReferenceLicenses:(id)sender { if(self.onShowLicenses) self.onShowLicenses(); }
- (void)openPlatform:(id)sender { NSURL *url=[NSURL URLWithString:FYTranslationServicePreset(self.settings.provider)[@"platform"]]; if(url) [NSWorkspace.sharedWorkspace openURL:url]; }
@end
