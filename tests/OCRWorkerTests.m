#import "FYOCRRecognitionWorker.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
static void ReleasePixels(void *info,const void *data,size_t size){(*(NSUInteger *)info)++;free((void *)data);}
static CGImageRef Image(NSUInteger *released){unsigned char *pixels=calloc(32*32*4,1);CGDataProviderRef p=CGDataProviderCreateWithData(released,pixels,32*32*4,ReleasePixels);CGColorSpaceRef s=CGColorSpaceCreateDeviceRGB();CGImageRef i=CGImageCreate(32,32,8,32,128,s,(CGBitmapInfo)kCGImageAlphaPremultipliedLast,p,NULL,NO,kCGRenderingIntentDefault);CGColorSpaceRelease(s);CGDataProviderRelease(p);return i;}
@interface WorkerProbe : NSObject
@property(nonatomic,strong) NSMutableArray *calls;
@property(nonatomic,strong) OCRTextItem *item;
@end
@implementation WorkerProbe
@end
static FYOCRRecognitionOperationLease *Operations(WorkerProbe *p){
 return [[FYOCRRecognitionOperationLease alloc] initWithBlocks:^NSString *(CGImageRef i,FYOCRRecognitionSettings *s,NSArray **out,NSError **e){[p.calls addObject:@"full"];*out=@[p.item];return p.item.text;}
 items:^NSArray *(CGImageRef i,FYOCRRecognitionSettings *s,NSError **e){[p.calls addObject:@"items"];Check(CGImageGetWidth(i)>0,@"native recognizer receives actual image pixels");return @[p.item];}
 enlarged:^NSString *(CGImageRef i,CGRect region,FYOCRRecognitionSettings *s,NSArray **out,NSError **e){[p.calls addObject:@"enlarged"];*out=@[p.item];return p.item.text;}
 sourceText:^NSString *(NSArray *items,NSArray **out){[p.calls addObject:@"source"];*out=items;return [[items valueForKey:@"text"] componentsJoinedByString:@"\n"];}
 speakers:^NSArray *(NSArray *items,CGImageRef i){[p.calls addObject:@"speaker"];Check(CGImageGetWidth(i)==32,@"speaker pixels remain valid");return items;}
 modal:^NSArray *(NSArray *items,CGImageRef i,NSArray *x){[p.calls addObject:@"modal"];Check(CGImageGetWidth(i)==32,@"modal pixel analysis finishes before image release");return items;}
 manualPass1:^(void (^work)(void)){[p.calls addObject:@"scope_begin"];work();[p.calls addObject:@"scope_end"];}];
}
int main(void){@autoreleasepool{
 FYOCRRecognitionWorker *worker=[FYOCRRecognitionWorker new];
 Check(class_getInstanceVariable(FYOCRRecognitionWorker.class,"_host")==NULL,@"worker has no idle host storage");
 for(NSUInteger route=0;route<3;route++){
  BOOL manual=route==2,scoped=route==1;NSUInteger released=0;NSUInteger *releaseCounter=&released;CGImageRef image=Image(&released);
  FYOCRRecognitionImageLease *lease=[[FYOCRRecognitionImageLease alloc] initWithOwnedImage:image];
  WorkerProbe *p=[WorkerProbe new];p.calls=[NSMutableArray new];p.item=[OCRTextItem new];p.item.text=@"合成识别";p.item.boundingBox=CGRectMake(.2,.2,.4,.1);
  NSMutableArray *exclusions=[NSMutableArray new];
  FYOCRRecognitionSettings *s=[[FYOCRRecognitionSettings alloc] initWithManual:manual language:0 fastOCR:NO autoFit:NO scope:scoped?CGRectMake(.25,.25,.5,.5):CGRectMake(0,0,1,1) exclusions:exclusions];[exclusions addObject:@"external mutation"];
  Check(s.exclusions.count==0&&s.manual==manual&&!s.fastOCR&&!s.autoFit,@"immutable main-thread settings copy their array inputs");
  NSMutableArray *stages=[NSMutableArray new];__block NSUInteger raw=0;
  FYOCRRecognitionResult *result=[worker recognizeImageLease:lease settings:s refinement:[FYOCRRefinementStabilizer new] operations:Operations(p) cropScope:^(CGRect crop,CGSize size,void(^work)(void)){Check(size.width==32&&crop.size.width==16,@"canonical geometry reports the real pixel crop");work();} observer:^(FYOCRWorkerStage stage,FYOCRWorkerProgress *v,CGImageRef pixels){
   [stages addObject:@(stage)];if(stage==FYOCRWorkerRawCrop)raw++;
   if(stage==FYOCRWorkerMerged){Check(pixels&&*releaseCounter==0,@"merged observation precedes release");Check(v.modalItems[0]==p.item,@"observation model preserves original item identity");}
   if(stage==FYOCRWorkerReleasedImage) { Check(!pixels&&!lease.image&&*releaseCounter==1,@"finished notification follows actual image release"); }
  }];
  Check(!lease.image&&released==1,@"worker consumes and releases exactly its own image before returning");[lease finishImage];Check(released==1,@"repeat release is harmless");
  Check(result.modalItems.count==1&&result.modalItems[0]==p.item,@"immutable result retains original OCR object identity");
  for(NSString *setter in @[@"setItems:",@"setModalItems:",@"setText:",@"setError:",@"setDuration:"])Check(![result respondsToSelector:NSSelectorFromString(setter)],@"result has no mutable interface");
  NSArray *expected=manual?@[@"scope_begin",@"items",@"scope_end",@"modal"]:scoped?@[@"items",@"source",@"speaker",@"modal"]:@[@"full",@"speaker",@"modal"];
  Check([p.calls isEqual:expected],@"manual and realtime paths preserve native action order");
  Check(raw==(scoped?1:0),@"raw crop diagnostics occur only in the realtime scoped path");
  if(manual)Check([stages isEqual:@[@(FYOCRWorkerMappedPass1)]],@"manual path emits only its existing mapped observation");
  else Check([stages.firstObject integerValue]==FYOCRWorkerBegin&&[stages.lastObject integerValue]==FYOCRWorkerReleasedImage,@"realtime stages preserve start-to-release order");
 }
 __weak WorkerProbe *releasedHost;FYOCRRecognitionOperationLease *held;
 @autoreleasepool{WorkerProbe *p=[WorkerProbe new];releasedHost=p;held=Operations(p);}
 Check(releasedHost!=nil,@"bounded operation lease retains the original native receiver");held=nil;Check(!releasedHost,@"finished operation lease releases receiver while worker remains");
 NSUInteger released=0;
 @autoreleasepool{FYOCRRecognitionImageLease *unfinished=[[FYOCRRecognitionImageLease alloc] initWithOwnedImage:Image(&released)];Check(unfinished.image!=NULL,@"cancelled-before-work lease owns its image");}
 Check(released==1,@"unstarted lease releases image when discarded");
 printf("PASS OCR worker: %lu checks; native operations, real crop/image release, immutable results and bounded leases\n",(unsigned long)checks);
 }return 0;}
