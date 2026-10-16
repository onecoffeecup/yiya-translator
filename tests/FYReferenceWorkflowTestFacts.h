#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "presentation/FYReferenceQueryCoordinator.h"
#import "presentation/FYSourceHoverCoordinator.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString*message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
static void HoverCleared(void);
@interface ReferenceTextFact : NSObject
@property(nonatomic,strong) NSMutableAttributedString *textStorage;
@property(nonatomic) BOOL editable,selectable;
@property(nonatomic) NSUInteger dismisses;
- (NSString*)string;
- (BOOL)isEditable;
- (void)dismissSourceHover;
@end
@implementation ReferenceTextFact
- (instancetype)init{if((self=[super init])){_textStorage=[[NSMutableAttributedString alloc]initWithString:@""];_selectable=YES;}return self;}
- (NSString*)string{return self.textStorage.string;}
- (BOOL)isEditable{return self.editable;}
- (void)dismissSourceHover{self.dismisses++;HoverCleared();}
@end
@interface ReferenceValueFact : NSObject
@property(nonatomic,copy) NSString *stringValue,*title,*identifier;
@property(nonatomic,strong) NSMutableArray *items;
@property(nonatomic) NSInteger indexOfSelectedItem;
@property(nonatomic,weak) id target;
@property(nonatomic) SEL action;
- (void)addItemWithTitle:(NSString*)text;
@end
@implementation ReferenceValueFact
- (instancetype)init{if((self=[super init]))_items=[NSMutableArray new];return self;}
- (void)addItemWithTitle:(NSString*)text{[self.items addObject:text];}
@end
@interface ReferenceFacts : NSObject
@property(nonatomic,strong) NSMutableArray *events,*queries,*tokenizers,*tips;
@property(nonatomic,strong) FYReferenceDictionary *dictionary;
@property(nonatomic,strong) FYJapaneseTokenizer *tokenizer;
@property(nonatomic,strong) ReferenceTextFact *main,*grammar,*quick;
@property(nonatomic,strong) ReferenceValueFact *search;
@property(nonatomic,strong) FYAnalysisResult *analysis,*quickAnalysis;
@property(nonatomic,strong) NSString *quickID,*quickSource,*quickAnalysisSource;
@property(nonatomic) NSInteger version;
@property(nonatomic) BOOL requested,matches;
@property(nonatomic) NSUInteger resourceReads,entryChanges,clears,emptyResults;
@property(nonatomic,strong) NSArray *renderedRecords;
@property(nonatomic,copy) NSString *lastEmptyWord,*lastError;
@end
@implementation ReferenceFacts
- (instancetype)init{if((self=[super init])){_events=[NSMutableArray new];_queries=[NSMutableArray new];_tokenizers=[NSMutableArray new];_tips=[NSMutableArray new];_search=[ReferenceValueFact new];_main=[ReferenceTextFact new];_grammar=[ReferenceTextFact new];_quick=[ReferenceTextFact new];_requested=YES;_quickID=@"quick";_version=3;_quickSource=@"猫猫😀猫";_quickAnalysisSource=@"";_main.textStorage=[[NSMutableAttributedString alloc]initWithString:@"猫猫😀猫"];_grammar.textStorage=[[NSMutableAttributedString alloc]initWithString:_main.string];_quick.textStorage=[[NSMutableAttributedString alloc]initWithString:_quickSource];}return self;}
@end
static ReferenceFacts*activeFacts;
static void HoverCleared(void){[activeFacts.events addObject:@"clear-hover"];}
@interface ReferenceResourceBoundary : NSObject
@property(nonatomic,weak) ReferenceFacts*facts;
- (NSURL*)referenceResourceURL:(NSString*)name;
@end
@implementation ReferenceResourceBoundary
- (NSURL*)referenceResourceURL:(NSString*)name{self.facts.resourceReads++;[self.facts.events addObject:@"resource"];return[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:@"synthetic-reference-not-opened.sqlite"]];}
@end
static void DictionaryLookup(id object,SEL cmd,NSString*word,NSString*reading,void(^reply)(NSArray*,NSError*)){[activeFacts.events addObject:@"lookup"];[activeFacts.queries addObject:@{ @"object":object,@"word":word ?: @"",@"reading":reading ?: @"",@"reply":[reply copy]}];}
static void Tokenize(id object,SEL cmd,NSString*source,void(^reply)(NSArray*)){[activeFacts.events addObject:@"tokenize"];[activeFacts.tokenizers addObject:@{@"object":object,@"source":source ?: @"",@"reply":[reply copy]}];}
static IMP dictionaryIMP,tokenizerIMP;
static void InstallServices(void){dictionaryIMP=method_setImplementation(class_getInstanceMethod(FYReferenceDictionary.class,@selector(lookupWord:reading:completion:)),(IMP)DictionaryLookup);tokenizerIMP=method_setImplementation(class_getInstanceMethod(FYJapaneseTokenizer.class,@selector(rangesInText:completion:)),(IMP)Tokenize);}
static void RestoreServices(void){method_setImplementation(class_getInstanceMethod(FYReferenceDictionary.class,@selector(lookupWord:reading:completion:)),dictionaryIMP);method_setImplementation(class_getInstanceMethod(FYJapaneseTokenizer.class,@selector(rangesInText:completion:)),tokenizerIMP);}
@protocol ReferenceWorkflowDriver <NSObject>
@property(nonatomic) NSInteger referenceRequestGeneration;
@property(nonatomic,copy) NSString*referenceActiveWord;
@property(nonatomic,copy) NSArray*referenceRecords;
@property(nonatomic,strong) FYReferenceDictionary*referenceDictionary;
@property(nonatomic) NSUInteger sourceHoverGeneration,quickSourceHoverGeneration;
@property(nonatomic) BOOL sourceHoverSuspended;
@property(nonatomic,strong) NSCache*sourceHoverCache;
- (id)verticalStack;
- (void)lookupReferenceWord:(NSString*)word reading:(NSString*)reading;
- (void)applyAnalysisHoverTips:(FYAnalysisResult*)analysis source:(NSString*)source views:(NSArray*)views;
- (void)populateSourceHoverTips:(NSString*)source views:(NSArray*)views analysis:(FYAnalysisResult*)analysis fallback:(NSString*)fallback isCurrent:(BOOL(^)(void))isCurrent;
- (void)refreshSourceHoverTips;
- (void)refreshQuickSentenceHoverTips;
@end
static NSError*Failure(void){return[NSError errorWithDomain:@"synthetic" code:9 userInfo:@{NSLocalizedDescriptionKey:@"合成错误"}];}
static NSDictionary*Record(NSString*gloss){return@{@"readings":@[@"ねこ"],@"spellings":@[@"猫"],@"senses":@[@{@"number":@1,@"glosses":@[gloss],@"pos":@[],@"examples":@[]}],@"reference_levels":@[],@"source_url":@"https://synthetic.invalid/reference"};}
static NSDictionary*Pop(NSMutableArray*a){Check(a.count>0,@"expected held boundary callback");NSDictionary*r=a[0];[a removeObjectAtIndex:0];return r;}
static void QueryReplyAt(ReferenceFacts*f,NSUInteger index,NSArray*records,NSError*error){Check(index<f.queries.count,@"held dictionary index exists");NSDictionary*r=f.queries[index];[f.queries removeObjectAtIndex:index];void(^reply)(NSArray*,NSError*)=r[@"reply"];reply(records,error);}
static void QueryReply(ReferenceFacts*f,NSArray*r,NSError*e){QueryReplyAt(f,0,r,e);}
static void TokenReply(ReferenceFacts*f,NSArray*ranges){NSDictionary*r=Pop(f.tokenizers);void(^reply)(NSArray*)=r[@"reply"];reply(ranges);}
static NSString*LastTip(ReferenceFacts*f,NSRange range){for(NSDictionary*r in[f.tips reverseObjectEnumerator])if(NSEqualRanges([r[@"range"]rangeValue],range))return r[@"tip"];return nil;}
static NSArray*Ranges(void){return@[[NSValue valueWithRange:NSMakeRange(0,1)],[NSValue valueWithRange:NSMakeRange(1,1)],[NSValue valueWithRange:NSMakeRange(2,2)],[NSValue valueWithRange:NSMakeRange(4,1)],[NSValue valueWithRange:NSMakeRange(90,2)],[NSValue valueWithRange:NSMakeRange(0,0)]];}
static void DrainQueries(ReferenceFacts*f){while(f.queries.count)QueryReply(f,@[],Failure());}
static void RunReferenceWorkflow(id<ReferenceWorkflowDriver>s,ReferenceFacts*f){
 Check(!s.referenceDictionary&&!s.referenceRecords&&s.referenceRequestGeneration==0&&!s.sourceHoverCache,@"cold query/hover state creates no dictionary/cache/tasks");
 [(id)s setValue:nil forKey:@"referenceStack"];[s lookupReferenceWord:@"猫" reading:@""];Check(f.resourceReads==0&&f.queries.count==0&&s.referenceRequestGeneration==0,@"missing native stack guards all query setup");[(id)s setValue:[s verticalStack]forKey:@"referenceStack"];
 NSMutableString*word=[NSMutableString stringWithString:@"猫"];[s lookupReferenceWord:word reading:@"ねこ"];FYReferenceDictionary*shared=s.referenceDictionary;Check(shared&&f.resourceReads==1&&s.referenceRequestGeneration==1&&[s.referenceActiveWord isEqual:@"猫"]&&s.referenceRecords.count==0,@"query creates shared dictionary after original generation/snapshot setup");[word appendString:@"変更"];Check([s.referenceActiveWord isEqual:@"猫"],@"active word retains original copy behavior");
 [s lookupReferenceWord:@"犬" reading:@"いぬ"];Check(s.referenceDictionary==shared&&f.resourceReads==1&&s.referenceRequestGeneration==2,@"second query shares dictionary and advances only query generation");QueryReply(f,@[Record(@"late")],nil);Check(s.referenceRecords.count==0&&f.entryChanges==0,@"late first query cannot replace current records");NSMutableArray*raw=[NSMutableArray arrayWithObject:Record(@"current")];QueryReply(f,raw,nil);Check(s.referenceRecords!=raw&&s.referenceRecords.count==1&&f.entryChanges==1,@"current query copies records and triggers native entry selection");[raw removeAllObjects];Check(s.referenceRecords.count==1,@"external result mutation leaves copied query snapshot");
 [s lookupReferenceWord:@"空" reading:nil];QueryReply(f,@[],nil);Check(s.referenceRecords.count==0,@"empty query result preserves empty records");[s lookupReferenceWord:@"誤" reading:@""];QueryReply(f,nil,Failure());Check(s.referenceRecords==nil,@"query error preserves original nil records assignment");
 __block BOOL current=NO;NSUInteger resource=f.resourceReads;[f.events removeAllObjects];[s populateSourceHoverTips:@"" views:@[f.main]analysis:nil fallback:@"fallback"isCurrent:^BOOL{return current;}];Check(f.tokenizers.count==0&&f.resourceReads==resource&&[f.events.firstObject isEqual:@"clear-hover"],@"hover clears native attributes before empty/current guard without creating services");
 current=YES;FYVocabularyEntry*v=[FYVocabularyEntry new];v.surface=@"猫";v.reading=@"ねこ";v.meaning=@"AI释义";FYGrammarItem*g=[FYGrammarItem new];g.name=@"AI语法";g.matchedText=@"猫";g.matchedRange=NSMakeRange(0,1);g.meaning=@"语法义";FYAnalysisResult*analysis=[FYAnalysisResult new];analysis.vocabulary=@[v];analysis.grammar=@[g];[f.tips removeAllObjects];[s populateSourceHoverTips:f.main.string views:@[f.main,f.grammar]analysis:analysis fallback:@"fallback"isCurrent:^BOOL{return current;}];Check(s.sourceHoverCache.countLimit==300&&s.referenceDictionary==shared&&f.tokenizers.count==1&&f.resourceReads==resource,@"hover creates original 300-entry cache/tokenizer and shares same dictionary");Check([LastTip(f,NSMakeRange(0,1))containsString:@"AI语法"],@"AI grammar range overwrites overlapping vocabulary tip first");TokenReply(f,Ranges());Check(f.queries.count==2,@"valid UTF16 ranges group identical surfaces into two dictionary queries");Check([LastTip(f,NSMakeRange(2,2))containsString:@"😀\nfallback"],@"fallback keeps exact emoji UTF16 token range");Check([LastTip(f,NSMakeRange(0,1))containsString:@"AI语法"],@"AI grammar reapplied after token fallbacks");
 QueryReply(f,@[Record(@"dictionary")],nil);QueryReply(f,@[Record(@"dictionary")],nil);Check([s.sourceHoverCache objectForKey:@"猫"]&&[s.sourceHoverCache objectForKey:@"😀"],@"dictionary replies update both surface cache entries");Check([LastTip(f,NSMakeRange(0,1))containsString:@"AI语法"]&&[LastTip(f,NSMakeRange(4,1))containsString:@"AI释义"],@"AI analysis retains range priority after dictionary replies");
 NSUInteger before=f.queries.count;[s populateSourceHoverTips:f.main.string views:@[f.main]analysis:nil fallback:@"fallback"isCurrent:^BOOL{return current;}];TokenReply(f,Ranges());Check(f.queries.count==before&&[LastTip(f,NSMakeRange(2,2))containsString:@"JMdict"],@"cached surfaces apply without starting extra dictionary queries");
 [s.sourceHoverCache removeAllObjects];[s populateSourceHoverTips:f.main.string views:@[f.main]analysis:nil fallback:@"fallback"isCurrent:^BOOL{return current;}];TokenReply(f,Ranges());NSUInteger tipCount=f.tips.count;current=NO;QueryReply(f,@[Record(@"stale cache")],nil);Check(s.sourceHoverCache.countLimit==300&&f.tips.count==tipCount,@"stale dictionary result cannot update tips");Check([s.sourceHoverCache objectForKey:@"猫"]||[s.sourceHoverCache objectForKey:@"😀"],@"stale result still writes cache before currentness guard");DrainQueries(f);
 NSUInteger mainGen=s.sourceHoverGeneration,quickGen=s.quickSourceHoverGeneration,queryGen=s.referenceRequestGeneration;s.sourceHoverSuspended=YES;[s refreshSourceHoverTips];Check(s.sourceHoverGeneration==mainGen+1&&!s.sourceHoverSuspended&&s.quickSourceHoverGeneration==quickGen&&s.referenceRequestGeneration==queryGen,@"main hover resets suspension and owns only its independent generation");[s refreshQuickSentenceHoverTips];Check(s.quickSourceHoverGeneration==quickGen+1&&s.sourceHoverGeneration==mainGen+1&&s.referenceRequestGeneration==queryGen,@"quick hover advances its own generation without cancelling main/query");s.sourceHoverGeneration++;TokenReply(f,Ranges());Check(f.queries.count==0,@"stale main tokenizer cannot start dictionary queries");TokenReply(f,Ranges());DrainQueries(f);
 f.quick=nil;quickGen=s.quickSourceHoverGeneration;[s refreshQuickSentenceHoverTips];Check(s.quickSourceHoverGeneration==quickGen+1&&f.tokenizers.count==0,@"quick generation advances before nil-view guard");f.quick=[ReferenceTextFact new];f.quick.textStorage=[[NSMutableAttributedString alloc]initWithString:f.quickSource];
 for(NSUInteger gate=0;gate<6;gate++){f.requested=YES;f.quick.editable=NO;f.quickSource=f.quick.string;f.quickID=@"quick";f.version=3;[s refreshQuickSentenceHoverTips];NSUInteger tips=f.tips.count;switch(gate){case 0:f.requested=NO;break;case 1:f.quick.editable=YES;break;case 2:f.quickSource=@"changed";break;case 3:f.quickID=@"other";break;case 4:f.version++;break;default:{ReferenceTextFact*newView=[ReferenceTextFact new];newView.textStorage=[[NSMutableAttributedString alloc]initWithString:f.quick.string];f.quick=newView;break;}}TokenReply(f,Ranges());Check(f.tips.count==tips&&f.queries.count==0,@"each original quick requested/editability/source/ID/version/view-identity gate rejects stale tokenizer");}
 f.main.editable=NO;[s refreshSourceHoverTips];f.main.editable=YES;NSUInteger tips=f.tips.count;TokenReply(f,Ranges());Check(f.tips.count==tips&&f.queries.count==0,@"editable main source rejects deferred tokenizer");f.main.editable=NO;
}
typedef id<ReferenceWorkflowDriver>(^ReferenceFactory)(ReferenceFacts*);
static void RunReferenceLeases(ReferenceFactory factory){
 ReferenceFacts*f=[ReferenceFacts new];activeFacts=f;__weak id weak;@autoreleasepool{id<ReferenceWorkflowDriver>s=factory(f);weak=s;[s lookupReferenceWord:@"合成"reading:@""];}Check(weak!=nil,@"original dictionary query holds concrete native receiver");@autoreleasepool{QueryReply(f,@[],Failure());}Check(!weak,@"finished dictionary query releases receiver");
 f=[ReferenceFacts new];activeFacts=f;__weak ReferenceTextFact*view;@autoreleasepool{id<ReferenceWorkflowDriver>s=factory(f);weak=s;view=f.quick;[s refreshQuickSentenceHoverTips];f.quick=nil;}Check(weak&&view,@"tokenizer callback retains source and original quick target; isCurrent remains weak");@autoreleasepool{TokenReply(f,Ranges());}Check(!weak&&!view,@"stale tokenizer completion releases source and target leases");
}
