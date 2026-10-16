#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "presentation/FYCollectionQueryCoordinator.h"
#import "presentation/FYCollectionCardCoordinator.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
@interface CollectionValueFact : NSObject
@property(nonatomic,copy) NSString *stringValue,*title,*identifier;
@property(nonatomic) BOOL hidden,enabled;
@property(nonatomic) NSInteger tag,indexOfSelectedItem;
@property(nonatomic,strong) NSMutableArray *items,*events;
@property(nonatomic,copy) void(^onIdentifier)(void);
@property(nonatomic) NSUInteger identifierReads;
- (void)removeAllItems;
- (void)addItemWithTitle:(NSString *)title;
@end
@implementation CollectionValueFact
@synthesize identifier=_identifier;
- (NSString *)identifier{self.identifierReads++;if(self.onIdentifier)self.onIdentifier();return _identifier;}
- (void)setIdentifier:(NSString *)value{_identifier=[value copy];}
- (void)removeAllItems{[self.items removeAllObjects];}
- (void)addItemWithTitle:(NSString *)title{[self.items addObject:title];}
@end
@interface CollectionWorkflowStore : NSObject
@property(nonatomic,strong) NSMutableArray *history,*grammar,*sentences,*examples,*grammarDeletes,*updates,*wordDeletes,*toggles,*events;
@property(nonatomic,strong) FYRequestIdentity *toggleIdentity;
@property(nonatomic,copy) NSString *lastID;
@property(nonatomic) NSUInteger limit;
@property(nonatomic) FYReviewStatus status;
@end
@implementation CollectionWorkflowStore
- (instancetype)init{if((self=[super init])){_history=[NSMutableArray new];_grammar=[NSMutableArray new];_sentences=[NSMutableArray new];_examples=[NSMutableArray new];_grammarDeletes=[NSMutableArray new];_updates=[NSMutableArray new];_wordDeletes=[NSMutableArray new];_toggles=[NSMutableArray new];}return self;}
- (void)fetchRecentSentencesWithLimit:(NSUInteger)limit completion:(void(^)(NSArray*,NSError*))reply{self.limit=limit;[self.events addObject:@"fetch-history"];[self.history addObject:[reply copy]];}
- (void)fetchGrammarBookmarksWithCompletion:(void(^)(NSArray*,NSError*))reply{[self.events addObject:@"fetch-grammar"];[self.grammar addObject:[reply copy]];}
- (void)fetchSentenceBookmarks:(void(^)(NSArray*,NSError*))reply{[self.events addObject:@"fetch-sentences"];[self.sentences addObject:[reply copy]];}
- (void)fetchExamplesForVocabulary:(NSString*)word completion:(void(^)(NSArray*,NSError*))reply{self.lastID=word;[self.events addObject:@"fetch-examples"];[self.examples addObject:[reply copy]];}
- (void)deleteGrammarBookmark:(NSString*)word completion:(void(^)(NSError*))reply{self.lastID=word;[self.events addObject:@"delete-grammar"];[self.grammarDeletes addObject:[reply copy]];}
- (void)updateReviewStatus:(FYReviewStatus)status forVocabulary:(NSString*)word completion:(void(^)(NSError*))reply{self.status=status;self.lastID=word;[self.events addObject:@"update-word"];[self.updates addObject:[reply copy]];}
- (void)deleteVocabulary:(NSString*)word completion:(void(^)(NSError*))reply{self.lastID=word;[self.events addObject:@"delete-word"];[self.wordDeletes addObject:[reply copy]];}
- (void)toggleSentenceBookmark:(FYRequestIdentity*)identity completion:(void(^)(BOOL,NSError*))reply{self.toggleIdentity=identity;[self.events addObject:@"toggle-sentence"];[self.toggles addObject:[reply copy]];}
@end
@interface CollectionLearningBoundary : NSObject
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) FYSentenceRecord *history;
@property(nonatomic,copy) NSString *sentenceID,*source,*translation;
@property(nonatomic) NSInteger version;
@end
@implementation CollectionLearningBoundary
- (void)selectHistorySentence:(FYSentenceRecord*)record{self.history=record;[self.events addObject:@"select-history"];}
- (void)selectSentenceID:(NSString*)identifier version:(NSInteger)version sourceText:(NSString*)source translation:(NSString*)translation{self.sentenceID=identifier;self.version=version;self.source=source;self.translation=translation;[self.events addObject:@"select-sentence"];}
@end
@interface CollectionWorkflowFacts : NSObject
@property(nonatomic,strong) CollectionWorkflowStore *store;
@property(nonatomic,strong) CollectionLearningBoundary *learning;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) CollectionValueFact *grammarLabel,*mainButton,*quickButton,*statusLabel,*examplesLabel,*popup,*prompt;
@property(nonatomic,strong) FYAnalysisResult *analysis;
@property(nonatomic,strong) FYGrammarBookmark *mainBookmark;
@property(nonatomic,strong) NSArray *rawRendered;
@property(nonatomic,copy) NSString *quickID;
@property(nonatomic) BOOL pending,matches,bookmarked;
@property(nonatomic) NSUInteger summaries,rebuilds,quickUpdates,sentenceRefreshes,grammarRefreshes,vocabularyRefreshes;
@property(nonatomic,copy) void(^onSummary)(void);
@end
@implementation CollectionWorkflowFacts
- (instancetype)init{if((self=[super init])){_events=[NSMutableArray new];_store=[CollectionWorkflowStore new];_store.events=_events;_learning=[CollectionLearningBoundary new];_learning.events=_events;NSMutableArray*a=[NSMutableArray new];for(NSUInteger i=0;i<7;i++){CollectionValueFact*v=[CollectionValueFact new];v.stringValue=@"unchanged";v.title=@"unchanged";v.items=[NSMutableArray new];v.enabled=YES;[a addObject:v];}_grammarLabel=a[0];_mainButton=a[1];_quickButton=a[2];_statusLabel=a[3];_examplesLabel=a[4];_popup=a[5];_prompt=a[6];_quickID=@"quick";}return self;}
@end
@protocol CollectionWorkflowDriver <NSObject>
@property(nonatomic,strong) NSArray<FYSentenceRecord*> *historyRecords;
@property(nonatomic,strong) NSArray<FYGrammarBookmark*> *grammarBookmarks;
@property(nonatomic,strong) NSArray<FYVocabularyEntry*> *vocabularyExamplesList,*reviewList;
@property(nonatomic,copy) NSArray<FYRequestIdentity*> *savedSentences;
@property(nonatomic,strong) NSMutableSet<NSString*> *expandedWordCards;
@property(nonatomic,strong) NSMutableDictionary<NSString*,NSNumber*> *revealedMeanings,*wordExampleIndices;
@property(nonatomic) NSInteger wordCardsGeneration;
- (void)refreshHistory;
- (void)openHistoryAnalysis:(id)sender;
- (void)refreshGrammarBookmarks:(id)sender;
- (void)deleteGrammarBookmark:(id)sender;
- (void)refreshSavedSentences;
- (FYRequestIdentity*)savedSentenceForButton:(id)sender;
- (void)openSavedSentence:(id)sender;
- (void)removeSavedSentence:(id)sender;
- (void)refreshVocabularyExamplesPopup;
- (void)showVocabularyExamples:(id)sender;
- (FYVocabularyEntry*)wordForCardButton:(id)sender;
- (void)nextWordExample:(id)sender;
- (void)toggleWordMastered:(id)sender;
- (void)removeWordCard:(id)sender;
- (void)toggleSavedWordDetails:(id)sender;
- (void)toggleWordMeaning:(id)sender;
@end
static NSError*Failure(void){return[NSError errorWithDomain:@"synthetic" code:8 userInfo:@{NSLocalizedDescriptionKey:@"合成错误"}];}
static id Pop(NSMutableArray*a){Check(a.count>0,@"expected held boundary completion");id b=a[0];[a removeObjectAtIndex:0];return b;}
static void ReadReply(NSMutableArray*a,NSArray*v,NSError*e){void(^b)(NSArray*,NSError*)=Pop(a);b(v,e);}
static void WriteReply(NSMutableArray*a,NSError*e){void(^b)(NSError*)=Pop(a);b(e);}
static FYVocabularyEntry*Word(NSString*identifier){FYVocabularyEntry*w=[FYVocabularyEntry new];w.vocabularyID=identifier;w.surface=[@"合成詞" stringByAppendingString:identifier];w.meaning=@"合成释义";w.reading=@"ご";return w;}
static FYSentenceRecord*Record(NSString*identifier,NSString*text,NSInteger version){FYSentenceRecord*r=[FYSentenceRecord new];r.sentenceID=identifier;r.latestText=text;r.latestTranslation=@"合成译文";r.latestVersion=version;r.occurredAt=[NSDate dateWithTimeIntervalSince1970:100];return r;}
static FYRequestIdentity*Identity(NSString*identifier,NSInteger version){return[FYRequestIdentity identityWithSentenceID:identifier version:version requestID:@"fixture" sourceText:@"原句😀" translation:@"译文"];}
static CollectionValueFact*Button(NSString*identifier,NSInteger tag){CollectionValueFact*b=[CollectionValueFact new];b.identifier=identifier;b.tag=tag;b.enabled=YES;return b;}
static void RunWorkflow(id<CollectionWorkflowDriver>s,CollectionWorkflowFacts*f){
 Check(!s.historyRecords&&!s.grammarBookmarks&&!s.savedSentences&&!s.expandedWordCards,@"cold original state remains nil");
 [s refreshHistory];Check(f.store.limit==FYRecentSentenceLimit&&f.store.limit==5,@"history uses canonical five-sentence limit");ReadReply(f.store.history,nil,Failure());Check(!s.historyRecords,@"history error preserves nil data");
 FYSentenceRecord*a=Record(@"a",@"これは合成の長い原句です。",2),*b=Record(@"b",@"別の合成原句です。",3);[s refreshHistory];ReadReply(f.store.history,@[a,b],nil);Check(s.historyRecords.count==2&&s.historyRecords[0]==a,@"production display-history selection preserves current records");CollectionValueFact*button=Button(@"b",0);[f.events removeAllObjects];[s openHistoryAnalysis:button];Check(f.learning.history==b&&[f.events isEqual:@[@"select-history",@"source",@"status",@"clear-analysis",@"page0",@"analyze"]],@"history stable ID takes precedence and original navigation order includes clear");button.identifier=@"stale";[f.events removeAllObjects];[s openHistoryAnalysis:button];Check(f.events.count==0,@"stale history ID cannot open another row");button.identifier=@"";button.tag=0;[s openHistoryAnalysis:button];Check(f.learning.history==a,@"empty history ID retains index fallback");
 [s refreshHistory];ReadReply(f.store.history,nil,nil);Check(s.historyRecords.count==0,@"empty history result canonicalizes to empty");
 FYGrammarBookmark*g=[FYGrammarBookmark new];g.bookmarkID=@"g";g.name=@"合成语法";g.sourceTextSnapshot=@"原句";NSMutableArray*grammar=[NSMutableArray arrayWithObject:g];[f.events removeAllObjects];[s refreshGrammarBookmarks:nil];Check([f.events isEqual:@[@"fetch-sentences",@"fetch-grammar"]],@"grammar refresh starts sentence query before independent grammar query");ReadReply(f.store.sentences,nil,Failure());ReadReply(f.store.grammar,grammar,nil);Check(s.grammarBookmarks==grammar&&f.summaries>0&&f.quickUpdates==1,@"grammar result retains original strong array and updates summary/quick button");Check(f.grammarLabel.hidden&&[f.grammarLabel.stringValue isEqual:@""],@"nonempty grammar hides empty label");
 f.matches=YES;FYAnalysisResult*analysis=[FYAnalysisResult new];analysis.grammar=@[[FYGrammarItem new]];f.analysis=analysis;f.mainBookmark=g;[s refreshGrammarBookmarks:nil];ReadReply(f.store.sentences,nil,Failure());ReadReply(f.store.grammar,grammar,nil);Check([f.mainButton.title isEqual:@"已收藏 · 取消收藏"],@"matching grammar updates current bookmark title");f.mainBookmark=nil;[s refreshGrammarBookmarks:nil];ReadReply(f.store.sentences,nil,Failure());ReadReply(f.store.grammar,grammar,nil);Check([f.mainButton.title isEqual:@"收藏此语法"],@"matching unbookmarked grammar title");
 f.matches=NO;f.mainButton.title=@"preserve";[s refreshGrammarBookmarks:nil];ReadReply(f.store.sentences,nil,Failure());ReadReply(f.store.grammar,nil,Failure());Check(s.grammarBookmarks==grammar&&[f.grammarLabel.stringValue isEqual:@"语法收藏加载失败：合成错误"]&&[f.mainButton.title isEqual:@"preserve"],@"grammar failure preserves old list/main action");
 button=Button(@"",0);[s deleteGrammarBookmark:button];Check(f.store.grammarDeletes.count==0,@"empty bookmark ID is inert");button.identifier=@"g";[s deleteGrammarBookmark:button];Check([f.store.lastID isEqual:@"g"],@"delete uses stable grammar ID");WriteReply(f.store.grammarDeletes,Failure());Check(!f.grammarLabel.hidden&&[f.grammarLabel.stringValue isEqual:@"取消收藏失败：合成错误"],@"delete failure exposes original message");[s deleteGrammarBookmark:button];WriteReply(f.store.grammarDeletes,nil);ReadReply(f.store.sentences,nil,Failure());ReadReply(f.store.grammar,nil,nil);Check(s.grammarBookmarks&&s.grammarBookmarks.count==0,@"successful grammar delete refreshes original two queries");
 FYRequestIdentity*i=Identity(@"sentence",7);NSMutableArray*identities=[NSMutableArray arrayWithObject:i];[s refreshSavedSentences];ReadReply(f.store.sentences,identities,nil);Check(s.savedSentences!=identities&&s.savedSentences[0]==i,@"saved list copies array while preserving exact identity object");[identities removeAllObjects];Check(s.savedSentences.count==1,@"external mutable array changes do not change saved snapshot");Check(f.quickButton.enabled&&[f.quickButton.title isEqual:@"收藏这一句"],@"saved refresh updates quick bookmark controls");
 button=Button(@"sentence:6",0);Check([s savedSentenceForButton:button]==nil,@"saved lookup never falls back from stale version to index");button.identifier=@"sentence:7";Check([s savedSentenceForButton:button]==i,@"saved lookup binds ID and version");[f.events removeAllObjects];[s openSavedSentence:button];Check(f.learning.version==7&&[f.learning.sentenceID isEqual:@"sentence"]&&[f.events isEqual:@[@"select-sentence",@"source",@"status",@"page0",@"analyze"]],@"saved navigation keeps fixed version and does not clear analysis");
 f.pending=YES;[s removeSavedSentence:button];Check(f.store.toggles.count==0&&button.enabled,@"pending gate leaves sender alone");f.pending=NO;[s removeSavedSentence:button];Check(f.pending&&!button.enabled&&f.store.toggleIdentity==i,@"valid removal sets existing shared pending flag and disables sender");void(^toggle)(BOOL,NSError*)=Pop(f.store.toggles);toggle(NO,Failure());Check(!f.pending&&[f.statusLabel.stringValue isEqual:@"合成错误"]&&f.store.sentences.count==1,@"toggle completion clears pending then reports and refreshes even on error");ReadReply(f.store.sentences,nil,Failure());Check(s.savedSentences.count==1,@"sentence read error retains old snapshot");
 [s refreshSavedSentences];ReadReply(f.store.sentences,nil,nil);Check(s.savedSentences==nil,@"nil sentence result remains nil instead of new empty array");
 FYVocabularyEntry*w=Word(@"w"),*v=Word(@"v");NSMutableArray*words=[NSMutableArray arrayWithObjects:w,v,nil];s.reviewList=words;[s refreshVocabularyExamplesPopup];Check(s.vocabularyExamplesList==words&&[f.popup.items isEqual:@[w.surface,v.surface]],@"example choices retain review-array alias and original titles");f.popup.indexOfSelectedItem=-1;[s showVocabularyExamples:nil];Check(f.store.examples.count==0,@"negative popup index never starts query");f.popup.indexOfSelectedItem=8;[s showVocabularyExamples:nil];Check(f.store.examples.count==0,@"out-of-range popup index never starts query");f.popup.indexOfSelectedItem=1;[s showVocabularyExamples:nil];Check([f.store.lastID isEqual:@"v"],@"selected example query uses current entry stable ID");ReadReply(f.store.examples,nil,Failure());Check([f.examplesLabel.stringValue isEqual:@"读取例句失败：合成错误"],@"example query error wording");[s showVocabularyExamples:nil];ReadReply(f.store.examples,@[],nil);Check([f.examplesLabel.stringValue isEqual:@"该词条暂无例句。"],@"empty examples wording");FYVocabularyExample*example=[FYVocabularyExample new];example.sourceTextSnapshot=@"合成例句😀";example.translationSnapshot=@"翻译";[s showVocabularyExamples:nil];ReadReply(f.store.examples,@[example],nil);Check([f.examplesLabel.stringValue isEqual:@"• 合成例句😀\n译文：翻译\n"],@"example body exact Unicode/text formatting");s.reviewList=nil;[s refreshVocabularyExamplesPopup];Check(s.vocabularyExamplesList.count==0&&[f.popup.items isEqual:@[@"暂无词条"]],@"nil review list keeps existing empty popup placeholder");
 s.reviewList=words;button=Button(@"v",0);Check([s wordForCardButton:button]==v,@"word ID precedence over tag");button.identifier=@"stale";Check([s wordForCardButton:button]==nil,@"stale word ID does not select a different index");button.identifier=@"";button.tag=0;Check([s wordForCardButton:button]==w,@"word fallback only for absent ID");button.identifier=@"w";s.wordExampleIndices=nil;[s nextWordExample:button];Check([s.wordExampleIndices[@"w"] unsignedIntegerValue]==1&&f.rebuilds==1,@"next example lazily initializes map and rebuilds once");[s nextWordExample:button];Check([s.wordExampleIndices[@"w"] unsignedIntegerValue]==2&&f.rebuilds==2,@"next example increments current index");
 w.reviewStatus=FYReviewStatusKnown;[s toggleWordMastered:button];Check(f.store.status==FYReviewStatusLearning&&[f.store.lastID isEqual:@"w"],@"known word toggles to learning");WriteReply(f.store.updates,Failure());Check([f.prompt.stringValue isEqual:@"操作失败：合成错误"]&&f.vocabularyRefreshes==0,@"word update error preserves data and stops refresh");w.reviewStatus=FYReviewStatusNew;[s toggleWordMastered:button];Check(f.store.status==FYReviewStatusKnown,@"new word toggles to known");WriteReply(f.store.updates,nil);Check(f.vocabularyRefreshes==1,@"word update success refreshes vocabulary");[s removeWordCard:button];Check([f.store.lastID isEqual:@"w"],@"word removal uses selected ID");WriteReply(f.store.wordDeletes,Failure());Check(f.vocabularyRefreshes==1,@"word deletion failure does not reload");[s removeWordCard:button];WriteReply(f.store.wordDeletes,nil);Check(f.vocabularyRefreshes==2,@"word deletion success reloads");
 // Sender lifetime: input providers are synchronous and do not enter Store callbacks.
 __weak CollectionValueFact*weakButton;@autoreleasepool{CollectionValueFact*b=Button(@"w",0);weakButton=b;[s toggleWordMastered:b];}Check(!weakButton,@"word sender is not retained while async write is held");WriteReply(f.store.updates,nil);
}
typedef id<CollectionWorkflowDriver>(^WorkflowFactory)(CollectionWorkflowFacts*);
static void RunWorkflowLeases(WorkflowFactory factory){
 for(NSUInteger kind=0;kind<5;kind++){
  CollectionWorkflowFacts*f=[CollectionWorkflowFacts new];__weak id weak;@autoreleasepool{id<CollectionWorkflowDriver>s=factory(f);weak=s;s.reviewList=@[Word(@"w")];switch(kind){case 0:[s refreshHistory];break;case 1:[s refreshSavedSentences];break;case 2:[s deleteGrammarBookmark:Button(@"g",0)];break;case 3:[s toggleWordMastered:Button(@"w",0)];break;default:[s removeWordCard:Button(@"w",0)];break;}}
  Check(weak!=nil,@"original async query/operation keeps concrete receiver lease");@autoreleasepool{switch(kind){case 0:ReadReply(f.store.history,nil,Failure());break;case 1:ReadReply(f.store.sentences,nil,Failure());break;case 2:WriteReply(f.store.grammarDeletes,Failure());break;case 3:WriteReply(f.store.updates,Failure());break;default:WriteReply(f.store.wordDeletes,Failure());break;}}Check(!weak,@"completion releases source without an idle coordinator receiver");
 }
}
