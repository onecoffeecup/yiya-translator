#import "presentation/FYMainWindowController.h"
#import "FYLivePageTestFacts.h"
// Native UI/state and peer actions only. Callback/observer body is actual production.
@interface PageHostFixture : FYMainWindowController <PageSelectionFixture>
@property(nonatomic,strong) PageSelectionPeer *facts;
@end
@implementation PageHostFixture
- (instancetype)init{if((self=[super initWithHost:nil])){self.facts=[PageSelectionPeer new];self.learningSourceTextView=(FYSelectableSourceTextView *)self.facts.text;self.lemmaField=(NSTextField *)self.facts.lemma;self.readingField=(NSTextField *)self.facts.reading;self.meaningField=(NSTextField *)self.facts.meaning;[super setVocabSelectionGeneration:11];[super setVocabCompletionFromAI:YES];}return self;}
- (void)freezeLearningSentenceForSelection{[self.facts freezeLearningSentenceForSelection];}
- (void)updateWordPickForSelection{[self.facts updateWordPickForSelection];}
- (void)selectWordAtCharacterIndex:(NSUInteger)index{[self.facts selectWordAtCharacterIndex:index];}
- (void)setVocabCompletionFromAI:(BOOL)value{[super setVocabCompletionFromAI:value];self.facts.ai=value;[self.facts.trace addObject:@"ai"];}
- (void)setVocabSelectionGeneration:(NSInteger)value{[super setVocabSelectionGeneration:value];self.facts.generation=value;[self.facts.trace addObject:@"generation"];}
- (id)testWireLiveSelection{
#if FY_LIVE_PAGE_EXTRACTED
 return [self.livePageBuilder wireSourceSelectionWithReceiver:self];
#else
 return [self performSelector:NSSelectorFromString(@"testOriginalLivePageSelection")];
#endif
}
@end
int main(void){@autoreleasepool{
    PageHostFixture *source=[PageHostFixture new];RunSelectionFixture(source,source.facts);Check(source.vocabSelectionGeneration==15&&!source.vocabCompletionFromAI&&source.wordSelectionController.vocabSelectionGeneration==15,@"actual Main callbacks continue to write sole original Word3 owner");
    __weak PageHostFixture *weak;id token;void (^held)(void);@autoreleasepool{PageHostFixture *temporary=[PageHostFixture new];weak=temporary;token=[temporary testWireLiveSelection];held=((PageTextFact *)temporary.learningSourceTextView).didFinishSelection;}Check(!weak&&token&&held,@"original/new actual Main weak callbacks and real observer do not retain Main");held();[[NSNotificationCenter defaultCenter]removeObserver:token];Check(!weak&&NSApp==nil,@"actual released Main late callback stays safe and headless");
    printf("PASS LivePageBuilderHostTests: %lu checks; actual Main and exact original selection-body excerpt, real center/weak leases/Word3\n",(unsigned long)checks);
}return 0;}
