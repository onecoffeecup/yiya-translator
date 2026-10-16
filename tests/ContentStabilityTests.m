#import "FYDialogueStability.h"
#import "FYInlineOCRFrameStabilizer.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL b,NSString *m){checks++;if(!b){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface ClassifierProbe : NSObject
@property(nonatomic) NSUInteger calls;
@end
@implementation ClassifierProbe
@end
int main(void){@autoreleasepool{
 FYOCRStabilityOwner *owner=[FYOCRStabilityOwner new];
 Check(!owner.candidate&&owner.count==0,@"cold dialogue state has no evidence or work");
 __block NSUInteger keyReads=0;FYContentComparisonKey key=^NSString *(NSString *s){keyReads++;return s;};
 Check([FYDialogueStability isSameSubtitleText:@"え" comparedTo:@"え" mode:FYContentModeDialogue japanese:YES comparisonKey:key]&&keyReads==2,@"Japanese comparison preserves nonempty one-character identities and uses caller key");
 Check(![FYDialogueStability isSameSubtitleText:@"…" comparedTo:@"…" mode:FYContentModeDialogue japanese:YES comparisonKey:^NSString *(NSString *s){return @"";}],@"caller empty identity cannot confirm pure punctuation");
 Check(![FYDialogueStability isSameSubtitleText:@"A" comparedTo:@"A" mode:FYContentModeDialogue japanese:NO comparisonKey:nil],@"non-Japanese short-string minimum remains intact");
 Check([FYDialogueStability isSameSubtitleText:@"abcdefghiX" comparedTo:@"abcdefghij" mode:FYContentModeUI japanese:NO comparisonKey:nil],@"original long-text similarity policy remains accepted");
 Check(![FYDialogueStability isSameSubtitleText:@"abcdefghiX" comparedTo:@"abcdefghij" mode:FYContentModeDialogue japanese:YES comparisonKey:key],@"high similarity cannot turn a real Japanese correction into same identity");
 Check([FYDialogueStability similarityRatio:@"" comparedTo:@""]==1&&[FYDialogueStability similarityRatio:@"AB" comparedTo:@"AC"]==.5,@"canonical edit-distance behavior handles empty and substituted strings");
 NSString *rendered=@"今日はあの人と一緒に図書館へ行きます。",*corrected=@"今日はあの人と一緒に図書館へ行きません。";
 Check([FYDialogueStability similarityRatio:corrected comparedTo:rendered]>.85,@"fixture is a real high-similarity source correction");
 for(NSUInteger pass=1;pass<=3;pass++){
  BOOL stable=[FYDialogueStability isStableText:corrected owner:owner mode:FYContentModeDialogue japanese:YES renderedText:rendered comparisonKey:key];
  Check(owner.count==(NSInteger)pass&&stable==(pass==3),@"new correction needs three consecutive frames while complete caption exists");
 }
 [owner reset];Check(owner.count==0&&[owner.candidate isEqual:@""],@"explicit reset retains original empty-state semantics");
 Check(![FYDialogueStability isStableText:@"合成甲" owner:owner mode:FYContentModeDialogue japanese:YES renderedText:@"" comparisonKey:key],@"first dialogue observation waits");
 Check([FYDialogueStability isStableText:@"合成甲" owner:owner mode:FYContentModeDialogue japanese:YES renderedText:@"" comparisonKey:key],@"second equivalent observation confirms");
 Check(![FYDialogueStability isStableText:@"合成乙" owner:owner mode:FYContentModeDialogue japanese:YES renderedText:@"" comparisonKey:key]&&owner.count==1,@"new source breaks consecutive evidence");
 FYContentModeCoordinator *mode=[FYContentModeCoordinator new];
 Check(mode.stability&&mode.stability.detectedMode==0&&!mode.lastDecision,@"cold mode owner has original zero evidence and no classifier work");
 __block NSUInteger classified=0;
 FYContentModeDecision *(^ui)(NSInteger)=^FYContentModeDecision *(NSInteger fallback){classified++;Check(fallback==FYContentModeDialogue,@"classifier receives current confirmed mode");return [[FYContentModeDecision alloc] initWithMode:FYContentModeUI reason:@"synthetic UI evidence"];};
 Check([mode observeLocked:NO classifier:ui]==FYContentModeDialogue&&mode.stability.candidateHits==1&&classified==1,@"first mode candidate keeps confirmed mode");
 Check(mode.lastDecision.mode==FYContentModeUI&&[mode.lastDecision.reason isEqual:@"synthetic UI evidence"],@"last raw decision is distinct from confirmed mode");
 Check([mode observeLocked:YES classifier:ui]==FYContentModeDialogue&&classified==1&&mode.stability.candidateHits==1&&[mode.lastDecision.reason isEqual:@"mode_locked"],@"mode lock skips classifier and preserves candidate evidence");
 Check([mode observeLocked:NO classifier:ui]==FYContentModeUI&&mode.stability.candidateHits==0&&classified==2,@"unlock resumes original two-hit confirmation");
 FYContentModeDecision *decision=mode.lastDecision;
 Check(![decision respondsToSelector:@selector(setMode:)]&&![decision respondsToSelector:@selector(setReason:)],@"mode decisions expose immutable output");
 NSMutableString *reason=[@"snapshot" mutableCopy];FYContentModeDecision *snapshot=[[FYContentModeDecision alloc] initWithMode:1 reason:reason];[reason appendString:@" changed"];
 Check([snapshot.reason isEqual:@"snapshot"],@"external reason mutation cannot change decision");
 __weak ClassifierProbe *released;
 @autoreleasepool{ClassifierProbe *p=[ClassifierProbe new];released=p;[mode observeLocked:NO classifier:^FYContentModeDecision *(NSInteger fallback){p.calls++;return [[FYContentModeDecision alloc] initWithMode:fallback reason:@"current"]; }];Check(p.calls==1,@"small classifier protocol is invoked synchronously");}
 Check(!released,@"mode owner never stores or retains classifier receiver");
 FYInlineOCRFrameStabilizer *fields=[FYInlineOCRFrameStabilizer new];Check(!fields.ready&&[fields observeItems:nil].count==0,@"field owner cold/nil input has no confirmed items");
 OCRTextItem *item=[OCRTextItem new];item.text=@"合成字段";item.boundingBox=CGRectMake(.2,.2,.3,.05);item.lastLineBox=item.boundingBox;item.sourceBlockID=@"original-ID";item.confidence=.91;item.groupingConfidence=.87;item.speakerLabel=YES;
 [fields observeItems:@[item]];NSArray *accepted=[fields observeItems:@[item]];OCRTextItem *copy=accepted.firstObject;
 Check(fields.ready&&accepted.count==1&&copy!=item,@"confirmed fields use original independent observation-copy policy");
 Check([copy.sourceBlockID isEqual:item.sourceBlockID]&&copy.confidence==item.confidence&&copy.groupingConfidence==item.groupingConfidence&&copy.speakerLabel==item.speakerLabel&&CGRectEqualToRect(copy.lastLineBox,item.lastLineBox),@"field copy preserves all identity/diagnostic/geometry metadata");
 item.text=@"caller mutation";Check([copy.text isEqual:@"合成字段"],@"caller observation mutation cannot modify confirmed field");
 Check([fields observeItems:@[]].count==1&&fields.ready,@"first blank frame preserves confirmed field");
 Check([fields observeItems:nil].count==1&&fields.ready,@"second blank frame preserves confirmed field");
 Check([fields observeItems:@[]].count==0&&!fields.ready,@"third uninterrupted blank frame clears old page");
 [fields reset];Check(!fields.ready&&[fields observeItems:nil].count==0,@"field reset clears confirmed state");
 printf("PASS content stability: %lu checks; Foundation/CG, canonical dialogue/field/mode state and immutable decisions\n",(unsigned long)checks);
 }return 0;}
