#import "presentation/FYMainWindowController.h"
#import "FYInlineTranslationListTestFacts.h"
// Only the unrelated native scroll factory is overridden; all three original
// list methods, Main state getters and Host bridges execute unchanged.
@interface ListHostFixture : FYMainWindowController @end
@implementation ListHostFixture
- (NSScrollView *)makePageScrollWithContent:(NSView *)content { return [(ListNativePeer *)self.host makePageScrollWithContent:content]; }
@end
int main(void){@autoreleasepool{
    ListNativePeer *peer=[ListNativePeer new];FYMainWindowController *controller=[[ListHostFixture alloc]initWithHost:(id<FYMainWindowControllerHost>)peer];RunListNativeFixture((id<ListFixtureController>)controller,peer);
    NSMutableString *signature=[@"copy-signature" mutableCopy];controller.inlineTranslationListSignature=signature;[signature appendString:@"-mutated"];Check([controller.inlineTranslationListSignature isEqual:@"copy-signature"],@"actual Main compatibility preserves original signature copy");FYInlineBlockSnapshot *snapshot=[FYInlineBlockSnapshot new];NSMutableArray *array=[NSMutableArray arrayWithObject:snapshot];controller.inlineTranslationListSnapshots=array;[array removeAllObjects];Check(controller.inlineTranslationListSnapshots.count==1&&controller.inlineTranslationListSnapshots[0]==snapshot,@"actual Main snapshots copy array without cloning elements");
    Check(NSApp==nil,@"actual original/extracted Main fixture creates no application/native UI/device/database");printf("PASS InlineTranslationListHostTests: %lu checks; exact original/extracted Main same native fixture and copy contracts\n",(unsigned long)checks);
}return 0;}
