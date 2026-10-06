#import "LearningAppTestSupport.h"

static OCRTextItem *Line(NSString *text, CGRect box) {
    OCRTextItem *item=[OCRTextItem new];item.text=text;item.boundingBox=box;return item;
}

@interface CropCoordinateApp : AppDelegate
@property(nonatomic) BOOL recognizedBottom;
@end
@implementation CropCoordinateApp
- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)language error:(NSError **)error {
    CFDataRef pixels=CGDataProviderCopyData(CGImageGetDataProvider(image));
    const UInt8 *bytes=CFDataGetBytePtr(pixels);
    size_t offset=CGImageGetHeight(image)/2*CGImageGetBytesPerRow(image)+CGImageGetWidth(image)/2*4;
    self.recognizedBottom=bytes[offset+2]>200 && bytes[offset]<30;
    CFRelease(pixels);
    OCRTextItem *item=Line(@"なんだ、お初か。",CGRectMake(0.1,0.2,0.7,0.3));
    item.lastLineBox=item.boundingBox;
    return @[item];
}
@end

int main(void){@autoreleasepool{
    [NSApplication sharedApplication];
    NSArray *complete=@[Line(@"花椿",CGRectMake(0.25,0.28,0.08,0.04)),
        Line(@"なんだ、お初か。",CGRectMake(0.29,0.19,0.2,0.04)),
        Line(@"この子、宇賀神みよちゃん。",CGRectMake(0.29,0.12,0.4,0.04)),
        Line(@"ね？",CGRectMake(0.29,0.05,0.06,0.04))];
    NSArray *refined=@[Line(@"花椿",CGRectMake(0.251,0.281,0.08,0.04)),
        Line(@"この子、宇賀神みよちゃん。",CGRectMake(0.291,0.121,0.4,0.04)),
        Line(@"ね？",CGRectMake(0.291,0.051,0.06,0.04))];
    NSArray *merged=MergeRefinedOCRItems(complete,refined);
    NSString *expected=@"花椿\nなんだ、お初か。\nこの子、宇賀神みよちゃん。\nね？";
    Require([[[merged valueForKey:@"text"] componentsJoinedByString:@"\n"] isEqualToString:expected],@"second-pass omission preserves the first-pass body line in reading order");
    NSArray *corrected=MergeRefinedOCRItems(@[Line(@"宇賀神みよちゃん",CGRectMake(0.2,0.1,0.4,0.04))],
        @[Line(@"宇賀神美代ちゃん",CGRectMake(0.201,0.101,0.4,0.04))]);
    Require(corrected.count==1 && [[[corrected firstObject] text] isEqualToString:@"宇賀神美代ちゃん"],@"refined spelling replaces an overlapping coarse read without duplicates");
    NSArray *repeated=MergeRefinedOCRItems(@[Line(@"ね？",CGRectMake(0.2,0.2,0.1,0.04))],
        @[Line(@"ね？",CGRectMake(0.2,0.1,0.1,0.04))]);
    Require(repeated.count==2,@"the same words on different lines are retained");
    NSArray *reading=MergeRefinedOCRItems(@[Line(@"宇賀神美代ちゃん",CGRectMake(0.2,0.1,0.4,0.04))],
        @[Line(@"うがじん",CGRectMake(0.2,0.13,0.1,0.012))]);
    Require(reading.count==2,@"a small overlapping furigana box cannot replace a missing full body line");
    Require(MergeRefinedOCRItems(complete,@[]).count==complete.count,@"empty refinement keeps the complete first pass");
    CropCoordinateApp *app=[CropCoordinateApp new];
    // CGImage row zero is the top: red upper half, blue lower half.
    NSMutableData *data=[NSMutableData dataWithLength:200*100*4];UInt8 *bytes=data.mutableBytes;
    for(NSUInteger y=0;y<100;y++){for(NSUInteger x=0;x<200;x++){
        NSUInteger offset=(y*200+x)*4;bytes[offset]=y<50?255:0;bytes[offset+2]=y<50?0:255;bytes[offset+3]=255;
    }}
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGImageRef image=CGImageCreate(200,100,8,32,800,space,(CGBitmapInfo)kCGImageAlphaLast,provider,NULL,NO,kCGRenderingIntentDefault);
    NSArray *cropBlocks=nil;NSError *error=nil;
    [app recognizeEnlargedRegionOfImage:image regionX:0.2 regionY:0.1 regionWidth:0.5 regionHeight:0.2 fastOCR:NO languageSegment:0 blocks:&cropBlocks error:&error];
    Require(!error && app.recognizedBottom,@"a bottom dialogue region crops bottom pixels, not the opposite top region");
    CGRect box=[cropBlocks.firstObject boundingBox],last=[cropBlocks.firstObject lastLineBox];
    Require(fabs(box.origin.x-0.25)<0.001 && fabs(box.origin.y-0.14)<0.001 && fabs(box.size.width-0.35)<0.001 && fabs(box.size.height-0.06)<0.001,@"refined bounding boxes map back into full-frame Vision coordinates");
    Require(CGRectEqualToRect(box,last),@"last-line geometry uses the same full-frame coordinates");
    CGImageRelease(image);CGColorSpaceRelease(space);CGDataProviderRelease(provider);
    NSLog(@"PASS: same-frame OCR merge, omitted first line, corrected words, repeated lines, crop direction and full-frame coordinates");
}return 0;}
