#pragma once
#import <AppKit/AppKit.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface PageTextFact : NSObject
@property(nonatomic) BOOL trackingSelection;
@property(nonatomic,copy) void (^willBeginSelection)(void);
@property(nonatomic,copy) void (^didFinishSelection)(void);
@property(nonatomic,copy) void (^didClickAtCharacterIndex)(NSUInteger);
@end
@implementation PageTextFact @end
@interface PageFieldFact : NSObject
@property(nonatomic,copy) NSString *stringValue;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@end
@implementation PageFieldFact
@synthesize stringValue=_stringValue;
- (void)setStringValue:(NSString *)value{_stringValue=[value copy];if(self.trace)[self.trace addObject:self.name];}
@end
@interface PageSelectionPeer : NSObject
@property(nonatomic,strong) PageTextFact *text;
@property(nonatomic,strong) PageFieldFact *lemma,*reading,*meaning;
@property(nonatomic) BOOL ai;
@property(nonatomic) NSInteger generation;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic) NSUInteger freezes,updates,clicks,lastIndex;
@property(nonatomic) BOOL updateObservedReset,updateWasMainThread;
- (void)freezeLearningSentenceForSelection;
- (void)updateWordPickForSelection;
- (void)selectWordAtCharacterIndex:(NSUInteger)index;
@end
@implementation PageSelectionPeer
- (instancetype)init{if((self=[super init])){self.trace=[NSMutableArray new];self.text=[PageTextFact new];self.lemma=[PageFieldFact new];self.reading=[PageFieldFact new];self.meaning=[PageFieldFact new];NSUInteger i=0;for(PageFieldFact *field in @[self.lemma,self.reading,self.meaning]){field.stringValue=@"initial";field.name=@[@"lemma",@"reading",@"meaning"][i++];field.trace=self.trace;}self.generation=11;self.ai=YES;}return self;}
- (void)freezeLearningSentenceForSelection{self.freezes++;}
- (void)updateWordPickForSelection{self.updates++;self.updateWasMainThread=NSThread.isMainThread;self.updateObservedReset=!self.ai&&self.generation>=12&&!self.lemma.stringValue.length&&!self.reading.stringValue.length&&!self.meaning.stringValue.length;[self.trace addObject:@"update"];}
- (void)selectWordAtCharacterIndex:(NSUInteger)index{self.clicks++;self.lastIndex=index;}
@end
@protocol PageSelectionFixture <NSObject>
@property(nonatomic,strong) FYSelectableSourceTextView *learningSourceTextView;
@property(nonatomic) BOOL vocabCompletionFromAI;
@property(nonatomic) NSInteger vocabSelectionGeneration;
- (id)testWireLiveSelection;
@end
static void PostSelection(id object){[[NSNotificationCenter defaultCenter]postNotificationName:NSTextViewDidChangeSelectionNotification object:object];}
static void RunSelectionFixture(id<PageSelectionFixture> controller,PageSelectionPeer *peer){
    Check(NSApp==nil,@"native selection wiring creates no NSApplication/view/control/window");id token=[controller testWireLiveSelection];PageTextFact *text=peer.text;
    Check(token&&text.willBeginSelection&&text.didFinishSelection&&text.didClickAtCharacterIndex,@"actual original three callbacks and real center registration installed");Check(peer.generation==11&&peer.ai&&peer.freezes==0&&peer.updates==0,@"registration changes no word state or service actions");
    text.willBeginSelection();text.didFinishSelection();text.didClickAtCharacterIndex(20);Check(peer.freezes==1&&peer.updates==1&&peer.clicks==1&&peer.lastIndex==20,@"callbacks address concrete receiver actions and preserve character index");
    [peer.trace removeAllObjects];PostSelection([PageTextFact new]);Check(peer.generation==11&&peer.trace.count==0,@"real notification center filters unrelated text object");[[NSNotificationCenter defaultCenter]postNotificationName:@"SyntheticOtherNotification" object:text];Check(peer.generation==11&&peer.trace.count==0,@"real notification name filter preserved");
    text.trackingSelection=YES;PostSelection(text);Check(peer.generation==11&&peer.ai&&peer.lemma.stringValue.length&&peer.trace.count==0,@"tracking selection guard preserves form/AI/generation/actions");text.trackingSelection=NO;PostSelection(text);
    Check(peer.generation==12&&!peer.ai&&!peer.lemma.stringValue.length&&!peer.reading.stringValue.length&&!peer.meaning.stringValue.length&&peer.updateObservedReset,@"notification clears three fields/AI then increments original word generation before update");Check([[peer.trace componentsJoinedByString:@","]isEqual:@"lemma,reading,meaning,ai,generation,update"],@"actual observer reset sequence and downstream action exact");
    [peer.trace removeAllObjects];PostSelection(text);Check(peer.generation==13&&peer.updates==3,@"repeated completed selection still increments and updates without new dedup state");
    PageTextFact *replacement=[PageTextFact new];replacement.trackingSelection=YES;controller.learningSourceTextView=(FYSelectableSourceTextView *)replacement;peer.text=replacement;[peer.trace removeAllObjects];PostSelection(text);Check(peer.generation==13&&peer.trace.count==0,@"old observed object callback reads current receiver view tracking, not stale captured view");replacement.trackingSelection=NO;PostSelection(replacement);Check(peer.generation==13,@"view replacement does not implicitly move original observer object registration");PostSelection(text);Check(peer.generation==14&&peer.updates==4,@"old registered object dispatches original weak receiver/current view and word state");
    dispatch_semaphore_t finished=dispatch_semaphore_create(0);dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{PostSelection(text);dispatch_semaphore_signal(finished);});
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:3];BOOL delivered=NO;while(limit.timeIntervalSinceNow>0){if(dispatch_semaphore_wait(finished,DISPATCH_TIME_NOW)==0){delivered=YES;break;}[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];}
    Check(delivered&&peer.updateWasMainThread&&peer.generation==15&&peer.updates==5,@"background real notification delivers original reset/action on mainQueue without UI");
    [[NSNotificationCenter defaultCenter]removeObserver:token];PostSelection(text);Check(peer.generation==15&&peer.updates==5,@"test removes its real synthetic token and prevents later notification delivery");Check(NSApp==nil,@"real center/mainQueue wiring stayed headless without UI/device/database/API");
}
