#pragma once
#import <Foundation/Foundation.h>
#import "learning/FYLearningCoordinator.h"
#import "FYGrammarActionState.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
static FYAnalysisResult *Result(NSString *identifier,NSInteger version,NSUInteger count){FYAnalysisResult *r=[FYAnalysisResult new];r.sentenceID=identifier;r.version=version;NSMutableArray *items=[NSMutableArray new];for(NSUInteger i=0;i<count;i++){FYGrammarItem *g=[FYGrammarItem new];g.name=[NSString stringWithFormat:@"synthetic-%lu",(unsigned long)i];[items addObject:g];}r.grammar=items;return r;}
@interface GrammarAnalyzerBoundary : FYLearningAnalyzer
@property(nonatomic) NSUInteger expands,questions,examples,simplers,reviews,cancels;
@property(nonatomic,strong) FYGrammarItem *requestedItem;
@property(nonatomic,strong) FYAnalysisResult *requestedExisting;
@property(nonatomic,copy) NSString *requestedSource,*requestedTranslation,*requestedQuestion;
@property(nonatomic,copy) void (^answerReply)(NSString *,NSError *);
@property(nonatomic,copy) void (^reviewReply)(FYAnalysisResult *,NSError *);
@end
@implementation GrammarAnalyzerBoundary
- (void)cancelAll{self.cancels++;[super cancelAll];}
- (void)expandedExplanationForGrammar:(FYGrammarItem *)item sentenceText:(NSString *)text translation:(NSString *)translation completion:(void (^)(NSString *,NSError *))completion{self.expands++;self.requestedItem=item;self.requestedSource=text;self.requestedTranslation=translation;self.answerReply=completion;}
- (void)exampleSentenceForGrammar:(FYGrammarItem *)item sentenceText:(NSString *)text translation:(NSString *)translation completion:(void (^)(NSString *,NSError *))completion{self.examples++;self.requestedItem=item;self.answerReply=completion;}
- (void)simplerExplanationForGrammar:(FYGrammarItem *)item sentenceText:(NSString *)text translation:(NSString *)translation completion:(void (^)(NSString *,NSError *))completion{self.simplers++;self.requestedItem=item;self.answerReply=completion;}
- (void)answerQuestion:(NSString *)question grammar:(FYGrammarItem *)item sentenceText:(NSString *)text translation:(NSString *)translation completion:(void (^)(NSString *,NSError *))completion{self.questions++;self.requestedQuestion=question;self.requestedItem=item;self.answerReply=completion;}
- (void)reviewSentence:(NSString *)text translation:(NSString *)translation existingResult:(FYAnalysisResult *)existing completion:(void (^)(FYAnalysisResult *,NSError *))completion{self.reviews++;self.requestedExisting=existing;self.requestedSource=text;self.requestedTranslation=translation;self.reviewReply=completion;}
@end
@interface GrammarLearningBoundary : FYLearningCoordinator
@property(nonatomic,copy) NSString *identifier,*source,*translation;
@property(nonatomic) NSInteger version;
@property(nonatomic) NSUInteger analyzes,reviews,pins;
@property(nonatomic,strong) FYAnalysisResult *requestedExisting;
@property(nonatomic,copy) void (^analysisReply)(FYAnalysisResult *,NSError *);
@property(nonatomic,copy) void (^reviewReply)(FYAnalysisResult *,NSError *);
@end
@implementation GrammarLearningBoundary
- (NSString *)currentSentenceID{return self.identifier;}
- (NSString *)currentSourceText{return self.source;}
- (NSString *)currentTranslation{return self.translation;}
- (NSInteger)currentVersion{return self.version;}
- (void)pinCurrent{self.pins++;}
- (void)analyzeCurrent:(void (^)(FYAnalysisResult *,NSError *))completion{self.analyzes++;self.analysisReply=completion;}
- (void)reviewCurrentAnalysis:(FYAnalysisResult *)existing completion:(void (^)(FYAnalysisResult *,NSError *))completion{self.reviews++;self.requestedExisting=existing;self.reviewReply=completion;}
@end
@interface GrammarInteractionFacts : NSObject
@property(nonatomic,strong) GrammarLearningBoundary *learning;
@property(nonatomic,strong) GrammarAnalyzerBoundary *analyzer,*quickAnalyzer;
@property(nonatomic,strong) FYGrammarCatalog *catalog;
@property(nonatomic,strong) FYAnalysisResult *quickResult;
@property(nonatomic,copy) NSString *quickSource,*quickTranslation,*quickID,*quickAnalysisSource;
@property(nonatomic) NSInteger quickVersion,quickIndex;
@property(nonatomic) BOOL quickAnalyzing,applicable,errorColor;
@property(nonatomic,copy) NSString *status,*detailName,*detailBody,*followup,*base,*model,*key;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic) NSUInteger refreshed,controls,quickDetails,renders,preserveCalls,configSync;
@end
@implementation GrammarInteractionFacts
- (instancetype)init{if((self=[super init])){self.learning=[GrammarLearningBoundary new];self.learning.identifier=@"main";self.learning.source=@"synthetic main source";self.learning.translation=@"synthetic main translation";self.learning.version=1;self.analyzer=[GrammarAnalyzerBoundary new];self.quickAnalyzer=[GrammarAnalyzerBoundary new];self.catalog=[FYGrammarCatalog new];self.quickID=@"quick";self.quickSource=@"synthetic quick source";self.quickTranslation=@"synthetic quick translation";self.quickAnalysisSource=self.quickSource;self.quickVersion=2;self.quickIndex=0;self.applicable=YES;self.base=@"https://example.invalid/v1";self.model=@"synthetic-model";self.key=@"synthetic-key";self.trace=[NSMutableArray new];}return self;}
@end
@protocol GrammarFixtureController <NSObject>
@property(nonatomic) NSInteger analysisRequestGeneration,followupRequestGeneration;
@property(nonatomic) BOOL learningAnalysisBusy;
@property(nonatomic,copy) NSString *grammarAnalysisError;
@property(nonatomic,strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic,strong) FYGrammarActionState *grammarActions,*quickGrammarActions;
- (void)analyzeCurrentSentence:(id)sender;
- (void)requestGrammarFollowupExample:(BOOL)example;
- (void)requestGrammarQuestion:(NSString *)question;
- (FYGrammarActionState *)grammarActionsForQuick:(BOOL)quick;
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick;
- (void)testExpandQuick:(BOOL)quick;
- (void)testReviewQuick:(BOOL)quick;
@end
static void InstallActions(id<GrammarFixtureController>c,GrammarInteractionFacts *f){FYGrammarActionState *a=[FYGrammarActionState new];a.analyzer=[GrammarAnalyzerBoundary new];FYGrammarActionState *b=[FYGrammarActionState new];b.analyzer=[GrammarAnalyzerBoundary new];c.grammarActions=a;c.quickGrammarActions=b;[c grammarActionsForQuick:NO];[c grammarActionsForQuick:YES];[f.trace removeAllObjects];}
static void RunGrammarFixture(id<GrammarFixtureController>c,GrammarInteractionFacts *f){
    f.learning.identifier=@"";[c analyzeCurrentSentence:nil];Check(!f.learning.analyzes&&[f.status isEqual:@"当前没有可分析的句子，请先开始翻译。"],@"empty initial sentence returns before analysis/service work");f.learning.identifier=@"main";[f.trace removeAllObjects];[c analyzeCurrentSentence:nil];Check(c.learningAnalysisBusy&&c.analysisRequestGeneration==1&&f.learning.pins==1&&f.learning.analyzes==1,@"initial request pins/increments/marks busy once");Check([[f.trace componentsJoinedByString:@","]isEqual:@"syncDisplayed,clear,statusRefresh,page0,busyYES"],@"original initial native/peer ordering retained");
    FYAnalysisResult *success=Result(@"main",1,2);void (^reply)(FYAnalysisResult *,NSError *)=f.learning.analysisReply;f.learning.analysisReply=nil;reply(success,nil);reply=nil;Check(c.currentAnalysis==success&&!c.learningAnalysisBusy&&f.refreshed==1,@"current initial result passes real canonical identity/version/generation gates");
    [c analyzeCurrentSentence:nil];reply=f.learning.analysisReply;f.learning.analysisReply=nil;f.learning.version=2;reply(Result(@"main",1,1),nil);reply=nil;Check(c.learningAnalysisBusy&&f.refreshed==1,@"same sentence newer version rejects old result before clearing current busy");f.learning.version=1;[c analyzeCurrentSentence:nil];reply=f.learning.analysisReply;f.learning.analysisReply=nil;reply(Result(@"other",1,1),nil);reply=nil;Check(!c.learningAnalysisBusy&&f.refreshed==1,@"returned result belongs-to-request gate follows busy release exactly");
    [c analyzeCurrentSentence:nil];reply=f.learning.analysisReply;f.learning.analysisReply=nil;NSError *error=[NSError errorWithDomain:@"synthetic" code:1 userInfo:@{NSLocalizedDescriptionKey:@"synthetic failure"}];reply(nil,error);reply=nil;Check([c.grammarAnalysisError isEqual:@"synthetic failure"]&&[f.status isEqual:@"分析失败：synthetic failure"]&&f.errorColor&&[f.detailName isEqual:@"本次分析未完成"]&&!c.learningAnalysisBusy,@"initial error native strings/color and original busy order unchanged");
    c.currentAnalysis=success;f.applicable=YES;[c requestGrammarFollowupExample:NO];Check(f.analyzer.simplers==1&&[f.followup isEqual:@"正在生成…"],@"simpler followup enters original learning analyzer scope");void (^answer)(NSString *,NSError *)=f.analyzer.answerReply;f.analyzer.answerReply=nil;c.followupRequestGeneration++;answer(@"obsolete",nil);answer=nil;Check([f.followup isEqual:@"正在生成…"],@"followup stale generation rejected by real canonical gate");[c requestGrammarFollowupExample:YES];answer=f.analyzer.answerReply;f.analyzer.answerReply=nil;answer(@"example",nil);answer=nil;Check(f.analyzer.examples==1&&[f.followup isEqual:@"AI 建议\nexample"],@"example uses independent requested method and formatted delivery");[c requestGrammarQuestion:@"question"];answer=f.analyzer.answerReply;f.analyzer.answerReply=nil;answer(nil,error);answer=nil;Check([f.followup isEqual:@"生成失败：synthetic failure；可以重新提问。"],@"question error preserves original native message");f.applicable=NO;[c requestGrammarQuestion:@"invalid"];Check([f.followup isEqual:@"请先分析当前句子，再选择语法点。"],@"non-applicable question never starts another service task");f.applicable=YES;
    FYLearningTransport transportA=^(NSURLRequest *request,void(^completion)(NSData *,NSURLResponse *,NSError *)){Check(NO,@"synthetic main transport must not send HTTP");};
    FYLearningTransport transportB=^(NSURLRequest *request,void(^completion)(NSData *,NSURLResponse *,NSError *)){Check(NO,@"synthetic quick transport must not send HTTP");};
    f.analyzer.transport=transportA;f.quickAnalyzer.transport=transportB;
    InstallActions(c,f);FYGrammarActionState *main=c.grammarActions,*quick=c.quickGrammarActions;GrammarAnalyzerBoundary *ma=(GrammarAnalyzerBoundary *)main.analyzer,*qa=(GrammarAnalyzerBoundary *)quick.analyzer;Check(main!=quick&&ma!=qa,@"main and quick actions/analyzers stay independent original owners");Check(ma.transport==transportA&&qa.transport==transportB&&ma.transport!=qa.transport,@"missing action transport binds only to its original main/quick source");
    FYLearningTransport originalTransport=ma.transport;f.analyzer.transport=transportB;[c grammarActionsForQuick:NO];Check(ma.transport==originalTransport,@"already bound action transport is not replaced by later source transport changes");Check(![main.context containsString:f.key]&&main.context.length&&[ma.apiKey isEqual:f.key],@"context identity excludes key while analyzer still authenticates with configured synthetic key");NSUInteger canceled=ma.cancels;[c grammarActionsForQuick:NO];Check(ma.cancels==canceled,@"same context/key does not reset or cancel");f.key=@"synthetic-key-next";[c grammarActionsForQuick:NO];Check(ma.cancels==canceled+1&&qa.cancels==1,@"key change resets only requested surface, key not added to context JSON");[c grammarActionsForQuick:YES];
    FYGrammarItem *item=success.grammar[0];[c testExpandQuick:NO];Check(main.expandedItem==item&&[main.pending containsObject:item]&&ma.expands==1&&ma.requestedItem==item,@"expand registers exact item identity before held request");[c testExpandQuick:NO];Check(ma.expands==1,@"pending same item prevents duplicate expansion");answer=ma.answerReply;ma.answerReply=nil;answer(@" explanation ",nil);answer=nil;Check(![main.pending containsObject:item]&&[[main.explanations objectForKey:item]isEqual:@" explanation "],@"successful expansion keeps raw answer while Trim tests only emptiness");[c testExpandQuick:NO];Check(main.expandedItem==nil&&ma.expands==1,@"cached expanded item collapses without new task");[c testExpandQuick:NO];Check(main.expandedItem==item&&ma.expands==1,@"cached explanation reopens without request");[main.explanations removeObjectForKey:item];main.expandedItem=nil;[c testExpandQuick:NO];answer=ma.answerReply;ma.answerReply=nil;answer(@" \n",nil);answer=nil;Check([main.errors objectForKey:item]&&! [main.pending containsObject:item],@"empty explanation records exact retry error and releases pending");[c testExpandQuick:NO];Check(ma.expands==3&&! [main.errors objectForKey:item],@"error retry clears old error and starts exactly one task");answer=ma.answerReply;ma.answerReply=nil;[main reset];answer(@"late",nil);answer=nil;Check([main.explanations objectForKey:item]==nil,@"reset generation rejects old expansion without repopulating cache");
    f.quickResult=Result(@"quick",2,1);[c grammarActionsForQuick:NO];[c grammarActionsForQuick:YES];Check([c grammarActionItemForQuick:YES]==f.quickResult.grammar[0],@"quick selected item uses real index gate without first fallback");f.quickIndex=99;Check([c grammarActionItemForQuick:YES]==nil,@"quick invalid item index rejected");f.quickIndex=0;[c testExpandQuick:YES];Check(qa.expands==1&&qa.requestedItem==f.quickResult.grammar[0]&&f.quickDetails>0,@"quick expansion uses its own analyzer/item and native detail actions");answer=qa.answerReply;qa.answerReply=nil;answer(@"quick explanation",nil);answer=nil;Check([quick.explanations objectForKey:f.quickResult.grammar[0]]&&! [main.explanations objectForKey:f.quickResult.grammar[0]],@"quick cache cannot populate main surface");
    c.learningAnalysisBusy=NO;c.currentAnalysis=success;[c testReviewQuick:NO];Check(main.reviewing&&f.learning.reviews==1&&f.learning.requestedExisting==success&&[main.reviewStatus isEqual:@"正在补查遗漏与疑点，已有解释仍可阅读。"],@"review preserves original existing-result identity and separate learning scope");[c testReviewQuick:NO];Check(f.learning.reviews==1,@"review busy prevents duplicate request");reply=f.learning.reviewReply;f.learning.reviewReply=nil;reply(nil,error);reply=nil;Check(c.currentAnalysis==success&&!main.reviewing&&[main.reviewStatus isEqual:@"复核失败：synthetic failure；已有结果已保留，可重试。"],@"review failure retains verified old result and releases only own state");[c testReviewQuick:NO];reply=f.learning.reviewReply;f.learning.reviewReply=nil;FYAnalysisResult *reviewed=Result(@"main",1,3);reply(reviewed,nil);reply=nil;Check(c.currentAnalysis==reviewed&&[main.reviewStatus isEqual:@"复核完成 · 补充了 1 条语法"],@"review success computes additions against captured existing and refreshes actual result");
    [c testReviewQuick:YES];Check(qa.reviews==1&&quick.reviewing&&f.learning.reviews==2,@"quick review uses independent state analyzer rather than main learning coordinator");reply=qa.reviewReply;qa.reviewReply=nil;FYAnalysisResult *quickReview=Result(@"quick",2,1);reply(quickReview,nil);reply=nil;Check(f.quickResult==quickReview&&!quick.reviewing&&f.renders==1&&[quick.reviewStatus isEqual:@"复核完成 · 本次没有新增语法"],@"quick success writes original quick owner/render and preserves own status");
    [c testReviewQuick:NO];reply=f.learning.reviewReply;f.learning.reviewReply=nil;[main reset];reply(Result(@"main",1,5),nil);reply=nil;Check(c.currentAnalysis==reviewed&&!main.reviewing,@"reset/stale review cannot overwrite current result");
    c.grammarActions=main;[c grammarActionsForQuick:NO];main.expandedItem=nil;[main.explanations removeObjectForKey:reviewed.grammar[0]];[c testExpandQuick:NO];answer=ma.answerReply;ma.answerReply=nil;FYGrammarActionState *replacement=[FYGrammarActionState new];replacement.analyzer=[GrammarAnalyzerBoundary new];c.grammarActions=replacement;answer(@"old state",nil);answer=nil;Check([main.explanations objectForKey:reviewed.grammar[0]]==nil,@"state pointer replacement rejects same-generation obsolete expansion");
}
