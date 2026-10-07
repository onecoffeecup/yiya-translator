#import "FYInlineLayout.h"
static void Expect(BOOL ok, NSString *message) { if(!ok){NSLog(@"FAIL %@",message);exit(1);} }
int main(void) { @autoreleasepool {
Expect([FYInlineNormalizeTranslationParagraphs(nil) isEqual:@""],@"nil is empty");
Expect([FYInlineNormalizeTranslationParagraphs(@" 日本語\n译文 ") isEqual:@"日本語译文"],@"wrapped lines join without extra spaces");
Expect([FYInlineNormalizeTranslationParagraphs(@"一\n\n二") isEqual:@"一\n\n二"],@"blank line preserves paragraph");
Expect([FYInlineNormalizeTranslationParagraphs(@" \n一\n \n\n二\n ") isEqual:@"一\n\n二"],@"empty runs and edge whitespace collapse");
Expect([FYInlineNormalizeTranslationParagraphs(@"hello world\nnext line") isEqual:@"hello worldnext line"],@"internal spaces unchanged, no invented separator");
Expect(FYInlineLongCardLineHeight(14.2,-3.1,0)==26,@"ceil font metrics before adding line spacing");
Expect(FYInlineLongCardMinimumHeight(26)==151,@"three readable lines plus header and padding");
Expect(FYInlineLongCardBodyViewport(151)==78,@"minimum card body exposes three lines");
Expect(FYInlineLongCardBodyViewport(50)==0,@"undersized card body viewport clamps to zero");
Expect(NSEqualSizes(FYInlineLongCardSize(NSMakeSize(120,20),YES),NSMakeSize(120,28)),@"compact entry does not force expanded minimum width");
Expect(NSEqualSizes(FYInlineLongCardSize(NSMakeSize(120,20),NO),NSMakeSize(160,34)),@"expanded card retains readable minimum width and height");
Expect(NSEqualSizes(FYInlineLongCardSize(NSMakeSize(300,200),YES),NSMakeSize(300,200)),@"engine measured larger size unchanged");
Expect(NSEqualRects(FYInlineLongCardBodyFrame(300,200,18,37),NSMakeRect(18,55,264,127)),@"body viewport honors placement title band");
Expect(NSEqualRects(FYInlineLongCardBodyFrame(100,50,18,0),NSMakeRect(18,18,80,24)),@"hidden title retains body minimums");
Expect(NSEqualRects(FYInlineLongCardBodyFrame(300,200,18,.25),NSMakeRect(18,18.25,264,163.75)),@"small positive title band still offsets body even below header threshold");
NSLog(@"PASS InlineTextPolicyTests: 15 assertions, no UI initialization");
} return 0; }
