#import "presentation/FYInlineTranslationListRenderer.h"
#import "FYInlineTranslationListTestFacts.h"
#import <objc/runtime.h>
@interface NativeListFixture : ListNativePeer <FYInlineTranslationListSource,FYInlineTranslationListRenderSource,ListFixtureController>
@property(nonatomic,strong) FYInlineTranslationListCoordinator *coordinator;
@property(nonatomic,strong) FYInlineTranslationListRenderer *renderer;
@property(nonatomic,strong) NSView *inlineTranslationListCard;
@property(nonatomic,strong) NSTextField *inlineTranslationListCount;
@property(nonatomic,strong) NSStackView *inlineTranslationListStack;
@end
@implementation NativeListFixture
@dynamic inlineTranslationListSignature,inlineTranslationListSnapshots;
- (instancetype)init{if((self=[super init])){self.coordinator=[FYInlineTranslationListCoordinator new];self.renderer=[FYInlineTranslationListRenderer new];}return self;}
- (NSString *)inlineTranslationListSignature{return self.coordinator.inlineTranslationListSignature;}
- (void)setInlineTranslationListSignature:(NSString *)v{self.coordinator.inlineTranslationListSignature=v;}
- (NSArray *)inlineTranslationListSnapshots{return self.coordinator.inlineTranslationListSnapshots;}
- (void)setInlineTranslationListSnapshots:(NSArray *)v{self.coordinator.inlineTranslationListSnapshots=v;}
- (NSView *)makeInlineTranslationListCard{return [self.renderer makeCardWithReceiver:self];}
- (void)refreshInlineTranslationList{[self.coordinator refreshWithReceiver:self];}
- (void)openInlineTranslationRow:(NSButton *)sender{NSInteger index=sender.tag;[self.coordinator openRowAtIndex:index receiver:self];}
- (BOOL)isInlineTranslationListReady{return self.inlineTranslationListStack&&self.inlineTranslationListCard;}
- (void)setInlineTranslationListHidden:(BOOL)v{self.inlineTranslationListCard.hidden=v;}
- (void)clearInlineTranslationListRows{[self clearArrangedSubviews:self.inlineTranslationListStack];}
- (void)updateInlineTranslationListCountText:(NSString *)v{self.inlineTranslationListCount.stringValue=v;}
- (void)appendInlineTranslationListRowForPlacement:(FYInlinePlacement *)p currentSnapshots:(NSArray *)s{[self.renderer appendRowForPlacement:p currentSnapshots:s receiver:self];}
- (NSFont *)inlineTranslationListFontOfSize:(CGFloat)size{return [NSFont systemFontOfSize:size];}
@end
int main(void){@autoreleasepool{
    NativeListFixture *source=[NativeListFixture new];RunListNativeFixture(source,source);
    unsigned int n=0;Ivar *v=class_copyIvarList(FYInlineTranslationListRenderer.class,&n);free(v);Check(n==0,@"native card/row renderer owns no source/view/cache/state");
    __weak NativeListFixture *weak;FYInlineTranslationListCoordinator *core;FYInlineTranslationListRenderer *native;@autoreleasepool{NativeListFixture *temporary=[NativeListFixture new];weak=temporary;core=temporary.coordinator;native=temporary.renderer;[temporary makeInlineTranslationListCard];}Check(!weak&&core&&native,@"independent native constructor and coordinator do not retain borrowed receiver");
    printf("PASS InlineTranslationListRendererTests: %lu checks; actual native card/row/font/factory order, UI boundary facts only\n",(unsigned long)checks);
}return 0;}
