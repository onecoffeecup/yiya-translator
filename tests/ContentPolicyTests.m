#import "FYContentPolicy.h"
#import "FYOCRPixelAnalysis.h"
#import "FYOCRTextProcessing.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL b,NSString *m){checks++;if(!b){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
static OCRTextItem *Item(NSString *s,CGRect r){OCRTextItem *i=[OCRTextItem new];i.text=s;i.boundingBox=r;i.lineCount=1;i.sourceBlockID=s;i.confidence=.9;return i;}
@interface PolicyOverride : FYContentPolicy
@end
@implementation PolicyOverride
+ (BOOL)looksLikeUIFrame:(NSArray<OCRTextItem *> *)items { return YES; }
@end
int main(void){@autoreleasepool{
 FYContentPolicy *policy=[FYContentPolicy new];Check(policy&&!class_getInstanceVariable(FYContentPolicy.class,"_host"),@"cold stateless policy has no host/context/work");
 for(NSString *text in @[@"Hello.",@"Hello…",@"設定",@"え……"]){
  OCRTextItem *i=Item(text,CGRectMake(.2,.2,.6,.05));FYContentTextFilterReason r=[FYContentPolicy filterReasonForText:text normalized:FYNormalizeOCRTextForComparison(text) boundingBox:i.boundingBox strict:NO japanese:NO];
  Check(r==FYContentTextKeep,@"canonical policy keeps real text including English punctuation and one-character kana");
 }
 Check([FYContentPolicy filterReasonForText:@"..." normalized:@"..." boundingBox:CGRectMake(.2,.2,.6,.05) strict:YES japanese:NO]==FYContentTextPunctuationOnly,@"pure punctuation still has original rejection reason");
 OCRTextItem *spoken=Item(@"今日はみんなで図書館へ行きましょう。",CGRectMake(.2,.12,.6,.05));
 FYContentModeDecision *mode=[FYContentPolicy modeDecisionForItems:@[spoken] fallback:FYContentModeUI];
 Check(mode.mode==FYContentModeDialogue,@"real single-line dialogue selects original dialogue mode");
 Check([PolicyOverride modeDecisionForItems:@[spoken] fallback:FYContentModeDialogue].mode==FYContentModeUI,@"inherited policy retains original self/subclass helper dispatch");
 NSArray *choices=@[Item(@"設定",CGRectMake(.1,.4,.1,.03)),Item(@"保存",CGRectMake(.1,.3,.1,.03)),Item(@"閉じる",CGRectMake(.1,.2,.1,.03))];
 Check([FYContentPolicy modeDecisionForItems:choices fallback:0].mode==FYContentModeUI,@"explicit menu retains UI-first classification");
 FYContentRoute *route=[FYContentPolicy dialogueRouteForItems:@[spoken] optionsCanPasteInline:NO filterObserver:nil];
 Check([route.dialogueText containsString:spoken.text]&&route.dialogueItems.firstObject==spoken,@"dialogue route keeps original source text and observation identity");
 Check([route.reason isEqual:@"options_mapping_unavailable"],@"unmapped options retain original route reason");
 Check([[FYContentPolicy dialogueTextWithoutTrailingButton:@"思い出した。使用"] isEqual:@"思い出した。使用"],@"fused trailing button known gap is preserved during refactor");
 NSArray *items=@[spoken];NSArray *out=nil;NSString *text=[FYOCRTextProcessing sourceTextForItems:items blocks:&out];
 Check(out==items&&[text isEqual:spoken.text],@"clean-source processing does not copy or delete original observations");
 NSSet *rendered=[NSSet setWithObject:spoken.text];
 Check([FYOCRTextProcessing itemsExcludingOwnOverlay:items renderedTexts:rendered].count==0,@"explicit overlaid-image path still excludes rendered snapshots");
 Check([FYOCRTextProcessing sourceTextForItems:items blocks:NULL].length>0,@"clean-image path keeps same text even if it could match a translation");
 CGRect modal=CGRectMake(.2,.2,.5,.5);OCRTextItem *inside1=Item(@"合成正文一",CGRectMake(.3,.4,.2,.05)),*inside2=Item(@"合成正文二",CGRectMake(.3,.3,.2,.05)),*outside=Item(@"框外内容",CGRectMake(.9,.8,.09,.05));
 NSArray *three=@[inside1,outside,inside2];NSArray *scoped=[FYOCRPixelAnalysis items:three inModalRegion:modal exclusions:@[]];
 Check([scoped isEqual:@[inside1,inside2]],@"canonical modal filtering preserves surviving order and identity");
 Check([FYOCRPixelAnalysis items:three inModalRegion:modal exclusions:@[[NSValue valueWithRect:inside1.boundingBox]]]==three,@"insufficient remaining modal evidence falls back to original array");
 Check([FYOCRPixelAnalysis itemsByMarkingSpeakerLabels:three inImage:NULL]==three,@"missing pixel image does not mark or mutate observed text");
 CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGContextRef ctx=CGBitmapContextCreate(NULL,100,100,8,0,space,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(space);
 CGContextSetRGBFillColor(ctx,.1,.1,.1,1);CGContextFillRect(ctx,CGRectMake(0,0,100,100));CGImageRef image=CGBitmapContextCreateImage(ctx);CGContextRelease(ctx);
 FYOCRPixelBuffer buffer=FYCreateOCRPixelBuffer(image);Check(buffer.pixels&&buffer.width==100&&buffer.height==100,@"independent pixel module makes the real caller-owned RGBA buffer");
 CGRect unchanged=CGRectMake(9,9,9,9);Check(!FYDetectBrightOCRContentRegion(buffer.pixels,100,100,buffer.bytesPerRow,&unchanged,NULL,NULL,0)&&CGRectEqualToRect(unchanged,CGRectMake(9,9,9,9)),@"ambiguous dark pixels preserve region output");
 FYReleaseOCRPixelBuffer(&buffer);Check(!buffer.pixels&&!buffer.context,@"pixel buffer ends its owned resources");FYReleaseOCRPixelBuffer(&buffer);Check(!buffer.pixels&&!buffer.context,@"repeated pixel release is safe");CGImageRelease(image);
 Check([FYOCRPixelAnalysis items:three scopedToModalInImage:NULL exclusions:@[]]==three,@"null image modal path retains exact original observation array");
 printf("PASS content policy: %lu checks; Foundation/CG, inherited dispatch, real pixels, source identity and known gap\n",(unsigned long)checks);
 }return 0;}
