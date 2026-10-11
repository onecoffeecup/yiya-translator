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
static CGImageRef EmbeddedImage(CGImageRef game, CGRect viewport, CGSize canvas) {
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,canvas.width,canvas.height,8,0,space,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context,.10,.12,.15,1);
    CGContextFillRect(context,CGRectMake(0,0,canvas.width,canvas.height));
    CGContextDrawImage(context,viewport,game);
    CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);return image;
}
static CGRect EmbeddedBox(CGRect box,CGRect viewport,CGSize canvas) {
    return CGRectMake((viewport.origin.x+box.origin.x*viewport.size.width)/canvas.width,
        (viewport.origin.y+box.origin.y*viewport.size.height)/canvas.height,
        box.size.width*viewport.size.width/canvas.width,box.size.height*viewport.size.height/canvas.height);
}

int main(void) { @autoreleasepool {
    NSURL *url=[NSURL fileURLWithPath:@"tests/fixtures/replay/assets/speaker-plate.png"];
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)url,NULL);
    CGImageRef image=source ? CGImageSourceCreateImageAtIndex(source,0,NULL) : NULL;
    Check(image!=NULL,@"synthetic source pixels must load");
    NSURL *patternURL=[NSURL fileURLWithPath:@"tests/fixtures/replay/assets/speaker-plate-textured.png"];
    CGImageSourceRef patternSource=CGImageSourceCreateWithURL((__bridge CFURLRef)patternURL,NULL);
    CGImageRef patterned=patternSource ? CGImageSourceCreateImageAtIndex(patternSource,0,NULL) : NULL;
    Check(patterned!=NULL,@"synthetic ink and textured body fixture must load");
    OCRTextItem *tightLabel=Item(@"青木",CGRectMake(.267,.256,.07,.043));
    OCRTextItem *patternBody=Item(@"田中に相談してね。",CGRectMake(.289,.179,.17,.053));
    NSArray *patternMarked=[FYOCRManager itemsByMarkingSpeakerLabels:@[tightLabel,patternBody] inImage:patterned];
    Check([(OCRTextItem *)patternMarked.firstObject speakerLabel] && !tightLabel.speakerLabel,@"tight ink bounds and a nonuniform translucent body still confirm the separate filled plate");
    Check([[FYContentRouter dialogueRouteForItems:patternMarked optionsCanPasteInline:YES filterObserver:nil].dialogueText isEqual:patternBody.text],@"exclude the structural label and retain a name mentioned in the body");
    CGSize canvas=CGSizeMake(1370,796);CGRect viewport=CGRectMake(396,305,800,450);
    CGImageRef embedded=EmbeddedImage(patterned,viewport,canvas);
    OCRTextItem *embeddedLabel=Item(@"青木",EmbeddedBox(tightLabel.boundingBox,viewport,canvas));
    OCRTextItem *embeddedBody=Item(patternBody.text,EmbeddedBox(patternBody.boundingBox,viewport,canvas));
    NSArray *embeddedMarked=[FYOCRManager itemsByMarkingSpeakerLabels:@[embeddedLabel,embeddedBody] inImage:embedded];
    Check([(OCRTextItem *)embeddedMarked.firstObject speakerLabel],@"a filled name plate remains metadata when the game is embedded above OBS controls");
    Check([[FYContentRouter dialogueRouteForItems:embeddedMarked optionsCanPasteInline:NO filterObserver:nil].dialogueText isEqual:patternBody.text],@"full-window fallback must also exclude the confirmed plate");
    CGImageRelease(embedded);
    CGImageRelease(patterned);CFRelease(patternSource);
    OCRTextItem *body=Item(@"明日は休みです。",CGRectMake(.289,.117,.18,.054));
    for (NSString *text in @[@"ててて",@"ink",@"？？？",@"みよ",@"青木",@"ルード"]) {
        OCRTextItem *label=Item(text,CGRectMake(.267,.183,.068,.057));
        NSArray *marked=[FYOCRManager itemsByMarkingSpeakerLabels:@[label,body] inImage:image];
        OCRTextItem *result=marked.firstObject;
        Check(result.speakerLabel && !label.speakerLabel,@"mark only copies with positive plate evidence");
        Check([result.text isEqual:text] && CGRectEqualToRect(result.boundingBox,label.boundingBox) &&
            result.confidence==label.confidence && [result.sourceBlockID isEqual:label.sourceBlockID],@"role evidence must not rewrite OCR or lose metadata");
        NSString *expected=body.text;
        FYContentRoute *route=[FYContentRouter dialogueRouteForItems:marked optionsCanPasteInline:YES filterObserver:nil];
        Check([route.dialogueText isEqual:expected] && route.optionItems.count==0,@"every confirmed plate is metadata; dialogue contains only the spoken body");
    }
    for (NSString *text in @[@"え……",@"うん、",@"ここ",@"ててて",@"Wait",@"田中",@"待機"]) {
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
    OCRTextItem *mentionedName=Item(@"田中に相談してね。",body.boundingBox);
    NSArray *mentioned=[FYOCRManager itemsByMarkingSpeakerLabels:@[Item(@"青木",label.boundingBox),mentionedName] inImage:image];
    Check([[FYContentRouter dialogueRouteForItems:mentioned optionsCanPasteInline:YES filterObserver:nil].dialogueText isEqual:mentionedName.text],@"a character name within the spoken sentence is preserved verbatim");
    CGImageRelease(image);CFRelease(source);
    NSLog(@"PASS SpeakerPlateTests: %lu assertions",(unsigned long)Checks);
} return 0; }
