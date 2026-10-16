#import "inline/FYInlineRenderingGeometry.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
int main(void){@autoreleasepool{
    Check(FYInlineLongCardLineHeight(12.2,-3.1,.2)==24,@"line height keeps ceil before original eight-point spacing");
    Check(FYInlineLongCardLineHeight(12,-3,0)==23,@"integral native metrics preserve spacing without extra rounding");
    Check(FYInlineLongCardMinimumHeight(19)==93,@"minimum readable card retains three lines and original padding");
    Check(FYInlineLongCardBodyViewport(33)==0&&FYInlineLongCardBodyViewport(80)==44,@"body viewport clamps only negative available height");
    Check(NSEqualSizes(FYInlineLongCardSize(NSMakeSize(40,20),YES),NSMakeSize(60,28)),@"compact card retains minimum size");
    Check(NSEqualSizes(FYInlineLongCardSize(NSMakeSize(100,20),NO),NSMakeSize(160,34)),@"normal card retains minimum size");
    Check(NSEqualSizes(FYInlineLongCardSize(NSMakeSize(300,400),NO),NSMakeSize(300,400)),@"large card size remains unchanged");
    Check(NSEqualRects(FYInlineLongCardBodyFrame(300,200,14,24),NSMakeRect(14,38,272,148)),@"body geometry keeps actual title-band offset");
    Check(NSEqualRects(FYInlineLongCardBodyFrame(300,200,14,0),NSMakeRect(14,14,272,172)),@"body without title retains original padding");
    NSRect fractional=FYInlineLongCardBodyFrame(300,200,14,.1);Check(fabs(fractional.origin.y-14.1)<.00001&&fabs(fractional.size.height-171.9)<.00001,@"positive fractional title band retains original branch and precision");
    Check(NSEqualRects(FYInlineLongCardBodyFrame(40,20,14,24),NSMakeRect(14,38,80,24)),@"small-body readable minima remain approved behavior");
    Check(NSEqualRects(FYInlineLongCardBodyFrame(300,200,14,-1),NSMakeRect(14,14,272,172)),@"nonpositive title band follows original no-title branch");
    printf("PASS InlineRenderingGeometryTests: %lu checks; canonical pure rendering dimensions\n",(unsigned long)checks);
}return 0;}
