#import "presentation/FYMainWindowController.h"
#import "FYWordSelectionTestServices.h"
@interface WordTextFact : NSObject
@property(nonatomic,strong) NSString *string;
@property(nonatomic) NSRange selectedRange;
@property(nonatomic) BOOL trackingSelection;
@end
@implementation WordTextFact @end
@interface WordLabelFact : NSObject
@property(nonatomic,copy) NSString *stringValue;
@end
@implementation WordLabelFact @end
@interface WordAreaFact : NSObject
@property(nonatomic,getter=isHidden) BOOL hidden;
@end
@implementation WordAreaFact @end
@interface WordHostPeer : NSObject
@property(nonatomic,strong) FYLearningCoordinator *learningCoordinator;
@property(nonatomic,strong) FYJapaneseTokenizer *japaneseTokenizer;
@property(nonatomic,strong) NSTextField *vocabularyStatusLabel;
@property(nonatomic) NSInteger referenceRequestGeneration;
@property(nonatomic,copy) NSString *referenceActiveWord;
@property(nonatomic) NSUInteger statusRefreshes,sourceRefreshes,clears,lists;
@end
@implementation WordHostPeer
- (void)refreshLearningStatus{self.statusRefreshes++;}
- (void)refreshLearningSource{self.sourceRefreshes++;}
- (void)clearAnalysisDisplay{self.clears++;}
- (void)refreshVocabularyList{self.lists++;}
@end
static void TokenReply(SelectionTokenizerFact *t,NSRange range){void (^reply)(NSRange)=[t.replies[0]copy];[t.replies removeObjectAtIndex:0];reply(range);}
static FYMainWindowController *Controller(WordHostPeer *peer,SelectionLearningFact *learning,SelectionTokenizerFact *token){peer.learningCoordinator=(FYLearningCoordinator *)learning;peer.japaneseTokenizer=(FYJapaneseTokenizer *)token;peer.vocabularyStatusLabel=(NSTextField *)[WordLabelFact new];FYMainWindowController *h=[[FYMainWindowController alloc]initWithHost:(id<FYMainWindowControllerHost>)peer];h.displayedSentenceID=@"sentence";h.displayedVersion=1;h.displayedSourceText=@"ああ";h.displayedTranslation=@"synthetic";learning.currentSentenceID=@"sentence";learning.currentVersion=1;learning.currentSourceText=@"ああ";WordTextFact *text=[WordTextFact new];text.string=@"ああ";text.selectedRange=NSMakeRange(0,1);h.learningSourceTextView=(FYSelectableSourceTextView *)text;h.lemmaField=(NSTextField *)[WordLabelFact new];h.readingField=(NSTextField *)[WordLabelFact new];h.meaningField=(NSTextField *)[WordLabelFact new];h.vocabularySelectionLabel=(NSTextField *)[WordLabelFact new];h.wordPickSurfaceLabel=(NSTextField *)[WordLabelFact new];h.wordPickArea=(NSStackView *)[WordAreaFact new];return h;}
int main(void){@autoreleasepool{
 Check(NSApp==nil,@"actual original/extracted main learning host remains headless");WordHostPeer *peer=[WordHostPeer new];SelectionLearningFact *learning=[SelectionLearningFact new];SelectionTokenizerFact *token=[SelectionTokenizerFact new];FYMainWindowController *h=Controller(peer,learning,token);WordTextFact *text=(WordTextFact *)h.learningSourceTextView;
 text.selectedRange=NSMakeRange(NSNotFound,1);Check([[h selectedLearningText]isEqual:@""],@"actual NotFound returns empty");text.selectedRange=NSMakeRange(2,1);Check([[h selectedLearningText]isEqual:@""],@"actual out-of-bounds returns empty");text.selectedRange=NSMakeRange(1,1);Check([[h selectedLearningText]isEqual:@"あ"],@"actual original UTF16 selected substring");text.trackingSelection=YES;h.lemmaField.stringValue=@"held";[h updateWordPickForSelection];Check([h.lemmaField.stringValue isEqual:@"held"],@"actual tracking guard leaves forms unchanged");text.trackingSelection=NO;h.vocabCompletionFromAI=YES;[h updateWordPickForSelection];Check(h.lemmaField.stringValue.length==0&&!h.vocabCompletionFromAI&&!h.wordPickArea.hidden&&[h.wordPickSurfaceLabel.stringValue isEqual:@"遇到的词形：あ"],@"actual native form adapters preserve reset/show/status");[h closeWordPick:nil];Check(h.wordPickArea.hidden&&text.selectedRange.location==1&&!text.selectedRange.length,@"actual close keeps range location and clears length");
 h.displayedSentenceID=@"visible";h.displayedVersion=2;[h freezeLearningSentenceForSelection];Check([learning.currentSentenceID isEqual:@"visible"]&&learning.currentVersion==2&&learning.pins==1&&peer.statusRefreshes==1&&peer.referenceRequestGeneration==1&&[peer.referenceActiveWord isEqual:@""],@"actual freeze/sync/pin/reference/Host sequence");[h vocabularyFormChanged:nil];Check(h.vocabSelectionGeneration==2&&!h.vocabCompletionFromAI&&[h.vocabularySelectionLabel.stringValue hasPrefix:@"手动填写"],@"actual manual change advances original generation and clears AI");
 text.selectedRange=NSMakeRange(0,1);text.selectedRange=NSMakeRange(0,1);[h selectWordAtCharacterIndex:0];[h selectWordAtCharacterIndex:1];TokenReply(token,NSMakeRange(1,1));Check(text.selectedRange.location==0,@"actual stale tokenizer generation cannot replace current selection");TokenReply(token,NSMakeRange(1,1));Check(text.selectedRange.location==1,@"actual latest tokenizer gate applies to original native view");
 h.lemmaField.stringValue=@" lemma ";h.readingField.stringValue=@" read ";h.meaningField.stringValue=@" meaning ";[h bookmarkSelectedVocabulary:nil];Check(h.savingVocabulary&&[learning.submitted.lemma isEqual:@"lemma"]&&[learning.submitted.reading isEqual:@"read"]&&[learning.submitted.meaning isEqual:@"meaning"]&&learning.submitted.completionSource==FYCompletionSourceManual,@"actual bookmark uses original form reads/Trim/manual model and busy state");[h bookmarkSelectedVocabulary:nil];Check(learning.bookmarks==1,@"actual busy prevents another bookmark");h.vocabSelectionGeneration++;learning.bookmarkReply(Suggestion(),NO,nil);learning.bookmarkReply=nil;Check(!h.savingVocabulary&&peer.lists==1,@"actual stale save releases original busy before list refresh");
 text.selectedRange=NSMakeRange(0,1);[h completeSelectedVocabulary:nil];text.selectedRange=NSMakeRange(1,1);NSString *lemma=h.lemmaField.stringValue;learning.completionReply(Suggestion(),nil);learning.completionReply=nil;Check(h.lemmaField.stringValue==lemma&&!h.vocabCompletionFromAI,@"actual same-text other occurrence rejects AI by range identity");text.selectedRange=NSMakeRange(0,1);[h completeSelectedVocabulary:nil];learning.completionReply(Suggestion(),nil);learning.completionReply=nil;Check([h.lemmaField.stringValue isEqual:@"原形"]&&[h.readingField.stringValue isEqual:@"読み"]&&[h.meaningField.stringValue isEqual:@"意思"]&&h.vocabCompletionFromAI&&[h.vocabularySelectionLabel.stringValue hasPrefix:@"あ（AI 建议"],@"actual current AI applies original UI field/state/hints");
 [h followLatestSentence:nil];Check(peer.clears==1&&learning.follows==1,@"actual follow clears analysis before async work");learning.followReply();learning.followReply=nil;Check(peer.sourceRefreshes==1&&peer.statusRefreshes==2,@"actual follow weak callback keeps Host refresh order");
 __weak FYMainWindowController *strongLease;SelectionTokenizerFact *heldToken=[SelectionTokenizerFact new];WordHostPeer *heldPeer=[WordHostPeer new];@autoreleasepool{FYMainWindowController *q=Controller(heldPeer,[SelectionLearningFact new],heldToken);strongLease=q;[q selectWordAtCharacterIndex:0];}@autoreleasepool{Check(strongLease!=nil,@"actual tokenizer completion preserves original strong concrete controller lease");TokenReply(heldToken,NSMakeRange(0,1));}Check(!strongLease,@"actual tokenizer controller releases after callback completes");
 SelectionLearningFact *heldLearning=[SelectionLearningFact new];__weak FYMainWindowController *weakAI;@autoreleasepool{FYMainWindowController *q=Controller(heldPeer,heldLearning,[SelectionTokenizerFact new]);weakAI=q;[q completeSelectedVocabulary:nil];}Check(!weakAI,@"actual AI callback remains weak concrete controller");heldLearning.completionReply(Suggestion(),nil);heldLearning.completionReply=nil;
 Check(NSApp==nil,@"same fixture actual main callbacks/state/adapters remain headless; real desktop behavior only compiled");printf("PASS WordSelectionHostTests: %lu checks;actual original/extracted main controller,strong/weak/range/gen/UI boundary facts,no UI objects\n",(unsigned long)checks);
}return 0;}
