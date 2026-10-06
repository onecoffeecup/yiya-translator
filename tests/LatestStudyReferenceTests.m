#import "LearningAppTestSupport.h"

// Exercise the real asynchronous capture/reference path without screen access,
// the user's database, or network requests. A pixel identifies the clicked frame.
@interface LatestStudyReferenceApp : AppDelegate
@property(nonatomic) unsigned char frameNumber;
@property(nonatomic) NSUInteger captures;
@property(nonatomic) BOOL failCapture;
@property(nonatomic,strong) dispatch_semaphore_t recognitionGate;
@end
@implementation LatestStudyReferenceApp
- (uint32_t)selectedWindowID { return 42; }
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID {
    self.captures++;
    if(self.failCapture){return nil;}
    unsigned char pixel[]={self.frameNumber,0,0,255};
    CFDataRef data=CFDataCreate(NULL,pixel,4);
    CGDataProviderRef provider=CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGImageRef image=CGImageCreate(1,1,8,32,4,space,(CGBitmapInfo)kCGImageAlphaLast,provider,NULL,NO,kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);CGDataProviderRelease(provider);CFRelease(data);
    return image;
}
- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)language error:(NSError **)error {
    Require(!fastOCR,@"explicit reference uses accurate local recognition");
    CFDataRef data=CGDataProviderCopyData(CGImageGetDataProvider(image));
    unsigned char frame=CFDataGetBytePtr(data)[0];CFRelease(data);
    if(self.recognitionGate){dispatch_semaphore_wait(self.recognitionGate,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC));}
    if(frame==0){return @[];}
    OCRTextItem *item=[OCRTextItem new];
    item.text=frame==2?@"今日は一緒に帰りましょう。":@"明日は図書館で会いましょう。";
    if(frame==4){item.text=@"花椿\nこの子、宇賀神みよちゃん。\nね？";}
    if(frame==5){item.text=@"花椿\nこの子、宇賀神みよちゃんじゃない。\nね？";}
    if(frame==6){item.text=@"花椿\nね？";}
    item.boundingBox=CGRectMake(0.2,0.12,0.65,0.05);
    return @[item];
}
@end

int main(void){@autoreleasepool{
    [NSApplication sharedApplication];
    FYLearningStore *store=Store([NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite"]]);
    FYGrammarCatalog *catalog=[FYGrammarCatalog new];
    LatestStudyReferenceApp *app=[LatestStudyReferenceApp new];
    app.learningStore=store;
    app.learningCoordinator=[[FYLearningCoordinator alloc] initWithStore:store analyzer:Analyzer(catalog) tokenizer:[FYJapaneseTokenizer new] catalog:catalog];
    [app createMainWindow];
    app.detectedModeSegment = ContentModeDialogue;
    FYRequestIdentity *old=[app.learningCoordinator recordText:@"前の台詞を話しています。" kind:FYSentenceKindDialogue];
    [app.learningCoordinator setTranslation:@"上一句译文。" forIdentity:old];[app.learningCoordinator pinCurrent];Drain(store);
    app.running=YES;app.inFlight=YES;app.frameNumber=2;
    NSTextView *draft=[app.mainStudyChatView valueForKey:@"input"];
    draft.string=@"这句话什么意思？";
    app.recognitionGate=dispatch_semaphore_create(0);
    [app referenceLatestStudySentence:nil];
    Require(app.chatResolvingSource && !app.studyChatSession.source.length,@"previous context is cleared while fresh OCR is pending");
    Require([draft.string isEqualToString:@"这句话什么意思？"],@"recognition busy state preserves the user's draft");
    app.frameNumber=3;dispatch_semaphore_signal(app.recognitionGate);
    Pump(^BOOL{return !app.chatResolvingSource;});
    Require([app.studyChatSession.source isEqualToString:@"今日は一緒に帰りましょう。"],@"reference uses the clicked frame even when regular translation is in flight and the game advances");
    Require(!app.studyChatSession.translation.length,@"new source never carries the previous sentence translation");
    Require([draft.string isEqualToString:@"这句话什么意思？"],@"finishing recognition cannot clear the user's draft");
    Require([app.learningCoordinator.currentSentenceID isEqualToString:old.sentenceID] && [app.learningCoordinator.latestSentenceID isEqualToString:old.sentenceID],@"on-demand reference preserves the pinned reader and recorded history");
    app.recognitionGate=nil;
    FYRequestIdentity *latest=[app.learningCoordinator recordText:@"明日は図書館で会いましょう。" kind:FYSentenceKindDialogue];
    [app.learningCoordinator setTranslation:@"明天在图书馆见吧。" forIdentity:latest];Drain(store);
    [app referenceLatestStudySentence:nil];Pump(^BOOL{return !app.chatResolvingSource;});
    Require([app.studyChatSession.translation isEqualToString:@"明天在图书馆见吧。"],@"already translated matching source keeps its own translation");
    app.frameNumber=0;
    [app referenceLatestStudySentence:nil];Pump(^BOOL{return !app.chatResolvingSource;});
    Require(!app.studyChatSession.source.length,@"empty frame cannot silently fall back to previous dialogue");
    app.failCapture=YES;[app referenceLatestStudySentence:nil];
    Require(!app.chatResolvingSource && !app.studyChatSession.source.length,@"failed capture recovers without quoting an old sentence");
    app.failCapture=NO;app.frameNumber=2;app.recognitionGate=dispatch_semaphore_create(0);
    [app referenceLatestStudySentence:nil];
    app.quickSentenceSource=@"別の質問で選んだ句です。";app.quickSentenceTranslation=@"另一个明确选择的句子。";
    [app askQuickSentence:nil];dispatch_semaphore_signal(app.recognitionGate);Tick();Tick();
    Require([app.studyChatSession.source isEqualToString:app.quickSentenceSource] && !app.chatResolvingSource,@"late recognition cannot replace a later explicit quick-sentence selection");
    app.recognitionGate=nil;
    latest=[app.learningCoordinator recordText:@"花椿\nなんだ、お初か。\nこの子、宇賀神みよちゃん。\nね？" kind:FYSentenceKindDialogue];
    [app.learningCoordinator setTranslation:@"什么嘛，是小初啊。\n这孩子，是宇贺神美代。\n对吧？" forIdentity:latest];Drain(store);
    app.frameNumber=4;
    [app referenceLatestStudySentence:nil];Pump(^BOOL{return !app.chatResolvingSource;});
    Require([app.studyChatSession.source isEqualToString:latest.sourceText] && [app.studyChatSession.translation containsString:@"小初"],@"fresh OCR with an anchored missing first body line reuses the complete source and matching translation");
    app.frameNumber=5;
    [app referenceLatestStudySentence:nil];Pump(^BOOL{return !app.chatResolvingSource;});
    Require([app.studyChatSession.source containsString:@"じゃない"] && !app.studyChatSession.translation.length,@"a genuine negation in the same speaker's fresh line never inherits the previous source or translation");
    app.frameNumber=6;
    [app referenceLatestStudySentence:nil];Pump(^BOOL{return !app.chatResolvingSource;});
    Require(![app.studyChatSession.source containsString:@"お初"] && !app.studyChatSession.translation.length,@"a speaker and generic short tail are insufficient to reconstruct the previous line");
    app.running=NO;app.recognitionGate=nil;
    NSUInteger captures=app.captures;
    [app referenceLatestStudySentence:nil];Pump(^BOOL{return !app.chatResolvingSource;});
    Require(app.captures==captures && [app.studyChatSession.source isEqualToString:latest.sourceText],@"paused capture references the latest stored sentence independently of the pinned reader");
    [app.mainWindow orderOut:nil];
    NSLog(@"PASS: current-frame reference, pending translation, click snapshot, pinned reader, matching translation, failures, stale OCR and paused history");
}return 0;}
