#import "FYStudyChatContextTestFacts.h"
@interface StudyChatSourceFixture : NSObject <FYStudyChatContextSource,StudyChatDriver>
@property(nonatomic,strong) ChatContextFacts *facts;
@property(nonatomic,strong) FYStudyChatContextCoordinator *core;
@property(nonatomic,strong) id inlineReturnSnapshot;
@end
@implementation StudyChatSourceFixture
- (instancetype)init{if((self=[super init])){_core=[FYStudyChatContextCoordinator new];}return self;}
- (NSInteger)chatContextGeneration{return self.core.chatContextGeneration;}
- (void)setChatContextGeneration:(NSInteger)value{self.core.chatContextGeneration=value;}
- (BOOL)chatResolvingSource{return self.core.chatResolvingSource;}
- (void)setChatResolvingSource:(BOOL)value{self.core.chatResolvingSource=value;}
- (BOOL)studyChatUsesDialogueMode{return self.facts.mode==0;}
- (NSInteger)studyChatLanguageSegment{return self.facts.language.selectedSegment;}
- (NSString *)studyChatFallbackSource{return self.facts.source.string;}
- (NSString *)studyChatFallbackTranslation{return self.facts.translation.stringValue;}
- (void)clearStudyChatReturnSnapshot{self.inlineReturnSnapshot=nil;self.facts.visibility++;[self.facts.events addObject:@"visibility"];}
- (void)restoreStudyChatDraftText:(NSString *)text{[self.facts.mainDraft restoreDraftText:text];[self.facts.overlayDraft restoreDraftText:text];}
- (void)configureStudyChatAnalyzer:(FYLearningAnalyzer *)analyzer{
 analyzer.baseURL=self.facts.base.stringValue ?: @"";analyzer.apiKey=self.facts.key.stringValue ?: @"";
 NSString *model=[self.facts.model.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];analyzer.model=model.length?model:self.facts.fallbackModel.stringValue;
}
- (void)referenceLatestStudySentence:(id)sender{[self.core referenceLatestWithReceiver:self];}
- (void)resolveLatestStudyIdentity:(void (^)(FYRequestIdentity *))completion{[self.core resolveLatestIdentity:completion receiver:self];}
- (void)resolveLatestStudySentence:(void (^)(NSString *,NSString *))completion{[self.core resolveLatestSentence:completion receiver:self];}
- (void)sendStudyChat:(NSString *)text{[self.core send:text receiver:self];}

- (FYStudyChatSession *)studyChatSession{return self.facts.session;}
- (FYLearningCoordinator *)learningCoordinator{return (FYLearningCoordinator *)self.facts.learning;}
- (FYLearningStore *)learningStore{return (FYLearningStore *)self.facts.store;}
- (BOOL)running{return self.facts.running;}
- (uint32_t)selectedWindowID{return self.facts.windowID;}
- (void)ensureStudyChatSession{self.facts.ensures++;[self.facts.events addObject:@"ensure"];}
- (void)refreshStudyChatViews{self.facts.refreshes++;[self.facts.events addObject:@"refresh"];}
- (void)showError:(NSString *)text{self.facts.error=text;[self.facts.events addObject:@"error"];}
- (void)captureLatestStudySentenceWithCompletion:(void (^)(NSString *,NSError *))completion{[self.facts.events addObject:@"capture"];[self.facts.captures addObject:[completion copy]];}
@end
static id<StudyChatDriver> Source(ChatContextFacts*f){StudyChatSourceFixture*s=[StudyChatSourceFixture new];s.facts=f;return s;}
int main(void){@autoreleasepool{FYStudyChatContextCoordinator*c=[FYStudyChatContextCoordinator new];unsigned count=0;Ivar*v=class_copyIvarList(c.class,&count);free(v);Check(count==2&&!class_getInstanceVariable(c.class,"_receiver")&&!class_getInstanceVariable(c.class,"_session"),@"Foundation context owns exactly original two scalars, no receiver/session/cancel resource");ChatContextFacts*f=[ChatContextFacts new];RunStudyChatFixture(Source(f),f);RunStudyChatLeases(^id<StudyChatDriver>(ChatContextFacts*f){return Source(f);});printf("PASS StudyChatContextTests: %lu checks; Foundation real context and session algorithms, synthetic boundary services only\n",(unsigned long)checks);}return 0;}
