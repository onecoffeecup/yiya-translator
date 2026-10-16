#import "presentation/FYStudyPresentationController.h"
#import "FYStudyChatContextTestFacts.h"
@interface StudyChatHostFixture : FYStudyPresentationController <StudyChatDriver>
@property(nonatomic,strong) ChatContextFacts *facts;
@end
@implementation StudyChatHostFixture

- (FYStudyChatSession *)studyChatSession{return self.facts.session;}
- (FYLearningCoordinator *)learningCoordinator{return (FYLearningCoordinator *)self.facts.learning;}
- (FYLearningStore *)learningStore{return (FYLearningStore *)self.facts.store;}
- (BOOL)running{return self.facts.running;}
- (uint32_t)selectedWindowID{return self.facts.windowID;}
- (void)ensureStudyChatSession{self.facts.ensures++;[self.facts.events addObject:@"ensure"];}
- (void)refreshStudyChatViews{self.facts.refreshes++;[self.facts.events addObject:@"refresh"];}
- (void)showError:(NSString *)text{self.facts.error=text;[self.facts.events addObject:@"error"];}
- (void)captureLatestStudySentenceWithCompletion:(void (^)(NSString *,NSError *))completion{[self.facts.events addObject:@"capture"];[self.facts.captures addObject:[completion copy]];}

- (NSInteger)effectiveModeSegment{return self.facts.mode;}
- (NSSegmentedControl *)languageControl{return (NSSegmentedControl *)self.facts.language;}
- (NSTextField *)baseURLField{return (NSTextField *)self.facts.base;}
- (NSSecureTextField *)apiKeyField{return (NSSecureTextField *)self.facts.key;}
- (NSTextField *)learningModelField{return (NSTextField *)self.facts.model;}
- (NSTextField *)modelField{return (NSTextField *)self.facts.fallbackModel;}
- (FYSelectableSourceTextView *)learningSourceTextView{return (FYSelectableSourceTextView *)self.facts.source;}
- (NSTextField *)learningTranslationLabel{return (NSTextField *)self.facts.translation;}
- (FYStudyChatView *)mainStudyChatView{return (FYStudyChatView *)self.facts.mainDraft;}
- (FYStudyChatView *)overlayStudyChatView{return (FYStudyChatView *)self.facts.overlayDraft;}
- (void)updateInlineReturnButtonVisibility{self.facts.visibility++;[self.facts.events addObject:@"visibility"];}
@end
static id<StudyChatDriver> Source(ChatContextFacts*f){StudyChatHostFixture*s=[[StudyChatHostFixture alloc]initWithHost:nil];s.facts=f;return s;}
int main(void){@autoreleasepool{Check(NSApp==nil,@"actual native Study fixture creates no UI/application");ChatContextFacts*f=[ChatContextFacts new];id<StudyChatDriver>s=Source(f);RunStudyChatFixture(s,f);RunStudyChatLeases(^id<StudyChatDriver>(ChatContextFacts*f){return Source(f);});Check(NSApp==nil,@"native config/fallback/draft adapters keep headless isolation");printf("PASS StudyChatContextHostTests: %lu checks; actual old/new native same fixture and original strong source leases\n",(unsigned long)checks);}return 0;}
