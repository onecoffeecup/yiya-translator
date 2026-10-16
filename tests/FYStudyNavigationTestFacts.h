#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import "presentation/FYStudyNavigationCoordinator.h"
#import "presentation/FYQuickSentenceCoordinator.h"
#import "presentation/FYStudyChatContextCoordinator.h"
#import "presentation/FYPresentationText.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString*m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface NavAnalyzerBoundary : FYLearningAnalyzer
@property(nonatomic,strong) NSMutableArray*events;
@property(nonatomic,strong) NSMutableArray*replies;
@property(nonatomic,copy) NSString*name;
@property(nonatomic) NSUInteger cancels;
@end
@implementation NavAnalyzerBoundary
- (instancetype)init{if((self=[super init]))_replies=[NSMutableArray new];return self;}
- (void)cancelAll{self.cancels++;[self.events addObject:self.name?:@"cancel"];}
- (void)answerConversation:(NSArray*)messages completion:(void(^)(NSString*,NSError*))completion{[self.replies addObject:[completion copy]];[self.events addObject:@"answer"];}
@end
@interface NavSessionBoundary : FYStudyChatSession
@property(nonatomic,strong) NSMutableArray*events;
@end
@implementation NavSessionBoundary
- (void)referenceSource:(NSString*)source translation:(NSString*)translation{[self.events addObject:@"reference"];[super referenceSource:source translation:translation];}
- (void)startNewConversationWithSource:(NSString*)source translation:(NSString*)translation{[self.events addObject:@"start"];[super startNewConversationWithSource:source translation:translation];}
@end
@interface NavPanelFact : NSObject
@property(nonatomic,strong) NSMutableArray*events;
@property(nonatomic,copy) NSString*name;
- (void)orderOut:(id)sender;
- (void)center;
- (void)makeKeyWindow;
- (void)makeKeyAndOrderFront:(id)sender;
@end
@implementation NavPanelFact
- (void)orderOut:(id)sender{[self.events addObject:[self.name stringByAppendingString:@"-hide"]];}
- (void)center{[self.events addObject:@"center"];}
- (void)makeKeyWindow{[self.events addObject:@"focus"];}
- (void)makeKeyAndOrderFront:(id)sender{[self.events addObject:@"main-activate"];}
@end
@interface NavDraftFact : NSObject
@property(nonatomic,copy) NSString*text;
@property(nonatomic,copy) NSString*name;
@property(nonatomic,strong) NSMutableArray*events;
- (void)setDraftText:(NSString*)text;
- (void)restoreDraftText:(NSString*)text;
@end
@implementation NavDraftFact
- (void)setDraftText:(NSString*)text{self.text=text;[self.events addObject:[self.name stringByAppendingString:@"-set"]];}
- (void)restoreDraftText:(NSString*)text{self.text=text;[self.events addObject:[self.name stringByAppendingString:@"-restore"]];}
@end
@interface NavEpochFact : NSObject
@property(nonatomic) NSUInteger epoch;
@property(nonatomic,strong) NSMutableArray*events;
- (NSUInteger)sessionEpoch;
@end
@implementation NavEpochFact
- (NSUInteger)sessionEpoch{[self.events addObject:@"epoch"];return self.epoch;}
@end
@interface NavLearningBoundary : NSObject
@property(nonatomic,copy) NSString*currentSourceText;
@property(nonatomic,copy) NSString*currentTranslation;
@property(nonatomic,strong) FYRequestIdentity*recordedIdentity;
@property(nonatomic,strong) FYRequestIdentity*selected;
@property(nonatomic,copy) NSString*recordedText;
@property(nonatomic) FYSentenceKind recordedKind;
@property(nonatomic) NSUInteger records,selections;
@property(nonatomic,strong) NSMutableArray*events;
- (FYRequestIdentity*)recordText:(NSString*)text kind:(FYSentenceKind)kind;
- (void)selectSentenceID:(NSString*)ID version:(NSInteger)version sourceText:(NSString*)text translation:(NSString*)translation;
@end
@implementation NavLearningBoundary
- (FYRequestIdentity*)recordText:(NSString*)text kind:(FYSentenceKind)kind{self.records++;self.recordedText=text;self.recordedKind=kind;[self.events addObject:@"record"];return self.recordedIdentity;}
- (void)selectSentenceID:(NSString*)ID version:(NSInteger)version sourceText:(NSString*)text translation:(NSString*)translation{self.selections++;self.selected=[FYRequestIdentity identityWithSentenceID:ID version:version requestID:@"selected" sourceText:text translation:translation];[self.events addObject:@"select-fixed"];}
@end
@class StudyNavigationFacts;
@protocol StudyNavigationDriver <NSObject>
@property(nonatomic,strong) FYInlineBlockSnapshot*inlineBlockSnapshot;
@property(nonatomic,strong) FYInlineBlockSnapshot*inlineReturnSnapshot;
@property(nonatomic,copy) NSString*inlineReturnSourceText;
@property(nonatomic,copy) NSString*quickSentenceID;
@property(nonatomic,copy) NSString*quickSentenceSource;
@property(nonatomic,copy) NSString*quickSentenceTranslation;
@property(nonatomic) NSInteger quickSentenceVersion;
@property(nonatomic) BOOL quickSentenceRequested;
@property(nonatomic) NSInteger quickSentenceGeneration;
@property(nonatomic) BOOL quickSentenceIsInlineBlock;
@property(nonatomic) BOOL studyChatOverlayRequested;
@property(nonatomic) NSInteger quickSelectedGrammarIndex;
@property(nonatomic) NSInteger chatContextGeneration;
@property(nonatomic) BOOL chatResolvingSource;
@property(nonatomic,strong) FYAnalysisResult*quickSentenceAnalysis;
@property(nonatomic,copy) NSString*quickSentenceAnalysisError;
@property(nonatomic,copy) NSString*quickSentenceAnalysisSource;
@property(nonatomic,copy) NSString*quickSentenceAnalysisTranslation;
@property(nonatomic) BOOL quickSentenceAnalyzing;
@property(nonatomic,strong) FYAnalysisResult*currentAnalysis;
@property(nonatomic) NSInteger analysisRequestGeneration;
@property(nonatomic) NSInteger selectedGrammarIndex;
@property(nonatomic) CGFloat quickSentenceScrollOffset;
- (void)askQuickSentence:(id)sender;
- (void)showQuickSentence:(id)sender;
- (void)openStudyWorkspace:(id)sender;
- (void)openInlineLearningForBlockText:(NSString*)source translation:(NSString*)translation;
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot*)snapshot;
- (void)bindInlineStudyChatToSource:(NSString*)source translation:(NSString*)translation;
- (void)returnFromStudyChatToInlineLearning:(id)sender;
@end
@interface StudyNavigationFacts : NSObject
@property(nonatomic,strong) NSMutableArray*events,*identities;
@property(nonatomic,strong) FYQuickSentenceCoordinator*quick;
@property(nonatomic,strong) FYStudyChatContextCoordinator*context;
@property(nonatomic,strong) FYGrammarActionState*actions;
@property(nonatomic,strong) NavAnalyzerBoundary*chatAnalyzer,*quickAnalyzer,*detailAnalyzer,*otherAnalyzer;
@property(nonatomic,strong) NavSessionBoundary*session;
@property(nonatomic,strong) NavLearningBoundary*learning;
@property(nonatomic,strong) NavPanelFact*quickPanel,*chatPanel,*mainWindow;
@property(nonatomic,strong) NavEpochFact*epochFact;
@property(nonatomic,strong) NavDraftFact*mainDraft,*overlayDraft;
@property(nonatomic,weak) id<StudyNavigationDriver>driver;
@property(nonatomic,weak) id lastSender;
@property(nonatomic) BOOL foreground,selecting,matches,captureEnabled,createPanelOnRender,analyzeBusy;
@property(nonatomic,strong) FYAnalysisResult*currentResult;
@property(nonatomic) NSInteger analysisGeneration,selectedGrammar;
@property(nonatomic) CGFloat scrollOffset;
@property(nonatomic) NSUInteger renders,analyses,closes,savedRefreshes,currentAnalyses;
@property(nonatomic,copy) void(^onRender)(void);
@property(nonatomic,copy) void(^onClose)(void);
@property(nonatomic,copy) void(^onActivate)(void);
@end
@implementation StudyNavigationFacts
- (instancetype)init{if((self=[super init])){_events=[NSMutableArray new];_identities=[NSMutableArray new];_quick=[FYQuickSentenceCoordinator new];_context=[FYStudyChatContextCoordinator new];_chatAnalyzer=[NavAnalyzerBoundary new];_chatAnalyzer.events=_events;_chatAnalyzer.name=@"chat-cancel";_quickAnalyzer=[NavAnalyzerBoundary new];_quickAnalyzer.events=_events;_quickAnalyzer.name=@"quick-cancel";_detailAnalyzer=[NavAnalyzerBoundary new];_detailAnalyzer.events=_events;_detailAnalyzer.name=@"detail-cancel";_otherAnalyzer=[NavAnalyzerBoundary new];_quick.quickSentenceAnalyzer=_quickAnalyzer;_actions=[FYGrammarActionState new];_actions.analyzer=_detailAnalyzer;_session=[NavSessionBoundary new];_session.events=_events;_session.analyzer=_chatAnalyzer;_learning=[NavLearningBoundary new];_learning.events=_events;_learning.recordedIdentity=[FYRequestIdentity identityWithSentenceID:@"recorded" version:6 requestID:@"r" sourceText:@"recorded" translation:nil];_epochFact=[NavEpochFact new];_epochFact.epoch=0x100000007ULL;_epochFact.events=_events;_mainDraft=[NavDraftFact new];_mainDraft.name=@"main";_mainDraft.events=_events;_mainDraft.text=@"main draft";_overlayDraft=[NavDraftFact new];_overlayDraft.name=@"overlay";_overlayDraft.events=_events;_overlayDraft.text=@"overlay draft";_chatPanel=[NavPanelFact new];_chatPanel.name=@"chat";_chatPanel.events=_events;_mainWindow=[NavPanelFact new];_mainWindow.name=@"main";_mainWindow.events=_events;_foreground=YES;_createPanelOnRender=YES;}return self;}
@end
typedef id<StudyNavigationDriver>(^NavDriverFactory)(StudyNavigationFacts*f);
static FYAnalysisResult*Result(void){FYAnalysisResult*r=[FYAnalysisResult new];r.schemaVersion=3;r.grammar=@[[FYGrammarItem new]];r.vocabulary=@[[FYVocabularyEntry new]];r.sentenceNote=@"note";r.structureParts=@[@{@"text":@"part"}];r.structureTitle=@"title";r.sentenceID=@"old-result-id";r.version=1;r.status=FYAnalysisStatusFailed;return r;}
static FYRequestIdentity*Identity(NSString*ID,NSInteger version,NSString*source,NSString*translation){return [FYRequestIdentity identityWithSentenceID:ID version:version requestID:@"synthetic" sourceText:source translation:translation];}
static FYInlineBlockSnapshot*Snapshot(NSString*block,NSString*ID,NSInteger version,NSString*source,NSString*translation){FYInlineBlockSnapshot*s=[FYInlineBlockSnapshot new];s.blockID=block;s.sentenceID=ID;s.version=version;s.sourceText=source;s.translation=translation;s.lineBoxes=@[[NSValue valueWithRect:CGRectMake(.1,.2,.3,.04)]];s.inputEpoch=9;s.inputSource=1;return s;}
static void IdentityReply(StudyNavigationFacts*f,FYRequestIdentity*i){Check(f.identities.count>0,@"held original identity resolver completion exists");void(^reply)(FYRequestIdentity*)=f.identities.firstObject;[f.identities removeObjectAtIndex:0];reply(i);}
static void ChatReply(StudyNavigationFacts*f){Check(f.chatAnalyzer.replies.count>0,@"held real session network completion exists");void(^reply)(NSString*,NSError*)=f.chatAnalyzer.replies.firstObject;[f.chatAnalyzer.replies removeObjectAtIndex:0];reply(@"answer",nil);}
static NSArray*Tail(NSArray*a,NSUInteger n){Check(a.count>=n,@"event trace contains expected terminal actions");return [a subarrayWithRange:NSMakeRange(a.count-n,n)];}
static void RunStudyNavigationFixture(id<StudyNavigationDriver>d,StudyNavigationFacts*f){
 void**app=dlsym(RTLD_DEFAULT,"NSApp");Check(!app||!*app,@"navigation tests create no app/window/view/device/database");Check(!d.inlineBlockSnapshot&&!d.inlineReturnSnapshot&&!d.quickSentenceGeneration&&!d.quickSentenceRequested&&!d.studyChatOverlayRequested,@"original navigation defaults remain nil/zero");
 __weak FYInlineBlockSnapshot*weakSnapshot;@autoreleasepool{FYInlineBlockSnapshot*owned=Snapshot(@"lease",@"id",1,@"owned",nil);weakSnapshot=owned;d.inlineBlockSnapshot=owned;}@autoreleasepool{Check(weakSnapshot&&d.inlineBlockSnapshot==weakSnapshot,@"current snapshot retains original strong lease after caller releases its reference");d.inlineReturnSnapshot=d.inlineBlockSnapshot;d.inlineBlockSnapshot=nil;Check(weakSnapshot&&d.inlineReturnSnapshot==weakSnapshot,@"return snapshot independently retains exact same snapshot without copying");}d.inlineReturnSnapshot=nil;Check(!weakSnapshot,@"clearing both original snapshot references releases object without duplicate owner");NSMutableString*copyInput=[@"copy-input" mutableCopy];d.inlineReturnSourceText=copyInput;d.quickSentenceID=copyInput;d.quickSentenceSource=copyInput;d.quickSentenceTranslation=copyInput;[copyInput appendString:@"-changed"];Check([d.inlineReturnSourceText isEqual:@"copy-input"]&&[d.quickSentenceID isEqual:@"copy-input"]&&[d.quickSentenceSource isEqual:@"copy-input"]&&[d.quickSentenceTranslation isEqual:@"copy-input"],@"four navigation strings preserve original copy ownership");d.inlineReturnSourceText=nil;d.quickSentenceID=nil;
 d.quickSentenceSource=@"same source";d.quickSentenceTranslation=@"same translation";[f.session referenceSource:d.quickSentenceSource translation:d.quickSentenceTranslation];[f.session send:@"question"];NSUInteger cancels=f.chatAnalyzer.cancels;id session=f.session;id sender=[NSObject new];d.chatResolvingSource=YES;[f.events removeAllObjects];[d askQuickSentence:sender];Check(d.chatContextGeneration==1&&!d.chatResolvingSource&&f.session==session&&f.session.sending&&f.chatAnalyzer.cancels==cancels,@"same-source/translation AI round trip invalidates context resolution but preserves ongoing session answer");Check([f.events isEqual:@[@"capture-scroll",@"show-chat"]]&&f.lastSender==sender&&[f.mainDraft.text isEqual:@"main draft"]&&[f.overlayDraft.text isEqual:@"overlay draft"],@"ask captures scroll before native show, preserves original event sender and both drafts");ChatReply(f);d.quickSentenceTranslation=@"different translation";[f.events removeAllObjects];[d askQuickSentence:sender];Check([f.events isEqual:@[@"capture-scroll",@"reference",@"chat-cancel",@"show-chat"]]&&[f.session.translation isEqual:@"different translation"],@"changed translation alone references same session at original point");
 [f.events removeAllObjects];[d bindInlineStudyChatToSource:@"new block" translation:@"new translation"];Check(f.session==session&&[f.session.source isEqual:@"new block"]&&[f.session.translation isEqual:@"new translation"]&&f.session.messages.count==0,@"explicit block binding starts new conversation in existing session");Check([f.events isEqual:@[@"ensure",@"start",@"chat-cancel",@"main-get",@"main-set",@"overlay-get",@"overlay-set",@"chat-refresh"]]&&[f.mainDraft.text isEqual:@""]&&[f.overlayDraft.text isEqual:@""],@"bind clears main then overlay via setDraft, then refreshes; no restore substitution");
 f.foreground=NO;[f.events removeAllObjects];NSInteger generation=d.quickSentenceGeneration;[d showQuickSentence:nil];Check([f.events isEqual:@[@"foreground"]]&&d.quickSentenceGeneration==generation&&!f.identities.count,@"background quick entry returns before request/generation/identity service");f.foreground=YES;d.quickSentenceIsInlineBlock=YES;d.quickSentenceAnalysis=Result();d.quickSentenceAnalysisError=@"old";d.quickSelectedGrammarIndex=2;[f.events removeAllObjects];[d showQuickSentence:nil];Check(d.quickSentenceRequested&&!d.quickSentenceIsInlineBlock&&d.quickSentenceGeneration==generation+1&&f.identities.count==1,@"quick entry updates original flags/generation before held identity resolution");d.quickSentenceRequested=NO;NSUInteger renders=f.renders;IdentityReply(f,Identity(@"stale",2,@"stale",@""));Check(f.renders==renders&&d.quickSentenceAnalysis!=nil,@"closed quick entry ignores held identity before clearing cached result");
 [d showQuickSentence:nil];[d showQuickSentence:nil];IdentityReply(f,Identity(@"old",1,@"old",@""));Check(f.renders==renders,@"old quick generation cannot replace a newer identity request");f.quickPanel=nil;f.matches=NO;[f.events removeAllObjects];IdentityReply(f,Identity(@"current",7,@"current source",@"current translation"));Check([d.quickSentenceID isEqual:@"current"]&&d.quickSentenceVersion==7&&[d.quickSentenceSource isEqual:@"current source"]&&[d.quickSentenceTranslation isEqual:@"current translation"]&&!d.quickSentenceAnalysis&&!d.quickSentenceAnalysisError&&d.quickSelectedGrammarIndex==0,@"new identity clears incompatible analysis and writes exact captured identity/version/text");Check([f.events isEqual:@[@"cancel",@"detail-cancel",@"quick-cancel",@"analysis-matches",@"chat-panel-get",@"chat-hide",@"panel-get",@"render",@"saved-refresh",@"panel-get",@"center",@"foreground",@"panel-get",@"focus",@"analyze"]],@"quick resolution preserves cancel/gates/hide, pre-render panel existence, render/saved/center/focus/analyze order");
 FYAnalysisResult*cached=Result();d.quickSentenceAnalysis=cached;d.quickSentenceAnalyzing=NO;d.quickSentenceAnalysisSource=@"current source";d.quickSentenceAnalysisTranslation=@"current translation";d.quickSelectedGrammarIndex=1;NSUInteger analyzes=f.analyses;NSUInteger quickCancels=f.quickAnalyzer.cancels;[d showQuickSentence:nil];[f.events removeAllObjects];IdentityReply(f,Identity(@"current",7,@"current source",@"current translation"));Check(d.quickSentenceAnalysis==cached&&d.quickSelectedGrammarIndex==1&&f.quickAnalyzer.cancels==quickCancels&&f.analyses==analyzes&&![f.events containsObject:@"center"],@"same analysis source/translation keeps cached result/index and existing panel without cancel/reanalyze/recenter");
 d.quickSentenceAnalysis=nil;d.quickSentenceAnalyzing=NO;f.matches=YES;f.learning.currentSourceText=@"reuse source";f.learning.currentTranslation=@"reuse translation";FYAnalysisResult*main=Result();d.currentAnalysis=main;[d showQuickSentence:nil];IdentityReply(f,Identity(@"reuse",9,@"reuse source",@"reuse translation"));Check(d.quickSentenceAnalysis==main&&[d.quickSentenceAnalysisSource isEqual:@"reuse source"]&&[d.quickSentenceAnalysisTranslation isEqual:@"reuse translation"]&&f.analyses==analyzes,@"matching main analysis is reused with original result identity and source/translation snapshots");
 f.selecting=YES;d.quickSentenceAnalysis=cached;d.quickSentenceAnalysisSource=@"reuse source";d.quickSentenceAnalysisTranslation=@"reuse translation";[d showQuickSentence:nil];[f.events removeAllObjects];IdentityReply(f,Identity(@"reuse",9,@"reuse source",@"reuse translation"));Check(![f.events containsObject:@"foreground"]&&![f.events containsObject:@"focus"],@"capture-region selection short circuits foreground/focus only after rendering");f.selecting=NO;
 // Snapshot input guards and canonical line geometry preserve existing text/indices.
 [f.events removeAllObjects];d.quickSentenceAnalyzing=YES;NSUInteger records=f.learning.records;[d openInlineLearningForBlockText:@" \n x " translation:nil];Check(f.events.count==0&&f.learning.records==records,@"trimmed one-character inline text creates no snapshot or input reads");f.captureEnabled=YES;[d openInlineLearningForBlockText:@"  日本語\n\n次の行  " translation:nil];FYInlineBlockSnapshot*s=d.inlineBlockSnapshot;Check([s.sourceText isEqual:@"日本語\n\n次の行"]&&[s.translation isEqual:@""]&&s.lineBoxes.count==2&&s.inputSource==1&&s.inputEpoch==0x100000007ULL&&[s.blockID isEqual:NormalizeForComparison(s.sourceText)],@"inline text keeps original normalized identity, full-width epoch, real line structure and empty translation fallback");Check(CGRectEqualToRect(s.lineBoxes[0].rectValue,CGRectMake(0,.9,1,.05))&&CGRectEqualToRect(s.lineBoxes[1].rectValue,CGRectMake(0,MAX(0.0,.9-1*.05),1,.05)),@"canonical original per-kept-line approximation remains unchanged");Check([[f.events subarrayWithRange:NSMakeRange(0,4)]isEqual:@[@"capture-enabled",@"capture-get",@"epoch",@"record"]]&&[f.learning.recordedText isEqual:s.sourceText]&&f.learning.recordedKind==FYSentenceKindSnapshot,@"input source then native epoch are read before original learning Snapshot record");Check([s.sentenceID isEqual:@"recorded"]&&s.version==6&&d.inlineReturnSnapshot==s&&[d.inlineReturnSourceText isEqual:s.sourceText],@"same snapshot object receives original DB identity/version and becomes both current/return references");
 f.mainDraft.text=@"retained main";f.overlayDraft.text=@"retained overlay";[f.session send:@"pending same block"];cancels=f.chatAnalyzer.cancels;cached=Result();d.quickSentenceAnalysis=cached;d.quickSentenceAnalysisError=@"cached error";d.quickSentenceAnalysisSource=@"different analysis source";d.quickSentenceAnalysisTranslation=@"cached translation";d.quickSelectedGrammarIndex=1;d.quickSentenceScrollOffset=33;d.quickSentenceAnalyzing=NO;FYInlineBlockSnapshot*same=Snapshot(s.blockID,@"existing",11,@" same block new text ",@"same block translation");records=f.learning.records;[f.events removeAllObjects];[d openInlineLearningWithSnapshot:same];Check(d.inlineBlockSnapshot==same&&d.inlineReturnSnapshot==same&&[same.sourceText isEqual:@"same block new text"]&&same.version==11&&f.learning.records==records,@"opening same block uses blockID only, mutates/saves exact input snapshot and preserves existing identity");Check(d.quickSentenceAnalysis==cached&&[d.quickSentenceAnalysisError isEqual:@"cached error"]&&d.quickSelectedGrammarIndex==1&&d.quickSentenceScrollOffset==33&&f.chatAnalyzer.cancels==cancels&&f.session.sending&&[f.mainDraft.text isEqual:@"retained main"]&&[f.overlayDraft.text isEqual:@"retained overlay"],@"same-block open preserves cached analysis despite analysisSource mismatch, scroll, ongoing answer and both drafts");ChatReply(f);
 FYInlineBlockSnapshot*other=Snapshot(@"other-block",@"other-id",12,@" other text ",nil);d.quickSentenceAnalyzing=YES;[f.events removeAllObjects];[d openInlineLearningWithSnapshot:other];Check(d.inlineBlockSnapshot==other&&d.inlineReturnSnapshot==other&&d.quickSentenceIsInlineBlock&&d.quickSentenceRequested&&!d.studyChatOverlayRequested&&[d.quickSentenceSource isEqual:@"other text"]&&[d.quickSentenceTranslation isEqual:@""]&&[d.quickSentenceID isEqual:@"other-id"]&&d.quickSentenceVersion==12,@"different block writes current/return/quick state with original trimmed source and ID/version");Check(!d.quickSentenceAnalysis&&!d.quickSentenceAnalysisError&&d.quickSelectedGrammarIndex==0&&[d.quickSentenceAnalysisSource isEqual:@""]&&[d.quickSentenceAnalysisTranslation isEqual:@""]&&d.quickSentenceScrollOffset==0&&[f.session.source isEqual:@"other text"]&&[f.mainDraft.text isEqual:@""]&&[f.overlayDraft.text isEqual:@""],@"new block resets original analysis/caches/scroll and explicitly binds existing chat/clears drafts");Check([f.events indexOfObject:@"cancel"]<[f.events indexOfObject:@"start"]&&[f.events indexOfObject:@"overlay-set"]<[f.events indexOfObject:@"render"],@"new block cancellation and both draft clears precede render");
 // Return uses a stricter sameBlock gate than opening the same block.
 cached=Result();d.quickSentenceAnalysis=cached;d.quickSentenceAnalysisSource=other.sourceText;d.quickSentenceAnalysisError=@"saved error";d.quickSelectedGrammarIndex=1;d.quickSentenceAnalyzing=NO;f.mainDraft.text=@"return draft";cancels=f.chatAnalyzer.cancels;[f.events removeAllObjects];[d returnFromStudyChatToInlineLearning:nil];Check(d.quickSentenceAnalysis==cached&&[d.quickSentenceAnalysisError isEqual:@"saved error"]&&d.quickSelectedGrammarIndex==1&&f.chatAnalyzer.cancels==cancels&&[f.mainDraft.text isEqual:@"return draft"],@"same block and same analysis source return preserves exact cached result/error/index, session and draft");Check([Tail(f.events,4)isEqual:@[@"restore-scroll",@"foreground",@"panel-get",@"focus"]],@"return ends with original restore/foreground/native panel read/focus actions");Check([f.events indexOfObject:@"render"]<[f.events indexOfObject:@"restore-scroll"]&&[f.events indexOfObject:@"restore-scroll"]<[f.events indexOfObject:@"focus"]&&![f.events containsObject:@"analyze"],@"return renders, restores saved scroll, then focuses without reanalysis");
 d.quickSentenceAnalysisSource=@"different";[f.events removeAllObjects];[d returnFromStudyChatToInlineLearning:nil];Check(!d.quickSentenceAnalysis&&!d.quickSentenceAnalysisError&&d.quickSelectedGrammarIndex==0&&[f.events.lastObject isEqual:@"analyze"]&&![f.events containsObject:@"cancel"],@"same block different analysis source return clears result/error/index and analyzes without adding cancel");d.quickSentenceAnalyzing=NO;d.inlineReturnSnapshot=nil;[f.events removeAllObjects];[d returnFromStudyChatToInlineLearning:nil];Check(f.events.count==0,@"missing return snapshot has no native or service effects");d.inlineReturnSnapshot=Snapshot(@"empty",nil,0,@"",nil);[d returnFromStudyChatToInlineLearning:nil];Check(f.events.count==0,@"empty return source has no effects");
 // Workspace carries values captured before close; selected index is still read after close.
 d.quickSentenceID=@"displayed";d.quickSentenceVersion=17;d.quickSentenceSource=@"fixed source";d.quickSentenceTranslation=@"fixed translation";cached=Result();d.quickSentenceAnalysis=cached;d.quickSentenceAnalysisSource=@"fixed source";d.quickSelectedGrammarIndex=1;d.analysisRequestGeneration=4;__weak id<StudyNavigationDriver> weakD=d;f.onClose=^{weakD.quickSentenceAnalysis=nil;weakD.quickSentenceID=@"later";weakD.quickSentenceSource=@"later source";weakD.quickSelectedGrammarIndex=7;};[f.events removeAllObjects];[d openStudyWorkspace:nil];f.onClose=nil;FYAnalysisResult*cloned=d.currentAnalysis;Check([f.learning.selected.sentenceID isEqual:@"displayed"]&&f.learning.selected.version==17&&[f.learning.selected.sourceText isEqual:@"fixed source"]&&[f.learning.selected.translation isEqual:@"fixed translation"]&&d.analysisRequestGeneration==5,@"workspace uses original captured display identity/text/version after close reentry changes quick state");Check(cloned!=cached&&cloned.schemaVersion==cached.schemaVersion&&cloned.grammar==cached.grammar&&cloned.vocabulary==cached.vocabulary&&cloned.structureParts==cached.structureParts&&[cloned.sentenceNote isEqual:cached.sentenceNote]&&[cloned.structureTitle isEqual:cached.structureTitle]&&[cloned.sentenceID isEqual:@"displayed"]&&cloned.version==17&&cloned.status==FYAnalysisStatusSuccess&&d.selectedGrammarIndex==7&&!f.analyzeBusy,@"workspace retains captured result through close, copies original fields into new fixed identity result and reads selected index at original late point");Check([f.events isEqual:@[@"page",@"main-window-get",@"main-activate",@"close",@"select-fixed",@"clear-main",@"learning-source",@"learning-status",@"main-idle",@"grammar-refresh"]],@"workspace activates before capture/close, then original select/clear/source/status/result refresh sequence");
 d.quickSentenceID=@"displayed";d.quickSentenceSource=@"fixed source";d.quickSentenceAnalysisSource=@"mismatch";NSUInteger mainAnalyses=f.currentAnalyses;[d openStudyWorkspace:nil];Check(f.currentAnalyses==mainAnalyses+1,@"incompatible quick result triggers existing main analysis instead of reuse");d.quickSentenceID=@"";NSUInteger selections=f.learning.selections;[f.events removeAllObjects];[d openStudyWorkspace:nil];Check(f.learning.selections==selections&&[f.events isEqual:@[@"page",@"main-window-get",@"main-activate",@"close"]],@"empty workspace identity still activates and closes before original empty gate");
 Check(!f.identities.count&&!f.chatAnalyzer.replies.count&&f.otherAnalyzer.cancels==0,@"all held operations consumed and unrelated analyzer/cancel scope untouched");app=dlsym(RTLD_DEFAULT,"NSApp");Check(!app||!*app,@"all seven real navigation algorithms remain headless");
}
static void RunStudyNavigationLease(NavDriverFactory factory){StudyNavigationFacts*f=[StudyNavigationFacts new];__weak id weakSource;@autoreleasepool{id<StudyNavigationDriver>d=factory(f);weakSource=d;[d showQuickSentence:nil];}Check(weakSource!=nil,@"held identity callback preserves original strong concrete source lease");@autoreleasepool{IdentityReply(f,Identity(@"lease",2,@"lease text",nil));}Check(!weakSource,@"navigation source releases after held callback delivery, no idle receiver retention");}
