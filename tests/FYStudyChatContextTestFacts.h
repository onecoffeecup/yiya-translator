#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "presentation/FYStudyChatContextCoordinator.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface ChatValueFact : NSObject
@property(nonatomic,copy) NSString *value;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic) NSInteger selectedSegment;
- (NSString *)stringValue;
- (NSString *)string;
@end
@implementation ChatValueFact
- (NSString *)stringValue{[self.events addObject:self.name];return self.value;}
- (NSString *)string{return [self stringValue];}
@end
@interface ChatDraftFact : NSObject
@property(nonatomic,copy) NSString *draft;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) NSMutableArray *events;
- (void)restoreDraftText:(NSString *)text;
@end
@implementation ChatDraftFact
- (void)restoreDraftText:(NSString *)text{self.draft=text;[self.events addObject:self.name];}
@end
@interface ChatAnalyzerBoundary : FYLearningAnalyzer
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) NSMutableArray *replies;
@property(nonatomic,copy) NSArray *lastRequest;
@property(nonatomic) NSUInteger cancels;
@end
@implementation ChatAnalyzerBoundary
- (instancetype)init{if((self=[super init])){_replies=[NSMutableArray new];}return self;}
- (void)setBaseURL:(NSString *)value{[self.events addObject:@"base-set"];[super setBaseURL:value];}
- (void)setApiKey:(NSString *)value{[self.events addObject:@"key-set"];[super setApiKey:value];}
- (void)setModel:(NSString *)value{[self.events addObject:@"model-set"];[super setModel:value];}
- (void)cancelAll{self.cancels++;[self.events addObject:@"cancel"];}
- (void)answerConversation:(NSArray<NSDictionary *> *)messages completion:(void (^)(NSString *,NSError *))completion{self.lastRequest=messages;[self.events addObject:@"answer"];[self.replies addObject:[completion copy]];}
@end
@interface ChatSessionBoundary : FYStudyChatSession
@property(nonatomic,strong) NSMutableArray *events;
@end
@implementation ChatSessionBoundary
- (void)startNewConversationWithSource:(NSString *)source translation:(NSString *)translation{[self.events addObject:@"start"];[super startNewConversationWithSource:source translation:translation];}
- (void)referenceSource:(NSString *)source translation:(NSString *)translation{[self.events addObject:@"reference"];[super referenceSource:source translation:translation];}
- (void)send:(NSString *)text{[self.events addObject:@"send"];[super send:text];}
@end
@interface ChatLearningBoundary : NSObject
@property(nonatomic,copy) NSString *latestSentenceID;
@property(nonatomic,copy) NSString *currentSentenceID;
@property(nonatomic) NSInteger currentVersion;
@property(nonatomic,copy) NSString *currentSourceText;
@property(nonatomic,copy) NSString *currentTranslation;
@end
@implementation ChatLearningBoundary
@end
@interface ChatStoreBoundary : NSObject
@property(nonatomic,strong) NSMutableArray *replies;
@property(nonatomic,copy) NSString *fetchedID;
@property(nonatomic,strong) NSMutableArray *events;
- (void)fetchSentence:(NSString *)sentenceID completion:(void (^)(FYSentenceRecord *,NSError *))completion;
@end
@implementation ChatStoreBoundary
- (instancetype)init{if((self=[super init])){_replies=[NSMutableArray new];}return self;}
- (void)fetchSentence:(NSString *)sentenceID completion:(void (^)(FYSentenceRecord *,NSError *))completion{self.fetchedID=sentenceID;[self.events addObject:@"fetch"];[self.replies addObject:[completion copy]];}
@end
@interface ChatContextFacts : NSObject
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) NSMutableArray *captures;
@property(nonatomic,strong) ChatSessionBoundary *session;
@property(nonatomic,strong) ChatAnalyzerBoundary *analyzer;
@property(nonatomic,strong) ChatLearningBoundary *learning;
@property(nonatomic,strong) ChatStoreBoundary *store;
@property(nonatomic,strong) ChatValueFact *base,*key,*model,*fallbackModel,*source,*translation,*language;
@property(nonatomic,strong) ChatDraftFact *mainDraft,*overlayDraft;
@property(nonatomic) BOOL running;
@property(nonatomic) uint32_t windowID;
@property(nonatomic) NSInteger mode;
@property(nonatomic,copy) NSString *error;
@property(nonatomic) NSUInteger ensures,refreshes,visibility;
@end
@implementation ChatContextFacts
- (instancetype)init{if((self=[super init])){
 _events=[NSMutableArray new];_captures=[NSMutableArray new];_session=[ChatSessionBoundary new];_session.events=_events;_analyzer=[ChatAnalyzerBoundary new];_analyzer.events=_events;_session.analyzer=_analyzer;_learning=[ChatLearningBoundary new];_store=[ChatStoreBoundary new];_store.events=_events;
 NSArray *names=@[@"base-get",@"key-get",@"model-get",@"fallback-model-get",@"source-get",@"translation-get",@"language-get"];NSMutableArray *fields=[NSMutableArray new];for(NSString *name in names){ChatValueFact *v=[ChatValueFact new];v.name=name;v.events=_events;[fields addObject:v];}_base=fields[0];_key=fields[1];_model=fields[2];_fallbackModel=fields[3];_source=fields[4];_translation=fields[5];_language=fields[6];_base.value=@"https://synthetic.invalid/v1";_key.value=@"synthetic-only-key";_model.value=@" learning-model \n";_fallbackModel.value=@" raw-fallback ";_source.value=@"画面原文";_translation.value=@"画面译文";
 _mainDraft=[ChatDraftFact new];_mainDraft.name=@"main-draft";_mainDraft.events=_events;_overlayDraft=[ChatDraftFact new];_overlayDraft.name=@"overlay-draft";_overlayDraft.events=_events;
 }return self;}
@end
@protocol StudyChatDriver <NSObject>
@property(nonatomic) NSInteger chatContextGeneration;
@property(nonatomic) BOOL chatResolvingSource;
@property(nonatomic,strong) id inlineReturnSnapshot;
- (void)referenceLatestStudySentence:(id)sender;
- (void)resolveLatestStudyIdentity:(void (^)(FYRequestIdentity *))completion;
- (void)resolveLatestStudySentence:(void (^)(NSString *,NSString *))completion;
- (void)sendStudyChat:(NSString *)text;
@end
typedef id<StudyChatDriver> (^ChatDriverFactory)(ChatContextFacts *facts);
static void Capture(ChatContextFacts *f,NSString *source,NSError *error){Check(f.captures.count>0,@"held capture callback exists");void(^reply)(NSString *,NSError *)=f.captures.firstObject;[f.captures removeObjectAtIndex:0];reply(source,error);}
static void Store(ChatContextFacts *f,FYSentenceRecord *record,NSError *error){Check(f.store.replies.count>0,@"held store callback exists");void(^reply)(FYSentenceRecord *,NSError *)=f.store.replies.firstObject;[f.store.replies removeObjectAtIndex:0];reply(record,error);}
static void Answer(ChatContextFacts *f,NSString *text){Check(f.analyzer.replies.count>0,@"held session network callback exists");void(^reply)(NSString *,NSError *)=f.analyzer.replies.firstObject;[f.analyzer.replies removeObjectAtIndex:0];reply(text,nil);}
static void Current(ChatContextFacts *f,NSString *source,NSString *translation){f.learning.latestSentenceID=@"current";f.learning.currentSentenceID=@"current";f.learning.currentVersion=7;f.learning.currentSourceText=source;f.learning.currentTranslation=translation;}
static void RunStudyChatFixture(id<StudyChatDriver>d,ChatContextFacts*f){
 void **app=dlsym(RTLD_DEFAULT,"NSApp");Check(!app||!*app,@"cold context check creates no app/view/window/device/database");Check(d.chatContextGeneration==0&&!d.chatResolvingSource,@"original context defaults remain zero/idle");
 __block FYRequestIdentity *identity=nil;[d resolveLatestStudyIdentity:^(FYRequestIdentity*i){identity=i;}];Check(!identity&&f.store.replies.count==0,@"no current/latest returns nil without database task");Current(f,@"固定原句",@"固定译文");[d resolveLatestStudyIdentity:^(FYRequestIdentity*i){identity=i;}];Check([identity.sentenceID isEqual:@"current"]&&identity.version==7&&[identity.sourceText isEqual:@"固定原句"]&&[identity.translation isEqual:@"固定译文"]&&identity.requestID.length>0,@"current identity preserves original ID/version/text/translation and fresh UUID");NSString *uuid=identity.requestID;[d resolveLatestStudyIdentity:^(FYRequestIdentity*i){identity=i;}];Check(![identity.requestID isEqual:uuid],@"every current resolution gets a fresh request identity");
 f.learning.latestSentenceID=@"latest";[d resolveLatestStudyIdentity:^(FYRequestIdentity*i){identity=i;}];Check([f.store.fetchedID isEqual:@"latest"]&&f.store.replies.count==1,@"latest different from pinned current queries original unique store");FYSentenceRecord *record=[FYSentenceRecord new];record.sentenceID=@"latest";record.latestVersion=9;record.latestText=@"最新原句";record.latestTranslation=@"最新译文";Store(f,record,nil);Check([identity.sentenceID isEqual:@"latest"]&&identity.version==9&&[identity.sourceText isEqual:@"最新原句"]&&[identity.translation isEqual:@"最新译文"],@"latest stored record wins over pinned/display text");uuid=identity.requestID;[d resolveLatestStudyIdentity:^(FYRequestIdentity*i){identity=i;}];Store(f,record,nil);Check(![identity.requestID isEqual:uuid],@"store path also creates new UUID per resolution");[d resolveLatestStudyIdentity:^(FYRequestIdentity*i){identity=i;}];Store(f,nil,[NSError errorWithDomain:@"synthetic" code:4 userInfo:nil]);Check(!identity,@"missing/error latest record keeps original nil result without fallback to current");
 __block NSString *source=nil,*translation=nil;Current(f,@"",nil);[f.events removeAllObjects];[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Check([source isEqual:@""]&&[translation isEqual:@""]&&![f.events containsObject:@"source-get"]&&![f.events containsObject:@"translation-get"],@"identity empty source and nil translation do not fall through to UI values");f.learning.currentSourceText=nil;[f.events removeAllObjects];[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Check([source isEqual:@""]&&[translation isEqual:@""]&&f.events.count==0,@"canonical identity factory normalizes nil source to empty and suppresses both UI fallbacks");f.learning.currentSentenceID=nil;f.learning.latestSentenceID=nil;[f.events removeAllObjects];[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Check([source isEqual:@"画面原文"]&&[translation isEqual:@"画面译文"]&&[f.events isEqual:@[@"source-get",@"translation-get"]],@"absent identity reads both native fallbacks in original order");f.source.value=nil;f.translation.value=nil;[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Check([source isEqual:@""]&&[translation isEqual:@""],@"both nil UI values resolve as empty");
 Current(f,@"最新原句",@"最新译文");f.running=YES;f.windowID=0;[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Check(f.captures.count==0&&[source isEqual:@"最新原句"],@"running without a selected window uses current identity");f.windowID=17;[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Check(f.captures.count==1,@"running selected window captures at click independently of pinned reader");Capture(f,@"另一个画面",nil);Check([source isEqual:@"另一个画面"]&&[translation isEqual:@""],@"different captured source does not borrow pinned translation");[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Capture(f,@"最新 原句",nil);Check([source isEqual:@"最新 原句"]&&[translation isEqual:@"最新译文"],@"canonical same-source comparison reuses translation without rewriting captured text");
 NSString *full=@"合成人物\n最初の一行です。\n明日は図書館に行きます。\n一緒に勉強しましょう。";NSString *fragment=@"合成人物\n明日は図書館に行きます。\n一緒に勉強しましょう。";Check(FYDialogueIsSpeakerAnchoredFragment(fragment,full),@"fixture is a canonical real speaker-anchored fragment");Current(f,full,@"明天去图书馆。");f.mode=0;f.language.selectedSegment=0;[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Capture(f,fragment,nil);Check([source isEqual:full]&&[translation isEqual:@"明天去图书馆。"],@"dialogue Japanese fragment restores full identity source and translation");f.language.selectedSegment=1;[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Capture(f,fragment,nil);Check([source isEqual:fragment]&&[translation isEqual:@""],@"other language does not apply speaker fragment expansion");f.mode=1;f.language.selectedSegment=0;[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Capture(f,fragment,nil);Check([source isEqual:fragment]&&[translation isEqual:@""],@"non-dialogue mode does not expand speaker fragment");NSError *error=[NSError errorWithDomain:@"synthetic" code:8 userInfo:@{NSLocalizedDescriptionKey:@"合成截图失败"}];NSUInteger n=f.store.replies.count;[d resolveLatestStudySentence:^(NSString*s,NSString*t){source=s;translation=t;}];Capture(f,nil,error);Check([f.error isEqual:@"合成截图失败"]&&[source isEqual:@""]&&[translation isEqual:@""]&&f.store.replies.count==n,@"capture failure reports original cause and empty completion without identity query");
 f.mode=0;Current(f,@"latest text",@"latest translation");[f.session referenceSource:@"old" translation:@"old translation"];[f.session send:@"old question"];id oldSession=f.session;NSUInteger cancels=f.analyzer.cancels;d.inlineReturnSnapshot=[NSObject new];[f.events removeAllObjects];[d referenceLatestStudySentence:nil];Check(f.session==oldSession&&d.chatContextGeneration==1&&d.chatResolvingSource&&f.session.messages.count==0&&[f.session.source isEqual:@""]&&f.analyzer.cancels==cancels+1,@"explicit latest increments context, clears same session conversation and cancels only session scope");Check(!d.inlineReturnSnapshot&&f.visibility==1&&[f.events isEqual:@[@"ensure",@"start",@"cancel",@"visibility",@"capture"]],@"return snapshot clears before click-time capture and native visibility update retains ordering");Answer(f,@"late old answer");Check(f.session.messages.count==0,@"session network generation rejects answer from previous conversation");Capture(f,@"latest text",nil);Check(!d.chatResolvingSource&&[f.session.source isEqual:@"latest text"]&&[f.session.translation isEqual:@"latest translation"],@"matching latest resolution references same session and clears resolving");
 [d referenceLatestStudySentence:nil];[d referenceLatestStudySentence:nil];Check(f.captures.count==2,@"successive latest requests keep original independent capture callbacks");Capture(f,@"stale",nil);Check(d.chatResolvingSource&&[f.session.source isEqual:@""],@"old latest callback cannot clear new resolving flag or replace context");Capture(f,@"newest",nil);Check(!d.chatResolvingSource&&[f.session.source isEqual:@"newest"],@"current latest callback commits normally");
 d.chatResolvingSource=YES;[f.events removeAllObjects];[d sendStudyChat:@"busy"];Check([f.events isEqual:@[@"ensure"]],@"context-busy send stops before config/session send");d.chatResolvingSource=NO;[f.events removeAllObjects];[d sendStudyChat:@"question"];NSArray *prefix=@[@"ensure",@"base-get",@"base-set",@"key-get",@"key-set",@"model-get",@"model-set",@"send",@"answer"];Check([f.events isEqual:prefix]&&[f.analyzer.model isEqual:@"learning-model"]&&f.session.sending,@"existing-source send preserves native config getter/setter interleave, trimmed learning model and direct send");Check(![f.events containsObject:@"fallback-model-get"]&&f.captures.count==0,@"nonempty learning model suppresses fallback and existing source suppresses capture");[f.events removeAllObjects];[d sendStudyChat:@"duplicate"];Check([f.events isEqual:@[@"ensure"]]&&f.analyzer.replies.count==1,@"network-busy send suppresses duplicate task/config");Answer(f,@"answer");Check(!f.session.sending&&f.session.messages.count==2,@"actual existing session completes the conversation");
 f.model.value=@" \n";[f.events removeAllObjects];[d sendStudyChat:@"fallback"];Check([f.analyzer.model isEqual:@" raw-fallback "]&&[[f.events subarrayWithRange:NSMakeRange(0,8)]isEqual:@[@"ensure",@"base-get",@"base-set",@"key-get",@"key-set",@"model-get",@"fallback-model-get",@"model-set"]],@"empty trimmed learning model reads raw fallback at original position");Answer(f,@"fallback reply");f.model.value=@"model";
 [f.session startNewConversationWithSource:@"" translation:@""];[f.events removeAllObjects];NSUInteger refreshes=f.refreshes;[d sendStudyChat:@"resolved question"];Check(d.chatResolvingSource&&f.refreshes==refreshes+1&&f.captures.count==1&&[[f.events subarrayWithRange:NSMakeRange(7,2)]isEqual:@[@"refresh",@"capture"]],@"source-less send marks busy and refreshes before context capture");Capture(f,@"resolved source",nil);Check(!d.chatResolvingSource&&f.session.sending&&[f.session.source isEqual:@"resolved source"]&&[f.events.lastObject isEqual:@"refresh"],@"matching resolution references then sends then refreshes");Check([f.analyzer.lastRequest.lastObject[@"role"]isEqual:@"user"],@"original session encodes request with canonical user role");Answer(f,@"resolved reply");
 [f.session startNewConversationWithSource:@"" translation:@""];[d sendStudyChat:@"保留的草稿🙂"];[d referenceLatestStudySentence:nil];NSInteger generation=d.chatContextGeneration;[f.events removeAllObjects];Capture(f,@"old resolved",nil);Check(d.chatContextGeneration==generation&&d.chatResolvingSource&&[f.session.source isEqual:@""]&&f.analyzer.replies.count==0,@"stale send result leaves newer resolution busy and creates no answer task");Check([f.mainDraft.draft isEqual:@"保留的草稿🙂"]&&[f.overlayDraft.draft isEqual:@"保留的草稿🙂"]&&[[f.events subarrayWithRange:NSMakeRange(f.events.count-3,3)]isEqual:@[@"refresh",@"main-draft",@"overlay-draft"]],@"stale send refreshes then restores both unchanged drafts in original order");Capture(f,@"new referenced",nil);Check(!d.chatResolvingSource&&[f.session.source isEqual:@"new referenced"],@"new latest finishes after stale send without draft or generation loss");Check(f.store.replies.count==0&&f.captures.count==0&&f.analyzer.replies.count==0,@"all held boundary callbacks are consumed, no real API/database/device tasks");app=dlsym(RTLD_DEFAULT,"NSApp");Check(!app||!*app,@"all production context/session algorithms finish without application initialization");
}
static void RunStudyChatLeases(ChatDriverFactory factory){
 ChatContextFacts*f=[ChatContextFacts new];f.running=YES;f.windowID=17;__weak id weakSource;
 @autoreleasepool{id<StudyChatDriver>s=factory(f);weakSource=s;[s referenceLatestStudySentence:nil];}Check(weakSource!=nil,@"held capture keeps original strong concrete native/source lease");@autoreleasepool{Capture(f,@"leased source",nil);}Check(!weakSource,@"source releases after capture/identity callback delivery");
 f=[ChatContextFacts new];f.running=YES;f.windowID=17;f.learning.latestSentenceID=@"latest";f.learning.currentSentenceID=@"current";
 @autoreleasepool{id<StudyChatDriver>s=factory(f);weakSource=s;[s sendStudyChat:@"held question"];Capture(f,@"leased captured",nil);}Check(weakSource&&f.store.replies.count==1,@"nested latest-store callback preserves original strong source lease after capture returns");@autoreleasepool{Store(f,nil,nil);}Check(!weakSource,@"source releases after nested resolver/send finishes");Answer(f,@"done");
 ChatAnalyzerBoundary*a=[ChatAnalyzerBoundary new];__weak FYStudyChatSession*weakSession;@autoreleasepool{FYStudyChatSession*s=[FYStudyChatSession new];s.analyzer=a;weakSession=s;[s referenceSource:@"context" translation:@""];[s send:@"question"];}Check(!weakSession&&a.replies.count==1,@"existing session network callback remains weak and does not gain context/source lease");void(^reply)(NSString*,NSError*)=a.replies.firstObject;[a.replies removeAllObjects];reply(@"late",nil);Check(!weakSession,@"late network answer safely ignores released original session");
}
