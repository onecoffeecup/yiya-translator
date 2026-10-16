#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "presentation/FYCollectionReviewCoordinator.h"
static NSUInteger checks;
static void Check(BOOL ok, NSString *message) { checks++; if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);} }
@interface CollectionFieldFact : NSObject
@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,copy) NSString *stringValue;
@property(nonatomic) BOOL hidden;
@property(nonatomic,copy) void(^onText)(NSString *);
@end
@implementation CollectionFieldFact
@synthesize stringValue=_stringValue,hidden=_hidden;
- (void)setStringValue:(NSString *)value { _stringValue=[value copy];[self.events addObject:[self.name stringByAppendingString:@"-text"]];if(self.onText)self.onText(value); }
- (void)setHidden:(BOOL)value { _hidden=value;[self.events addObject:[NSString stringWithFormat:@"%@-hidden-%d",self.name,value]]; }
@end
@interface CollectionStoreBoundary : NSObject
@property(nonatomic,strong) NSMutableArray *events,*fetches,*writes,*deletes;
@property(nonatomic,copy) NSString *writtenID,*deletedID;
@property(nonatomic) FYReviewStatus writtenStatus;
@end
@implementation CollectionStoreBoundary
- (instancetype)init{if((self=[super init])){_fetches=[NSMutableArray new];_writes=[NSMutableArray new];_deletes=[NSMutableArray new];}return self;}
- (void)fetchVocabularyListWithCompletion:(void(^)(NSArray *,NSError *))completion{[self.events addObject:@"fetch"];[self.fetches addObject:[completion copy]];}
- (void)updateReviewStatus:(FYReviewStatus)status forVocabulary:(NSString *)identifier completion:(void(^)(NSError *))completion{self.writtenID=identifier;self.writtenStatus=status;[self.events addObject:@"update"];[self.writes addObject:[completion copy]];}
- (void)deleteVocabulary:(NSString *)identifier completion:(void(^)(NSError *))completion{self.deletedID=identifier;[self.events addObject:@"delete"];[self.deletes addObject:[completion copy]];}
@end
@interface CollectionReviewFacts : NSObject
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) CollectionStoreBoundary *store;
@property(nonatomic,strong) CollectionFieldFact *word,*meaning,*prompt,*list,*empty;
@property(nonatomic) NSUInteger summaries,rebuilds,grammarRefreshes;
@property(nonatomic,copy) void(^onSummary)(void);
@property(nonatomic,copy) void(^onRebuild)(void);
@end
@implementation CollectionReviewFacts
- (instancetype)init{if((self=[super init])){_events=[NSMutableArray new];_store=[CollectionStoreBoundary new];_store.events=_events;NSMutableArray *fields=[NSMutableArray new];for(NSString*n in @[@"word",@"meaning",@"prompt",@"list",@"empty"]){CollectionFieldFact*f=[CollectionFieldFact new];f.name=n;f.events=_events;f.stringValue=@"unchanged";[fields addObject:f];}_word=fields[0];_meaning=fields[1];_prompt=fields[2];_list=fields[3];_empty=fields[4];[_events removeAllObjects];}return self;}
@end
@protocol CollectionReviewDriver <NSObject>
@property(nonatomic,strong) NSArray<FYVocabularyEntry *> *reviewList;
@property(nonatomic) NSInteger reviewIndex;
@property(nonatomic,strong) FYVocabularyEntry *reviewingEntry;
- (void)refreshVocabularyList;
- (void)nextReviewWord:(id)sender;
- (void)revealReviewMeaning:(id)sender;
- (void)markReviewKnown:(id)sender;
- (void)markReviewLearning:(id)sender;
- (void)setReviewStatus:(FYReviewStatus)status;
- (void)removeReviewWord:(id)sender;
@end
static NSError *Failure(void){return [NSError errorWithDomain:@"synthetic" code:6 userInfo:@{NSLocalizedDescriptionKey:@"合成错误"}];}
static FYVocabularyEntry *Word(NSString *identifier,NSString *surface){FYVocabularyEntry*w=[FYVocabularyEntry new];w.vocabularyID=identifier;w.surface=surface;w.reading=@"よみ";w.meaning=@"合成释义";return w;}
static void Fetch(CollectionReviewFacts*f,NSArray *entries,NSError*error){Check(f.store.fetches.count>0,@"expected held production fetch");void(^reply)(NSArray*,NSError*)=[f.store.fetches firstObject];[f.store.fetches removeObjectAtIndex:0];reply(entries,error);}
static void Write(CollectionReviewFacts*f,NSError*error){Check(f.store.writes.count>0,@"expected held production write");void(^reply)(NSError*)=[f.store.writes firstObject];[f.store.writes removeObjectAtIndex:0];reply(error);}
static void Delete(CollectionReviewFacts*f,NSError*error){Check(f.store.deletes.count>0,@"expected held production delete");void(^reply)(NSError*)=[f.store.deletes firstObject];[f.store.deletes removeObjectAtIndex:0];reply(error);}
static void RunReview(id<CollectionReviewDriver>s,CollectionReviewFacts*f){
 Check(!s.reviewList&&!s.reviewingEntry&&s.reviewIndex==0,@"cold review preserves nil state and creates no store request");
 [s nextReviewWord:nil];Check([f.prompt.stringValue isEqual:@"正在加载收藏…"]&&[f.events isEqual:@[@"prompt-text",@"fetch"]],@"nil list prompts then loads without selecting");
 Fetch(f,nil,Failure());Check(!s.reviewList&&[f.list.stringValue isEqual:@"加载收藏失败：合成错误"]&&!f.empty.hidden&&!f.list.hidden,@"load failure leaves nil data and exposes original error");
 Check(f.summaries==0&&f.rebuilds==0&&f.grammarRefreshes==0,@"load error returns before followup refreshes");
 [f.events removeAllObjects];s.reviewList=@[];[s nextReviewWord:nil];Check([f.events isEqual:@[@"prompt-text"]]&&[f.prompt.stringValue isEqual:@"没有可复习的词条"],@"empty list does not reload or select");
 FYVocabularyEntry*a=Word(@"a",@"合成語😀"),*b=Word(@"b",@"二番");NSMutableArray*list=[NSMutableArray arrayWithObjects:a,b,nil];s.reviewList=list;
 Check(s.reviewList==list,@"review list retains original mutable array alias");[list addObject:Word(@"c",@"三番")];Check(s.reviewList.count==3,@"external list mutation remains visible");
 s.reviewIndex=-7;[f.events removeAllObjects];[s nextReviewWord:nil];Check(s.reviewingEntry==a&&s.reviewIndex==1,@"canonical negative-index selection uses first entry and next index");
 Check(!f.word.hidden&&f.meaning.hidden&&[f.word.stringValue isEqual:a.surface]&&[f.meaning.stringValue isEqual:@""],@"next word reveals source and hides/resets meaning");
 Check([f.events isEqual:@[@"word-hidden-0",@"meaning-hidden-1",@"word-text",@"meaning-text",@"prompt-text"]],@"original individual native write order");
 [s nextReviewWord:nil];Check(s.reviewingEntry==b&&s.reviewIndex==2,@"next follows list order");s.reviewIndex=99;[s nextReviewWord:nil];Check(s.reviewingEntry==a&&s.reviewIndex==1,@"canonical out-of-range index wraps");
 [s revealReviewMeaning:nil];Check(!f.meaning.hidden&&[f.meaning.stringValue isEqual:@"（よみ） 合成释义"],@"reading/meaning exact format");
 a.reading=@"";a.meaning=nil;[s revealReviewMeaning:nil];Check([f.meaning.stringValue isEqual:@" （暂无释义）"],@"nil meaning uses fallback and original leading space");a.meaning=@"";[s revealReviewMeaning:nil];Check([f.meaning.stringValue isEqual:@" "],@"empty meaning is distinct from nil");
 s.reviewingEntry=nil;[f.events removeAllObjects];[s revealReviewMeaning:nil];[s markReviewKnown:nil];[s removeReviewWord:nil];Check([f.events isEqual:@[@"prompt-text",@"prompt-text",@"prompt-text"]]&&f.store.writes.count==0&&f.store.deletes.count==0,@"missing entry guards reveal/mark/remove without persistence");
 s.reviewingEntry=a;s.reviewIndex=5;[s refreshVocabularyList];NSUInteger oldSummary=f.summaries,oldRebuild=f.rebuilds;Fetch(f,nil,Failure());Check(s.reviewList==list&&s.reviewingEntry==a&&s.reviewIndex==5&&f.summaries==oldSummary&&f.rebuilds==oldRebuild,@"failed refresh retains all existing review state");
 FYVocabularyEntry*replacement=Word(@"a",@"同ID新对象");NSMutableArray*fresh=[NSMutableArray arrayWithObjects:b,replacement,nil];[s refreshVocabularyList];[f.events removeAllObjects];Fetch(f,fresh,nil);Check(s.reviewList==fresh&&s.reviewingEntry==replacement&&s.reviewIndex==0,@"refresh retains raw array and rebinds by ID to current instance");
 Check([f.events isEqual:@[@"empty-hidden-1",@"summary",@"cards",@"list-text",@"list-hidden-1",@"grammar"]],@"success refresh order including cards before final list label");
 s.reviewIndex=-1;[s refreshVocabularyList];Fetch(f,fresh,nil);Check(s.reviewIndex==0,@"original signed/unsigned comparison resets negative index on refresh");
 s.reviewingEntry=a;[s refreshVocabularyList];[f.events removeAllObjects];Fetch(f,@[b],nil);Check(!s.reviewingEntry&&f.word.hidden&&f.meaning.hidden&&[f.word.stringValue isEqual:@""]&&[f.meaning.stringValue isEqual:@""],@"disappeared entry clears both native labels and state");
 Check([f.prompt.stringValue isEqual:@"这个词已取消收藏，请点「下一个词」。"]&&[f.events indexOfObject:@"prompt-text"]<[f.events indexOfObject:@"cards"],@"disappearance prompt precedes rebuilding cards");
 [s refreshVocabularyList];Fetch(f,nil,nil);Check(s.reviewList&&s.reviewList.count==0&&s.reviewIndex==0&&!s.reviewingEntry&&!f.empty.hidden&&!f.list.hidden,@"nil fetch normalizes list to empty and resets review");Check([f.list.stringValue containsString:@"回到实时翻译页"]&&[f.word.stringValue isEqual:@""]&&[f.meaning.stringValue isEqual:@""],@"empty state preserves exact existing instructions and cleared text");
 // Reentrant native summary changes which reviewing entry is rebound, at the original point.
 s.reviewingEntry=a;__weak id<CollectionReviewDriver>ws=s;f.onSummary=^{ws.reviewingEntry=b;};[s refreshVocabularyList];Fetch(f,fresh,nil);f.onSummary=nil;Check(s.reviewingEntry==b,@"summary reentry occurs before current-entry ID lookup");
 __block BOOL rebuildSawOldLabel=NO;NSString*oldLabel=f.list.stringValue;f.onRebuild=^{rebuildSawOldLabel=[f.list.stringValue isEqual:oldLabel];};[s refreshVocabularyList];Fetch(f,@[],nil);f.onRebuild=nil;Check(rebuildSawOldLabel,@"native card rebuild sees pre-empty-branch label");
 s.reviewingEntry=a;[s markReviewKnown:nil];Check(f.store.writtenStatus==FYReviewStatusKnown&&[f.store.writtenID isEqual:@"a"],@"known action writes original selected ID/status");[f.events removeAllObjects];Write(f,Failure());Check([f.events isEqual:@[@"prompt-text"]]&&[f.prompt.stringValue isEqual:@"标记失败：合成错误"],@"mark failure does not reload");
 [s markReviewLearning:nil];Check(f.store.writtenStatus==FYReviewStatusLearning,@"learning action uses its own status");[f.events removeAllObjects];Write(f,nil);Check([f.events isEqual:@[@"fetch",@"prompt-text"]]&&[f.prompt.stringValue isEqual:@"已标记「还不熟」"],@"mark success initiates refresh before status prompt");Fetch(f,@[a],nil);
 [s markReviewKnown:nil];Write(f,nil);Check([f.prompt.stringValue isEqual:@"已标记「记住了」"],@"known success wording");Fetch(f,@[a],nil);
 [s removeReviewWord:nil];Check([f.store.deletedID isEqual:@"a"],@"delete uses selected stable ID");NSString*word=f.word.stringValue;Delete(f,Failure());Check(s.reviewingEntry==a&&[f.word.stringValue isEqual:word]&&[f.prompt.stringValue isEqual:@"取消收藏失败：合成错误"],@"delete failure retains selected state/text");
 [s removeReviewWord:nil];s.reviewingEntry=b;[f.events removeAllObjects];Delete(f,nil);Check(!s.reviewingEntry&&[f.word.stringValue isEqual:@""]&&[f.meaning.stringValue isEqual:@""]&&[f.events isEqual:@[@"word-text",@"meaning-text",@"fetch"]],@"original delete completion clears current state then reloads without added stale gate");Fetch(f,@[b],nil);
}
typedef id<CollectionReviewDriver>(^ReviewFactory)(CollectionReviewFacts*);
static void RunLeases(ReviewFactory factory){
 for(NSUInteger kind=0;kind<2;kind++){
  CollectionReviewFacts*f=[CollectionReviewFacts new];__weak id weak;
  @autoreleasepool{id<CollectionReviewDriver>s=factory(f);weak=s;s.reviewingEntry=Word(@"lease",@"保持");if(kind==0)[s refreshVocabularyList];else[s setReviewStatus:FYReviewStatusKnown];}
  Check(weak!=nil,@"original fetch/update callback holds concrete native source");
  @autoreleasepool{if(kind==0)Fetch(f,nil,Failure());else Write(f,Failure());}
  Check(weak==nil,@"completed callback releases original source lease");
 }
 CollectionReviewFacts*f=[CollectionReviewFacts new];__weak id weak;
 @autoreleasepool{id<CollectionReviewDriver>s=factory(f);weak=s;s.reviewingEntry=Word(@"weak",@"释放");[s removeReviewWord:nil];}
 Check(weak==nil&&f.store.deletes.count==1,@"delete callback preserves weak source and does not keep page alive");Delete(f,nil);Check(f.store.fetches.count==0,@"late weak delete after page release does not reload");
}
