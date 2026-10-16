// Host adapters for extracted diagnostics; UI composition and test seams remain here.
- (NSArray<NSDictionary *> *)diagnosticWindowInfos {
    return CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID)) ?: @[];
}

- (BOOL)diagnosticQuickTimeRunning {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.QuickTimePlayerX"].count > 0;
}



- (NSDictionary *)runtimeDiagnosticSnapshot {
    NSArray *infos = [self diagnosticWindowInfos];
    BOOL card = [self captureCardInputEnabled];
    NSDictionary *context = @{@"screen_permission": @([self hasScreenAccess]), @"input_source": @(card ? 1 : 0),
        @"running": @(self.running), @"in_flight": @(self.inFlight), @"generation": @(self.translationGeneration),
        @"selected_window_id": @([self selectedWindowID]), @"display_window_id": @([self displayTargetWindowID]),
        @"camera_authorized": @(card && [self.captureCardInput availability] == FYCaptureCardAvailabilityAuthorized),
        @"capture_running": @(card && self.captureCardInput.state == FYCaptureCardSessionStateRunning)};
    return [FYDiagnosticsController snapshotForWindowInfos:infos context:context quickTimeRunning:[self diagnosticQuickTimeRunning]];
}

- (NSArray<NSDictionary *> *)updateRuntimeDiagnostics {
    return [[self diagnosticsController] updateWithSnapshot:[self runtimeDiagnosticSnapshot]];
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

- (void)showDiagnosticMailFallback { [[self diagnosticsController] showMailFallback]; }

- (void)composeDiagnosticEmailForURL:(NSURL *)url {
    if (self.diagnosticMailService) { return; }
    [[self diagnosticsController] composeEmailForURL:url service:[self newDiagnosticMailService]];
}

- (void)sharingService:(NSSharingService *)service didFailToShareItems:(NSArray *)items error:(NSError *)error {
    [[self diagnosticsController] sharingService:service didFailToShareItems:items error:error];
}

- (void)sharingService:(NSSharingService *)service didShareItems:(NSArray *)items {
    [[self diagnosticsController] sharingService:service didShareItems:items];
}

- (void)saveRuntimeDiagnosticsForEmail:(BOOL)email {
    if (self.exportingDiagnostics) { return; }
    __weak typeof(self) weakSelf = self;
    [[self diagnosticsController] saveSnapshot:[self runtimeDiagnosticSnapshot] forWindow:self.mainWindow email:email
        compose:^(NSURL *url) { [weakSelf composeDiagnosticEmailForURL:url]; }];
}
