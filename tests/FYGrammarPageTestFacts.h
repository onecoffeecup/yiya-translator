#import <AppKit/AppKit.h>
#import "learning/FYLearningModels.h"
static NSUInteger checks;
static BOOL expectNativeBoundary=NO;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
static NSStackView *NativeBoundary(void){if(expectNativeBoundary){printf("FY_GRAMMAR_NATIVE_FACTORY_REACHED; no native view was constructed\n");fflush(stdout);exit(43);}Check(NO,@"invalid structure must return before any native factory");return nil;}
@protocol GrammarPageGuardDriver <NSObject>
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick;
- (NSArray<NSButton *> *)mainStructureButtons;
- (void)setMainStructureButtons:(NSArray<NSButton *> *)buttons;
- (NSArray<NSButton *> *)quickStructureButtons;
- (void)setQuickStructureButtons:(NSArray<NSButton *> *)buttons;
- (NSScrollView *)mainStructureScrollView;
- (void)setMainStructureScrollView:(NSScrollView *)scroll;
- (NSScrollView *)quickStructureScrollView;
- (void)setQuickStructureScrollView:(NSScrollView *)scroll;
@end
static NSDictionary *Part(id location,id length,NSString *text){return @{@"location":location,@"length":length,@"text":text,@"role":@"合成角色",@"meaning":@"合成说明"};}
static FYAnalysisResult *Graph(NSArray *parts){FYAnalysisResult *r=[FYAnalysisResult new];r.structureParts=parts;r.grammar=@[];return r;}
static void RunGrammarPageGuardFixture(id<GrammarPageGuardDriver>d){
 Check(NSApp==nil,@"builder guards run without app/view/control/window");NSObject *marker=[NSObject new];NSArray *main=@[(id)marker],*quick=@[(id)marker];NSScrollView *mainScroll=(id)[NSObject new],*quickScroll=(id)[NSObject new];[d setMainStructureButtons:main];[d setQuickStructureButtons:quick];[d setMainStructureScrollView:mainScroll];[d setQuickStructureScrollView:quickScroll];
 NSArray *cases=@[
 @[@[],@"猫は学校へ。"],
 @[@[Part(@0,@2,@"猫は")],@"猫は学校へ。"],
 @[@[Part(@2,@1,@"学"),Part(@0,@2,@"猫は")],@"猫は学校へ。"],
 @[@[Part(@7,@1,@"外"),Part(@0,@1,@"猫")],@"猫は学校へ。"],
 @[@[Part(@6,@1,@"外"),Part(@0,@1,@"猫")],@"猫は学校へ。"],
 @[@[Part(@1,@(NSUIntegerMax),@"外"),Part(@0,@1,@"猫")],@"猫は学校へ。"],
 @[@[Part(@(-1),@1,@"外"),Part(@0,@1,@"猫")],@"猫は学校へ。"],
 @[@[Part(@0,@2,@"別文"),Part(@2,@4,@"学校へ。")],@"猫は学校へ。"],
 @[@[Part(@0,@2,@"猫は"),Part(@3,@2,@"別文")],@"猫は学校へ。"],
 @[@[Part(@0,@1,@"猫"),Part(@1,@1,@"は")],@""],
 @[@[Part(@0,@1,@"😀"),Part(@2,@1,@"猫")],@"😀猫は。"],
 @[@[Part(@0,@2,@"猫は"),Part(@1,@1,@"は")],@"猫は学校へ。"]];
 for(BOOL isQuick=NO;;isQuick=YES){
  Check([d structureViewForAnalysis:nil source:nil quick:isQuick]==nil,@"nil analysis keeps original empty structure return");
  for(NSArray *entry in cases){FYAnalysisResult *r=Graph(entry[0]);NSArray *original=r.structureParts;NSString *source=entry[1];Check([d structureViewForAnalysis:r source:source quick:isQuick]==nil,@"count/order/outside/overflow/text/UTF16 invalid structure rejected before UI");Check(r.structureParts==original&&[source isEqual:entry[1]],@"guard never changes source characters, ranges or parts array");}
  FYAnalysisResult *nilSource=Graph(@[Part(@0,@1,@"猫"),Part(@1,@1,@"は")]);Check([d structureViewForAnalysis:nilSource source:nil quick:isQuick]==nil,@"nil source cannot admit nonempty ranges");
  if(isQuick)break;
 }
 Check([d mainStructureButtons]==main&&[d quickStructureButtons]==quick&&[d mainStructureScrollView]==mainScroll&&[d quickStructureScrollView]==quickScroll,@"invalid input preserves original main/quick resource identities");Check(NSApp==nil,@"all actual guards executed without constructing UI, devices, database or credentials");
}
static void RunValidGrammarBoundary(id<GrammarPageGuardDriver>d,NSString *mode){expectNativeBoundary=YES;BOOL quick=[mode containsString:@"quick"];BOOL emoji=[mode containsString:@"emoji"];NSString *source=emoji?@"😀猫は。":@"猫は学校へ。";FYAnalysisResult *r=emoji?Graph(@[Part(@0,@2,@"😀"),Part(@2,@3,@"猫は。")]):Graph(@[Part(@0,@2,@"猫は"),Part(@2,@4,@"学校へ。")]);[d structureViewForAnalysis:r source:source quick:quick];Check(NO,@"valid original structure must reach native factory boundary");}
static void CheckValidBoundaryChildren(NSString *binary){
 for(NSString *mode in @[@"valid-main",@"valid-quick",@"valid-emoji-main",@"valid-emoji-quick"]){NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:binary];task.arguments=@[mode];NSPipe *pipe=[NSPipe pipe];task.standardOutput=pipe;task.standardError=pipe;NSError *error=nil;Check([task launchAndReturnError:&error],@"private valid-guard boundary child launches");NSData *data=[pipe.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];NSString *output=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];Check(task.terminationStatus==43&&[output containsString:@"FY_GRAMMAR_NATIVE_FACTORY_REACHED"],@"valid main/quick ASCII/emoji reaches first real factory, deliberate stop precedes all view construction");}
}
