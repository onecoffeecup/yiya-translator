#import "FYOCRVisionEngine.h"+#import <math.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
int main(void){@autoreleasepool{
    FYOCRVisionEngine *engine=[FYOCRVisionEngine new];
    Check(!engine.configurationObserver,@"cold standalone Vision engine has no callback or initiated request");
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,640,480,8,0,space,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context,1,1,1,1);CGContextFillRect(context,CGRectMake(0,0,640,480));
    CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);
    for(NSUInteger route=0;route<2;route++){
        __block NSUInteger configured=0,raw=0;
        BOOL fast=route==1;NSInteger language=fast?1:0;
        engine.configurationObserver=^(BOOL observedFast,NSInteger observedLanguage,size_t width,size_t height,CGFloat minimum){
            configured++;Check(observedFast==fast&&observedLanguage==language,@"real Vision receives original mode/language configuration");
            Check(width==640&&height==480&&fabs(minimum-(fast?32.0/480.0:.10))<.000001,@"actual request keeps original adaptive minimum height");
        };
        Check(configured==0,@"assigning observer starts no recognition");
        NSError *error=nil;
        NSArray *items=[engine recognizeTextItemsInImage:image fastOCR:fast languageSegment:language rawObserver:^(NSArray *observations){raw++;Check(observations.count==0,@"blank synthetic pixels produce no raw glyph observations");} error:&error];
        Check(!error&&items.count==0&&configured==1&&raw==1,@"standalone engine executes real Vision and delivers its raw observation once");
    }
    CGImageRelease(image);
    printf("PASS standalone Vision: %lu checks; Foundation/CoreGraphics/Vision, real synthetic pixels\n",(unsigned long)checks);
}return 0;}
