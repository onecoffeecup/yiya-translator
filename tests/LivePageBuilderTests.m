#import "presentation/FYLivePageBuilder.h"
#import "FYLivePageTestFacts.h"
#import <objc/runtime.h>
@interface PageSelectionSource : PageSelectionPeer <FYLivePageSelectionSource,PageSelectionFixture>
@property(nonatomic,strong) FYLivePageBuilder *builder;
@end
@implementation PageSelectionSource
- (instancetype)init{if((self=[super init]))self.builder=[FYLivePageBuilder new];return self;}
- (FYSelectableSourceTextView *)learningSourceTextView{return (FYSelectableSourceTextView *)self.text;}
- (void)setLearningSourceTextView:(FYSelectableSourceTextView *)view{self.text=(PageTextFact *)view;}
- (NSTextField *)lemmaField{return (NSTextField *)self.lemma;}
- (NSTextField *)readingField{return (NSTextField *)self.reading;}
- (NSTextField *)meaningField{return (NSTextField *)self.meaning;}
- (BOOL)vocabCompletionFromAI{return self.ai;}
- (void)setVocabCompletionFromAI:(BOOL)value{self.ai=value;[self.trace addObject:@"ai"];}
- (NSInteger)vocabSelectionGeneration{return self.generation;}
- (void)setVocabSelectionGeneration:(NSInteger)value{self.generation=value;[self.trace addObject:@"generation"];}
- (id)testWireLiveSelection{return [self.builder wireSourceSelectionWithReceiver:self];}
@end
int main(void){@autoreleasepool{
    unsigned int n=0;Ivar *v=class_copyIvarList(FYLivePageBuilder.class,&n);free(v);FYLivePageBuilder *cold=[FYLivePageBuilder new];Check(cold&&n==0&&NSApp==nil,@"independent native builder cold initialization creates zero views/resources/source/state");PageSelectionSource *source=[PageSelectionSource new];RunSelectionFixture(source,source);
    __weak FYLivePageBuilder *weakBuilder=source.builder;source.builder=nil;Check(!weakBuilder,@"receiver callbacks/notification do not retain stateless builder");source.text.didFinishSelection=nil; // replacement view had no callbacks; original fixture already checked original callbacks.
    __weak PageSelectionSource *weak;id token;void (^held)(void);@autoreleasepool{PageSelectionSource *temporary=[PageSelectionSource new];weak=temporary;token=[temporary testWireLiveSelection];held=temporary.text.willBeginSelection;}Check(!weak&&token&&held,@"real center registration and held native callback do not retain concrete source");held();[[NSNotificationCenter defaultCenter]removeObserver:token];Check(!weak&&NSApp==nil,@"late weak callback is safe after receiver release without UI");
    printf("PASS LivePageBuilderTests: %lu checks; actual native weak callbacks/real notification center/mainQueue, cold stateless builder; full native construction compiled only\n",(unsigned long)checks);
}return 0;}
