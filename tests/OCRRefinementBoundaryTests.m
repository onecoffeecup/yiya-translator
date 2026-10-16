#import "FYOCRRefinementSession.h"
#import <objc/runtime.h>
#import <math.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *message) { checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);} }
static OCRTextItem *Item(NSString *text,CGRect box) { OCRTextItem *i=[OCRTextItem new];i.text=text;i.boundingBox=box;i.lastLineBox=box;i.lineCount=1;i.sourceBlockID=text;i.confidence=.93;return i; }
static FYOCRRefinementIdentity *Identity(NSUInteger changed) {
 return [[FYOCRRefinementIdentity alloc] initWithGeneration:changed==1?8:7 windowID:changed==2?43:42
 captureCard:changed==3 inputEpoch:changed==4?4:3 language:changed==5?1:0
 scopeSignature:changed==6?@"scope-B":@"scope-A" width:changed==7?1601:1600 height:changed==8?901:900];
}
static void CheckContext(void) {
 FYOCRRefinementSession *s=[FYOCRRefinementSession new];
 Check(!s.legacyContext&&!s.stabilizer,@"cold context owner starts no state or external work");
 FYOCRRefinementIdentity *id0=Identity(0);
 Check([id0.legacyRepresentation isEqual:@{@"generation":@7,@"window":@42,@"source":@NO,@"epoch":@3,@"language":@0,@"scope":@"scope-A",@"width":@1600,@"height":@900}],@"typed identity retains the exact legacy dictionary contract");
 Check(id0.generation==7&&id0.windowID==42&&!id0.captureCard&&id0.inputEpoch==3&&id0.language==0&&id0.width==1600&&id0.height==900&&[id0.scopeSignature isEqual:@"scope-A"],@"identity exposes typed primitive inputs");
 for(NSString *name in @[@"Generation",@"WindowID",@"CaptureCard",@"InputEpoch",@"Language",@"ScopeSignature",@"Width",@"Height",@"LegacyRepresentation"])
  Check(![id0 respondsToSelector:NSSelectorFromString([NSString stringWithFormat:@"set%@:",name])],@"identity has no setters");
 NSMutableString *scope=[@"original scope" mutableCopy];
 FYOCRRefinementIdentity *copy=[[FYOCRRefinementIdentity alloc] initWithGeneration:1 windowID:2 captureCard:NO inputEpoch:3 language:0 scopeSignature:scope width:4 height:5];
 [scope appendString:@" changed"];
 Check([copy.scopeSignature isEqual:@"original scope"]&&[copy.legacyRepresentation[@"scope"] isEqual:@"original scope"],@"mutable caller scope cannot change the immutable identity");
 NSMutableDictionary *external=[copy.legacyRepresentation mutableCopy];external[@"generation"]=@99;
 Check([copy.legacyRepresentation[@"generation"] integerValue]==1,@"external dictionary mutation cannot change canonical identity");
 FYOCRRefinementStabilizer *state=[s stateForIdentity:id0];
 Check(state&&state==s.stabilizer,@"session is the sole state owner");
 Check([s stateForIdentity:Identity(0)]==state,@"equivalent identities reuse consecutive-frame evidence");
 CGRect box=CGRectMake(.2,.2,.4,.05);OCRTextItem *coarse=Item(@"合成首遍",box);
 [state observeCoarseItems:@[coarse] refinedItems:@[Item(@"精读甲",box)]];
 [state observeCoarseItems:@[coarse] refinedItems:@[Item(@"精读乙",box)]];
 Check(state.fallbackCount==1,@"canonical state has real jitter evidence");
 for(NSUInteger changed=1;changed<=8;changed++) {
  FYOCRRefinementStabilizer *next=[s stateForIdentity:Identity(changed)];
  Check(next!=state&&next.fallbackCount==0,@"each original context dimension isolates new worker state");
  [state observeCoarseItems:@[coarse] refinedItems:@[Item(@"精读丙",box)]];
  Check(s.stabilizer==next&&s.stabilizer.fallbackCount==0,@"late old OCR cannot write new context evidence");
  [s stateForIdentity:id0];
 }
 __weak FYOCRRefinementStabilizer *released;
 FYOCRRefinementSession *lifetime=[FYOCRRefinementSession new];
 @autoreleasepool { FYOCRRefinementStabilizer *old=[lifetime stateForIdentity:id0];released=old;[lifetime stateForIdentity:Identity(1)];Check(released!=nil,@"old worker lease retains its original state"); }
 Check(!released&&lifetime.stabilizer,@"replaced context state releases after its worker finishes");
 NSMutableDictionary *legacy=[id0.legacyRepresentation mutableCopy];s.legacyContext=legacy;[legacy removeAllObjects];
 Check(s.legacyContext.count==8,@"compatibility context assignment copies its dictionary");
 s.stabilizer=nil;
 Check([s stateForIdentity:id0]==nil,@"equal context plus explicit nil state preserves legacy separate-assignment behavior");
 s.legacyContext=nil;Check([s stateForIdentity:id0]!=nil,@"explicit context invalidation creates fresh state");
 s.stabilizer=nil;s.legacyContext=nil;Check(!s.stabilizer&&!s.legacyContext,@"capture failure clears only context state");
}
static void CheckPipeline(void) {
 CGRect box=CGRectMake(.2,.2,.4,.05);OCRTextItem *coarse=Item(@"合成首遍",box),*fine=Item(@"精读结果",box);
 FYOCRRefinementStabilizer *s=[FYOCRRefinementStabilizer new];
 __block NSUInteger recognition=0,observers=0;NSMutableArray *order=[NSMutableArray new];
 NSString *text=@"sentinel";NSArray *blocks=@[coarse];
 BOOL accepted=FYApplyOCRRefinementWithStabilizer(@[coarse],YES,^NSString *(CGRect region,NSArray **out,NSError **error) {
  recognition++;[order addObject:@"recognize"];Check(fabs(region.origin.x-.17)<.00001&&fabs(region.size.width-.46)<.00001,@"original fitted-region coordinates are used");*out=@[fine];return fine.text;
 },^{observers++;[order addObject:@"accept"];Check(s.fallbackCount==0,@"observer precedes merging");},s,&text,&blocks);
 Check(accepted&&recognition==1&&observers==1&&[order isEqual:@[@"recognize",@"accept"]],@"canonical recognition/observer sequence is preserved");
 Check(blocks.count==1&&blocks[0]==fine&&[text isEqual:fine.text],@"accepted pass preserves original observation identity and source text");
 Check(CGRectEqualToRect(coarse.boundingBox,box)&&[coarse.text isEqual:@"合成首遍"]&&coarse.confidence==.93,@"selection never mutates coarse observation metadata");
 [s observeCoarseItems:@[coarse] refinedItems:@[Item(@"变动精读",box)]];Check(s.fallbackCount==1,@"real refinement jitter selects coarse before reset");
 NSString *sentinel=@"keep existing";NSArray *original=@[coarse];text=sentinel;blocks=original;
 accepted=FYApplyOCRRefinementWithStabilizer(@[coarse],NO,^NSString *(CGRect region,NSArray **out,NSError **error){recognition++;return @"unexpected";},^{observers++;},s,&text,&blocks);
 Check(!accepted&&recognition==1&&observers==1&&text==sentinel&&blocks==original&&s.fallbackCount==0,@"ineligible second pass resets evidence and leaves caller output untouched");
 for(NSUInteger errorKind=0;errorKind<2;errorKind++) {
  accepted=FYApplyOCRRefinementWithStabilizer(@[coarse],YES,^NSString *(CGRect region,NSArray **out,NSError **error){if(errorKind)*error=[NSError errorWithDomain:@"synthetic" code:1 userInfo:nil];*out=@[fine];return errorKind?fine.text:@"　\n";},^{observers++;},s,&text,&blocks);
  Check(!accepted&&observers==1&&text==sentinel&&blocks==original,@"blank/error refinement cannot overwrite previous output or emit acceptance");
 }
 CGRect untouched=CGRectMake(9,9,9,9);Check(!FYOCRRefinementRegion(@[coarse],YES,.2,&untouched)&&CGRectEqualToRect(untouched,CGRectMake(9,9,9,9)),@"ineligible large region preserves the output rectangle");
 Check(FYApplyOCRRefinement(@[coarse],YES,^NSString *(CGRect region,NSArray **out,NSError **error){*out=@[fine];return fine.text;},nil,NULL,NULL),@"legacy pure entry accepts nil output pointers and observer");
 OCRTextItem *quoted=Item(@"私は「花境」を知っています。",box),*lost=Item(@"私は「」を知っています。",box);
 NSArray *merged=[FYOCRRefinement mergeCoarseItems:@[quoted] refinedItems:@[lost]];
 Check(merged.count==1&&merged[0]==quoted,@"canonical quotation protection retains complete coarse source");
 OCRTextItem *correction=Item(@"私は「花園」を知っています。",box);
 merged=[FYOCRRefinement mergeCoarseItems:@[quoted] refinedItems:@[correction]];
 Check(merged.count==1&&merged[0]==correction,@"complete refinement correction remains accepted");
 OCRTextItem *wide=Item(@"同じ行",CGRectMake(.1,.3,.6,.08)),*tight=Item(@"同じ行",CGRectMake(.1,.31,.6,.04));
 merged=[FYOCRRefinement mergeCoarseItems:@[wide] refinedItems:@[tight]];
 Check(merged.count==1&&merged[0]==tight,@"same physical line keeps refined metadata without duplication");
 OCRTextItem *distant=Item(@"同じ行",CGRectMake(.1,.8,.6,.04));
 Check([FYOCRRefinement mergeCoarseItems:@[wide] refinedItems:@[distant]].count==2,@"same text at distinct positions remains two observations");
 OCRTextItem *outer=Item(@"AB",CGRectMake(.2,.2,.5,.1)),*left=Item(@"A",CGRectMake(.2,.2,.25,.1)),*right=Item(@"B",CGRectMake(.45,.2,.25,.1));
 NSArray *resolved=[FYOCRRefinement resolveOverlappingItems:@[outer,left,right]];
 Check([resolved isEqual:@[left,right]],@"canonical overlap resolution retains surviving order and object identities");
 Check([FYNormalizeOCRTextForComparison(@"　A \nB　") isEqual:@"AB"]&&[FYNormalizeOCRTextForComparison(nil) isEqual:@""],@"original whitespace normalization is shared");
 Check(FYContainsJapaneseKana(@"あ")&&FYContainsJapaneseKana(@"カ")&&!FYContainsJapaneseKana(@"漢字"),@"canonical kana scan does not reinterpret Han-only text");
 FYOCRRefinementStabilizer *ordered=[FYOCRRefinementStabilizer new];
 OCRTextItem *steady=Item(@"精读稳定乙",box);
 [ordered observeCoarseItems:@[coarse] refinedItems:@[Item(@"精读初始甲",box)]];
 [ordered observeCoarseItems:@[coarse] refinedItems:@[steady]];
 [ordered observeCoarseItems:@[coarse] refinedItems:@[steady]];
 Check(ordered.fallbackCount==1,@"observer-order fixture has real coarse fallback evidence");
 __block BOOL observed=NO;
 accepted=FYApplyOCRRefinementWithStabilizer(@[coarse],YES,^NSString *(CGRect region,NSArray **out,NSError **error){*out=@[steady];return steady.text;},^{observed=YES;Check(ordered.fallbackCount==1,@"accepted observer runs before the merge clears prior fallback evidence");},ordered,&text,&blocks);
 Check(accepted&&observed,@"accepted observation is delivered exactly at the canonical stage");
 Check(ordered.fallbackCount==0&&blocks.count==1&&blocks[0]==steady,@"third stable refinement then clears fallback and selects refined identity");
}
int main(void){@autoreleasepool{CheckContext();CheckPipeline();}printf("PASS OCR refinement boundary: %lu checks; Foundation/CoreGraphics, canonical algorithms and context leases\n",(unsigned long)checks);return 0;}
