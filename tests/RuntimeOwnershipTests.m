#import "app/FYAppDelegateInternal.h"
#import <objc/runtime.h>
#import "inline/FYInlineTextModelsInternal.h"

static NSUInteger checks;
static void Check(BOOL value, NSString *message) {
    checks++;
    if (!value) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(2); }
}
@interface RuntimeTaskProbe : NSObject
@property(nonatomic) NSUInteger cancelCalls;
@end
@implementation RuntimeTaskProbe
- (void)cancel { self.cancelCalls++; }
@end
@interface RuntimeHostProbe : AppDelegate
@property(nonatomic) NSUInteger invalidations;
@property(nonatomic, strong) FYContentTranslationSnapshot *clockSnapshot;
@end
@implementation RuntimeHostProbe
- (void)invalidateContentTranslation { self.invalidations++; [super invalidateContentTranslation]; }
- (NSDate *)translationProcessingDate {
    self.clockSnapshot = [self.translationRuntimeController.contentState snapshot];
    return [NSDate date];
}
- (void)refreshOverlayVisibility:(id)sender {}
- (void)setStatus:(NSString *)status {}
- (void)updateRunState {}
@end

static void (^heldReply)(NSString *, NSError *);
@interface RuntimeReplyProbe : AppDelegate
@end
@implementation RuntimeReplyProbe
- (void)translateTextRealtime:(NSString *)text systemPrompt:(NSString *)prompt maxTokens:(NSInteger)tokens
                  completion:(void (^)(NSString *, NSError *))completion {
    heldReply = [completion copy];
}
@end

static void (^heldInlineReply)(NSError *);
static NSMutableArray<NSString *> *heldInlineValues;
@interface RuntimeInlineReplyProbe : AppDelegate
@end
@implementation RuntimeInlineReplyProbe
- (void)translateInlineBatch:(NSArray<OCRTextItem *> *)items indexes:(NSArray<NSNumber *> *)indexes
    keys:(NSArray<NSString *> *)keys translations:(NSMutableArray<NSString *> *)translations
    long:(BOOL)longText completion:(void (^)(NSError *))completion {
    heldInlineReply = [completion copy]; heldInlineValues = translations;
}
@end

@interface RuntimePreviewProbe : AppDelegate
@property(nonatomic, strong) dispatch_semaphore_t captureEntered;
@property(nonatomic, strong) dispatch_semaphore_t captureRelease;
@property(nonatomic) NSUInteger previewApplies;
@end
@implementation RuntimePreviewProbe
- (BOOL)livePreviewVisible { return YES; }
- (uint32_t)displayTargetWindowID { return 42; }
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID {
    dispatch_semaphore_signal(self.captureEntered);
    dispatch_semaphore_wait(self.captureRelease, DISPATCH_TIME_FOREVER);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 4, 4, 8, 16, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}
- (void)applyPreviewImage:(CGImageRef)image {
    Check(NSThread.isMainThread && image != NULL, @"original preview receiver receives pixels on main");
    self.previewApplies++;
}
@end

@interface RuntimeOCRProbe : RuntimePreviewProbe
@end
@implementation RuntimeOCRProbe
- (BOOL)captureCardInputEnabled { return NO; }
- (void)refreshDisplayGeometryIfNeeded:(BOOL)force {}
- (NSArray<NSDictionary *> *)updateRuntimeDiagnostics { return @[]; }
@end

static AppDelegate *mappingExternalHost;
@interface RuntimeMappingProbe : AppDelegate
@property(nonatomic, strong) NSMutableArray *mappingEvents;
@property(nonatomic, copy) void (^duringMappingBuild)(void);
@end
@implementation RuntimeMappingProbe
- (NSRect)appKitFrameForWindowItem:(WindowItem *)window {
    [self.mappingEvents addObject:@"frame"]; return NSMakeRect(-100,20,640,640);
}
- (BOOL)captureCardEstimatedDisplayRectForWindow:(WindowItem *)window outRect:(NSRect *)rect {
    [self.mappingEvents addObject:@"fit"]; *rect=NSMakeRect(-100,20,640,640);return YES;
}
- (BOOL)buildCaptureGridsWithFrame:(double **)templ templateW:(size_t *)tw templateH:(size_t *)th
    scene:(double **)scene sceneW:(size_t *)sw sceneH:(size_t *)sh videoAspect:(CGFloat *)aspect
    sceneWidth:(size_t)width forWindow:(WindowItem *)window reason:(NSString **)reason {
    [self.mappingEvents addObject:@"build"];
    Check(width==320 && window.windowID==7, @"native mapping build override receives original window and grid width");
    if(self.duringMappingBuild)self.duringMappingBuild();
    *tw=*th=8;*sw=*sh=64;*aspect=1;*templ=malloc(64*sizeof(double));*scene=malloc(4096*sizeof(double));
    for(size_t y=0;y<64;y++)for(size_t x=0;x<64;x++)(*scene)[y*64+x]=x+3*y;
    for(size_t y=0;y<8;y++)for(size_t x=0;x<8;x++)(*templ)[y*8+x]=x+3*y;
    FYNormalizeSignature(*templ,64);return YES;
}
- (void)storeCaptureCardMapping:(NSRect)rect windowFrame:(NSRect)frame videoAspect:(CGFloat)aspect
    deviceID:(NSString *)device source:(NSString *)source confidence:(CGFloat)confidence forWindowID:(uint32_t)windowID {
    [self.mappingEvents addObject:@"store"];
    Check(windowID==7 && [source isEqual:@"auto"] && confidence>.99,
        @"mapping coordinator calls concrete host store override with canonical result");
    [super storeCaptureCardMapping:rect windowFrame:frame videoAspect:aspect deviceID:device
        source:source confidence:confidence forWindowID:windowID];
}
- (void)resetInlineLayoutCacheAfterMappingChange {
    [self.mappingEvents addObject:@"reset"];
    Check(self.lastMappingValidationDate!=nil, @"native reset observes store grace date before layout reset");
    [super resetInlineLayoutCacheAfterMappingChange];
}
@end

static void Wait(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && deadline.timeIntervalSinceNow > 0) {
        @autoreleasepool {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
        }
    }
    Check(done(), @"preview lifetime check finishes within the deadline");
}

int main(void) { @autoreleasepool {
    __weak AppDelegate *released;
    FYTranslationRuntimeController *runtime;
    FYCaptureRuntimeController *capture;
    @autoreleasepool {
        AppDelegate *cold = [AppDelegate new]; released = cold;
        runtime = cold.translationRuntimeController; capture = cold.captureRuntimeController;
        for (NSString *name in @[@"recognitionWorkflow",@"contentPreparation",@"contentAdmission",@"requestWorkflow",@"resultDelivery"]) {
            id stage=[runtime valueForKey:name];
            Check(stage!=nil,[name stringByAppendingString:@" cold stage is available without starting work"]);
            unsigned int fieldCount=0; Ivar *fields=class_copyIvarList([stage class],&fieldCount); free(fields);
            Check(fieldCount==0,[name stringByAppendingString:@" has no duplicate mutable state or persistent host lease"]);
        }
        Check(!cold.running && !cold.timer && !cold.previewTimer && !cold.inFlight && !cold.previewInFlight,
              @"cold runtime access does not start polling or work");
        Check(runtime.recognitionScheduler && !runtime.recognitionScheduler.running &&
              !runtime.recognitionScheduler.inFlight && !runtime.recognitionScheduler.timer,
              @"cold recognition owner starts no timer or cycle");
        Check(runtime.refinementSession && !runtime.refinementSession.legacyContext && !runtime.refinementSession.stabilizer,
              @"cold refinement session starts no context evidence or external work");
        Check(capture.mappingCoordinator && !capture.mappingCoordinator.captureMappingCache &&
              !capture.mappingCoordinator.autoLocateSchedule && !capture.mappingCoordinator.mappingValidationSchedule,
              @"cold mapping coordinator retains no native resources and leaves original lazy owners empty");
        FYInlinePlacement *coldPlacement=[FYInlinePlacement new];
        FYInlineLayoutResult *coldLayout=[FYInlineLayoutResult new];
        Check(!coldPlacement.font && !coldPlacement.paragraphStyle && !coldLayout.placements.count,
              @"shared pure layout model construction creates no native font/style or layout work");
        Check(class_getInstanceVariable(FYInlineLayoutResult.class,"_byBlockID") &&
              !class_getInstanceVariable(FYInlineLayoutEngine.class,"_byBlockID"),
              @"result model is sole owner of original placement index");
        coldPlacement.blockID=@"synthetic model";coldPlacement.stableBodyFontSize=19;
        coldLayout.placements=@[coldPlacement];
        Check([coldLayout placementForBlockID:@"synthetic model"]==coldPlacement &&
              coldLayout.visiblePlacements.firstObject==coldPlacement && coldPlacement.stableBodyFontSize==19,
              @"production host and pure consumer share same placement class, index and variant fields");
        FYInlineOverlayController *nativeDisplay=cold.inlineOverlayController;
        Check([nativeDisplay isKindOfClass:FYInlineDisplayCoordinator.class]&&
              class_getInstanceVariable(FYInlineDisplayCoordinator.class,"_inlinePanelsByBlockID")&&
              class_getInstanceVariable(FYInlineDisplayCoordinator.class,"_lastInlineLayoutResult"),
              @"production native display receiver inherits sole Foundation/CG panel/cache/result owner");
        unsigned int displayCount=0;Ivar *displayIvars=class_copyIvarList(FYInlineDisplayCoordinator.class,&displayCount);free(displayIvars);
        Check(displayCount==16&&!class_getInstanceVariable(FYInlineDisplayCoordinator.class,"_host")&&
              !class_getInstanceVariable(FYInlineDisplayCoordinator.class,"_inlineLayoutEngine"),
              @"display coordinator owns exactly16 original fields without idle native host or second engine");
        unsigned int nativeDisplayCount=0;Ivar *nativeDisplayIvars=class_copyIvarList(FYInlineOverlayController.class,&nativeDisplayCount);BOOL duplicates=NO;
        NSSet *displayNames=[NSSet setWithArray:@[@"_inlineLongCardPanels",@"_inlinePanelsByBlockID",@"_inlineStableBlockIDs",@"_inlineTranslationPanels",@"_lastInlineCompactEntryCount",@"_lastInlineLayoutBoxes",@"_lastInlineLayoutContentKey",@"_lastInlineLayoutDebugContext",@"_lastInlineLayoutDebugViewport",@"_lastInlineLayoutGeometryKey",@"_lastInlineLayoutResult",@"_lastInlineRenderGeometryToken",@"_lastInlineRenderedItems",@"_lastInlineRenderedTranslations",@"_lastInlineTranslationKey",@"_lastInlineUnplaceableCount"]];
        for(unsigned int i=0;i<nativeDisplayCount;i++)if([displayNames containsObject:@(ivar_getName(nativeDisplayIvars[i]))])duplicates=YES;free(nativeDisplayIvars);
        Check(!duplicates,@"native controller has no second storage for any of16 transferred display fields");
        NSMutableDictionary *panelAlias=[NSMutableDictionary new];cold.inlinePanelsByBlockID=panelAlias;
        Check(nativeDisplay.inlinePanelsByBlockID==panelAlias&&((FYInlineDisplayCoordinator *)nativeDisplay).inlinePanelsByBlockID==panelAlias,
              @"concrete host compatibility setter preserves mutable panel registry alias in sole inherited owner");
        FYInlineManualPlacementCoordinator *manualOwner=nativeDisplay.manualPlacementCoordinator;
        FYInlineDragController *dragOwner=nativeDisplay.dragController;
        Check(manualOwner&&dragOwner&&!dragOwner.inlineModifierTimer&&!dragOwner.inlineDraggingPanel&&!dragOwner.inlineOptionDragArmed,
              @"cold manual and native drag component access creates only empty owners without polling or UI resources");
        unsigned int manualCount=0,dragCount=0;Ivar *manualIvars=class_copyIvarList(FYInlineManualPlacementCoordinator.class,&manualCount);Ivar *dragIvars=class_copyIvarList(FYInlineDragController.class,&dragCount);free(manualIvars);free(dragIvars);
        Check(manualCount==2&&dragCount==3&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineManualOffsets")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineManualOffsetAge")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineDraggingPanel")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineModifierTimer")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineOptionDragArmed"),
              @"two manual dictionary fields and three drag/resource fields each have sole independent owner");
        NSMutableDictionary *manualAlias=[NSMutableDictionary new],*manualAgeAlias=[NSMutableDictionary new];cold.inlineManualOffsets=manualAlias;cold.inlineManualOffsetAge=manualAgeAlias;
        Check(manualOwner.inlineManualOffsets==manualAlias&&manualOwner.inlineManualOffsetAge==manualAgeAlias&&
              nativeDisplay.inlineManualOffsets==manualAlias&&nativeDisplay.inlineManualOffsetAge==manualAgeAlias,
              @"host/native manual compatibility getters preserve exact mutable aliases in sole coordinator");
        __weak NSObject *dragMarker;
        @autoreleasepool{NSObject *marker=[NSObject new];dragMarker=marker;cold.inlineDraggingPanel=(NSPanel *)marker;Check(dragOwner.inlineDraggingPanel==(NSPanel *)marker&&nativeDisplay.inlineDraggingPanel==(NSPanel *)marker,@"host drag setter writes sole native resource owner without extra state");}
        Check(!dragMarker&&!dragOwner.inlineDraggingPanel&&!cold.inlineDraggingPanel,@"dragging resource compatibility remains weak after original panel release");
        FYMainWindowController *mainOwner=cold.mainWindowController;FYDisplayedSentenceState *visibleOwner=mainOwner.displayedSentenceState;FYWordSelectionController *wordOwner=mainOwner.wordSelectionController;
        Check(visibleOwner&&wordOwner&&!visibleOwner.displayedSentenceID&&!visibleOwner.displayedVersion&&!wordOwner.vocabSelectionGeneration&&!wordOwner.savingVocabulary&&!wordOwner.vocabCompletionFromAI,
              @"cold displayed/word owners create only original empty state without views/services/tasks");
        unsigned int visibleCount=0,wordCount=0;Ivar *visibleIvars=class_copyIvarList(FYDisplayedSentenceState.class,&visibleCount);Ivar *wordIvars=class_copyIvarList(FYWordSelectionController.class,&wordCount);free(visibleIvars);free(wordIvars);
        Check(visibleCount==4&&wordCount==3&&!class_getInstanceVariable(FYMainWindowController.class,"_displayedSentenceID")&&
              !class_getInstanceVariable(FYMainWindowController.class,"_displayedSourceText")&&!class_getInstanceVariable(FYMainWindowController.class,"_displayedTranslation")&&
              !class_getInstanceVariable(FYMainWindowController.class,"_displayedVersion")&&!class_getInstanceVariable(FYMainWindowController.class,"_vocabSelectionGeneration")&&
              !class_getInstanceVariable(FYMainWindowController.class,"_savingVocabulary")&&!class_getInstanceVariable(FYMainWindowController.class,"_vocabCompletionFromAI"),
              @"displayed four fields and word generation/busy/AI three fields each have sole owners without main duplicate ivars");
        NSMutableString *displayAlias=[@"visible-copy" mutableCopy];cold.displayedSentenceID=displayAlias;cold.displayedSourceText=displayAlias;cold.displayedTranslation=displayAlias;cold.displayedVersion=4;[displayAlias appendString:@"changed"];
        Check([visibleOwner.displayedSentenceID isEqual:@"visible-copy"]&&[visibleOwner.displayedSourceText isEqual:@"visible-copy"]&&
              [visibleOwner.displayedTranslation isEqual:@"visible-copy"]&&visibleOwner.displayedVersion==4&&[mainOwner.displayedSentenceID isEqual:@"visible-copy"],
              @"host/main visible identity/version/text/translation compatibility preserves original copy ownership");
        cold.vocabSelectionGeneration=7;cold.savingVocabulary=YES;cold.vocabCompletionFromAI=YES;
        Check(wordOwner.vocabSelectionGeneration==7&&wordOwner.savingVocabulary&&wordOwner.vocabCompletionFromAI&&mainOwner.vocabSelectionGeneration==7,
              @"host/main vocabulary state writes exact sole word owner without paired task state");
        Check(!class_getInstanceVariable(FYWordSelectionController.class,"_host")&&!class_getInstanceVariable(FYWordSelectionController.class,"_source")&&
              !class_getInstanceVariable(FYWordSelectionController.class,"_learningCoordinator")&&!class_getInstanceVariable(FYDisplayedSentenceState.class,"_learningCoordinator"),
              @"word/display components do not own idle host/source or duplicate learning service state");
        cold.displayedSentenceID=nil;cold.displayedSourceText=nil;cold.displayedTranslation=nil;cold.displayedVersion=0;cold.vocabSelectionGeneration=0;cold.savingVocabulary=NO;cold.vocabCompletionFromAI=NO;
        FYLiveReadingCoordinator *readingOwner=mainOwner.liveReadingCoordinator;FYLiveReadingRenderer *readingRenderer=mainOwner.liveReadingRenderer;
        Check(readingOwner&&readingRenderer&&NSApp==nil&&mainOwner.displayedSentenceState==visibleOwner&&mainOwner.wordSelectionController==wordOwner,
              @"cold live refresh/renderer owners create no UI or alternate displayed/word owners");
        unsigned int readingCount=0,readingRenderCount=0;Ivar *readingIvars=class_copyIvarList(FYLiveReadingCoordinator.class,&readingCount);Ivar *readingRenderIvars=class_copyIvarList(FYLiveReadingRenderer.class,&readingRenderCount);free(readingIvars);free(readingRenderIvars);
        Check(readingCount==0&&readingRenderCount==0,
              @"live refresh and native renderer are stateless without second source/identity/view/font/cache owner");
        Check(!class_getInstanceVariable(FYLiveReadingCoordinator.class,"_host")&&!class_getInstanceVariable(FYLiveReadingCoordinator.class,"_receiver")&&
              !class_getInstanceVariable(FYLiveReadingRenderer.class,"_host")&&!class_getInstanceVariable(FYLiveReadingRenderer.class,"_receiver")&&
              mainOwner.liveReadingCoordinator==readingOwner&&mainOwner.liveReadingRenderer==readingRenderer,
              @"main lazy live component ownership is stable and no idle host/receiver lease retained");
        FYInlineTranslationListCoordinator *listOwner=mainOwner.inlineTranslationListCoordinator;FYInlineTranslationListRenderer *listRenderer=mainOwner.inlineTranslationListRenderer;
        Check(listOwner&&listRenderer&&!listOwner.inlineTranslationListSignature&&!listOwner.inlineTranslationListSnapshots&&
              !mainOwner.inlineTranslationListCard&&!mainOwner.inlineTranslationListStack&&!mainOwner.inlineTranslationListCount&&NSApp==nil,
              @"cold list owners retain original nil state without UI/resources/services");
        unsigned int listCount=0,listNativeCount=0;Ivar *listIvars=class_copyIvarList(FYInlineTranslationListCoordinator.class,&listCount);Ivar *listNativeIvars=class_copyIvarList(FYInlineTranslationListRenderer.class,&listNativeCount);free(listIvars);free(listNativeIvars);
        Check(listCount==2&&listNativeCount==0&&!class_getInstanceVariable(FYMainWindowController.class,"_inlineTranslationListSignature")&&
              !class_getInstanceVariable(FYMainWindowController.class,"_inlineTranslationListSnapshots"),
              @"list original two copy fields have sole owner, native renderer no duplicate state");
        NSMutableString *listSignature=[@"list-copy" mutableCopy];FYInlineBlockSnapshot *listSnapshot=[FYInlineBlockSnapshot new];NSMutableArray *listArray=[NSMutableArray arrayWithObject:listSnapshot];
        cold.inlineTranslationListSignature=listSignature;cold.inlineTranslationListSnapshots=listArray;[listSignature appendString:@"changed"];[listArray removeAllObjects];
        Check([listOwner.inlineTranslationListSignature isEqual:@"list-copy"]&&listOwner.inlineTranslationListSnapshots.count==1&&
              listOwner.inlineTranslationListSnapshots[0]==listSnapshot&&mainOwner.inlineTranslationListSnapshots==listOwner.inlineTranslationListSnapshots,
              @"host/Main list state compatibility preserves original copy array and element identity");
        Check(!class_getInstanceVariable(FYInlineTranslationListCoordinator.class,"_receiver")&&!class_getInstanceVariable(FYInlineTranslationListRenderer.class,"_receiver")&&
              mainOwner.inlineTranslationListCoordinator==listOwner&&mainOwner.inlineTranslationListRenderer==listRenderer&&mainOwner.liveReadingCoordinator==readingOwner,
              @"list components retain no idle receiver and do not duplicate original reading owner");
        cold.inlineTranslationListSignature=nil;cold.inlineTranslationListSnapshots=nil;
        FYLivePageBuilder *livePageOwner=mainOwner.livePageBuilder;
        Check(livePageOwner&&NSApp==nil&&!mainOwner.framePreview&&!mainOwner.learningSourceTextView&&mainOwner.wordSelectionController==wordOwner&&mainOwner.inlineTranslationListCoordinator==listOwner,
              @"cold native page builder creates no UI/observer/service or duplicate original owners");
        unsigned int livePageCount=0;Ivar *livePageIvars=class_copyIvarList(FYLivePageBuilder.class,&livePageCount);free(livePageIvars);
        Check(livePageCount==0&&!class_getInstanceVariable(FYLivePageBuilder.class,"_receiver")&&!class_getInstanceVariable(FYLivePageBuilder.class,"_observer"),
              @"native page builder retains no idle receiver/view/token/state");
        Check([mainOwner livePageActionTarget]==cold&&mainOwner.livePageBuilder==livePageOwner&&mainOwner.liveReadingRenderer==readingRenderer,
              @"native page SDK action target remains original Host and builder/reading ownership stays stable");
        unsigned int frameFieldCount=0;Ivar *frameFields=class_copyIvarList(FYFrameDrivenContentView.class,&frameFieldCount);free(frameFields);
        Check(frameFieldCount==3&&class_getInstanceVariable(FYFrameDrivenContentView.class,"_layoutContent")&&class_getInstanceVariable(FYFrameDrivenContentView.class,"_layoutWidth")&&class_getInstanceVariable(FYFrameDrivenContentView.class,"_layoutHeight"),
              @"independent same frame-driven native class owns original three resources and no Root or duplicate geometry state");
        FYReferencePresentationController *referenceNative=cold.referencePresentationController;FYReferenceQueryCoordinator *referenceQuery=referenceNative.queryCoordinator;FYSourceHoverCoordinator *hoverCore=referenceNative.hoverCoordinator;
        unsigned referenceQueryCount=0,hoverCount=0,referenceRendererCount=0;Ivar *referenceFields=class_copyIvarList(FYReferenceQueryCoordinator.class,&referenceQueryCount);free(referenceFields);referenceFields=class_copyIvarList(FYSourceHoverCoordinator.class,&hoverCount);free(referenceFields);referenceFields=class_copyIvarList(FYReferenceRenderer.class,&referenceRendererCount);free(referenceFields);
        Check(referenceQuery&&hoverCore&&referenceQueryCount==4&&hoverCount==4&&referenceRendererCount==0&&!referenceNative.referenceStack&&!referenceNative.referenceDictionary&&!referenceNative.sourceHoverCache&&NSApp==nil,
              @"reference query and hover owners stay cold; renderer owns no state or views");
        BOOL referenceUnique=YES;for(NSString *name in @[@"referenceRequestGeneration",@"referenceActiveWord",@"referenceRecords",@"referenceDictionary",@"sourceHoverGeneration",@"quickSourceHoverGeneration",@"sourceHoverCache",@"sourceHoverSuspended"]){NSString *ivar=[@"_" stringByAppendingString:name];Class owner=[@[@"referenceRequestGeneration",@"referenceActiveWord",@"referenceRecords",@"referenceDictionary"] containsObject:name]?FYReferenceQueryCoordinator.class:FYSourceHoverCoordinator.class;referenceUnique=referenceUnique&&class_getInstanceVariable(owner,ivar.UTF8String)&&!class_getInstanceVariable(FYReferencePresentationController.class,ivar.UTF8String)&&!class_getInstanceVariable(AppDelegate.class,ivar.UTF8String);}
        Check(referenceUnique&&[referenceNative conformsToProtocol:@protocol(FYReferenceQuerySource)]&&[referenceNative conformsToProtocol:@protocol(FYSourceHoverSource)]&&[referenceNative conformsToProtocol:@protocol(FYReferenceRenderSource)],
              @"eight reference fields have exactly one business owner through typed native contracts");
        NSMutableString *referenceWord=[NSMutableString stringWithString:@"synthetic"];NSMutableArray *referenceRecords=[NSMutableArray new];cold.referenceActiveWord=referenceWord;cold.referenceRecords=referenceRecords;[referenceWord appendString:@"-changed"];[referenceRecords addObject:@{}];
        Check([referenceQuery.referenceActiveWord isEqual:@"synthetic"]&&referenceQuery.referenceRecords.count==0,
              @"reference word and records keep original copy snapshots");
        NSCache *referenceCache=[NSCache new];cold.sourceHoverCache=referenceCache;cold.referenceRequestGeneration=7;cold.sourceHoverGeneration=11;cold.quickSourceHoverGeneration=13;cold.sourceHoverSuspended=YES;
        Check(hoverCore.sourceHoverCache==referenceCache&&referenceQuery.referenceRequestGeneration==7&&hoverCore.sourceHoverGeneration==11&&hoverCore.quickSourceHoverGeneration==13&&hoverCore.sourceHoverSuspended,
              @"query main hover and quick hover retain separate generations and original cache alias");
        referenceQuery.referenceActiveWord=nil;referenceQuery.referenceRecords=nil;hoverCore.sourceHoverCache=nil;referenceQuery.referenceRequestGeneration=0;hoverCore.sourceHoverGeneration=0;hoverCore.quickSourceHoverGeneration=0;hoverCore.sourceHoverSuspended=NO;
        Check(!cold.referenceActiveWord&&!cold.referenceRecords&&!cold.sourceHoverCache&&[referenceNative referenceActionTarget]==cold&&!class_getInstanceVariable(FYReferenceQueryCoordinator.class,"_receiver")&&!class_getInstanceVariable(FYSourceHoverCoordinator.class,"_receiver"),
              @"reference reverse facades share state and business owners keep no idle host");
        FYCollectionController *collectionNative=cold.collectionController;FYCollectionQueryCoordinator *collectionQueries=collectionNative.queryCoordinator;FYCollectionCardCoordinator *collectionCards=collectionNative.cardCoordinator;
        unsigned queryCount=0,cardCount=0,rendererCount=0;Ivar*fields=class_copyIvarList(FYCollectionQueryCoordinator.class,&queryCount);free(fields);fields=class_copyIvarList(FYCollectionCardCoordinator.class,&cardCount);free(fields);fields=class_copyIvarList(FYCollectionRenderer.class,&rendererCount);free(fields);
        Check(collectionQueries&&collectionCards&&queryCount==4&&cardCount==3&&rendererCount==0&&!collectionNative.wordCardStack&&!collectionNative.savedSentenceStack&&NSApp==nil,
              @"collection query/card owners and zero-state renderer stay cold without native resources");
        BOOL collectionUnique=YES;for(NSString*name in @[@"historyRecords",@"grammarBookmarks",@"vocabularyExamplesList",@"savedSentences",@"expandedWordCards",@"revealedMeanings",@"wordExampleIndices"]){NSString*ivar=[@"_" stringByAppendingString:name];Class owner=[@[@"historyRecords",@"grammarBookmarks",@"vocabularyExamplesList",@"savedSentences"] containsObject:name]?FYCollectionQueryCoordinator.class:FYCollectionCardCoordinator.class;collectionUnique=collectionUnique&&class_getInstanceVariable(owner,ivar.UTF8String)&&!class_getInstanceVariable(FYCollectionController.class,ivar.UTF8String)&&!class_getInstanceVariable(AppDelegate.class,ivar.UTF8String);}
        Check(collectionUnique&&[collectionNative conformsToProtocol:@protocol(FYCollectionQuerySource)]&&[collectionNative conformsToProtocol:@protocol(FYCollectionCardSource)]&&[collectionNative conformsToProtocol:@protocol(FYCollectionRenderSource)],
              @"all seven collection fields have one business owner through typed native contracts");
        NSMutableArray*collectionArray=[NSMutableArray array];cold.historyRecords=collectionArray;cold.grammarBookmarks=(id)collectionArray;cold.vocabularyExamplesList=(id)collectionArray;cold.savedSentences=(id)collectionArray;
        Check(collectionQueries.historyRecords==collectionArray&&collectionQueries.grammarBookmarks==(id)collectionArray&&collectionQueries.vocabularyExamplesList==(id)collectionArray&&collectionQueries.savedSentences!=(id)collectionArray,
              @"collection arrays retain original strong aliases except saved identities copy snapshot");
        NSMutableSet*collectionExpanded=[NSMutableSet new];NSMutableDictionary*collectionMeaning=[NSMutableDictionary new];NSMutableDictionary*collectionIndices=[NSMutableDictionary new];cold.expandedWordCards=collectionExpanded;cold.revealedMeanings=collectionMeaning;cold.wordExampleIndices=collectionIndices;
        Check(collectionCards.expandedWordCards==collectionExpanded&&collectionCards.revealedMeanings==collectionMeaning&&collectionCards.wordExampleIndices==collectionIndices&&[collectionNative collectionActionTarget]==cold,
              @"mutable card containers and original weak action target keep exact aliases");
        collectionQueries.historyRecords=nil;collectionQueries.grammarBookmarks=nil;collectionQueries.vocabularyExamplesList=nil;collectionQueries.savedSentences=nil;collectionCards.expandedWordCards=nil;collectionCards.revealedMeanings=nil;collectionCards.wordExampleIndices=nil;
        Check(!cold.historyRecords&&!cold.grammarBookmarks&&!cold.vocabularyExamplesList&&!cold.savedSentences&&!cold.expandedWordCards&&!cold.revealedMeanings&&!cold.wordExampleIndices&&!class_getInstanceVariable(FYCollectionQueryCoordinator.class,"_receiver")&&!class_getInstanceVariable(FYCollectionCardCoordinator.class,"_store"),
              @"reverse facades share state and neither business owner keeps idle host/store");
        FYCollectionController *reviewNative=cold.collectionController;FYCollectionReviewCoordinator *reviewCore=reviewNative.reviewCoordinator;
        unsigned reviewCount=0;Ivar*reviewFields=class_copyIvarList(FYCollectionReviewCoordinator.class,&reviewCount);free(reviewFields);
        Check(reviewCore&&reviewCount==3&&!reviewCore.reviewList&&!reviewCore.reviewingEntry&&reviewCore.reviewIndex==0&&NSApp==nil,
              @"collection review cold state owns three original fields without windows or a store connection");
        BOOL reviewUnique=YES;for(NSString*name in @[@"reviewList",@"reviewIndex",@"reviewingEntry"]){NSString*ivar=[@"_" stringByAppendingString:name];reviewUnique=reviewUnique&&class_getInstanceVariable(FYCollectionReviewCoordinator.class,ivar.UTF8String)&&!class_getInstanceVariable(FYCollectionController.class,ivar.UTF8String)&&!class_getInstanceVariable(AppDelegate.class,ivar.UTF8String);}
        Check(reviewUnique&&[reviewNative conformsToProtocol:@protocol(FYCollectionReviewSource)]&&!class_getInstanceVariable(FYCollectionReviewCoordinator.class,"_receiver")&&!class_getInstanceVariable(FYCollectionReviewCoordinator.class,"_store"),
              @"review has one physical state owner and a typed control-free workflow without idle host/store");
        FYVocabularyEntry*reviewEntry=[FYVocabularyEntry new];NSMutableArray*reviewList=[NSMutableArray arrayWithObject:reviewEntry];cold.reviewList=reviewList;cold.reviewIndex=7;cold.reviewingEntry=reviewEntry;
        Check(reviewCore.reviewList==reviewList&&reviewCore.reviewIndex==7&&reviewCore.reviewingEntry==reviewEntry&&reviewNative.reviewList==reviewList,
              @"Root/Collection compatibility accessors retain original strong array and entry aliases");
        reviewCore.reviewIndex=2;reviewCore.reviewingEntry=nil;reviewCore.reviewList=nil;
        Check(cold.reviewIndex==2&&!cold.reviewingEntry&&!cold.reviewList&&!reviewNative.reviewWordLabel&&!reviewNative.reviewMeaningLabel,
              @"reverse review accessors share state and do not create native controls");
        cold.reviewIndex=0;
        BOOL studyRenderersEmpty=YES;for(Class rendererClass in @[FYStudyChatRenderer.class,FYQuickSentenceRenderer.class,FYStudyScrollRenderer.class]){id renderer=[rendererClass new];unsigned count=0;Ivar*fields=class_copyIvarList(rendererClass,&count);free(fields);studyRenderersEmpty=studyRenderersEmpty&&renderer&&count==0;}
        Check(studyRenderersEmpty&&!cold.quickSentencePanel&&!cold.mainStudyChatView&&!cold.overlayStudyChatView,
              @"three native Study renderers initialize zero state and no views/windows/resources");
        BOOL studyViewsUnique=YES;for(NSString*name in @[@"mainStudyChatView",@"overlayStudyChatView",@"quickSentencePanel",@"quickGrammarChoices",@"quickGrammarDetailCard"]){NSString*ivar=[@"_" stringByAppendingString:name];studyViewsUnique=studyViewsUnique&&class_getInstanceVariable(FYStudyPresentationController.class,ivar.UTF8String)&&!class_getInstanceVariable(AppDelegate.class,ivar.UTF8String);}
        Check(studyViewsUnique,@"all original native views/arrays retain Study as sole physical owner");
        Check([cold.studyPresentationController studyActionTarget]==cold&&[cold.studyPresentationController conformsToProtocol:@protocol(FYStudyChatRenderSource)]&&[cold.studyPresentationController conformsToProtocol:@protocol(FYQuickSentenceRenderSource)]&&[cold.studyPresentationController conformsToProtocol:@protocol(FYStudyScrollRenderSource)],
              @"typed native view contracts preserve same original weak Host action target");
        Check(!class_getInstanceVariable(FYStudyPresentationController.class,"_studyChatRenderer")&&!class_getInstanceVariable(FYStudyPresentationController.class,"_quickSentenceRenderer")&&!class_getInstanceVariable(FYStudyPresentationController.class,"_studyScrollRenderer"),
              @"stateless renderer classes introduce no idle renderer/source state or duplicate view resources");
        FYStudyPresentationController *navNative=cold.studyPresentationController;FYStudyNavigationCoordinator *navCore=navNative.studyNavigationCoordinator;
        Check(navCore&&!navCore.inlineBlockSnapshot&&!navCore.inlineReturnSnapshot&&!navCore.inlineReturnSourceText&&!navCore.quickSentenceID&&!navCore.quickSentenceSource&&!navCore.quickSentenceTranslation&&!navCore.quickSentenceVersion&&!navCore.quickSentenceRequested&&!navCore.quickSentenceGeneration&&!navCore.quickSentenceIsInlineBlock&&!navCore.studyChatOverlayRequested&&!navCore.quickSelectedGrammarIndex&&!navNative.quickSentencePanel&&!navNative.studyChatSession,
              @"cold navigation creates twelve original empty fields without UI/session/device work");
        unsigned int navCount=0;Ivar *navFields=class_copyIvarList(FYStudyNavigationCoordinator.class,&navCount);free(navFields);BOOL navUnique=navCount==12;
        for(NSString*name in @[@"inlineBlockSnapshot",@"inlineReturnSnapshot",@"inlineReturnSourceText",@"quickSentenceID",@"quickSentenceSource",@"quickSentenceTranslation",@"quickSentenceVersion",@"quickSentenceRequested",@"quickSentenceGeneration",@"quickSentenceIsInlineBlock",@"studyChatOverlayRequested",@"quickSelectedGrammarIndex"]){NSString*ivar=[@"_" stringByAppendingString:name];navUnique=navUnique&&class_getInstanceVariable(FYStudyNavigationCoordinator.class,ivar.UTF8String)&&!class_getInstanceVariable(FYStudyPresentationController.class,ivar.UTF8String)&&!class_getInstanceVariable(AppDelegate.class,ivar.UTF8String);}
        Check(navUnique,@"all twelve navigation fields have one Foundation owner without Native/Root duplicates");
        FYInlineBlockSnapshot *navSnapshot=[FYInlineBlockSnapshot new];NSMutableString *navText=[@"nav-copy" mutableCopy];cold.inlineBlockSnapshot=navSnapshot;cold.inlineReturnSnapshot=navSnapshot;cold.inlineReturnSourceText=navText;cold.quickSentenceID=navText;cold.quickSentenceSource=navText;cold.quickSentenceTranslation=navText;cold.quickSentenceVersion=3;cold.quickSentenceRequested=YES;cold.quickSentenceGeneration=7;cold.quickSentenceIsInlineBlock=YES;cold.studyChatOverlayRequested=YES;cold.quickSelectedGrammarIndex=2;[navText appendString:@"changed"];
        Check(navCore.inlineBlockSnapshot==navSnapshot&&navCore.inlineReturnSnapshot==navSnapshot&&[navCore.inlineReturnSourceText isEqual:@"nav-copy"]&&[navCore.quickSentenceID isEqual:@"nav-copy"]&&[navCore.quickSentenceSource isEqual:@"nav-copy"]&&[navCore.quickSentenceTranslation isEqual:@"nav-copy"]&&navCore.quickSentenceVersion==3&&navCore.quickSentenceRequested&&navCore.quickSentenceGeneration==7&&navCore.quickSentenceIsInlineBlock&&navCore.studyChatOverlayRequested&&navCore.quickSelectedGrammarIndex==2,
              @"Root/native navigation compatibility preserves same snapshots, string copies and scalar state");
        navCore.quickSentenceVersion=4;navCore.quickSentenceGeneration=8;navCore.quickSentenceRequested=NO;navCore.studyChatOverlayRequested=NO;
        Check(cold.quickSentenceVersion==4&&cold.quickSentenceGeneration==8&&!cold.quickSentenceRequested&&!cold.studyChatOverlayRequested&&!class_getInstanceVariable(FYStudyNavigationCoordinator.class,"_receiver")&&!class_getInstanceVariable(FYStudyNavigationCoordinator.class,"_session"),
              @"navigation business writes are visible through both facades without idle receiver or second session/cancellation owner");
        cold.inlineBlockSnapshot=nil;cold.inlineReturnSnapshot=nil;cold.inlineReturnSourceText=nil;cold.quickSentenceID=nil;cold.quickSentenceSource=nil;cold.quickSentenceTranslation=nil;cold.quickSentenceVersion=0;cold.quickSentenceGeneration=0;cold.quickSentenceIsInlineBlock=NO;cold.quickSelectedGrammarIndex=0;
        FYStudyPresentationController *quickNative=cold.studyPresentationController;FYQuickSentenceCoordinator *quickCore=quickNative.quickSentenceCoordinator;
        Check(quickCore&&!quickCore.quickAnalysisGeneration&&!quickCore.quickSentenceAnalyzing&&!quickCore.quickSentenceAnalysis&&!quickCore.quickSentenceAnalysisError&&!quickCore.quickSentenceAnalysisSource&&!quickCore.quickSentenceAnalysisTranslation&&!quickCore.quickSentenceAnalyzer&&!quickCore.sentenceBookmarkPending&&!quickCore.quickGrammarBookmarkPending&&!quickNative.quickSentencePanel&&!quickNative.studyChatSession,
              @"cold quick workflow creates only nine empty fields without analyzers/session/UI or device work");
        unsigned int quickFieldCount=0;Ivar *quickFields=class_copyIvarList(FYQuickSentenceCoordinator.class,&quickFieldCount);free(quickFields);BOOL quickUnique=quickFieldCount==9;
        for(NSString *name in @[@"quickAnalysisGeneration",@"quickSentenceAnalyzing",@"quickSentenceAnalysis",@"quickSentenceAnalysisError",@"quickSentenceAnalysisSource",@"quickSentenceAnalysisTranslation",@"quickSentenceAnalyzer",@"sentenceBookmarkPending",@"quickGrammarBookmarkPending"]){NSString*ivar=[@"_" stringByAppendingString:name];quickUnique=quickUnique&&class_getInstanceVariable(FYQuickSentenceCoordinator.class,ivar.UTF8String)&&!class_getInstanceVariable(FYStudyPresentationController.class,ivar.UTF8String)&&!class_getInstanceVariable(AppDelegate.class,ivar.UTF8String);}
        Check(quickUnique,@"all nine quick state fields have exactly one Foundation owner without Root/native duplicate ivars");
        FYAnalysisResult *quickResult=[FYAnalysisResult new];NSMutableString*quickError=[@"quick-copy" mutableCopy];cold.quickSentenceAnalysis=quickResult;cold.quickAnalysisGeneration=7;cold.quickSentenceAnalyzing=YES;cold.quickSentenceAnalysisError=quickError;cold.quickSentenceAnalysisSource=@"quick-source";cold.quickSentenceAnalysisTranslation=@"quick-translation";cold.sentenceBookmarkPending=YES;cold.quickGrammarBookmarkPending=YES;[quickError appendString:@"changed"];
        Check(quickCore.quickSentenceAnalysis==quickResult&&quickCore.quickAnalysisGeneration==7&&quickCore.quickSentenceAnalyzing&&[quickCore.quickSentenceAnalysisError isEqual:@"quick-copy"]&&[quickCore.quickSentenceAnalysisSource isEqual:@"quick-source"]&&[quickCore.quickSentenceAnalysisTranslation isEqual:@"quick-translation"]&&quickCore.sentenceBookmarkPending&&quickCore.quickGrammarBookmarkPending,
              @"Root/native quick compatibility writes same strong/copy/scalar owner");
        quickCore.quickAnalysisGeneration=8;quickCore.quickSentenceAnalyzing=NO;quickCore.sentenceBookmarkPending=NO;quickCore.quickGrammarBookmarkPending=NO;
        Check(cold.quickAnalysisGeneration==8&&!cold.quickSentenceAnalyzing&&!cold.sentenceBookmarkPending&&!cold.quickGrammarBookmarkPending&&!class_getInstanceVariable(FYQuickSentenceCoordinator.class,"_receiver")&&!class_getInstanceVariable(FYQuickSentenceCoordinator.class,"_store"),
              @"quick business writes are visible through facades with no idle receiver or second store/cancel service");
        cold.quickSentenceAnalysis=nil;cold.quickAnalysisGeneration=0;cold.quickSentenceAnalysisError=nil;cold.quickSentenceAnalysisSource=nil;cold.quickSentenceAnalysisTranslation=nil;
        FYStudyPresentationController *studyNative=cold.studyPresentationController;FYStudyChatContextCoordinator *chatCore=studyNative.studyChatContextCoordinator;
        Check(chatCore&&!chatCore.chatContextGeneration&&!chatCore.chatResolvingSource&&!studyNative.studyChatSession&&!studyNative.mainStudyChatView&&!studyNative.overlayStudyChatView&&!studyNative.studyChatPanel,
              @"cold chat context access creates only two original scalars, no session/UI/device work");
        unsigned int chatFieldCount=0;Ivar *chatFields=class_copyIvarList(FYStudyChatContextCoordinator.class,&chatFieldCount);free(chatFields);
        Check(chatFieldCount==2&&!class_getInstanceVariable(FYStudyPresentationController.class,"_chatContextGeneration")&&!class_getInstanceVariable(FYStudyPresentationController.class,"_chatResolvingSource")&&!class_getInstanceVariable(AppDelegate.class,"_chatContextGeneration")&&!class_getInstanceVariable(AppDelegate.class,"_chatResolvingSource"),
              @"chat context generation/resolving have one Foundation state owner, no native/Root duplicate ivars");
        cold.chatContextGeneration=7;cold.chatResolvingSource=YES;
        Check(chatCore.chatContextGeneration==7&&chatCore.chatResolvingSource&&studyNative.chatContextGeneration==7,
              @"Root and native compatibility write the same chat context state");
        chatCore.chatContextGeneration=8;chatCore.chatResolvingSource=NO;
        Check(cold.chatContextGeneration==8&&!cold.chatResolvingSource&&!class_getInstanceVariable(FYStudyChatContextCoordinator.class,"_receiver")&&!class_getInstanceVariable(FYStudyChatContextCoordinator.class,"_session"),
              @"business writes are visible through both facades without idle receiver or duplicate session/cancellation");
        cold.chatContextGeneration=0;cold.chatResolvingSource=NO;
        FYGrammarPresentationController *grammarNative=cold.grammarPresentationController;FYGrammarInteractionCoordinator *grammarCore=grammarNative.grammarInteractionCoordinator;
        Check(grammarCore&&!grammarCore.currentAnalysis&&!grammarCore.grammarActions&&!grammarCore.quickGrammarActions&&!grammarCore.analysisRequestGeneration&&!grammarCore.followupRequestGeneration&&!grammarCore.learningAnalysisBusy&&!grammarCore.grammarAnalysisError,
              @"cold grammar sole owner creates original seven empty fields, no action analyzers/services/UI");
        unsigned int grammarFieldCount=0;Ivar *grammarFields=class_copyIvarList(FYGrammarInteractionCoordinator.class,&grammarFieldCount);free(grammarFields);
        Check(grammarFieldCount==7&&!class_getInstanceVariable(FYGrammarPresentationController.class,"_analysisRequestGeneration")&&
              !class_getInstanceVariable(FYGrammarPresentationController.class,"_followupRequestGeneration")&&!class_getInstanceVariable(FYGrammarPresentationController.class,"_learningAnalysisBusy")&&
              !class_getInstanceVariable(FYGrammarPresentationController.class,"_currentAnalysis")&&!class_getInstanceVariable(FYGrammarPresentationController.class,"_grammarAnalysisError")&&
              !class_getInstanceVariable(FYGrammarPresentationController.class,"_grammarActions")&&!class_getInstanceVariable(FYGrammarPresentationController.class,"_quickGrammarActions"),
              @"grammar seven fields each have one Foundation owner without native duplicates");
        FYAnalysisResult *grammarResult=[FYAnalysisResult new];NSMutableString *grammarError=[@"grammar-copy" mutableCopy];cold.currentAnalysis=grammarResult;cold.analysisRequestGeneration=8;cold.followupRequestGeneration=3;cold.learningAnalysisBusy=YES;cold.grammarAnalysisError=grammarError;[grammarError appendString:@"changed"];
        Check(grammarCore.currentAnalysis==grammarResult&&grammarCore.analysisRequestGeneration==8&&grammarCore.followupRequestGeneration==3&&grammarCore.learningAnalysisBusy&&[grammarCore.grammarAnalysisError isEqual:@"grammar-copy"]&&grammarNative.currentAnalysis==grammarResult,
              @"Root/native grammar compatibility writes same original result/generations/busy/error copy owner");
        Check(!class_getInstanceVariable(FYGrammarInteractionCoordinator.class,"_receiver")&&!class_getInstanceVariable(FYGrammarInteractionCoordinator.class,"_host")&&!class_getInstanceVariable(FYGrammarInteractionCoordinator.class,"_learningCoordinator"),
              @"grammar business owner retains no idle receiver/Root or second learning service");
        cold.currentAnalysis=nil;cold.analysisRequestGeneration=0;cold.followupRequestGeneration=0;cold.learningAnalysisBusy=NO;cold.grammarAnalysisError=nil;
        FYInlineCardRenderer *nativeRenderer=nativeDisplay.cardRenderer;unsigned int nativeRendererCount=0;Ivar *nativeRendererIvars=class_copyIvarList(FYInlineCardRenderer.class,&nativeRendererCount);free(nativeRendererIvars);
        Check(nativeRenderer&&nativeRendererCount==0,
              @"cold native card renderer creates a stateless component without UI/cache/source or native resources");
        FYInlinePlacement *rendererPlacement=[FYInlinePlacement new];rendererPlacement.translationFrame=CGRectMake(1,2,30,40);rendererPlacement.labelFrame=CGRectMake(3,4,20,22);rendererPlacement.cornerRadius=7;
        InlinePanelLayout directRenderLayout=[nativeRenderer inlinePanelLayoutFromPlacement:rendererPlacement];InlinePanelLayout hostRenderLayout=[nativeDisplay inlinePanelLayoutFromPlacement:rendererPlacement];
        Check(CGRectEqualToRect(directRenderLayout.frame,hostRenderLayout.frame)&&CGRectEqualToRect(directRenderLayout.labelFrame,hostRenderLayout.labelFrame)&&directRenderLayout.cornerRadius==hostRenderLayout.cornerRadius,
              @"actual native compatibility uses sole renderer implementation for original raw layout mapping");
        Check(!class_getInstanceVariable(FYInlineCardRenderer.class,"_inlineLayoutEngine")&&
              !class_getInstanceVariable(FYInlineCardRenderer.class,"_fontProvider")&&
              !class_getInstanceVariable(FYInlineCardRenderer.class,"_layoutHeightCache"),
              @"card renderer adds no second engine/font/cache state; measurement ownership remains original");
        FYInlineOverflowController *overflowOwner=nativeDisplay.overflowController;
        Check(overflowOwner&&!overflowOwner.inlineOverflowPanel&&!overflowOwner.inlineOverflowChoicePanel&&
              !overflowOwner.inlineOverflowChoiceKeyMonitor&&!overflowOwner.inlineOverflowEntries&&!overflowOwner.inlineOverflowCount,
              @"cold overflow policy/native owner creates zero original state without UI/monitor or retained source");
        unsigned int overflowPolicyCount=0,overflowNativeCount=0;Ivar *overflowPolicyIvars=class_copyIvarList(FYInlineOverflowCoordinator.class,&overflowPolicyCount);Ivar *overflowNativeIvars=class_copyIvarList(FYInlineOverflowController.class,&overflowNativeCount);free(overflowPolicyIvars);free(overflowNativeIvars);
        Check(overflowPolicyCount==6&&overflowNativeCount==3&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineOverflowPanel")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineOverflowChoicePanel")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineOverflowChoiceKeyMonitor")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineOverflowEntries")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineOverflowCount")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineOverflowPanelCount")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineOverflowCandidateCount")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineOverflowCandidateFrames")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineOverflowEmptySince"),
              @"six policy fields and three native resources have sole owners without facade duplicate ivars");
        NSMutableArray *overflowAlias=[NSMutableArray arrayWithObject:@{}];cold.inlineOverflowEntries=overflowAlias;[overflowAlias addObject:@{}];cold.inlineOverflowCandidateCount=7;cold.inlineOverflowCandidateFrames=1;
        Check(overflowOwner.inlineOverflowEntries==overflowAlias&&nativeDisplay.inlineOverflowEntries==overflowAlias&&
              overflowOwner.inlineOverflowEntries.count==2&&overflowOwner.inlineOverflowCandidateCount==7&&overflowOwner.inlineOverflowCandidateFrames==1,
              @"host/native compatibility preserves original strong mutable entries alias and candidate state in sole policy");
        __weak NSObject *overflowPanelMarker;__weak NSObject *overflowChoiceMarker;__weak NSObject *overflowMonitorMarker;
        @autoreleasepool{NSObject *entryMarker=[NSObject new];NSObject *choiceMarker=[NSObject new];NSObject *monitorMarker=[NSObject new];overflowPanelMarker=entryMarker;overflowChoiceMarker=choiceMarker;overflowMonitorMarker=monitorMarker;cold.inlineOverflowPanel=(NSPanel *)entryMarker;cold.inlineOverflowChoicePanel=(NSPanel *)choiceMarker;cold.inlineOverflowChoiceKeyMonitor=monitorMarker;}
        @autoreleasepool{Check(overflowPanelMarker&&overflowChoiceMarker&&overflowMonitorMarker&&
              overflowOwner.inlineOverflowPanel==(NSPanel *)overflowPanelMarker&&overflowOwner.inlineOverflowChoicePanel==(NSPanel *)overflowChoiceMarker&&overflowOwner.inlineOverflowChoiceKeyMonitor==overflowMonitorMarker,
              @"three native overflow resources retain original strong leases after caller releases markers");cold.inlineOverflowPanel=nil;cold.inlineOverflowChoicePanel=nil;cold.inlineOverflowChoiceKeyMonitor=nil;}
        Check(!overflowPanelMarker&&!overflowChoiceMarker&&!overflowMonitorMarker,
              @"clearing sole overflow resource fields releases all leases without compatibility duplicates");
        cold.inlineOverflowEntries=nil;cold.inlineOverflowCandidateCount=0;cold.inlineOverflowCandidateFrames=0;
        FYInlineExpandedReadingController *expandedOwner=nativeDisplay.expandedReadingController;
        Check(expandedOwner&&!expandedOwner.inlineExpandedReadingPanel&&!expandedOwner.inlineExpandedReadingKeyMonitor&&
              !expandedOwner.inlineExpandedReadingBlockID&&!expandedOwner.inlineExpandedMissingFrames,
              @"cold expanded owner holds only zero original state and creates no UI or event monitor");
        unsigned int expandedCount=0;Ivar *expandedIvars=class_copyIvarList(FYInlineExpandedReadingController.class,&expandedCount);free(expandedIvars);
        Check(expandedCount==4&&!class_getInstanceVariable(FYInlineOverlayController.class,"_inlineExpandedReadingPanel")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineExpandedReadingKeyMonitor")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineExpandedReadingBlockID")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineExpandedMissingFrames"),
              @"four expanded lifecycle fields have single independent owner without duplicate native storage");
        NSMutableString *expandedID=[@"expanded-copy" mutableCopy];cold.inlineExpandedReadingBlockID=expandedID;[expandedID appendString:@"changed"];
        Check([expandedOwner.inlineExpandedReadingBlockID isEqual:@"expanded-copy"]&&
              [nativeDisplay.inlineExpandedReadingBlockID isEqual:@"expanded-copy"],
              @"host/native compatibility stores original copy identity in sole expanded owner");
        __weak NSObject *expandedPanelMarker;__weak NSObject *expandedMonitorMarker;
        @autoreleasepool{NSObject *panelMarker=[NSObject new];NSObject *monitorMarker=[NSObject new];expandedPanelMarker=panelMarker;expandedMonitorMarker=monitorMarker;cold.inlineExpandedReadingPanel=(NSPanel *)panelMarker;cold.inlineExpandedReadingKeyMonitor=monitorMarker;}
        @autoreleasepool{Check(expandedPanelMarker&&expandedMonitorMarker&&
              expandedOwner.inlineExpandedReadingPanel==(NSPanel *)expandedPanelMarker&&expandedOwner.inlineExpandedReadingKeyMonitor==expandedMonitorMarker,
              @"expanded facade keeps original strong panel/monitor leases after caller releases markers");cold.inlineExpandedReadingPanel=nil;cold.inlineExpandedReadingKeyMonitor=nil;}
        Check(!expandedPanelMarker&&!expandedMonitorMarker,
              @"clearing sole expanded resource fields releases leases with no facade duplicate references");
        cold.inlineExpandedReadingBlockID=nil;cold.inlineExpandedMissingFrames=0;
        FYInlineSelectionCoordinator *selection=nativeDisplay.selectionCoordinator;FYInlineCardActionBinder *cardBinder=nativeDisplay.cardActionBinder;
        unsigned int selectionCount=0,binderCount=0;Ivar *selectionIvars=class_copyIvarList(FYInlineSelectionCoordinator.class,&selectionCount);Ivar *binderIvars=class_copyIvarList(FYInlineCardActionBinder.class,&binderCount);free(selectionIvars);free(binderIvars);
        Check(selection&&cardBinder&&selectionCount==0&&binderCount==0,
              @"cold selection and native card binders create stateless components without idle source/current state or UI");
        FYInlineBlockSnapshot *currentSelection=[FYInlineBlockSnapshot new];currentSelection.blockID=@"synthetic-selection";currentSelection.sentenceID=@"linked-db";currentSelection.version=3;cold.inlineBlockSnapshot=currentSelection;
        Check(cold.studyPresentationController.inlineBlockSnapshot==currentSelection&&nativeDisplay.inlineBlockSnapshot==currentSelection&&
              cold.studyPresentationController.studyNavigationCoordinator.inlineBlockSnapshot==currentSelection&&
              !class_getInstanceVariable(FYStudyPresentationController.class,"_inlineBlockSnapshot")&&
              !class_getInstanceVariable(FYInlineOverlayController.class,"_inlineBlockSnapshot"),
              @"navigation is sole current snapshot owner while Study and native selection see exact same peer object");
        unsigned int snapshotCount=0;Ivar *snapshotIvars=class_copyIvarList(FYInlineBlockSnapshot.class,&snapshotCount);free(snapshotIvars);
        Check(snapshotCount==8&&[currentSelection.sentenceID isEqual:@"linked-db"]&&currentSelection.version==3,
              @"pure snapshot keeps original eight fields and later database identity/version binding");
        OCRTextItem *selectionItem=[OCRTextItem new];selectionItem.text=@"合成选择";selectionItem.boundingBox=CGRectMake(.1,.2,.3,.04);
        Check([[nativeDisplay inlineBlockIdentityForItem:selectionItem]isEqual:[selection inlineBlockIdentityForItem:selectionItem]],
              @"actual host/native consumers share canonical pure identity implementation");
        FYInlineCardPressState *coldPress=[FYInlineCardPressState new];
        Check(NSEqualPoints(coldPress.pressPoint,NSZeroPoint)&&!coldPress.collapsePressed&&
              !coldPress.pressMovedBeyondThreshold&&coldPress.titleBarHeight==0,
              @"production pure card press owner starts without native view/control/window or callback");
        Check(class_getInstanceVariable(FYInlineLongCardView.class,"_pressState")&&
              !class_getInstanceVariable(FYInlineLongCardView.class,"_pressPoint")&&
              !class_getInstanceVariable(FYInlineLongCardView.class,"_pressMovedBeyondThreshold")&&
              !class_getInstanceVariable(FYInlineLongCardView.class,"_collapsePressed")&&
              !class_getInstanceVariable(FYInlineLongCardView.class,"_titleBarHeight")&&
              class_getInstanceVariable(FYInlineCardPressState.class,"_titleBarHeight")&&
              class_conformsToProtocol(FYInlineLongCardView.class,@protocol(FYInlineCardPressNativeActions)),
              @"real host links native card to sole gesture state through explicit action contract without duplicate scalars");
        FYInlineLayoutEngine *coldEngine=[FYInlineLayoutEngine defaultEngine];
        Check(coldEngine.textMeasurer && !coldEngine.textMeasurer.fontProvider &&
              !coldEngine.textMeasurer.layoutHeightCache && [coldEngine conformsToProtocol:@protocol(FYInlineTextMeasurementState)],
              @"cold native measurement owner creates no font/style/cache or external work");
        Check(!class_getInstanceVariable(FYInlineLayoutEngine.class,"_fontProvider") &&
              !class_getInstanceVariable(FYInlineLayoutEngine.class,"_layoutHeightCache") &&
              class_getInstanceVariable(FYInlineTextMeasurer.class,"_fontProvider") &&
              class_getInstanceVariable(FYInlineTextMeasurer.class,"_layoutHeightCache"),
              @"measurer alone owns original font provider and round height cache");
        FYInlineLayoutCalculator *coldCalculator=[FYInlineLayoutCalculator defaultCalculator];
        Check([coldEngine isKindOfClass:FYInlineLayoutCalculator.class] &&
              class_getInstanceVariable(FYInlineLayoutCalculator.class,"_revision") &&
              class_getInstanceVariable(FYInlineLayoutCalculator.class,"_shortFontSize") &&
              !class_getInstanceVariable(FYInlineLayoutCalculator.class,"_layoutHeightCache") &&
              !class_getInstanceVariable(FYInlineLayoutCalculator.class,"_textMeasurer"),
              @"calculator alone owns configuration/revision, native facade inherits actual receiver without native storage in core");
        unsigned int layoutIvarCount=0;Ivar *layoutIvars=class_copyIvarList(FYInlineLayoutEngine.class,&layoutIvarCount);free(layoutIvars);
        Check(layoutIvarCount==1 && class_getInstanceVariable(FYInlineLayoutEngine.class,"_textMeasurer"),
              @"native facade has only measurer owner and no duplicate calculation state");
        BOOL sameDefaults=YES;
        for(NSString *key in @[@"shortFontSize",@"coverFontSize",@"longBodyFontSize",@"longTitleFontSize",@"longLineSpacing",@"minimumBodyLines",@"cardMaxWidth",@"cardWidthFraction",@"cardWideFraction",@"cardMaxHeight",@"cardHeightFraction",@"minimumLongBodyFontSize",@"minimumCardWidth",@"viewportMargin",@"panelGap",@"compactEntryHeight",@"compactEntryTitle",@"compactEntryFontSize",@"compactEntryHorizontalPadding",@"foldedEntryFallbackTitle",@"foldedEntryHintTooLong",@"foldedEntryHintCrowded",@"stabilityTolerance",@"shortWidthFraction",@"shortMaxWidth"]) {
            if(![[coldEngine valueForKey:key]isEqual:[coldCalculator valueForKey:key]])sameDefaults=NO;
        }
        Check(sameDefaults,@"pure and native factories use the same complete original default configuration");
        coldEngine.panelGap=7;
        Check(((FYInlineLayoutCalculator *)coldEngine).panelGap==7&&coldCalculator.panelGap==4,
              @"native compatibility configuration writes sole inherited state and independent calculators keep separate state");
        coldEngine.panelGap=4;
        __block NSUInteger nativeFontCalls=0;
        coldEngine.fontProvider=^NSFont *(CGFloat size,NSFontWeight weight){nativeFontCalls++;return [NSFont systemFontOfSize:size weight:weight];};
        Check(coldEngine.fontProvider==coldEngine.textMeasurer.fontProvider && !nativeFontCalls,
              @"legacy font-provider setter stores same copied closure without invoking native factory");
        NSMutableDictionary *heightAlias=[NSMutableDictionary new];coldEngine.textMeasurer.layoutHeightCache=heightAlias;
        Check(coldEngine.layoutHeightCache==heightAlias,@"engine cache compatibility getter reads sole native owner and retains mutable alias");
        coldEngine.textMeasurer.fontProvider=nil;coldEngine.textMeasurer.layoutHeightCache=nil;
        Check(!coldEngine.fontProvider&&!coldEngine.layoutHeightCache&&!nativeFontCalls,
              @"clearing sole measurement owner is reflected by legacy API without font work");
        for (NSString *name in @[@"captureMappingCache", @"autoLocateSchedule", @"mappingValidationSchedule"]) {
            Check(!class_getInstanceVariable(FYCaptureRuntimeController.class, [@"_" stringByAppendingString:name].UTF8String),
                  @"mapping compatibility accessors do not synthesize duplicate owner storage");
        }
        NSMutableDictionary *mappingAlias=[NSMutableDictionary new];cold.captureCardVideoRects=mappingAlias;
        Check(capture.mappingCoordinator.captureMappingCache.entries==mappingAlias && cold.captureCardVideoRects==mappingAlias,
              @"concrete host mutable mapping alias reaches the sole coordinator cache");
        NSDate *mappingDate=NSDate.date;cold.lastAutoLocateAttempt=mappingDate;cold.lastMappingValidationDate=mappingDate;
        Check(capture.mappingCoordinator.autoLocateSchedule.lastAttemptDate==mappingDate &&
              capture.mappingCoordinator.mappingValidationSchedule.lastValidationDate==mappingDate,
              @"host date setters write directly to the sole locate and validation owners");
        capture.captureMappingCache=nil;
        Check(!capture.mappingCoordinator.captureMappingCache && [capture mappingCache]!=nil && cold.captureCardVideoRects==nil,
              @"nil raw mapping owner preserves lazy recreation and leaves old external alias untouched");
        Check(runtime.ocrWorker && !class_getInstanceVariable(FYOCRRecognitionWorker.class, "_host"),
              @"cold worker is stateless and retains no idle native receiver");
        FYOCRManager *engineFacade = [FYOCRManager new];
        Check(engineFacade.visionEngine && !engineFacade.configurationObserver &&
              !class_getInstanceVariable(FYOCRManager.class, "_configurationObserver"),
              @"cold Vision engine creates no request and facade has no duplicate observer storage");
        __block NSUInteger configured = 0;
        engineFacade.configurationObserver = ^(BOOL fast, NSInteger language, size_t width, size_t height, CGFloat minimum) { configured++; };
        Check(engineFacade.visionEngine.configurationObserver == engineFacade.configurationObserver && configured == 0,
              @"configuration callback belongs only to Vision engine and is not called by construction");
        engineFacade.visionEngine.configurationObserver = nil;
        Check(engineFacade.configurationObserver == nil, @"compatibility observer reads the sole engine owner");
        Check(!class_getInstanceVariable(FYTranslationRuntimeController.class, "_ocrRefinementContext") &&
              !class_getInstanceVariable(FYTranslationRuntimeController.class, "_ocrRefinementStabilizer"),
              @"runtime has no duplicate refinement context or worker state");
        for (NSString *name in @[@"running", @"timer", @"inFlight", @"ocrGeometryGeneration", @"ocrDisplayTargetWindowID", @"lastOCRedCaptureFrameIndex"]) {
            Check(!class_getInstanceVariable(FYTranslationRuntimeController.class, [@"_" stringByAppendingString:name].UTF8String),
                  @"runtime compatibility fields have no duplicate recognition state");
        }
        Check(!class_getInstanceVariable(FYCaptureRuntimeController.class, "_lastOCRedCaptureFrameIndex"),
              @"capture facade no longer owns OCR frame consumption state");
        Check(!cold.mainWindow && !cold.captionPanel && !cold.regionSelectionPanel && !cold.captureCalibrationPanel,
              @"runtime construction creates no windows");
        Check(class_getInstanceVariable(FYCaptureRuntimeController.class, "_captureCardInput") &&
              !object_getIvar(capture, class_getInstanceVariable(FYCaptureRuntimeController.class, "_captureCardInput")),
              @"cold construction does not even create an input device session");
        Check(cold.captureQueue == capture.captureQueue && cold.previewQueue == capture.previewQueue &&
              cold.captureQueue && cold.previewQueue && cold.captureQueue != cold.previewQueue,
              @"capture and preview retain separate serial queues, with preview owned by its scheduler");
        Check(cold.previewQueue == capture.previewScheduler.queue && capture.previewScheduler.source == capture,
              @"preview scheduler owns its queue and uses a weak typed capture adapter");
        for (NSString *name in @[@"previewTimer", @"previewQueue", @"previewInFlight", @"previewRequestSerial",
            @"previewRenderSerial", @"lastPreviewCaptureFrameIndex", @"lastPreviewDate"]) {
            Check(!class_getInstanceVariable(FYCaptureRuntimeController.class, [@"_" stringByAppendingString:name].UTF8String),
                  @"capture adapter compatibility properties do not duplicate scheduler storage");
        }
        Check(capture.displayTargetTracker && !capture.displayTargetTracker.displayTargetResolved && !capture.displayTargetTracker.geometryGeneration,
              @"cold target tracker is the single idle geometry owner");
        for (NSString *name in @[@"displayTargetResolved", @"displayTargetAmbiguous", @"resolvedDisplayTargetID", @"lastDisplayTargetProbeDate",
            @"lastWindowRecoveryAttemptDate", @"geometryGeneration", @"lastDisplayGeometryToken"]) {
            Check(!class_getInstanceVariable(FYCaptureRuntimeController.class, [@"_" stringByAppendingString:name].UTF8String),
                  @"capture target compatibility accessors do not duplicate tracker storage");
        }
        cold.geometryGeneration = 71; cold.displayTargetResolved = YES; cold.resolvedDisplayTargetID = 83;
        cold.lastDisplayGeometryToken = @"synthetic geometry";
        Check(capture.displayTargetTracker.geometryGeneration == 71 && capture.displayTargetTracker.displayTargetResolved &&
              capture.displayTargetTracker.resolvedDisplayTargetID == 83 && [capture.displayTargetTracker.lastDisplayGeometryToken isEqual:@"synthetic geometry"],
              @"host target properties write the same tracker through capture facade");
        capture.displayTargetTracker.geometryGeneration = 0; capture.displayTargetTracker.displayTargetResolved = NO;
        capture.displayTargetTracker.resolvedDisplayTargetID = 0; capture.displayTargetTracker.lastDisplayGeometryToken = nil;
        Check(runtime.contentState && !runtime.contentState.operations && !runtime.contentState.items &&
              [runtime conformsToProtocol:@protocol(FYInlinePlacementDeliverySource)],
              @"cold content owner and delivery adapter need no UI or resource activity");
        for (NSString *name in @[@"contentTranslationRevision", @"contentTranslationOperations", @"contentTranslationText",
            @"contentTranslationMode", @"contentTranslationUIItems", @"contentTranslationGeometryGeneration", @"contentTranslationDisplayTarget"]) {
            Check(!class_getInstanceVariable(FYTranslationRuntimeController.class, [@"_" stringByAppendingString:name].UTF8String),
                  @"translation adapter does not duplicate content-owner storage");
        }
        Check(runtime.inlineCoordinator && runtime.requestCoordinator && !runtime.requestCoordinator.realtimeTaskOwner &&
              !runtime.inlineCoordinator.pendingLongBatch && runtime.inlineCoordinator.serial == 0,
              @"cold request/cache coordinators have no task or pending work");
        for (NSString *name in @[@"inlineCacheOwner", @"inlineTranslationSerial", @"pendingInlineLongBatch", @"dialogueTranslationCache", @"translationTaskOwner"]) {
            Check(!class_getInstanceVariable(FYTranslationRuntimeController.class, [@"_" stringByAppendingString:name].UTF8String),
                  @"runtime facade does not duplicate request/cache coordinator state");
        }
        Check([cold conformsToProtocol:@protocol(FYTranslationRuntimeControllerHost)] &&
              [cold conformsToProtocol:@protocol(FYCaptureRuntimeControllerHost)], @"host exposes both explicit runtime contracts");
    }
    Check(!released && !runtime.host && !capture.host, @"idle runtime components do not retain the host");
    unsigned int propertyCount = 0;
    objc_property_t *properties = class_copyPropertyList(AppDelegate.class, &propertyCount);
    NSUInteger delegated = 0;
    BOOL noDuplicateStorage = YES;
    for (unsigned int i = 0; i < propertyCount; i++) {
        const char *attributes = property_getAttributes(properties[i]);
        if (!strstr(attributes, ",D")) { continue; }
        delegated++;
        NSString *ivar = [@"_" stringByAppendingString:@(property_getName(properties[i]))];
        if (class_getInstanceVariable(AppDelegate.class, ivar.UTF8String)) { noDuplicateStorage = NO; }
    }
    free(properties);
    Check(delegated > 0 && noDuplicateStorage, @"category compatibility properties never synthesize duplicate host storage");
    for (NSString *ivar in @[@"_running", @"_timer", @"_inFlight", @"_translationGeneration", @"_contentTranslationRevision",
        @"_pendingInlineLongBatch", @"_translationTaskOwner", @"_inlineFrameStabilizer", @"_captureQueue", @"_previewQueue",
        @"_previewInFlight", @"_captureCardInput", @"_geometryGeneration", @"_windowManager"]) {
        Check(class_getInstanceVariable(AppDelegate.class, ivar.UTF8String) == NULL, @"host facade has no duplicate runtime storage");
    }
    RuntimeHostProbe *app = [RuntimeHostProbe new];
    RuntimeTaskProbe *network = [RuntimeTaskProbe new], *service = [RuntimeTaskProbe new];
    app.translationTaskOwner = [FYTranslationTaskOwner new]; app.translationTaskOwner.activeTask = (id)network;
    app.serviceTestTaskOwner = [FYTranslationTaskOwner new]; app.serviceTestTaskOwner.activeTask = (id)service;
    app.inFlight = YES; app.previewInFlight = YES;
    app.ocrGeometryGeneration = 4; app.ocrDisplayTargetWindowID = 71;
    FYOCRRefinementStabilizer *refinement = [FYOCRRefinementStabilizer new];
    app.ocrRefinementContext = @{@"synthetic compatibility": @1}; app.ocrRefinementStabilizer = refinement;
    Check([app.translationRuntimeController.refinementSession.legacyContext isEqual:app.ocrRefinementContext] &&
          app.translationRuntimeController.refinementSession.stabilizer == refinement,
          @"native compatibility refinement properties resolve to the sole context owner");
    app.translationRuntimeController.refinementSession.stabilizer = nil;
    Check(app.ocrRefinementStabilizer == nil && app.ocrRefinementContext.count == 1,
          @"separate legacy nil assignments keep context identity without introducing new reset behavior");
    app.lastOCRedCaptureFrameIndex = 37;
    Check(app.translationRuntimeController.recognitionScheduler.inFlight &&
          app.translationRuntimeController.recognitionScheduler.geometryGeneration == 4 &&
          app.translationRuntimeController.recognitionScheduler.displayTargetWindowID == 71 &&
          app.captureRuntimeController.lastOCRedCaptureFrameIndex == 37,
          @"native metadata and OCR slot resolve to the sole recognition owner");
    app.captureRuntimeController.lastOCRedCaptureFrameIndex = 38;
    Check(app.lastOCRedCaptureFrameIndex == 38 && ![app.translationRuntimeController.recognitionScheduler needsCaptureFrame:38],
          @"capture compatibility writes share the production recognition-frame predicate");
    NSUInteger first = [app.translationRuntimeController beginContentTranslation:@"猫です。" mode:ContentModeDialogue];
    Check(app.invalidations == 1 && network.cancelCalls == 1 && service.cancelCalls == 0,
          @"direct runtime entry preserves the host override and cancels only translation work");
    Check(app.contentTranslationOperations == 1 && app.contentTranslationRevision == first &&
          [app.translationRuntimeController.contentTranslationText isEqual:@"猫です。"], @"new content has one lease and one state source");
    Check(app.contentTranslationGeometryGeneration == 4 && app.contentTranslationDisplayTarget == 71,
          @"content lease retains the submitting OCR geometry and target");
    Check(app.clockSnapshot.operations == 1 && [app.clockSnapshot.text isEqual:@"猫です。"] &&
          app.clockSnapshot.geometryGeneration == 0 && app.clockSnapshot.displayTarget == 0,
          @"host clock override keeps the original content-before-clock-before-geometry order");
    FYContentTranslationState *content = app.translationRuntimeController.contentState;
    Check(content.revision == first && content.operations == 1 && content.geometryGeneration == 4 && content.displayTarget == 71,
          @"content compatibility reads resolve to the single domain owner");
    OCRTextItem *left = [OCRTextItem new], *right = [OCRTextItem new];
    left.text = @"合成左字段"; right.text = @"合成右字段";
    left.boundingBox = CGRectMake(.1,.2,.3,.1); right.boundingBox = CGRectMake(.5,.2,.3,.1);
    app.contentTranslationUIItems = @[left, right];
    Check(content.items == app.contentTranslationUIItems && [app pendingInlineMatchesItems:@[left, right]] &&
          ![app pendingInlineMatchesItems:@[right, left]],
          @"production OCR observations use original cache keys and ordered identity in the content owner");
    Check(app.inFlight && app.previewInFlight, @"network invalidation does not release capture or preview slots");
    NSUInteger second = [app beginContentTranslation:@"犬です。" mode:ContentModeDialogue];
    [app finishContentTranslation:first];
    Check(second > first && app.contentTranslationOperations == 1, @"an older completion cannot release the new content lease");
    [app finishContentTranslation:second];
    Check(app.contentTranslationOperations == 0, @"current content completion releases its own lease");
    app.captureRuntimeController.previewRequestSerial = 12;
    app.previewRenderSerial = 20; app.lastPreviewCaptureFrameIndex = 99;
    NSInteger generation = app.translationGeneration;
    [app advanceTranslationGeneration];
    Check(app.translationGeneration == generation + 1 && app.previewRequestSerial == 13 && app.previewRenderSerial == 21 &&
          app.lastPreviewCaptureFrameIndex == 0, @"generation changes invalidate preview work across the sole scheduler owner");
    Check(app.captureRuntimeController.previewScheduler.requestSerial == 13 &&
          app.captureRuntimeController.previewScheduler.renderSerial == 21 &&
          app.captureRuntimeController.previewScheduler.inFlight, @"compatibility writes and invalidation share scheduler state and preserve its busy slot");
    Check(service.cancelCalls == 0 && app.serviceTestTaskOwner.activeTask == (id)service,
          @"run generation changes leave service testing independent");
    app.inlineTranslationCache[@"synthetic-cache"] = @"合成译文";
    Check(app.translationRuntimeController.inlineCacheOwner.entries == app.inlineTranslationCache &&
          [app.inlineTranslationCache[@"synthetic-cache"] isEqual:@"合成译文"], @"compatibility cache access resolves to its sole canonical owner");
    FYContentRouter *router = app.contentRouter;
    Check([router isKindOfClass:FYContentPolicy.class] &&
          [FYContentRouter respondsToSelector:@selector(dialogueRouteForItems:optionsCanPasteInline:filterObserver:)] &&
          [FYContentRouter respondsToSelector:@selector(modeDecisionForItems:fallback:)],
          @"router preserves inherited stateless route/classifier API beside its separate state owner");
    Check(router.modeCoordinator && router.modeCoordinator.stability == router.modeStability &&
          !class_getInstanceVariable(FYContentRouter.class, "_modeStability") &&
          !class_getInstanceVariable(FYContentRouter.class, "_lastModeDecision"),
          @"router facade has no duplicate mode state or decision storage");
    app.detectedModeSegment = ContentModeUI;
    Check(app.translationRuntimeController.contentRouter == router && router.modeStability.detectedMode == ContentModeUI,
          @"mode compatibility properties use the production router state");
    Check(router.modeCoordinator.stability.detectedMode == app.detectedModeSegment,
          @"native mode compatibility resolves to the sole coordinator-owned evidence");
    app.running = YES;
    [app stop];
    Check(!app.running && !app.inFlight && !app.timer && !app.previewTimer && app.contentTranslationOperations == 0 &&
          !app.pendingInlineLongBatch && app.inlineTranslationCache.count == 0,
          @"stop cleans the run lease, polling and inline cache using the original pipeline");
    Check(service.cancelCalls == 0, @"stop does not cancel the service-test task");
    Check(app.translationRuntimeController.requestCoordinator.realtimeTaskOwner == app.translationTaskOwner &&
          app.translationRuntimeController.inlineCoordinator.cache == app.inlineCacheOwner &&
          app.translationRuntimeController.inlineCoordinator.serial == app.inlineTranslationSerial &&
          !app.translationRuntimeController.inlineCoordinator.pendingLongBatch,
          @"native invalidation and stop resolve to the sole request/cache owners");

    // Moving the method must preserve its original strong host capture while
    // a reply is outstanding, as well as the device observer's weak capture.
    __weak AppDelegate *pendingHost;
    __block NSUInteger replies = 0;
    @autoreleasepool {
        RuntimeReplyProbe *pending = [RuntimeReplyProbe new]; pendingHost = pending;
        [pending translateDialogueText:@"猫です。" identity:nil systemPrompt:@"synthetic"
            completion:^(NSString *value, NSError *error) { replies++; }];
    }
    Check(pendingHost && heldReply, @"pending dialogue reply retains the original host receiver");
    heldReply(@"是猫。", nil); heldReply = nil;
    Check(replies == 1 && !pendingHost, @"completing and releasing the reply releases the host");

    __weak AppDelegate *longHost;
    __block NSUInteger longReplies = 0;
    @autoreleasepool {
        RuntimeInlineReplyProbe *pending = [RuntimeInlineReplyProbe new]; longHost = pending;
        OCRTextItem *item = [OCRTextItem new]; item.text = @"合成长正文"; item.blockKind = InlineBlockKindLong;
        [pending translateInlineLongItems:@[item] indexes:@[@0] keys:@[@"L:synthetic"] translations:[@[@""] mutableCopy]
            completion:^(NSError *error) { Check(!error, @"original inline receiver completion remains successful"); longReplies++; }];
    }
    Check(longHost != nil && heldInlineReply != nil, @"queued long-batch transport lease retains the original native receiver");
    heldInlineValues[0] = @"合成长译文"; heldInlineReply(nil); heldInlineReply = nil; heldInlineValues = nil;
    Wait(^BOOL { return longHost == nil; });
    Check(longReplies == 1, @"finished long batch releases receiver and delivers once");

    __weak AppDelegate *previewHost;
    FYLivePreviewScheduler *previewScheduler;
    dispatch_semaphore_t release;
    @autoreleasepool {
        RuntimePreviewProbe *pending = [RuntimePreviewProbe new]; previewHost = pending;
        pending.running = YES; pending.framePreview = (id)[NSObject new];
        pending.captureEntered = dispatch_semaphore_create(0);
        pending.captureRelease = dispatch_semaphore_create(0); release = pending.captureRelease;
        previewScheduler = pending.captureRuntimeController.previewScheduler;
        [pending previewTimerFired:nil];
        __block BOOL entered = NO;
        Wait(^BOOL {
            if (!entered) { entered = dispatch_semaphore_wait(pending.captureEntered, DISPATCH_TIME_NOW) == 0; }
            return entered;
        });
    }
    Check(previewHost != nil && previewScheduler.inFlight, @"queued preview frame lease retains original host across extraction");
    dispatch_semaphore_signal(release);
    Wait(^BOOL { return !previewScheduler.inFlight; });
    Wait(^BOOL { return previewHost == nil; });
    Check(!previewScheduler.source, @"completed preview releases host and its weak capture adapter");

    __weak AppDelegate *ocrHost;
    FYRecognitionCycleScheduler *recognitionScheduler;
    @autoreleasepool {
        RuntimeOCRProbe *pending = [RuntimeOCRProbe new]; ocrHost = pending;
        pending.running = YES; pending.lastDiagnosticCheckDate = NSDate.date;
        pending.captureEntered = dispatch_semaphore_create(0);
        pending.captureRelease = dispatch_semaphore_create(0); release = pending.captureRelease;
        recognitionScheduler = pending.translationRuntimeController.recognitionScheduler;
        [pending timerFired:nil];
        __block BOOL entered = NO;
        Wait(^BOOL {
            if (!entered) entered = dispatch_semaphore_wait(pending.captureEntered, DISPATCH_TIME_NOW) == 0;
            return entered;
        });
        pending.translationGeneration++;
    }
    Check(ocrHost && recognitionScheduler.inFlight, @"production queued recognition cycle retains its original receiver");
    dispatch_semaphore_signal(release);
    Wait(^BOOL { return ocrHost == nil; });
    Check(recognitionScheduler.inFlight && !recognitionScheduler.timer,
          @"stale capture releases its host lease and preserves a newer generation's slot");
    [recognitionScheduler finishCurrentCycle];

    __weak AppDelegate *observedHost;
    FYCaptureCardInput *input;
    @autoreleasepool {
        AppDelegate *observed = [AppDelegate new]; observedHost = observed;
        input = observed.captureCardInput;
    }
    Check(!observedHost && input.stateChangeHandler, @"device observation keeps the original weak host lifetime");
    unsigned int captureIvarCount=0; Ivar *captureIvars=class_copyIvarList(FYCaptureCardInput.class,&captureIvarCount);free(captureIvars);
    Check(captureIvarCount==0 && [input isKindOfClass:FYCaptureSessionController.class],
          @"native input facade inherits the original receiver without duplicate session state");
    Check(class_getInstanceVariable(FYCaptureSessionController.class,"_sessionQueue") &&
          class_getInstanceVariable(FYCaptureSessionController.class,"_frameQueue") &&
          class_getInstanceVariable(FYCaptureSessionController.class,"_slot"),
          @"single session controller owns both native queues and the independent frame slot");
    input.stateChangeHandler();
    __weak AppDelegate *mappingHost;
    FYCaptureMappingCoordinator *mappingCore;
    NSMutableArray *mappingEvents=[NSMutableArray new];
    @autoreleasepool {
        mappingExternalHost=[RuntimeMappingProbe new];mappingHost=mappingExternalHost;
        ((RuntimeMappingProbe *)mappingExternalHost).mappingEvents=mappingEvents;
        ((RuntimeMappingProbe *)mappingExternalHost).duringMappingBuild=^{mappingExternalHost=nil;};
        capture=mappingExternalHost.captureRuntimeController;mappingCore=capture.mappingCoordinator;
        WindowItem *window=[WindowItem new];window.windowID=7;
        Check([capture autoDetectCaptureCardVideoRectForWindow:window reason:NULL],
              @"production adapter completes canonical locate after caller releases host during native build");
        Check([mappingEvents isEqual:@[@"frame",@"build",@"fit",@"store",@"reset"]] &&
              [[mappingCore mappingCache]entryForWindowID:7] && ![mappingCore locateSchedule].lastAttemptDate,
              @"scoped strong native lease preserves concrete receiver overrides and single state through completion");
    }
    Check(!mappingHost && !capture.host && [[mappingCore mappingCache]entryForWindowID:7],
          @"operation completion releases host while independent mapping state stays usable");
    printf("PASS RuntimeOwnershipTests: %lu checks; cold/weak ownership, separate slots, host overrides, leases, service isolation and stop\n", (unsigned long)checks);
} return 0; }
