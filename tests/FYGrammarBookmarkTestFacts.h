#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "presentation/FYGrammarInteractionCoordinator.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
static FYGrammarItem *Item(NSString *name){FYGrammarItem *i=[FYGrammarItem new];i.name=name;return i;}
static FYAnalysisResult *Result(NSArray *items){FYAnalysisResult *r=[FYAnalysisResult new];r.sentenceID=@"sentence";r.version=3;r.grammar=items;return r;}
@interface BookmarkSenderFact : NSObject
@property(nonatomic) NSInteger index;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,copy) void (^onRead)(void);
- (NSInteger)tag;
@end
@implementation BookmarkSenderFact
- (NSInteger)tag{[self.events addObject:@"tag"];if(self.onRead)self.onRead();return self.index;}
@end
@interface BookmarkButtonFact : NSObject
@property(nonatomic,getter=isEnabled) BOOL enabled;
@property(nonatomic,strong) NSMutableArray *events;
@end
@implementation BookmarkButtonFact
@synthesize enabled=_enabled;
- (BOOL)isEnabled{[self.events addObject:@"enabled-get"];return _enabled;}
- (void)setEnabled:(BOOL)value{_enabled=value;[self.events addObject:value?@"enable":@"disable"];}
@end
@interface BookmarkFieldFact : NSObject
@property(nonatomic,copy) NSString *stringValue;
@property(nonatomic,strong) NSMutableArray *events;
@end
@implementation BookmarkFieldFact
@synthesize stringValue=_stringValue;
- (void)setStringValue:(NSString *)text{_stringValue=[text copy];[self.events addObject:@"status"];}
@end
@interface BookmarkLearningBoundary : NSObject
@property(nonatomic,copy) NSString *currentSentenceID;
@property(nonatomic) NSInteger currentVersion;
@property(nonatomic,weak) FYGrammarItem *requestedItem;
@property(nonatomic,strong) NSMutableArray *events,*replies;
@property(nonatomic) NSUInteger calls,cancels;
- (void)bookmarkGrammar:(FYGrammarItem *)item completion:(void (^)(NSError *))completion;
@end
@implementation BookmarkLearningBoundary
- (void)bookmarkGrammar:(FYGrammarItem *)item completion:(void (^)(NSError *))completion{self.calls++;self.requestedItem=item;[self.events addObject:@"learning"];[self.replies addObject:[completion copy]];}
- (void)cancelAll{self.cancels++;}
@end
@interface BookmarkStoreBoundary : NSObject
@property(nonatomic,copy) NSString *deletedID;
@property(nonatomic,strong) NSMutableArray *events,*replies;
@property(nonatomic) NSUInteger calls,cancels;
- (void)deleteGrammarBookmark:(NSString *)identifier completion:(void (^)(NSError *))completion;
@end
@implementation BookmarkStoreBoundary
- (void)deleteGrammarBookmark:(NSString *)identifier completion:(void (^)(NSError *))completion{self.calls++;self.deletedID=identifier;[self.events addObject:@"delete"];[self.replies addObject:[completion copy]];}
- (void)cancelAll{self.cancels++;}
@end
@interface GrammarBookmarkFacts : NSObject
@property(nonatomic,strong) FYGrammarInteractionCoordinator *core;
@property(nonatomic,strong) BookmarkLearningBoundary *learning;
@property(nonatomic,strong) BookmarkStoreBoundary *store;
@property(nonatomic,strong) BookmarkButtonFact *button;
@property(nonatomic,strong) BookmarkFieldFact *field;
@property(nonatomic,strong) FYGrammarItem *selected;
@property(nonatomic,strong) FYGrammarBookmark *existing;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic) NSUInteger refreshed,selectedReads;
@property(nonatomic,copy) void (^onSelectedRead)(void);
- (BOOL)analysisMatchesCurrentSentence;
- (FYAnalysisResult *)currentAnalysis;
- (FYGrammarItem *)selectedGrammarItem;
- (FYGrammarBookmark *)bookmarkForCurrentGrammar;
- (void)refreshGrammarBookmarks:(id)sender;
@end
@implementation GrammarBookmarkFacts
- (instancetype)init{if((self=[super init])){_core=[FYGrammarInteractionCoordinator new];_events=[NSMutableArray new];_learning=[BookmarkLearningBoundary new];_learning.events=_events;_learning.replies=[NSMutableArray new];_learning.currentSentenceID=@"sentence";_learning.currentVersion=3;_store=[BookmarkStoreBoundary new];_store.events=_events;_store.replies=[NSMutableArray new];_button=[BookmarkButtonFact new];_button.events=_events;_button.enabled=YES;_field=[BookmarkFieldFact new];_field.events=_events;_field.stringValue=@"unchanged";}return self;}
- (BOOL)analysisMatchesCurrentSentence{[self.events addObject:@"gate"];return self.core.currentAnalysis&&[FYLearningCoordinator analysisMatchesSentenceID:self.core.currentAnalysis.sentenceID version:self.core.currentAnalysis.version currentSentenceID:self.learning.currentSentenceID currentVersion:self.learning.currentVersion];}
- (FYAnalysisResult *)currentAnalysis{[self.events addObject:@"analysis"];return self.core.currentAnalysis;}
- (FYGrammarItem *)selectedGrammarItem{self.selectedReads++;[self.events addObject:@"selected"];if(self.onSelectedRead)self.onSelectedRead();return self.selected;}
- (FYGrammarBookmark *)bookmarkForCurrentGrammar{[self.events addObject:@"existing"];return self.existing;}
- (void)refreshGrammarBookmarks:(id)sender{Check(sender==nil,@"refresh keeps original nil action payload");self.refreshed++;[self.events addObject:@"refresh"];}
@end
@protocol GrammarBookmarkDriver <NSObject>
- (void)performItem:(BookmarkSenderFact *)sender;
- (void)performSelected;
@end
typedef id<GrammarBookmarkDriver> (^BookmarkDriverFactory)(GrammarBookmarkFacts *facts);
static void Finish(NSMutableArray *replies,NSError *error){Check(replies.count>0,@"held original service completion exists");void(^reply)(NSError *)=replies.firstObject;[replies removeObjectAtIndex:0];reply(error);}
static NSError *Failure(void){return [NSError errorWithDomain:@"synthetic" code:3 userInfo:@{NSLocalizedDescriptionKey:@"合成错误"}];}
static void Reset(GrammarBookmarkFacts *f,FYAnalysisResult *result,FYGrammarItem *item){f.core.currentAnalysis=result;f.selected=item;f.existing=nil;f.learning.currentSentenceID=@"sentence";f.learning.currentVersion=3;f.button.enabled=YES;f.field.stringValue=@"unchanged";f.selectedReads=0;f.onSelectedRead=nil;[f.events removeAllObjects];}
static void RunGrammarBookmarkFixture(id<GrammarBookmarkDriver>d,GrammarBookmarkFacts *f){
 void **app=dlsym(RTLD_DEFAULT,"NSApp");Check(!app||!*app,@"bookmark fixture initializes no application/window/control/database");FYGrammarItem *a=Item(@"条目甲"),*b=Item(@"条目乙");FYAnalysisResult *result=Result(@[a,b]);BookmarkSenderFact *sender=[BookmarkSenderFact new];sender.events=f.events;sender.index=1;Reset(f,result,a);NSUInteger calls=f.learning.calls;
 f.learning.currentVersion=4;[d performItem:sender];Check(f.learning.calls==calls&&[f.events isEqual:@[@"gate"]],@"inapplicable item returns before index or analysis argument reads");Reset(f,result,a);sender.index=-1;[d performItem:sender];Check(f.learning.calls==calls&&[f.events isEqual:@[@"gate",@"analysis",@"tag"]],@"negative index uses original no-fallback gate and single original parameter evaluation");sender.index=2;[f.events removeAllObjects];[d performItem:sender];Check(f.learning.calls==calls,@"out-of-range item creates no task");
 Reset(f,result,a);sender.index=1;[d performItem:sender];Check(f.learning.calls==calls+1&&f.learning.requestedItem==b&&[f.events isEqual:@[@"gate",@"analysis",@"tag",@"learning"]],@"valid item keeps gate→analysis array→tag→canonical item/service sequence");Check([f.field.stringValue isEqual:@"unchanged"]&&f.button.isEnabled,@"row request leaves existing status/enable unchanged while waiting");[f.events removeAllObjects];Finish(f.learning.replies,Failure());Check([f.field.stringValue isEqual:@"收藏失败：合成错误"]&&f.refreshed==0&&[f.events isEqual:@[@"status"]],@"row error keeps exact error text and does not refresh");
 Reset(f,result,a);[d performItem:sender];f.core.currentAnalysis=nil;f.selected=nil;[f.events removeAllObjects];Finish(f.learning.replies,nil);Check([f.field.stringValue isEqual:@"已收藏语法「条目乙」。"]&&[f.events isEqual:@[@"status",@"refresh"]],@"original row completion still reports captured item after context change, without new stale gate");
 Reset(f,result,a);sender.index=0;__weak GrammarBookmarkFacts *weakFacts=f;sender.onRead=^{weakFacts.core.currentAnalysis=Result(@[b]);};[d performItem:sender];Check(f.learning.requestedItem==a&&[f.events isEqual:@[@"gate",@"analysis",@"tag",@"learning"]],@"tag reentry changes current analysis only after canonical array argument captured");sender.onRead=nil;Finish(f.learning.replies,nil);
 Reset(f,result,a);[d performItem:nil];Check(f.learning.requestedItem==a,@"nil original sender still reads zero index through native provider");Finish(f.learning.replies,nil);
 Reset(f,result,a);f.core.currentAnalysis=nil;[d performSelected];Check([f.events isEqual:@[@"gate"]],@"selected operation short-circuits before item/button for no analysis");Reset(f,result,nil);[d performSelected];Check([f.events isEqual:@[@"gate",@"selected"]],@"nil selected item short-circuits before enabled getter");Reset(f,result,a);f.button.enabled=NO;[f.events removeAllObjects];[d performSelected];Check([f.events isEqual:@[@"gate",@"selected",@"enabled-get"]],@"disabled native action preserves original short-circuit and sends no request");
 Reset(f,result,a);calls=f.learning.calls;[d performSelected];Check(f.learning.calls==calls+1&&f.learning.requestedItem==a&&[f.events isEqual:@[@"gate",@"selected",@"enabled-get",@"selected",@"existing",@"disable",@"learning"]],@"selected operation queries item twice, snapshots existing then disables before service");[f.events removeAllObjects];[d performSelected];Check(f.learning.calls==calls+1&&[f.events isEqual:@[@"gate",@"selected",@"enabled-get"]],@"duplicate selected request is blocked by original button gate");[f.events removeAllObjects];Finish(f.learning.replies,nil);Check(f.button.isEnabled&&[f.field.stringValue isEqual:@"语法与原句已收藏。"]&&[[f.events subarrayWithRange:NSMakeRange(0,5)]isEqual:@[@"selected",@"gate",@"enable",@"status",@"refresh"]],@"matching selected completion keeps pointer/identity gates then enable/status/refresh order");
 Reset(f,result,a);[d performSelected];Finish(f.learning.replies,Failure());Check(f.button.isEnabled&&[f.field.stringValue isEqual:@"收藏操作失败：合成错误"],@"selected error reenables and retains exact error reason");
 Reset(f,result,a);FYGrammarBookmark *existing=[FYGrammarBookmark new];existing.bookmarkID=@"bookmark-id";f.existing=existing;NSUInteger deletes=f.store.calls;calls=f.learning.calls;[d performSelected];Check(f.store.calls==deletes+1&&f.learning.calls==calls&&[f.store.deletedID isEqual:@"bookmark-id"],@"existing selected bookmark uses unique store delete, not learning insertion");f.existing=nil;Finish(f.store.replies,nil);Check([f.field.stringValue isEqual:@"已取消语法收藏。"]&&f.button.isEnabled,@"delete callback uses captured existing snapshot after query changes");
 Reset(f,result,a);[d performSelected];f.selected=b;[f.events removeAllObjects];Finish(f.learning.replies,Failure());Check([f.events isEqual:@[@"selected",@"refresh"]]&&[f.field.stringValue isEqual:@"unchanged"],@"stale item callback only refreshes and does not read gate/update status");Check(!f.button.isEnabled,@"stale item callback does not enable a replacement operation");
 Reset(f,result,a);[d performSelected];f.learning.currentVersion=4;[f.events removeAllObjects];Finish(f.learning.replies,nil);Check([f.events isEqual:@[@"selected",@"gate",@"refresh"]]&&[f.field.stringValue isEqual:@"unchanged"],@"same item stale sentence version only refreshes");Check(!f.button.isEnabled,@"stale version completion preserves disabled state");
 Reset(f,result,a);f.onSelectedRead=^{if(weakFacts.selectedReads==2)weakFacts.selected=b;};[d performSelected];Check(f.learning.requestedItem==b&&f.selectedReads==2,@"second selected getter is reevaluated after native enabled read");f.onSelectedRead=nil;Finish(f.learning.replies,nil);
 Reset(f,result,a);calls=f.learning.calls;[d performItem:sender];[d performItem:sender];Check(f.learning.calls==calls+2&&f.learning.replies.count==2,@"row actions preserve original independent repeated requests");Finish(f.learning.replies,nil);Finish(f.learning.replies,nil);Check(f.learning.cancels==0&&f.store.cancels==0&&f.learning.replies.count==0&&f.store.replies.count==0,@"bookmark operations add no cancellation scope or leftover service callbacks");app=dlsym(RTLD_DEFAULT,"NSApp");Check(!app||!*app,@"actual Foundation/native adapter paths completed with no UI initialization");
}
static void RunGrammarBookmarkLeases(BookmarkDriverFactory factory){
 GrammarBookmarkFacts *f=[GrammarBookmarkFacts new];__weak id weakSource;__weak BookmarkSenderFact *weakSender;__weak FYGrammarItem *weakItem;
 @autoreleasepool{id<GrammarBookmarkDriver>s=factory(f);weakSource=s;FYGrammarItem *item=Item(@"租约条目");weakItem=item;f.core.currentAnalysis=Result(@[item]);f.selected=item;BookmarkSenderFact *sender=[BookmarkSenderFact new];sender.events=f.events;weakSender=sender;[s performItem:sender];f.core.currentAnalysis=nil;f.selected=nil;}
 Check(weakSource!=nil&&weakItem!=nil,@"original row callback strongly leases concrete source and captured item");Check(!weakSender,@"native index provider is consumed synchronously and does not retain sender in async callback");@autoreleasepool{Finish(f.learning.replies,nil);}Check(!weakSource&&!weakItem,@"row source/item release after service completion is cleared and delivered");
 f=[GrammarBookmarkFacts new];__weak FYGrammarBookmark *weakExisting;
 @autoreleasepool{id<GrammarBookmarkDriver>s=factory(f);weakSource=s;FYGrammarItem *item=Item(@"选中租约");weakItem=item;f.core.currentAnalysis=Result(@[item]);f.selected=item;FYGrammarBookmark *existing=[FYGrammarBookmark new];existing.bookmarkID=@"lease-bookmark";weakExisting=existing;f.existing=existing;[s performSelected];f.core.currentAnalysis=nil;f.selected=nil;f.existing=nil;}
 Check(weakSource&&weakItem&&weakExisting,@"selected delete callback keeps original strong source/item/existing leases");@autoreleasepool{Finish(f.store.replies,nil);}Check(!weakSource&&!weakItem&&!weakExisting,@"selected/delete leases release after stale callback refresh");
}
