// Included inside AppDelegate's implementation. Reads metadata, never screenshots.
- (NSArray<NSDictionary *> *)diagnosticWindowInfos {
    return CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID)) ?: @[];
}

- (BOOL)diagnosticQuickTimeRunning {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.QuickTimePlayerX"].count > 0;
}

- (NSString *)diagnosticRoleForOwner:(NSString *)owner ownProcess:(BOOL)own {
    if (own || FYWindowOwnerIsYiya(owner)) { return @"yiya"; }
    if ([owner rangeOfString:@"QuickTime" options:NSCaseInsensitiveSearch].location != NSNotFound) { return @"quicktime"; }
    if ([owner rangeOfString:@"OBS" options:NSCaseInsensitiveSearch].location != NSNotFound) { return @"obs"; }
    return owner.length ? @"other" : @"unknown";
}

- (NSDictionary *)runtimeDiagnosticSnapshot {
    NSArray *infos = [self diagnosticWindowInfos];
    NSMutableArray *windows = [NSMutableArray array];
    NSUInteger ownCount = 0, externalCount = 0, candidates = 0, quickTimeCount = 0;
    uint32_t selected = [self selectedWindowID];
    BOOL selectedExists = NO, selectedSelf = NO;
    NSString *selectedRole = @"unknown";
    for (NSDictionary *info in infos) {
        NSString *owner = info[(id)kCGWindowOwnerName] ?: @"";
        BOOL own = [info[(id)kCGWindowOwnerPID] intValue] == getpid() || FYWindowOwnerIsYiya(owner);
        NSString *role = [self diagnosticRoleForOwner:owner ownProcess:own];
        uint32_t windowID = [info[(id)kCGWindowNumber] unsignedIntValue];
        NSInteger layer = [info[(id)kCGWindowLayer] integerValue];
        CGRect bounds = CGRectZero;
        CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds);
        BOOL normal = layer == 0 && bounds.size.width >= 160 && bounds.size.height >= 100;
        BOOL candidate = FYWindowItemFromInfo(info) != nil;
        if (candidate) { candidates++; }
        if (normal && own) { ownCount++; }
        if (normal && !own && owner.length) { externalCount++; }
        if (normal && [role isEqual:@"quicktime"]) { quickTimeCount++; }
        if (windowID == selected && selected != 0) { selectedExists = YES; selectedSelf = own; selectedRole = role; }
        [windows addObject:@{@"window_id": @(windowID), @"pid": info[(id)kCGWindowOwnerPID] ?: @0,
                             @"layer": @(layer), @"x": @(bounds.origin.x), @"y": @(bounds.origin.y),
                             @"width": @(bounds.size.width), @"height": @(bounds.size.height),
                             @"role": role, @"is_self": @(own), @"candidate": @(candidate),
                             @"owner_present": @(owner.length > 0), @"title_present": @([info[(id)kCGWindowName] length] > 0)}];
    }
    struct utsname machine;
    NSString *architecture = uname(&machine) == 0 ? @(machine.machine) : @"unknown";
    int translated = 0; size_t translatedSize = sizeof(translated);
    sysctlbyname("sysctl.proc_translated", &translated, &translatedSize, NULL, 0);
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    BOOL card = [self captureCardInputEnabled];
    BOOL cameraOK = card && [self.captureCardInput availability] == FYCaptureCardAvailabilityAuthorized;
    return @{@"app_version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"development",
             @"app_build": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown",
             @"macos_version": [NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion],
             @"architecture": architecture, @"translated_process": @(translated == 1),
             @"screen_permission": @([self hasScreenAccess]), @"input_source": @(card ? 1 : 0),
             @"running": @(self.running), @"in_flight": @(self.inFlight), @"generation": @(self.translationGeneration),
             @"selected_window_id": @(selected), @"display_window_id": @([self displayTargetWindowID]),
             @"selected_is_self": @(selectedSelf), @"selected_exists": @(selectedExists), @"selected_role": selectedRole,
             @"raw_windows": @(infos.count), @"candidate_windows": @(candidates), @"own_windows": @(ownCount),
             @"external_windows": @(externalCount), @"quicktime_windows": @(quickTimeCount),
             @"quicktime_running": @([self diagnosticQuickTimeRunning]), @"screen_count": @(NSScreen.screens.count),
             @"camera_authorized": @(cameraOK), @"capture_running": @(card && self.captureCardInput.state == FYCaptureCardSessionStateRunning),
             @"windows": windows};
}

- (NSArray<NSDictionary *> *)updateRuntimeDiagnostics {
    NSDictionary *snapshot = [self runtimeDiagnosticSnapshot];
    self.lastDiagnosticCheckDate = NSDate.date;
    NSMutableDictionary *event = [snapshot mutableCopy];
    event[@"window_id"] = snapshot[@"selected_window_id"];
    event[@"window_role"] = snapshot[@"selected_role"];
    [[FYRuntimeDiagnostics shared] recordEvent:@"window_check" fields:event];
    NSArray *findings = [FYRuntimeDiagnostics findingsForSnapshot:snapshot events:[FYRuntimeDiagnostics.shared recentEvents]];
    self.diagnosticStatusLabel.stringValue = [[findings valueForKey:@"message"] componentsJoinedByString:@"\n"];
    return findings;
}

- (void)runRuntimeDiagnostics:(id)sender {
    [self updateRuntimeDiagnostics];
    [self setStatus:@"运行检测已完成，结果见下方「诊断与反馈」。"];
}

- (NSView *)diagnosticControls {
    NSStackView *stack = [self verticalStack];
    [stack addArrangedSubview:[self cardTitle:@"诊断与反馈"]];
    self.diagnosticStatusLabel = [self mutedLabel:@"遇到窗口列表或字幕识别问题时，先点「运行检测」，再通过邮件反馈或导出诊断包。"];
    self.diagnosticStatusLabel.maximumNumberOfLines = 0;
    self.diagnosticStatusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.diagnosticStatusLabel.selectable = YES;
    self.diagnosticStatusLabel.identifier = @"runtime-diagnostic-result";
    [stack addArrangedSubview:self.diagnosticStatusLabel];
    [self pinFullWidth:self.diagnosticStatusLabel toStack:stack];
    NSStackView *actions = [self horizontalStack];
    [actions addArrangedSubview:[self workspaceButton:@"运行检测" action:@selector(runRuntimeDiagnostics:) primary:NO]];
    [actions addArrangedSubview:[self workspaceButton:@"导出诊断包…" action:@selector(exportRuntimeDiagnostics:) primary:NO]];
    [stack addArrangedSubview:actions];
    [stack addArrangedSubview:[self workspaceButton:@"通过邮件反馈…" action:@selector(emailRuntimeDiagnostics:) primary:YES]];
    NSTextField *privacy = [self mutedLabel:@"仅包含最近几分钟的权限、窗口和错误状态，不含密钥、截图或台词。邮件反馈先保存诊断包，再打开草稿，由你确认发送至 yiyatranslator@163.com。退出应用后内存记录清空，已保存文件保留。"];
    privacy.maximumNumberOfLines = 0;
    [stack addArrangedSubview:privacy];
    [self pinFullWidth:privacy toStack:stack];
    return stack;
}

- (void)exportRuntimeDiagnostics:(id)sender {
    [self saveRuntimeDiagnosticsForEmail:NO];
}

- (void)emailRuntimeDiagnostics:(id)sender {
    if (self.diagnosticMailService) {
        [self setStatus:@"请先完成或关闭已打开的反馈邮件；也可导出诊断包手动发送。"];
        return;
    }
    [self saveRuntimeDiagnosticsForEmail:YES];
}

- (NSSharingService *)newDiagnosticMailService {
    return [NSSharingService sharingServiceNamed:NSSharingServiceNameComposeEmail];
}

- (void)showDiagnosticMailFallback {
    self.diagnosticStatusLabel.stringValue = @"诊断包已保存在你选择的位置，尚未确认发送。请配置 Mac 的邮件应用后重试，或登录网页邮箱，把已保存的 JSON 文件作为附件发送至 yiyatranslator@163.com。";
    [self setStatus:@"邮件未完成，请使用已保存的诊断包手动反馈。"];
}

- (void)composeDiagnosticEmailForURL:(NSURL *)url {
    if (self.diagnosticMailService) { return; }
    NSString *body = @"译芽问题反馈\n\n问题表现：\n复现步骤：\n预期结果：\n\n附件是诊断包，仅包含权限、窗口及运行错误状态，不含密钥、截图或台词。请确认附件已添加，并补充问题描述后发送。";
    NSArray *items = @[body, url];
    NSSharingService *service = [self newDiagnosticMailService];
    if (!service || ![service canPerformWithItems:items]) {
        [self showDiagnosticMailFallback];
        return;
    }
    service.recipients = @[@"yiyatranslator@163.com"];
    service.subject = @"译芽 · 诊断与问题反馈";
    service.delegate = self;
    self.diagnosticMailService = service;
    [self setStatus:@"正在打开反馈邮件，请确认附件、补充问题描述并点击发送。"];
    [service performWithItems:items];
}

- (void)sharingService:(NSSharingService *)service didFailToShareItems:(NSArray *)items error:(NSError *)error {
    if (service != self.diagnosticMailService) { return; }
    service.delegate = nil;
    self.diagnosticMailService = nil;
    [self showDiagnosticMailFallback];
}

- (void)sharingService:(NSSharingService *)service didShareItems:(NSArray *)items {
    if (service != self.diagnosticMailService) { return; }
    service.delegate = nil;
    self.diagnosticMailService = nil;
    // The sharing service completing does not prove delivery to the recipient.
    [self setStatus:@"邮件操作已完成，请在邮件应用中确认发送状态。诊断包仍保留在保存位置。"];
}

- (void)saveRuntimeDiagnosticsForEmail:(BOOL)email {
    if (self.exportingDiagnostics) { return; }
    // Freeze the report before a save dialog changes the active window/context.
    NSDictionary *snapshot = [self runtimeDiagnosticSnapshot];
    [[FYRuntimeDiagnostics shared] recordEvent:@"export" fields:@{}];
    NSDictionary *report = [[FYRuntimeDiagnostics shared] reportForSnapshot:snapshot];
    self.diagnosticStatusLabel.stringValue = [[report[@"findings"] valueForKey:@"message"] componentsJoinedByString:@"\n"];
    self.exportingDiagnostics = YES;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = email ? @"保存诊断包并通过邮件反馈" : @"导出译芽诊断包";
    panel.message = email ? @"保存后将打开邮件草稿，附上此文件，收件人为 yiyatranslator@163.com。请确认后发送。" : @"不含密钥、截图或台词。保存后，将这个 JSON 文件通过聊天或邮件发给开发者。";
    panel.allowedContentTypes = @[UTTypeJSON];
    panel.canCreateDirectories = YES;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    panel.nameFieldStringValue = [NSString stringWithFormat:@"yiya-diagnostics-%@.json", [formatter stringFromDate:NSDate.date]];
    [panel beginSheetModalForWindow:self.mainWindow completionHandler:^(NSModalResponse response) {
        self.exportingDiagnostics = NO;
        if (response != NSModalResponseOK) { return; }
        NSError *error = nil;
        if (![FYRuntimeDiagnostics writeReport:report toURL:panel.URL error:&error]) {
            self.diagnosticStatusLabel.stringValue = [NSString stringWithFormat:@"诊断包保存失败（错误码 %ld）。请换一个可写入的位置后重试。", (long)error.code];
            [self setStatus:@"诊断包未保存，请重试。"];
            return;
        }
        if (email) {
            [self composeDiagnosticEmailForURL:panel.URL];
            return;
        }
        [self setStatus:@"诊断包已保存，请通过聊天或邮件发给开发者。"];
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[panel.URL]];
    }];
}
