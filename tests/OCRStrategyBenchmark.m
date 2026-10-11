// Offline experiment: fictional CoreText images, production Vision adapter,
// source deduplication, refinement merge and modal policy. No NSApplication,
// window capture, devices, settings, credentials, translation or network.
#import "FYOCRManager.h"
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <sys/stat.h>
#import <unistd.h>

static BOOL WriteJSON(id value, NSString *path) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:NULL];
    BOOL ok = [data writeToFile:path atomically:YES];
    if (ok) chmod(path.fileSystemRepresentation, 0600);
    return ok;
}

// Experimental input preparation only. The remaining crop recognition and
// coordinate remapping are inherited from the real FYOCRManager.
@interface FYAspectExperiment : FYOCRManager
@end
@implementation FYAspectExperiment
+ (CGImageRef)copyEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region pixelCrop:(CGRect *)outCrop {
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    CGRect crop = CGRectMake(floor(region.origin.x*w), floor((1-CGRectGetMaxY(region))*h),
                             MAX(2, floor(region.size.width*w)), MAX(2, floor(region.size.height*h)));
    crop = CGRectIntersection(crop, CGRectMake(0,0,w,h));
    if (CGRectIsNull(crop) || crop.size.width < 2 || crop.size.height < 2) return NULL;
    CGImageRef input = CGImageCreateWithImageInRect(image, crop);
    if (!input) return NULL;
    CGFloat scale = MIN(2.0, 1800.0/MAX(crop.size.width,crop.size.height));
    size_t sw = MAX(2, floor(crop.size.width*scale)), sh = MAX(2, floor(crop.size.height*scale));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL,sw,sh,8,0,space,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) { CGImageRelease(input); return NULL; }
    CGContextSetInterpolationQuality(context,kCGInterpolationHigh);
    CGContextDrawImage(context,CGRectMake(0,0,sw,sh),input);
    CGImageRef output = CGBitmapContextCreateImage(context);
    CGContextRelease(context); CGImageRelease(input);
    if (output && outCrop) *outCrop = crop;
    return output;
}
@end

static NSDictionary *Line(NSString *text, CGFloat x, CGFloat y, CGFloat size) {
    return @{ @"text":text, @"x":@(x), @"y":@(y), @"size":@(size) };
}
static NSDictionary *Case(NSString *name, NSInteger w, NSInteger h, NSArray *lines, NSString *style) {
    return @{ @"name":name, @"width":@(w), @"height":@(h), @"lines":lines, @"style":style };
}
static NSArray *Cases(void) {
    NSString *longLine = @"明日は図書館で新しい本を探してから、庭の花に水をあげる予定です。";
    return @[
      Case(@"dialogue-1080",1920,1080,@[Line(@"明日は図書館に行きます。",110,230,52),Line(@"庭の花がきれいに咲いています。",110,150,52)],@"light"),
      Case(@"wide-4k",3840,2160,@[Line(longLine,120,360,72),Line(@"帰り道で友達に会いました。",120,250,64)],@"light"),
      Case(@"wide-small",3200,900,@[Line(longLine,90,220,42),Line(@"春の風が窓から入ってきました。",90,140,42)],@"light"),
      Case(@"menu-sparse",1920,1080,@[Line(@"図書館へ行く",150,810,38),Line(@"庭で休む",1150,810,38),Line(@"友達に話しかける",150,240,38),Line(@"家に帰る",1150,240,38)],@"light"),
      Case(@"menu-small",1440,900,@[Line(@"新しいゲーム",140,700,28),Line(@"続きを始める",140,570,28),Line(@"設定を開く",140,440,28),Line(@"終了する",140,310,28)],@"light"),
      Case(@"dense-page",1920,1080,@[Line(@"今日の予定を確認しました。",100,850,38),Line(@"午前中は図書館で勉強します。",100,730,38),Line(@"午後は庭の花に水をあげます。",100,610,38),Line(@"夕方には友達と散歩します。",100,490,38),Line(@"雨が降ったら家で本を読みます。",100,370,38),Line(@"明日も楽しい一日になります。",100,250,38)],@"light"),
      Case(@"low-contrast",1920,1080,@[Line(@"静かな雨が降り始めました。",110,230,48),Line(@"窓の外に小さな鳥がいます。",110,155,48)],@"low"),
      Case(@"dark-dialogue",1920,1080,@[Line(@"星がたくさん見えますね。",100,250,48),Line(@"明日もここで会いましょう。",100,170,48)],@"dark"),
      Case(@"edge-text",1600,900,@[Line(@"次のページへ進みます。",8,70,40),Line(@"今日はよく晴れています。",8,12,40)],@"light"),
      Case(@"short-and-reading",1600,900,@[Line(@"はるか",110,270,16),Line(@"春香",110,225,38),Line(@"え",110,150,38),Line(@"一緒に帰りましょう。",220,150,38)],@"light"),
      Case(@"mixed-labels",1920,1080,@[Line(@"セーブ 03",100,750,38),Line(@"10月10日",100,600,38),Line(@"図書館 Library",100,450,38),Line(@"音量 80%",100,300,38)],@"light"),
      Case(@"blank",1920,1080,@[],@"light")
    ];
}
static NSArray *StressCases(void) {
    return @[
      Case(@"tiny-menu",1920,1080,@[Line(@"新しいゲームを始める",130,720,14),Line(@"前の記録から続きを始める",130,570,14),Line(@"設定を確認してから終了する",130,420,14)],@"light"),
      Case(@"tiny-dialogue-4k",3840,2160,@[Line(@"図書館へ行く前に、庭の小さな花に水をあげましょう。",110,220,22),Line(@"明日もきっと楽しい一日になります。",110,150,22)],@"light"),
      Case(@"soft-dialogue",1920,1080,@[Line(@"雨が降り始めたので、窓を閉めましょう。",110,225,28),Line(@"本を読みながら、友達を待っています。",110,165,28)],@"soft"),
      Case(@"soft-menu",1600,900,@[Line(@"図書館の本を借りる",110,630,20),Line(@"庭の花を調べる",920,630,20),Line(@"友達に手紙を書く",110,220,20),Line(@"明日の予定を確認する",920,220,20)],@"soft")
    ];
}

static CGImageRef Generate(NSDictionary *spec, NSMutableArray *truth) {
    size_t w=[spec[@"width"] unsignedIntegerValue],h=[spec[@"height"] unsignedIntegerValue];
    BOOL dark=[spec[@"style"] isEqual:@"dark"],low=[spec[@"style"] isEqual:@"low"];
    BOOL soft=[spec[@"style"] isEqual:@"soft"];
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,w,h,8,0,space,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space); if (!context) return NULL;
    CGFloat background=dark ? .10 : .94;
    CGContextSetRGBFillColor(context,background,background,background,1);
    CGContextFillRect(context,CGRectMake(0,0,w,h));
    for (NSDictionary *line in spec[@"lines"]) {
        CGFloat x=[line[@"x"] doubleValue],y=[line[@"y"] doubleValue],size=[line[@"size"] doubleValue];
        CTFontRef font=CTFontCreateWithName(CFSTR("HiraginoSans-W3"),size,NULL);
        NSDictionary *attributes=@{(__bridge NSString *)kCTFontAttributeName:(__bridge id)font,
          (__bridge NSString *)kCTForegroundColorFromContextAttributeName:@YES};
        CTLineRef text=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)[[NSAttributedString alloc] initWithString:line[@"text"] attributes:attributes]);
        CGFloat ascent=0,descent=0,leading=0; double width=CTLineGetTypographicBounds(text,&ascent,&descent,&leading);
        if (x+width>w || y-descent<0 || y+ascent>h) { CFRelease(text);CFRelease(font);CGContextRelease(context);return NULL; }
        CGFloat ink=dark ? .97 : (low ? .73 : (soft ? .55 : .08));
        CGContextSetRGBFillColor(context,ink,ink,ink,1);CGContextSetTextPosition(context,x,y);CTLineDraw(text,context);
        [truth addObject:@{ @"text":line[@"text"], @"box":@[@(x/w),@((y-descent)/h),@(width/w),@((ascent+descent)/h)] }];
        CFRelease(text);CFRelease(font);
    }
    CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);
    if (soft && image) {
        // Deterministic resolution loss: render at one third size and restore.
        // Ground truth remains the original fictional text, never OCR output.
        for (NSUInteger pass=0;pass<2;pass++) {
            size_t dw=pass==0 ? w/3 : w,dh=pass==0 ? h/3 : h;
            space=CGColorSpaceCreateDeviceRGB();
            context=CGBitmapContextCreate(NULL,dw,dh,8,0,space,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(space);
            if (!context) {CGImageRelease(image);return NULL;}
            CGContextSetInterpolationQuality(context,kCGInterpolationHigh);
            CGContextDrawImage(context,CGRectMake(0,0,dw,dh),image);
            CGImageRelease(image);image=CGBitmapContextCreateImage(context);CGContextRelease(context);
            if (!image) return NULL;
        }
    }
    return image;
}

static NSArray *Snapshot(NSArray<OCRTextItem *> *items) {
    NSMutableArray *result=[NSMutableArray array];
    for (OCRTextItem *item in items) { CGRect b=item.boundingBox;
        [result addObject:@{ @"text":item.text ?: @"", @"confidence":@(item.confidence),
          @"box":@[@(b.origin.x),@(b.origin.y),@(b.size.width),@(b.size.height)] }];
    }
    return result;
}
static NSDictionary *Run(CGImageRef image, NSString *mode) {
    FYOCRManager *ocr=[FYOCRManager new];
    NSMutableArray *requests=[NSMutableArray array];
    ocr.configurationObserver=^(BOOL fast,NSInteger language,size_t w,size_t h,CGFloat minimum) {
        [requests addObject:@{ @"width":@(w),@"height":@(h),@"minimum_text_height":@(minimum),@"fast":@(fast),@"language":@(language) }];
    };
    NSString *(^recognize)(CGImageRef,NSArray **,NSError **)=^NSString *(CGImageRef input,NSArray **blocks,NSError **error) {
        return [FYOCRManager sourceTextForItems:[ocr recognizeTextItemsInImage:input fastOCR:NO languageSegment:0 error:error] blocks:blocks];
    };
    NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;
    NSError *error=nil;NSArray<OCRTextItem *> *blocks=nil;
    NSString *text=recognize(image,&blocks,&error);
    NSArray *coarse=Snapshot(blocks);
    __block NSError *refinementError=nil;
    Class preparation=[mode isEqual:@"current"] ? FYOCRManager.class : FYAspectExperiment.class;
    NSString *(^refine)(CGRect,NSArray **,NSError **)=^NSString *(CGRect region,NSArray **items,NSError **innerError) {
        NSString *value=[preparation recognizeEnlargedImage:image visionRegion:region recognizer:recognize blocks:items error:innerError];
        if (innerError && *innerError) refinementError=*innerError;
        return value;
    };
    if (!error && ([mode isEqual:@"current"] || [mode isEqual:@"aspect"])) {
        FYApplyOCRRefinement(blocks,YES,refine,nil,&text,&blocks);
    } else if (!error) {
        NSMutableArray *fine=[NSMutableArray array];NSUInteger count=0;
        for (OCRTextItem *block in blocks) {
            CGRect b=block.boundingBox;
            // Fixed exploratory heuristic, never reads the expected answers.
            if ([mode isEqual:@"quality"] && block.confidence>=.90 && b.size.height*CGImageGetHeight(image)>=48) continue;
            if (count>=8) break;
            CGFloat paddingY=b.size.height*.35,paddingX=b.size.height*.5*CGImageGetHeight(image)/CGImageGetWidth(image);
            CGRect region=CGRectIntersection(CGRectInset(b,-paddingX,-paddingY),CGRectMake(0,0,1,1));
            NSArray *items=nil;NSError *cropError=nil;refine(region,&items,&cropError);count++;
            if (cropError) break;
            if (items.count) [fine addObjectsFromArray:items];
        }
        if (fine.count) blocks=[FYOCRManager mergeCoarseItems:blocks refinedItems:fine];
    }
    blocks=[FYOCRManager items:blocks scopedToModalInImage:image exclusions:@[]];
    text=[[blocks valueForKey:@"text"] componentsJoinedByString:@"\n"] ?: @"";
    NSTimeInterval elapsed=NSProcessInfo.processInfo.systemUptime-start;
    return @{ @"mode":mode,@"elapsed_ms":@(elapsed*1000),@"requests":requests,
      @"coarse":coarse,@"blocks":Snapshot(blocks),@"text":text,
      @"error_code":@((error ?: refinementError).code) };
}

int main(int argc,const char *argv[]) { @autoreleasepool {
    alarm(420);
    if (argc!=4) return 2;
    NSString *directory=@(argv[1]);NSInteger repeats=[@(argv[2]) integerValue];
    if (repeats<1 || repeats>20) return 2;
    NSString *kind=@(argv[3]);NSArray *specs=[kind isEqual:@"stress"] ? StressCases() : Cases();
    if ([kind isEqual:@"all"]) specs=[Cases() arrayByAddingObjectsFromArray:StressCases()];
    NSArray *modes=@[@"current",@"aspect",@"regions",@"quality"];
    NSMutableArray *corpus=[NSMutableArray array],*runs=[NSMutableArray array];
    // Exclude lazy Vision initialization from the measured runs.
    NSMutableArray *warmTruth=[NSMutableArray array];CGImageRef warm=Generate(Cases()[0],warmTruth);
    if (!warm) return 2;
    for (NSString *mode in modes) if ([Run(warm,mode)[@"error_code"] integerValue]) {CGImageRelease(warm);return 3;}
    CGImageRelease(warm);
    NSUInteger caseIndex=0;
    for (NSDictionary *spec in specs) { @autoreleasepool {
        NSMutableArray *truth=[NSMutableArray array];CGImageRef image=Generate(spec,truth);if (!image) return 4;
        NSString *path=[directory stringByAppendingPathComponent:[spec[@"name"] stringByAppendingString:@".png"]];
        CGImageDestinationRef png=CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],CFSTR("public.png"),1,NULL);
        if (!png) {CGImageRelease(image);return 4;}
        CGImageDestinationAddImage(png,image,NULL);BOOL saved=CGImageDestinationFinalize(png);CFRelease(png);
        if (!saved) {CGImageRelease(image);return 4;}chmod(path.fileSystemRepresentation,0600);
        [corpus addObject:@{ @"name":spec[@"name"],@"image":path.lastPathComponent,@"width":spec[@"width"],@"height":spec[@"height"],@"truth":truth }];
        for (NSInteger repetition=0;repetition<repeats;repetition++) {
            for (NSUInteger offset=0;offset<modes.count;offset++) { @autoreleasepool {
                NSString *mode=modes[(offset+caseIndex+repetition)%modes.count];
                NSMutableDictionary *run=[Run(image,mode) mutableCopy];run[@"case"]=spec[@"name"];run[@"repetition"]=@(repetition);
                [runs addObject:run];
                if (!WriteJSON(@{ @"case":spec[@"name"],@"mode":mode,@"completed":@(runs.count),@"total":@(specs.count*modes.count*repeats) },[directory stringByAppendingPathComponent:@"progress.json"])) return 4;
                if ([run[@"error_code"] integerValue]) {WriteJSON(run,[directory stringByAppendingPathComponent:@"failure.json"]);CGImageRelease(image);return 3;}
            }}
        }
        CGImageRelease(image);caseIndex++;
    }}
    NSDictionary *result=@{ @"schema_version":@1,@"repeats":@(repeats),@"corpus_kind":kind,@"warmup":@"one unmeasured run per mode",
      @"modes":modes,@"corpus":corpus,@"runs":runs,@"os":NSProcessInfo.processInfo.operatingSystemVersionString };
    return WriteJSON(result,[directory stringByAppendingPathComponent:@"raw.json"]) ? 0 : 4;
} }
