#import "FYInlineDisplayCoordinatorInternal.h"
#import "FYPresentationText.h"

@implementation FYInlineDisplayFrame
- (instancetype)initWithResult:(FYInlineLayoutResult *)result previous:(FYInlineLayoutResult *)previous viewport:(NSRect)viewport items:(NSArray<OCRTextItem *> *)items itemsByBlockID:(NSDictionary<NSString *,OCRTextItem *> *)itemsByBlockID identity:(NSString *)identity contentKey:(NSString *)contentKey geometryKey:(NSString *)geometryKey reason:(NSString *)reason {
    if((self=[super init])){_result=result;_previous=previous;_viewport=viewport;_items=items;_itemsByBlockID=itemsByBlockID;_identity=identity;_contentKey=contentKey;_geometryKey=geometryKey;_reason=reason;}
    return self;
}
@end

@implementation FYInlineDisplayCoordinator
- (NSString *)inlineTranslationIdentityForTranslations:(NSArray<NSString *> *)translations
                                              forItems:(NSArray<OCRTextItem *> *)items {
    NSMutableString *identity = [NSMutableString string];
    NSUInteger count = MIN(translations.count, items.count);
    for (NSUInteger index = 0; index < count; index++) {
        OCRTextItem *item = items[index];
        [identity appendFormat:@"%@\n%@\n%.2f:%.2f:%.2f:%.2f\n",
         NormalizeForComparison(item.text), Trim(translations[index]),
         item.boundingBox.origin.x, item.boundingBox.origin.y,
         item.boundingBox.size.width, item.boundingBox.size.height];
    }
    return [identity copy];
}

- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items placementRect:(NSRect)windowFrame {
    if (NSWidth(windowFrame) < 2 || NSHeight(windowFrame) < 2) { return; }
    // 正在拖动某一面板：这一帧先不重排，避免 OCR 循环把面板从用户手里拽回去。
    // 拖动结束会记录新偏移，下一帧按新位置渲染。
    if (self.inlineDraggingPanel) { return; }
    // 记住这一帧的内容：几何变化（窗口移动、OBS 编辑器↔全屏投影）时用它按新几何重排，
    // 不再重新请求翻译。译文没变也可以只更新位置。
    if (translations.count > 0 && translations.count == items.count) {
        self.lastInlineLayoutDebugViewport=windowFrame;
        if ([self currentInlineLayoutDebugContext]) self.lastInlineLayoutDebugContext=[self currentInlineLayoutDebugContext];
        self.lastInlineRenderedTranslations = [translations copy];
        self.lastInlineRenderedItems = [items copy];
    }
    // 落位区域也进入内容指纹：窗口移动/缩放后即使页面文字没变，也必须重新布局，
    // 否则贴译会停在旧坐标上、跟原文错位（手动拖动过的位置同样要重新夹到可见区域内）。
    // 实际显示目标也进指纹：OBS 编辑器↔全屏投影是**另一个窗口**，同一段文字必须重排。
    FYInlineLayoutCalculator *engine = self.inlineLayoutEngine;
    engine.collectsLayoutDiagnostics=[self inlineLayoutDiagnosticsActive];
    NSString *geometryKey = [NSString stringWithFormat:@"|t=%u|vp=%.1f,%.1f,%.1f,%.1f|style=%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
                             [self displayTargetWindowID],
                             NSMinX(windowFrame), NSMinY(windowFrame), NSWidth(windowFrame), NSHeight(windowFrame),
                             engine.shortFontSize, engine.coverFontSize, engine.longBodyFontSize,
                             engine.minimumLongBodyFontSize, engine.longTitleFontSize, engine.compactEntryFontSize,
                             engine.shortMaxWidth, engine.cardMaxWidth, engine.cardMaxHeight];
    NSString *identity = [[self inlineTranslationIdentityForTranslations:translations forItems:items]
                          stringByAppendingString:geometryKey];
    NSMutableString *contentKey = [NSMutableString stringWithFormat:@"%lu:%lu|",
                                  (unsigned long)translations.count, (unsigned long)items.count];
    for (NSUInteger index = 0; index < MIN(translations.count, items.count); index++) {
        [contentKey appendFormat:@"%@\n%@\n", NormalizeForComparison(items[index].text), Trim(translations[index])];
    }
    // 两位小数仍有桶边界：0.0049 → 0.0059 只动了约 1px，却会跨桶。
    // 跟上次实际布局的框比较，避免逐帧比较把真正的缓慢移动也吞掉。
    BOOL minorOCRJitter = [self hasMinorOCRJitterForItems:items contentKey:contentKey geometryKey:geometryKey];
    // 页面文字没变：只把已有面板重新显示出来，绝不 close / 重建。
    // （旧实现每帧 clear + 新建 NSPanel，这正是贴译一闪一闪的原因。）
    if ((self.lastInlineTranslationKey && [self.lastInlineTranslationKey isEqualToString:identity] &&
         self.lastInlineLayoutResult) || minorOCRJitter) {
        if (minorOCRJitter) {
            // 跳过重排时仍要把这一帧轻微抖动后的原始身份映回面板身份。
            if (!self.inlineStableBlockIDs) { self.inlineStableBlockIDs = [NSMutableDictionary dictionary]; }
            for (NSUInteger index = 0; index < items.count; index++) {
                OCRTextItem *item = items[index];
                FYInlineTextBlock *block = [self inlineLayoutBlockForItem:item order:(NSInteger)index];
                NSString *stableID = [FYInlineBlockMatcher stableBlockIDForBlock:block
                                                                           text:block.text
                                                                    sourceFrame:[self appKitFrameForOCRItem:item inWindowFrame:windowFrame]
                                                                 previousResult:self.lastInlineLayoutResult];
                if (stableID.length > 0) { self.inlineStableBlockIDs[block.blockID] = stableID; }
            }
            for (NSPanel *panel in self.inlineLongCardPanels) {
                [self updateInlineLongCardSelectedBadgeForPanel:panel];
            }
        }
        self.inlineGeometryPending = NO;
        [self recordInlineLayoutDebug:self.lastInlineLayoutResult previous:self.lastInlineLayoutResult viewport:windowFrame
            reason:minorOCRJitter ? @"cache_minor_ocr_jitter" : @"cache_identical_input"];
        // 内容没变也要推进展开态记账（上一帧的排版结果里还有没有这一块）。
        [self advanceExpandedReadingState];
        [self refreshOverlayVisibility:nil];
        return;
    }
    NSUInteger count = MIN(translations.count, items.count);
    [self recordInlineRenderInputCount:count];

    NSMutableArray<FYInlineLayoutRequest *> *requests = [NSMutableArray array];
    NSMutableDictionary<NSString *, OCRTextItem *> *itemsByBlockID = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < count; index++) {
        NSString *translation = Trim(translations[index]);
        if (translation.length == 0) { continue; }
        OCRTextItem *item = items[index];
        FYInlineTextBlock *block = [self inlineLayoutBlockForItem:item order:(NSInteger)index];
        NSRect sourceFrame = [self appKitFrameForOCRItem:item inWindowFrame:windowFrame];
        FYInlineLayoutRequest *request = [FYInlineLayoutRequest requestWithBlock:block translation:translation sourceFrame:sourceFrame];
        NSValue *manual = [self inlineManualOffsetForText:block.text normalizedBox:block.boundingBox];
        if (manual) {
            request.manuallyPlaced = YES;
            request.manualOffset = manual.sizeValue;
        }
        [requests addObject:request];
        itemsByBlockID[block.blockID] = item;
    }
    FYInlineLayoutResult *previousLayout = self.lastInlineLayoutResult;
    NSString *layoutUpdateReason = !previousLayout ? @"initial" :
        (![self.lastInlineLayoutGeometryKey isEqual:geometryKey] ? @"geometry_or_style_changed" :
        (![self.lastInlineLayoutContentKey isEqual:contentKey] ? @"content_changed" : @"ocr_geometry_changed"));
    FYInlineLayoutResult *result = [self.inlineLayoutEngine layoutRequests:requests
                                                                 viewport:windowFrame
                                                                 previous:self.lastInlineLayoutResult];

    FYInlineDisplayFrame *frame = [[FYInlineDisplayFrame alloc] initWithResult:result previous:previousLayout
        viewport:windowFrame items:items itemsByBlockID:itemsByBlockID identity:identity
        contentKey:contentKey geometryKey:geometryKey reason:layoutUpdateReason];
    [self applyInlineDisplayFrame:frame];
}

- (BOOL)hasMinorOCRJitterForItems:(NSArray<OCRTextItem *> *)items contentKey:(NSString *)contentKey geometryKey:(NSString *)geometryKey {
    BOOL minorOCRJitter = self.lastInlineLayoutResult &&
        [self.lastInlineLayoutContentKey isEqualToString:contentKey] &&
        [self.lastInlineLayoutGeometryKey isEqualToString:geometryKey] &&
        self.lastInlineLayoutBoxes.count == items.count;
    for (NSUInteger index = 0; minorOCRJitter && index < items.count; index++) {
        NSRect before = self.lastInlineLayoutBoxes[index].rectValue;
        NSRect now = items[index].boundingBox;
        minorOCRJitter = fabs(NSMinX(before) - NSMinX(now)) < 0.003 &&
            fabs(NSMinY(before) - NSMinY(now)) < 0.003 &&
            fabs(NSWidth(before) - NSWidth(now)) < 0.003 &&
            fabs(NSHeight(before) - NSHeight(now)) < 0.003;
    }
    return minorOCRJitter;
}

- (void)applyInlineDisplayFrame:(FYInlineDisplayFrame *)frame {
    FYInlineLayoutResult *result=frame.result, *previousLayout=frame.previous;
    NSRect windowFrame=frame.viewport;
    NSArray<OCRTextItem *> *items=frame.items;
    NSDictionary<NSString *,OCRTextItem *> *itemsByBlockID=frame.itemsByBlockID;
    NSString *identity=frame.identity, *contentKey=frame.contentKey, *geometryKey=frame.geometryKey, *layoutUpdateReason=frame.reason;
    NSMutableArray<NSPanel *> *shortPanels = [NSMutableArray array];
    NSMutableArray<NSPanel *> *longPanels = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSPanel *> *keptPanels = [NSMutableDictionary dictionary];
    NSUInteger unplaceable = 0;
    NSUInteger compactEntries = 0;

    for (FYInlinePlacement *placement in result.placements) {
        OCRTextItem *item = itemsByBlockID[placement.sourceBlockID];
        if (!item) { continue; }
        if (placement.mode == FYInlineDisplayModeUnplaceable) {
            unplaceable += 1;
            // 诊断要能看出"到底是什么放不下"：原文框、长卡尺寸、紧凑入口尺寸、逐候选被拒原因
            // （含冲突的是哪一块、交叠多厚），而不是一句"所有候选冲突"。
            [self recordInlineUnplaceableDiagnosticForItem:item placement:placement viewport:windowFrame];
            continue;
        }
        // 紧凑入口一律用长卡视图渲染：它可能是"多行但被判成短块"的段落降级出来的，
        // 用短贴片视图会拿不到 labelFrame（引擎没有给紧凑入口算短贴片排版）。
        BOOL wantsLongCard = item.blockKind == InlineBlockKindLong ||
                             placement.mode == FYInlineDisplayModeCompactEntry;
        NSPanel *panel = self.inlinePanelsByBlockID[placement.blockID];
        if (panel && ([self inlinePanelHasLongCardContent:panel] != wantsLongCard)) {
            // 短贴片 ↔ 长卡切换：内容视图语义不同，只重建这一个面板。
            [self closeInlinePanel:panel];
            panel = nil;
        }
        if (wantsLongCard) {
            if (panel) {
                [self updateInlineLongCard:panel
                               translation:placement.translation
                                      item:item
                                     frame:placement.translationFrame
                                   compact:placement.compactEntry
                                 placement:placement];
            } else {
                panel = [self inlineLongPanelForTranslation:placement.translation
                                                       item:item
                                                      frame:placement.translationFrame
                                                  placement:placement];
            }
            if (!panel) { continue; }
            [longPanels addObject:panel];
        } else {
            InlinePanelLayout layout = [self inlinePanelLayoutFromPlacement:placement];
            if (panel) {
                [self updateInlinePanel:panel
                            translation:placement.translation
                             sourceText:item.text
                            sourceFrame:placement.sourceFrame
                            windowFrame:windowFrame
                                 layout:layout];
            } else {
                panel = [self inlinePanelForTranslation:placement.translation
                                             sourceText:item.text
                                            sourceFrame:placement.sourceFrame
                                            windowFrame:windowFrame
                                                 layout:layout];
            }
            if (!panel) { continue; }
            [shortPanels addObject:panel];
        }
        [self setInlinePanel:panel identifier:placement.blockID];
        [self wireInlinePanelDrag:panel placement:placement];
        keptPanels[placement.blockID] = panel;
        if (placement.mode == FYInlineDisplayModeCompactEntry) { compactEntries += 1; }
        // 诊断行里同时给出「OCR 归一化框」「换算出的原文框」「面板框」：
        // 现场错位时能一眼区分是坐标映射错、还是布局把面板放远了。
        // 紧凑入口额外打出长卡尺寸与入口尺寸，方便判断"是尺寸问题还是真的没地方"。
        [self recordInlinePlacedPanelDiagnostics:panel item:item placement:placement];
    }

    // 这一帧多出来的旧面板关掉。
    for (NSString *blockID in self.inlinePanelsByBlockID) {
        if (!keptPanels[blockID]) { [self closeInlinePanel:self.inlinePanelsByBlockID[blockID]]; }
    }
    self.inlinePanelsByBlockID = [keptPanels mutableCopy];
    self.inlineTranslationPanels = shortPanels;
    self.inlineLongCardPanels = longPanels;
    [self recordInlineLayoutDebug:result previous:previousLayout viewport:windowFrame reason:layoutUpdateReason];
    self.lastInlineLayoutResult = result;
    // 记录本帧「原始身份 → 稳定身份」，供选中判定/快照使用（缺字典时按需创建）。
    if (!self.inlineStableBlockIDs) { self.inlineStableBlockIDs = [NSMutableDictionary dictionary]; }
    [self.inlineStableBlockIDs removeAllObjects];
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.sourceBlockID.length == 0 || placement.blockID.length == 0) { continue; }
        self.inlineStableBlockIDs[placement.sourceBlockID] = placement.blockID;
    }
    // 手动位置：把这一帧仍然存在的块按当前锚点重新落键（抖动换桶也不会丢），
    // 连续多帧没出现的块直接丢弃 —— 换页时不把偏移继承给别的块。
    [self maintainInlineManualOffsetsForPlacements:result.placements];
    [self refreshInlineTranslationList];
    if (shortPanels.count + longPanels.count > 0) { [self startInlineModifierMonitorThroughHost]; }
    self.lastInlineUnplaceableCount = unplaceable;
    self.lastInlineCompactEntryCount = compactEntries;
    self.lastInlineTranslationKey = identity;
    self.lastInlineLayoutContentKey = [contentKey copy];
    self.lastInlineLayoutGeometryKey = geometryKey;
    NSMutableArray<NSValue *> *layoutBoxes = [NSMutableArray arrayWithCapacity:items.count];
    for (OCRTextItem *item in items) { [layoutBoxes addObject:[NSValue valueWithRect:item.boundingBox]]; }
    self.lastInlineLayoutBoxes = layoutBoxes;
    // 记下这次渲染用的几何上下文：文本没变但几何变了时，靠它判断必须重排。
    self.lastInlineRenderGeometryToken = self.lastDisplayGeometryToken ?: @"";
    self.inlineGeometryPending = NO;
    // 极端降级：确实连折叠入口都贴不到原文旁边的块，在游戏显示区域边缘给一个总入口。
    [self updateInlineOverflowEntryThroughHostWithPlacements:result.placements
                                            items:itemsByBlockID
                                         viewport:windowFrame
                                      unplaceable:unplaceable];
    // 展开态维护：读卡仍然属于当前页面就保持展开（并再次收起其它贴译）；
    // 连续两帧都见不到这一块才认为它不在当前场景了。
    // 长卡候选组合的逐条结果：现场日志直接区分"文字太长 / 可用空间不足 / 重复块假冲突"。
    for (FYInlinePlacement *placement in result.placements) {
        if (placement.variantDiagnostics.count == 0) { continue; }
        [self recordInlineCardVariantDiagnostic:placement];
    }
[self advanceExpandedReadingState];
    [self refreshOverlayVisibility:nil];
}
@end
