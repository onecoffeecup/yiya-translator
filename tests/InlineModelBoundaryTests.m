#import "inline/FYInlineGrouping.h"
#import "inline/FYInlineTextUtilities.h"
#import "inline/FYInlineTextModelsInternal.h"
#import <objc/runtime.h>
// Deliberately verify existing nil behavior despite legacy nonnull annotations.
#pragma clang diagnostic ignored "-Wnonnull"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
static FYInlineTextLine *Line(NSString *text,CGRect rect,CGFloat confidence,NSInteger index){return [FYInlineTextLine lineWithText:text rect:rect confidence:confidence sourceIndex:index];}
static FYInlinePlacement *Placement(NSString *identity,NSString *text,CGRect frame,FYInlineDisplayMode mode){FYInlinePlacement *p=[FYInlinePlacement new];p.blockID=identity;p.block=[FYInlineTextBlock new];p.block.text=text;p.sourceFrame=frame;p.mode=mode;return p;}
int main(void){@autoreleasepool{
    FYInlineTextBlock *block=[FYInlineTextBlock new];
    Check([block.text isEqual:@""]&&block.lineTexts.count==0&&block.lineBoxes.count==0&&block.lineConfidences.count==0&&block.sourceIndices.count==0&&block.groupingConfidence==1&&block.lineCount==0,@"cold block preserves original empty defaults without native work");
    NSMutableString *text=[NSMutableString stringWithString:@" 日文。 "];CGRect normalized=CGRectMake(.1,.7,.2,.04);
    FYInlineTextLine *line=Line(text,normalized,.91,17);[text appendString:@"changed"];
    Check([line.text isEqual:@" 日文。 "]&&CGRectEqualToRect(line.rect,normalized)&&line.confidence==.91&&line.sourceIndex==17,@"line copies source characters and preserves normalized geometry/confidence/index");
    Check([Line(nil,CGRectZero,0,-1).text isEqual:@""],@"line factory keeps nil-text empty behavior");
    NSMutableArray *texts=[NSMutableArray arrayWithObjects:@"一",@"二",nil];block.lineTexts=texts;[texts removeAllObjects];
    Check(block.lineCount==2&&[block.lineTexts isEqual:@[@"一",@"二"]],@"block owns copied line array and derives count from sole source");
    block.lineTexts=@[@"三"];Check(block.lineCount==1,@"line count updates with original mutable model setter");
    NSMutableString *translation=[NSMutableString stringWithString:@"中文"];
    CGRect screen=CGRectMake(-400,100,300,30);
    FYInlineLayoutRequest *request=[FYInlineLayoutRequest requestWithBlock:block translation:translation sourceFrame:screen];[translation appendString:@"changed"];
    Check(request.block==block&&[request.translation isEqual:@"中文"]&&CGRectEqualToRect(request.sourceFrame,screen),@"request retains same block, copies translation, keeps display coordinates");
    Check([[FYInlineLayoutRequest requestWithBlock:block translation:nil sourceFrame:screen].translation isEqual:@""],@"nil request translation remains empty");
    FYInlinePlacement *placement=[FYInlinePlacement new];
    Check([placement.blockID isEqual:@""]&&[placement.sourceBlockID isEqual:@""]&&[placement.translation isEqual:@""]&&[placement.reason isEqual:@""]&&placement.rejectedCandidates.count==0&&!placement.font&&!placement.paragraphStyle,@"cold placement preserves native-style-free defaults");
    NSMutableArray *settings=[NSMutableArray arrayWithObject:@19];placement.bodyFontSettings=settings;[settings addObject:@15];placement.stableBodyFontSize=19;placement.availableVariantCount=4;
    Check([placement.bodyFontSettings isEqual:@[@19]]&&placement.stableBodyFontSize==19&&placement.availableVariantCount==4,@"original private variant fields keep copy and scalar ownership in model");
    Check(class_getInstanceVariable(FYInlinePlacement.class,"_bodyFontSettings")&&class_getInstanceVariable(FYInlinePlacement.class,"_stableBodyFontSize")&&class_getInstanceVariable(FYInlinePlacement.class,"_availableVariantCount"),@"model alone synthesizes original variant storage");
    __weak NSObject *styleToken;
    @autoreleasepool {NSObject *token=[NSObject new];styleToken=token;placement.font=(NSFont *)token;}
    Check(styleToken&&placement.font==(NSFont *)styleToken,@"model strongly retains opaque original native-style reference without construction");
    placement.font=nil;Check(!styleToken,@"clearing style ends original retained resource lifetime");
    FYInlineLayoutResult *result=[FYInlineLayoutResult new];
    Check(!result.placements.count&&!result.visiblePlacements.count&&!result.unplaceableBlockIDs.count&&!result.compactEntryBlockIDs.count&&![result placementForBlockID:@"unknown"],@"cold result and index are empty");
    FYInlinePlacement *a=Placement(@"duplicate",@"甲",screen,FYInlineDisplayModeShortLabel),*b=Placement(@"duplicate",@"乙",screen,FYInlineDisplayModeCompactEntry),*c=Placement(@"blocked",@"丙",screen,FYInlineDisplayModeUnplaceable),*empty=Placement(@"",@"丁",screen,FYInlineDisplayModeFullCard);
    NSMutableArray *sequence=[NSMutableArray arrayWithObjects:a,b,c,empty,nil];result.placements=sequence;[sequence removeAllObjects];
    Check(result.placements.count==4&&result.placements[0]==a&&result.placements[1]==b,@"result copies outer sequence and retains original mutable placement elements");
    Check([result.visiblePlacements isEqual:@[a,b,empty]]&&[result.unplaceableBlockIDs isEqual:@[@"blocked"]]&&[result.compactEntryBlockIDs isEqual:@[@"duplicate"]],@"visible/blocked/compact derived collections preserve original order and mode policy");
    Check([result placementForBlockID:@"duplicate"]==b&&![result placementForBlockID:@""]&&![result placementForBlockID:nil],@"duplicate index keeps last placement and excludes empty identity");
    b.translation=@"更新";Check([[[result placementForBlockID:@"duplicate"]translation]isEqual:@"更新"],@"derived index retains live original model instead of duplicate snapshot");
    b.blockID=@"changed";Check([result placementForBlockID:@"duplicate"]==b&&![result placementForBlockID:@"changed"],@"index only rebuilds at original placements setter boundary");
    result.placements=result.placements;Check([result placementForBlockID:@"duplicate"]==a&&[result placementForBlockID:@"changed"]==b,@"setter rebuild reflects current IDs without replacing elements");
    result.placements=nil;Check(!result.placements.count&&!result.visiblePlacements.count&&!result.compactEntryBlockIDs.count&&!result.unplaceableBlockIDs.count&&![result placementForBlockID:@"blocked"],@"nil assignment clears all sole-owner derived state");
    __weak FYInlinePlacement *retained;
    FYInlineLayoutResult *owner;
    @autoreleasepool {owner=[FYInlineLayoutResult new];FYInlinePlacement *child=Placement(@"owned",@"合成",screen,FYInlineDisplayModeFullCard);retained=child;owner.placements=@[child];}
    @autoreleasepool {Check(retained&&[owner placementForBlockID:@"owned"]==retained,@"result owns original child through completed caller scope");}owner=nil;Check(!retained,@"result completion releases indexed and visible child references");
    Check([FYInlineNormalize(@" 日 文。　")isEqual:@"日文。"]&&[FYInlineTrim(@" 日 文。 ")isEqual:@"日 文。"],@"normalization only removes whitespace and retains punctuation/internal source trim");
    Check([FYInlineNormalizeTranslationParagraphs(@"一\n二\n\n三")isEqual:@"一二\n\n三"]&&[FYInlineNormalizeTranslationParagraphs(nil)isEqual:@""],@"body paragraph normalization retains original soft-wrap and blank-line semantics");
    Check(!FYInlineHasSentencePunctuation(@"（合成）")&&FYInlineHasSentencePunctuation(@"合成。")&&FYInlineLineEndsSentence(@"合成」"),@"field brackets differ from original sentence punctuation evidence");
    Check(FYInlineMedian(@[@3,@1,@2,@4])==3&&FYInlineMedian(@[])==0&&FYInlineClamp(8,10,4)==10,@"canonical median and inverted clamp policies unchanged");
    FYInlineGrouper *grouper=[FYInlineGrouper defaultGrouper];
    Check(grouper.maxBlockHeightFraction==.55&&grouper.minimumCharacters==2&&!grouper.shortLabelDetector&&[grouper blocksFromLines:nil].count==0,@"cold pure grouper retains original configuration and empty-input rule");
    FYInlineTextLine *low=Line(@"共通",CGRectMake(.1,.8,.2,.03),.4,1),*high=Line(@" 共 通 ",CGRectMake(.1,.8,.2,.03),.9,2),*elsewhere=Line(@"共通",CGRectMake(.6,.5,.2,.03),.7,3);
    NSArray *dedup=[grouper deduplicatedLines:@[low,elsewhere,high,Line(@"　 ",CGRectZero,1,4)]];
    Check([dedup isEqual:@[high,elsewhere]],@"same-place highest confidence wins while identical text at another position survives");
    Check(high.sourceIndex==2&&[high.text isEqual:@" 共 通 "],@"dedup keeps winning source identity and does not rewrite raw characters");
    NSMutableArray *many=[NSMutableArray new];
    for(NSInteger i=0;i<32;i++)[many addObject:Line(@"共通",CGRectMake(.05+(i%2)*.55,.95-(i/2)*.055,.1,.02),.8,i)];
    NSArray<FYInlineTextBlock *> *blocks=[grouper blocksFromLines:many];NSMutableSet *indices=[NSMutableSet new];NSMutableSet *identities=[NSMutableSet new];
    for(FYInlineTextBlock *item in blocks){[indices addObjectsFromArray:item.sourceIndices];[identities addObject:item.blockID];}
    Check(blocks.count==32&&indices.count==32&&identities.count==32,@"pure production grouping preserves more than twenty same-text fields with distinct coordinates/source indices");
    Check([blocks[0].sourceIndices isEqual:@[@0]]&&[blocks[1].sourceIndices isEqual:@[@1]]&&blocks[0].readingOrder==0&&blocks[1].readingOrder==1,@"original top-to-bottom left-to-right reading order retained");
    NSString *idA=[FYInlineBlockMatcher blockIDForText:@"共 通" lineBoxes:@[@(CGRectMake(.1001,.2,.1,.03))]],*idB=[FYInlineBlockMatcher blockIDForText:@"共通" lineBoxes:@[@(CGRectMake(.1004,.2,.1,.03))]],*idC=[FYInlineBlockMatcher blockIDForText:@"共通" lineBoxes:@[@(CGRectMake(.1006,.2,.1,.03))]];
    Check([idA isEqual:idB]&&![idA isEqual:idC],@"stable key preserves original three decimal coordinate quantization and normalized text");
    Check(![[FYInlineBlockMatcher blockIDForText:@"共通。" lineBoxes:@[]]isEqual:[FYInlineBlockMatcher blockIDForText:@"共通" lineBoxes:@[]]],@"punctuation remains part of stable identity");
    Check(fabs([FYInlineBlockMatcher textSimilarity:@"aaaa" right:@"aaab"]-2.0/3.0)<1e-9&&[FYInlineBlockMatcher textSimilarity:@" 日 本 " right:@"日本"]==1&&[FYInlineBlockMatcher textSimilarity:@"" right:@""]==0,@"original bigram multiplicities/normalization and empty-text similarity retained");
    Check([FYInlineBlockMatcher overlapRatio:CGRectMake(0,0,100,20) right:CGRectMake(0,0,50,20)]==1&&[FYInlineBlockMatcher overlapRatio:CGRectZero right:screen]==0,@"overlap uses smaller area and rejects empty rectangles");
    FYInlinePlacement *left=Placement(@"left",@"合成文字",CGRectMake(0,0,100,20),FYInlineDisplayModeShortLabel),*right=Placement(@"right",@"合成文字",CGRectMake(300,0,100,20),FYInlineDisplayModeFullCard);
    result.placements=@[left,right];FYInlineTextBlock *next=[FYInlineTextBlock new];next.text=@"合成文字";
    Check([[FYInlineBlockMatcher stableBlockIDForBlock:next text:next.text sourceFrame:CGRectMake(301,1,100,20) previousResult:result]isEqual:@"right"],@"same-text different-location previous models resolve by actual geometry");
    Check(![FYInlineBlockMatcher stableBlockIDForBlock:next text:next.text sourceFrame:CGRectMake(700,0,100,20) previousResult:result],@"distant same text never steals an existing placement identity");
    Check(![FYInlineBlockMatcher stableBlockIDForBlock:next text:next.text sourceFrame:CGRectMake(0,0,40,20) previousResult:result],@"original width-ratio gate rejects geometrically different field");
    Check(![FYInlineBlockMatcher stableBlockIDForBlock:next text:@"別内容" sourceFrame:left.sourceFrame previousResult:result]&&![FYInlineBlockMatcher stableBlockIDForBlock:next text:next.text sourceFrame:left.sourceFrame previousResult:nil],@"different text or absent previous result yields no stable identity");
    FYInlineTextLine *prose1=Line(@"合成段落。",CGRectMake(.1,.8,.2,.04),.9,40),*prose2=Line(@"続く説明。",CGRectMake(.1,.75,.2,.04),.9,41);
    Check([grouper kindForLines:@[prose1,prose2] normalized:@"合成段落。続く説明。"]==FYInlineBlockKindLong,@"production punctuation/tight-line evidence classifies narrow prose before short-menu guess");
    __block NSUInteger controlCalls=0;grouper.shortLabelDetector=^BOOL(NSString *value){controlCalls++;return YES;};
    Check([grouper kindForLines:@[Line(@"合成長文字合成長文字合成長文字合成長文字",normalized,.9,50)] normalized:@"合成長文字合成長文字合成長文字合成長文字"]==FYInlineBlockKindShort&&controlCalls==1,@"original explicit control callback keeps classification precedence and call count");grouper.shortLabelDetector=nil;
    NSArray *fieldBlocks=[grouper blocksFromLines:@[Line(@"所属",CGRectMake(.02,.8,.08,.03),.9,60),Line(@"帰宅部",CGRectMake(.20,.8,.12,.03),.9,61),Line(@"备注",CGRectMake(.02,.75,.08,.03),.9,62),Line(@"桜井琥一の弟。",CGRectMake(.20,.75,.32,.03),.9,63)]];
    BOOL separate=NO;for(FYInlineTextBlock *field in fieldBlocks)if([field.sourceIndices containsObject:@61])separate=[field.text isEqual:@"帰宅部"]&&![field.sourceIndices containsObject:@63];
    Check(separate,@"production field labels prevent short value merging into lower prose");
    __weak FYInlineTextBlock *notSaved;
    @autoreleasepool {FYInlineTextBlock *temporary=[FYInlineTextBlock new];notSaved=temporary;[FYInlineBlockMatcher stableBlockIDForBlock:temporary text:@"合成" sourceFrame:screen previousResult:nil];}
    Check(!notSaved,@"stateless matcher retains no caller block after synchronous query");
    printf("PASS inline model boundary: %lu checks; Foundation/CG, original model/index/copy/identity, canonical grouping/matching and no native initialization\n",(unsigned long)checks);
}return 0;}
