#import "presentation/FYLiveReadingRenderer.h"
#import "FYLiveReadingTestFacts.h"
#import <objc/runtime.h>
@interface NativeReadingSource : NSObject <FYLiveReadingRenderSource>
@property(nonatomic,strong) FYLiveReadingRenderer *renderer;
@property(nonatomic,strong) FYDisplayedSentenceState *display;
@property(nonatomic,strong) ReadingLearningFact *learning;
@property(nonatomic) NSInteger vocabSelectionGeneration;
@property(nonatomic) BOOL sourceHoverSuspended,learningAnalysisBusy;
@property(nonatomic,strong) FYAnalysisResult *currentAnalysis;
@property(nonatomic,strong) NSTextView *learningSourceTextView;
@property(nonatomic,strong) NSLayoutConstraint *sourceReadingHeight;
@property(nonatomic,strong) NSTextField *liveScreenSpeakerLabel,*liveScreenDialogueLabel,*learningPinnedLabel,*grammarPinnedLabel;
@property(nonatomic,strong) NSButton *pinSentenceButton,*analyzeButton,*grammarPageAnalyzeButton;
@property(nonatomic) NSUInteger chips,tabs,splits;
@end
@implementation NativeReadingSource
@dynamic displayedSentenceID,displayedSourceText,displayedTranslation,displayedVersion;
- (instancetype)init{if((self=[super init])){self.renderer=[FYLiveReadingRenderer new];self.display=[FYDisplayedSentenceState new];self.learning=[ReadingLearningFact new];self.sourceReadingHeight=(NSLayoutConstraint *)[ReadingConstraintFact new];self.liveScreenSpeakerLabel=(NSTextField *)[ReadingLabelFact new];self.liveScreenDialogueLabel=(NSTextField *)[ReadingLabelFact new];self.learningPinnedLabel=(NSTextField *)[ReadingLabelFact new];self.grammarPinnedLabel=(NSTextField *)[ReadingLabelFact new];self.pinSentenceButton=(NSButton *)[ReadingButtonFact new];self.analyzeButton=(NSButton *)[ReadingButtonFact new];self.grammarPageAnalyzeButton=(NSButton *)[ReadingButtonFact new];}return self;}
- (NSString *)displayedSentenceID{return self.display.displayedSentenceID;}
- (void)setDisplayedSentenceID:(NSString *)v{self.display.displayedSentenceID=v;}
- (NSString *)displayedSourceText{return self.display.displayedSourceText;}
- (void)setDisplayedSourceText:(NSString *)v{self.display.displayedSourceText=v;}
- (NSString *)displayedTranslation{return self.display.displayedTranslation;}
- (void)setDisplayedTranslation:(NSString *)v{self.display.displayedTranslation=v;}
- (NSInteger)displayedVersion{return self.display.displayedVersion;}
- (void)setDisplayedVersion:(NSInteger)v{self.display.displayedVersion=v;}
- (FYLearningCoordinator *)learningCoordinator{return (FYLearningCoordinator *)self.learning;}
- (NSFont *)liveReadingJapaneseFontOfSize:(CGFloat)s{return [NSFont systemFontOfSize:s];}
- (NSFont *)liveReadingUIFontOfSize:(CGFloat)s{return [NSFont systemFontOfSize:s];}
- (NSColor *)uiInk{return NSColor.brownColor;}
- (NSColor *)uiMuted{return NSColor.grayColor;}
- (NSColor *)uiAccent{return NSColor.orangeColor;}
- (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString **)speaker body:(NSString **)body{self.splits++;NSRange r=[text rangeOfString:@"\n"];BOOL split=r.location!=NSNotFound;if(speaker)*speaker=split?[text substringToIndex:r.location]:nil;if(body)*body=split?[text substringFromIndex:r.location+1]:text;}
- (void)refreshLiveChips{self.chips++;}
- (void)applyGrammarTabSelection{self.tabs++;}
@end
int main(void){@autoreleasepool{
 Check(NSApp==nil,@"native reading tests initialize no application/view/control/window");NativeReadingSource *s=[NativeReadingSource new];unsigned int n=0;Ivar *v=class_copyIvarList(FYLiveReadingRenderer.class,&n);free(v);Check(n==0,@"native live renderer owns no source/font/view/cache state");
 NSString *japanese=@"青木\nあいうえお";s.displayedSourceText=japanese;NSAttributedString *jp=[s.renderer liveReadingText:japanese japanese:YES receiver:s];Check([jp.string isEqual:japanese]&&jp.length==japanese.length,@"native Japanese formatting changes only attributes,all UTF16 chars intact");NSFont *prefix=[jp attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];NSFont *body=[jp attribute:NSFontAttributeName atIndex:3 effectiveRange:NULL];NSParagraphStyle *style=[jp attribute:NSParagraphStyleAttributeName atIndex:3 effectiveRange:NULL];Check(prefix.pointSize==13&&body.pointSize==19&&style.lineSpacing==0,@"original speaker13/body19/Japanese spacing0 preserved");
 NSString *translation=@"青木\n中文正文";NSAttributedString *zh=[s.renderer liveReadingText:translation japanese:NO receiver:s];Check([zh.string isEqual:translation]&&[[zh attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL]pointSize]==13&&[[zh attribute:NSParagraphStyleAttributeName atIndex:3 effectiveRange:NULL]lineSpacing]==5,@"matching source speaker styles translated prefix with original spacing5");s.displayedSourceText=@"别名\n原文";zh=[s.renderer liveReadingText:translation japanese:NO receiver:s];Check([[zh attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL]pointSize]==19,@"unmatched translated prefix retains full body style");NSAttributedString *empty=[s.renderer liveReadingText:nil japanese:YES receiver:s];Check(empty.length==0,@"nil source formatting keeps empty original string");
 ReadingTextFact *t=TextFact(@"真实原生文字高度测量。这是一段足够长的合成正文，用来验证实际栏宽变化后重新测量，不生成模拟字宽。重复正文，保留字符与索引。");s.learningSourceTextView=(NSTextView *)t;[s.renderer updateLiveSourceReadingHeightWithReceiver:s];CGFloat wide=s.sourceReadingHeight.constant;Check(wide==ExpectedReadingHeight(t),@"native reading height uses actual styled attributed boundingRect/padding/options/ceil+12");t.enclosingScrollView.contentView.bounds=CGRectMake(0,0,90,80);[s.renderer updateLiveSourceReadingHeightWithReceiver:s];Check(s.sourceReadingHeight.constant==ExpectedReadingHeight(t)&&s.sourceReadingHeight.constant>=wide&&s.sourceReadingHeight.constant<=190,@"actual narrower clip width remeasures text and clamps at190");t.enclosingScrollView.contentView.bounds=CGRectMake(0,0,0,80);CGFloat held=s.sourceReadingHeight.constant;[s.renderer updateLiveSourceReadingHeightWithReceiver:s];Check(s.sourceReadingHeight.constant==held,@"nonpositive native clip width returns before altering height");t.enclosingScrollView=nil;[s.renderer updateLiveSourceReadingHeightWithReceiver:s];Check(s.sourceReadingHeight.constant==held,@"absent scroll returns without height update");
 [s.renderer refreshLiveDialoguePresentation:japanese receiver:s];Check([s.liveScreenSpeakerLabel.stringValue isEqual:@"青木"]&&!s.liveScreenSpeakerLabel.hidden&&[s.liveScreenDialogueLabel.stringValue isEqual:@"あいうえお"]&&s.chips==1,@"native dialogue preserves helper outputs/label visibility and chips order");[s.renderer refreshLiveDialoguePresentation:@"" receiver:s];Check(s.liveScreenSpeakerLabel.hidden&&[s.liveScreenDialogueLabel.stringValue isEqual:@"等待识别对白"]&&s.chips==2,@"empty dialogue exact hint/speaker hide");
 s.learning.pinned=YES;s.learning.hasNewerSentence=YES;s.learning.currentSentenceID=@"sentence";s.learning.currentSourceText=@"source";[s.renderer refreshLearningStatusWithReceiver:s];Check([s.learningPinnedLabel.stringValue isEqual:@"已固定 · 有新台词"]&&[s.grammarPinnedLabel.stringValue isEqual:s.learningPinnedLabel.stringValue]&&[s.pinSentenceButton.title isEqual:@"跟随最新"]&&s.pinSentenceButton.enabled&&s.analyzeButton.enabled&&s.grammarPageAnalyzeButton.enabled&&s.tabs==1,@"native pin/newer/status/button/busy mirror and tab helper preserved");s.learningAnalysisBusy=YES;[s.renderer refreshLearningStatusWithReceiver:s];Check(!s.analyzeButton.enabled&&!s.grammarPageAnalyzeButton.enabled&&s.pinSentenceButton.enabled,@"analysis busy only disables original analyze pair");s.learning.pinned=NO;s.learning.currentSentenceID=@"";[s.renderer refreshLearningStatusWithReceiver:s];Check([s.learningPinnedLabel.stringValue isEqual:@"跟随最新"]&&[s.pinSentenceButton.title isEqual:@"固定此句"]&&!s.pinSentenceButton.enabled,@"empty sentence keeps original follow status and disabled pin");
 __weak NativeReadingSource *weak;@autoreleasepool{NativeReadingSource *q=[NativeReadingSource new];weak=q;[q.renderer liveReadingText:@"lease" japanese:YES receiver:q];}Check(!weak,@"native live renderer does not retain borrowed source");Check(NSApp==nil,@"actual native fonts/attributes/measure with UI facts remain headless");printf("PASS LiveReadingRendererTests: %lu checks;actual native font/attributes/height/dialogue/status,no UI objects\n",(unsigned long)checks);
}return 0;}
