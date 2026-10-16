#import "FYOCRRecognitionWorker.h"
@implementation FYOCRRecognitionSettings
- (instancetype)initWithManual:(BOOL)manual language:(NSInteger)language fastOCR:(BOOL)fast autoFit:(BOOL)autoFit scope:(CGRect)scope exclusions:(NSArray<NSValue *> *)exclusions {
 if((self=[super init])){_manual=manual;_language=language;_fastOCR=fast;_autoFit=autoFit;_scope=scope;_exclusions=[exclusions copy];}return self;
}
@end
@implementation FYOCRRecognitionImageLease { CGImageRef _image; }
- (instancetype)initWithOwnedImage:(CGImageRef)image { if((self=[super init]))_image=image;return self; }
- (CGImageRef)image { return _image; }
- (void)finishImage { if(_image){CGImageRelease(_image);_image=NULL;} }
- (void)dealloc { [self finishImage]; }
@end
@implementation FYOCRRecognitionOperationLease {
 NSString *(^_blocks)(CGImageRef,FYOCRRecognitionSettings *,NSArray<OCRTextItem *> **,NSError **);
 NSArray<OCRTextItem *> *(^_items)(CGImageRef,FYOCRRecognitionSettings *,NSError **);
 NSString *(^_enlarged)(CGImageRef,CGRect,FYOCRRecognitionSettings *,NSArray<OCRTextItem *> **,NSError **);
 NSString *(^_sourceText)(NSArray<OCRTextItem *> *,NSArray<OCRTextItem *> **);
 NSArray<OCRTextItem *> *(^_speakers)(NSArray<OCRTextItem *> *,CGImageRef);
 NSArray<OCRTextItem *> *(^_modal)(NSArray<OCRTextItem *> *,CGImageRef,NSArray<NSValue *> *);
 void (^_manualPass1)(void (^)(void));
}
- (instancetype)initWithBlocks:(NSString *(^)(CGImageRef,FYOCRRecognitionSettings *,NSArray<OCRTextItem *> **,NSError **))blocks items:(NSArray<OCRTextItem *> *(^)(CGImageRef,FYOCRRecognitionSettings *,NSError **))items enlarged:(NSString *(^)(CGImageRef,CGRect,FYOCRRecognitionSettings *,NSArray<OCRTextItem *> **,NSError **))enlarged sourceText:(NSString *(^)(NSArray<OCRTextItem *> *,NSArray<OCRTextItem *> **))sourceText speakers:(NSArray<OCRTextItem *> *(^)(NSArray<OCRTextItem *> *,CGImageRef))speakers modal:(NSArray<OCRTextItem *> *(^)(NSArray<OCRTextItem *> *,CGImageRef,NSArray<NSValue *> *))modal manualPass1:(void (^)(void (^)(void)))manualPass1 {
 if((self=[super init])){_blocks=[blocks copy];_items=[items copy];_enlarged=[enlarged copy];_sourceText=[sourceText copy];_speakers=[speakers copy];_modal=[modal copy];_manualPass1=[manualPass1 copy];}return self;
}
- (NSString *)recognizeBlocks:(CGImageRef)i settings:(FYOCRRecognitionSettings *)s blocks:(NSArray<OCRTextItem *> **)b error:(NSError **)e{return _blocks(i,s,b,e);}
- (NSArray *)recognizeItems:(CGImageRef)i settings:(FYOCRRecognitionSettings *)s error:(NSError **)e{return _items(i,s,e);}
- (NSString *)recognizeEnlarged:(CGImageRef)i region:(CGRect)r settings:(FYOCRRecognitionSettings *)s blocks:(NSArray<OCRTextItem *> **)b error:(NSError **)e{return _enlarged(i,r,s,b,e);}
- (NSString *)sourceTextForItems:(NSArray *)i blocks:(NSArray<OCRTextItem *> **)b{return _sourceText(i,b);}
- (NSArray *)markSpeakerItems:(NSArray *)i image:(CGImageRef)image{return _speakers(i,image);}
- (NSArray *)modalItems:(NSArray *)i image:(CGImageRef)image exclusions:(NSArray *)x{return _modal(i,image,x);}
- (void)performManualPass1:(void (^)(void))work{_manualPass1(work);}
@end
@interface FYOCRWorkerProgress ()
- (instancetype)initWithItems:(NSArray *)items modal:(NSArray *)modal error:(NSError *)error elapsed:(NSTimeInterval)elapsed pass1:(NSTimeInterval)pass1 pass2:(NSTimeInterval)pass2 fallback:(NSUInteger)fallback;
@end
@implementation FYOCRWorkerProgress
- (instancetype)initWithItems:(NSArray *)items modal:(NSArray *)modal error:(NSError *)error elapsed:(NSTimeInterval)elapsed pass1:(NSTimeInterval)pass1 pass2:(NSTimeInterval)pass2 fallback:(NSUInteger)fallback {
 if((self=[super init])){_items=[items copy];_modalItems=[modal copy];_error=error;_elapsed=elapsed;_pass1=pass1;_pass2=pass2;_fallbackCount=fallback;}return self;
}
@end
@interface FYOCRRecognitionResult ()
- (instancetype)initWithText:(NSString *)text items:(NSArray *)items modal:(NSArray *)modal error:(NSError *)error duration:(NSTimeInterval)duration;
@end
@implementation FYOCRRecognitionResult
- (instancetype)initWithText:(NSString *)text items:(NSArray *)items modal:(NSArray *)modal error:(NSError *)error duration:(NSTimeInterval)duration {
 if((self=[super init])){_text=[text copy];_items=[items copy];_modalItems=[modal copy];_error=error;_duration=duration;}return self;
}
@end
static void FYObserveOCR(FYOCRWorkerObserver observer,FYOCRWorkerStage stage,NSArray *items,NSArray *modal,NSError *error,NSTimeInterval elapsed,NSTimeInterval pass1,NSTimeInterval pass2,NSUInteger fallback,CGImageRef image) {
 if(observer) observer(stage,[[FYOCRWorkerProgress alloc] initWithItems:items modal:modal error:error elapsed:elapsed pass1:pass1 pass2:pass2 fallback:fallback],image);
}
@implementation FYOCRRecognitionWorker
- (FYOCRRecognitionResult *)recognizeImageLease:(FYOCRRecognitionImageLease *)lease settings:(FYOCRRecognitionSettings *)settings refinement:(FYOCRRefinementStabilizer *)refinement operations:(id<FYOCRRecognitionOperations>)operations cropScope:(FYOCRCropScopePerform)cropScope observer:(FYOCRWorkerObserver)observer {
 CGImageRef image=lease.image;
 if(!settings.manual) FYObserveOCR(observer,FYOCRWorkerBegin,nil,nil,nil,0,0,0,0,image);
 NSDate *start=[NSDate date];
 __block NSError *error=nil;
 __block NSArray<OCRTextItem *> *blocks=settings.manual ? nil : @[];
 NSString *text=nil;
 if(settings.manual) {
  [operations performManualPass1:^{ blocks=[FYOCRImageGeometry recognizeImage:image topLeftScope:settings.scope recognizer:^NSArray *(CGImageRef crop,NSError **inner){return [operations recognizeItems:crop settings:settings error:inner];} cropScope:cropScope error:&error]; }];
 } else {
  FYObserveOCR(observer,FYOCRWorkerDiagnosticImage,nil,nil,nil,0,0,0,0,image);
  if(CGRectEqualToRect(settings.scope,CGRectMake(0,0,1,1))) text=[operations recognizeBlocks:image settings:settings blocks:&blocks error:&error];
  else {
   NSArray *scoped=[FYOCRImageGeometry recognizeImage:image topLeftScope:settings.scope recognizer:^NSArray *(CGImageRef crop,NSError **inner){
    NSArray *raw=[operations recognizeItems:crop settings:settings error:inner];
    FYObserveOCR(observer,FYOCRWorkerRawCrop,raw,nil,inner ? *inner : nil,0,0,0,0,image);return raw;
   } cropScope:cropScope error:&error];
   text=[operations sourceTextForItems:scoped blocks:&blocks];
  }
 }
 FYObserveOCR(observer,FYOCRWorkerMappedPass1,blocks,nil,error,0,0,0,0,image);
 NSTimeInterval pass1=0;__block NSTimeInterval pass2=0;
 if(!settings.manual) {
  pass1=[[NSDate date] timeIntervalSinceDate:start];
  FYObserveOCR(observer,FYOCRWorkerPass1Complete,blocks,nil,error,pass1,pass1,0,0,image);
  FYApplyOCRRefinementWithStabilizer(blocks,settings.autoFit,^NSString *(CGRect region,NSArray **out,NSError **inner){
   CGRect scope=settings.scope;CGRect vision=CGRectMake(scope.origin.x,1-CGRectGetMaxY(scope),scope.size.width,scope.size.height);
   region=CGRectIntersection(region,vision);if(CGRectIsNull(region)||CGRectIsEmpty(region))return nil;
   return [operations recognizeEnlarged:image region:region settings:settings blocks:out error:inner];
  },^{pass2=[[NSDate date] timeIntervalSinceDate:start]-pass1;},refinement,&text,&blocks);
  if(refinement.fallbackCount)FYObserveOCR(observer,FYOCRWorkerRefinementSelection,blocks,nil,error,0,pass1,pass2,refinement.fallbackCount,image);
  FYObserveOCR(observer,FYOCRWorkerRefinementPerformance,blocks,nil,error,[[NSDate date] timeIntervalSinceDate:start],pass1,pass2,0,image);
  if(settings.language==0)blocks=[operations markSpeakerItems:blocks image:image];
 }
 NSDate *modalStart=settings.manual ? nil : [NSDate date];
 NSArray *modal=[operations modalItems:blocks image:image exclusions:settings.exclusions];
 if(!settings.manual) {
  FYObserveOCR(observer,FYOCRWorkerModalPerformance,blocks,modal,error,[[NSDate date] timeIntervalSinceDate:modalStart],pass1,pass2,0,image);
  FYObserveOCR(observer,FYOCRWorkerMerged,blocks,modal,error,0,pass1,pass2,0,image);
 }
 NSTimeInterval duration=[[NSDate date] timeIntervalSinceDate:start];
 [lease finishImage];
 if(!settings.manual)FYObserveOCR(observer,FYOCRWorkerReleasedImage,blocks,modal,error,duration,pass1,pass2,0,NULL);
 return [[FYOCRRecognitionResult alloc] initWithText:text items:blocks modal:modal error:error duration:duration];
}
@end
