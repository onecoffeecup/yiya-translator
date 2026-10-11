#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import "FYOCRManager.h"
#import "learning/FYLearningModels.h"

static NSUInteger Checks;
static void Check(BOOL value, NSString *message) {
    Checks++;if (!value) { NSLog(@"FAIL SpeakerPlateTests: %@",message);exit(1); }
}
static OCRTextItem *Item(NSString *text,CGRect box) {
    OCRTextItem *item=[OCRTextItem new];item.text=text;item.boundingBox=box;
    item.confidence=.9;item.sourceBlockID=@"synthetic-label";return item;
}
static CGImageRef Image(BOOL separate, BOOL bounded) {
    size_t w=800,h=450;unsigned char *pixels=calloc(w*h,4);
    for (size_t y=0;y<h;y++) for (size_t x=0;x<w;x++) {
        CGFloat xx=(x+.5)/w,yy=1-(y+.5)/h;
        unsigned char *p=pixels+(y*w+x)*4;p[0]=32;p[1]=45;p[2]=55;p[3]=255;
        if (xx>=.24 && xx<.72 && yy>=.07 && yy<.17) { p[0]=221;p[1]=227;p[2]=234; }
        if (xx>=.24 && xx<(bounded ? .36 : .72) && yy>=.17 && yy<(bounded ? .26 : .45)) {
            p[0]=separate ? 250 : 221;p[1]=separate ? 178 : 227;p[2]=separate ? 66 : 234;
        }
    }
    NSData *data=[NSData dataWithBytesNoCopy:pixels length:w*h*4 freeWhenDone:YES];
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGImageRef image=CGImageCreate(w,h,8,32,w*4,space,(CGBitmapInfo)kCGImageAlphaLast,provider,NULL,NO,kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return image;
}

int main(void) { @autoreleasepool {
    NSURL *url=[NSURL fileURLWithPath:@"tests/fixtures/replay/assets/speaker-plate.png"];
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)url,NULL);
    CGImageRef image=source ? CGImageSourceCreateImageAtIndex(source,0,NULL) : NULL;
    Check(image!=NULL,@"synthetic source pixels must load");
    OCRTextItem *body=Item(@"明日は休みです。",CGRectMake(.289,.117,.18,.054));
    for (NSString *text in @[@"ててて",@"ink",@"？？？",@"みよ",@"青木",@"ルード"]) {
        OCRTextItem *label=Item(text,CGRectMake(.267,.183,.068,.057));
        NSArray *marked=[FYOCRManager itemsByMarkingSpeakerLabels:@[label,body] inImage:image];
        OCRTextItem *result=marked.firstObject;
        Check(result.speakerLabel && !label.speakerLabel,@"mark only copies with positive plate evidence");
        Check([result.text isEqual:text] && CGRectEqualToRect(result.boundingBox,label.boundingBox) &&
            result.confidence==label.confidence && [result.sourceBlockID isEqual:label.sourceBlockID],@"role evidence must not rewrite OCR or lose metadata");
        BOOL known=[FYContentRouter looksLikeSpeakerName:text];
        NSString *expected=known ? [NSString stringWithFormat:@"%@\n%@",text,body.text] : body.text;
        FYContentRoute *route=[FYContentRouter dialogueRouteForItems:marked optionsCanPasteInline:YES filterObserver:nil];
        Check([route.dialogueText isEqual:expected] && route.optionItems.count==0,@"unrecognized plate is metadata; recognized speaker remains in complete source");
    }
    for (NSString *text in @[@"え……",@"うん、",@"ここ",@"ててて",@"Wait"]) {
        OCRTextItem *speech=Item(text,CGRectMake(.267,.183,.068,.057));
        FYContentRoute *route=[FYContentRouter dialogueRouteForItems:@[speech,body] optionsCanPasteInline:YES filterObserver:nil];
        Check([route.dialogueText hasPrefix:text],@"ordinary unmarked speech is never removed by script, repetition or width");
    }
    for (NSUInteger variant=0;variant<2;variant++) {
        CGImageRef ordinary=Image(variant==1,variant==0);
        OCRTextItem *speech=Item(@"え……",CGRectMake(.267,.183,.068,.057));
        NSArray *marked=[FYOCRManager itemsByMarkingSpeakerLabels:@[speech,body] inImage:ordinary];
        Check(![(OCRTextItem *)marked.firstObject speakerLabel],@"same body backdrop or unbounded scene color cannot prove a speaker plate");
        Check([[FYContentRouter dialogueRouteForItems:marked optionsCanPasteInline:YES filterObserver:nil].dialogueText hasPrefix:speech.text],@"ambiguous background preserves a short spoken first line");
        CGImageRelease(ordinary);
    }
    Check([FYOCRManager itemsByMarkingSpeakerLabels:@[body] inImage:image].firstObject==body,@"body without separate leading row stays untouched");
    Check([FYOCRManager itemsByMarkingSpeakerLabels:@[body] inImage:NULL].firstObject==body,@"missing pixels cannot prove label role");
    Check(!FYDialogueTextsAreEquivalent(@"青木\n明日は休みです。",@"田中\n明日は休みです。"),@"different recognized speakers keep distinct identities");
    OCRTextItem *label=Item(@"ててて",CGRectMake(.267,.183,.068,.057));
    OCRTextItem *shortBody=Item(@"え……",CGRectMake(.289,.117,.045,.054));
    NSArray *shortMarked=[FYOCRManager itemsByMarkingSpeakerLabels:@[label,shortBody] inImage:image];
    Check([(OCRTextItem *)shortMarked.firstObject speakerLabel],@"a real plate is still distinct above a narrower short body");
    Check([[FYContentRouter dialogueRouteForItems:shortMarked optionsCanPasteInline:YES filterObserver:nil].dialogueText isEqual:shortBody.text],@"preserve the short spoken body below an unrecognized plate");
    CGImageRelease(image);CFRelease(source);
    NSLog(@"PASS SpeakerPlateTests: %lu assertions",(unsigned long)Checks);
} return 0; }
