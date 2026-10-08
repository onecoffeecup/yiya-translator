// Rebuild fictional input assets, never capture a screen or open a device.
// clang -fobjc-arc tests/GenerateReplayMedia.m -framework Foundation \
//   -framework CoreGraphics -framework CoreText -framework ImageIO \
//   -framework AVFoundation -framework CoreVideo -framework CoreMedia -o /tmp/yiya-media
// /tmp/yiya-media tests/fixtures/replay/assets
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <unistd.h>

int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc != 2) return 2;
    NSString *directory=@(argv[1]);
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    size_t width=1600,height=900;
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,width,height,8,width*4,space,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space); if(!context) return 2;
    CGContextSetRGBFillColor(context,1,1,1,1); CGContextFillRect(context,CGRectMake(0,0,width,height));
    CTFontRef font=CTFontCreateWithName(CFSTR("Helvetica"),64,NULL);
    NSDictionary *attributes=@{(__bridge NSString *)kCTFontAttributeName:(__bridge id)font,
        (__bridge NSString *)kCTForegroundColorFromContextAttributeName:@YES};
    NSAttributedString *text=[[NSAttributedString alloc] initWithString:@"Welcome to the test garden" attributes:attributes];
    CTLineRef line=CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
    CGContextSetRGBFillColor(context,0,0,0,1); CGContextSetTextPosition(context,100,190); CTLineDraw(line,context);
    CFRelease(line); CFRelease(font);
    CGImageRef image=CGBitmapContextCreateImage(context); CGContextRelease(context);
    NSURL *png=[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"english-dialogue.png"]];
    CGImageDestinationRef destination=CGImageDestinationCreateWithURL((__bridge CFURLRef)png,CFSTR("public.png"),1,NULL);
    if(!destination) return 2;
    CGImageDestinationAddImage(destination,image,NULL);
    BOOL ok=CGImageDestinationFinalize(destination); CFRelease(destination); if(!ok) return 2;
    NSURL *video=[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"english-dialogue.mp4"]];
    [NSFileManager.defaultManager removeItemAtURL:video error:NULL];
    AVAssetWriter *writer=[[AVAssetWriter alloc] initWithURL:video fileType:AVFileTypeMPEG4 error:NULL];
    AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
        outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@(width),AVVideoHeightKey:@(height)}];
    AVAssetWriterInputPixelBufferAdaptor *adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32ARGB),
            (id)kCVPixelBufferWidthKey:@(width),(id)kCVPixelBufferHeightKey:@(height)}];
    [writer addInput:input]; if(![writer startWriting]) return 2;
    [writer startSessionAtSourceTime:kCMTimeZero];
    for(int index=0;index<4;index++) {
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
        while(!input.readyForMoreMediaData && deadline.timeIntervalSinceNow>0) usleep(5000);
        if(!input.readyForMoreMediaData) return 2;
        CVPixelBufferRef buffer=NULL;
        if(CVPixelBufferPoolCreatePixelBuffer(NULL,adaptor.pixelBufferPool,&buffer)!=kCVReturnSuccess) return 2;
        CVPixelBufferLockBaseAddress(buffer,0);
        space=CGColorSpaceCreateDeviceRGB();
        context=CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer),width,height,8,CVPixelBufferGetBytesPerRow(buffer),space,kCGImageAlphaNoneSkipFirst);
        CGColorSpaceRelease(space); if(!context) return 2;
        CGContextDrawImage(context,CGRectMake(0,0,width,height),image); CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(buffer,0);
        ok=[adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(index,2)]; CVPixelBufferRelease(buffer);
        if(!ok) return 2;
    }
    CGImageRelease(image); [input markAsFinished];
    __block BOOL done=NO; [writer finishWritingWithCompletionHandler:^{done=YES;}];
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
    while(!done && deadline.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return done && writer.status==AVAssetWriterStatusCompleted ? 0 : 2;
} }
