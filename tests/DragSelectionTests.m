#import "LearningAppTestSupport.h"
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".sqlite"]];
    FYGrammarCatalog *catalog=[FYGrammarCatalog new];FYLearningStore *store=Store(path);
    AppDelegate *app=App(store,Analyzer(catalog),catalog);app.japaneseTokenizer=[FYJapaneseTokenizer new];
    [app.learningCoordinator recordText:@"絵が得意でも、毎日練習しないと上達しない。" kind:FYSentenceKindDialogue];Drain(store);
    app.learningSourceTextView.editable=NO;[app refreshLearningSource];
    app.referenceActiveWord=@"旧选词";NSInteger previous=app.vocabSelectionGeneration;
    [app.learningSourceTextView setValue:@YES forKey:@"trackingSelection"];
    app.learningSourceTextView.willBeginSelection();
    Require(app.learningCoordinator.isPinned && app.vocabSelectionGeneration>previous,@"selection start freezes source and invalidates pending click tokenization");
    NSInteger queries=app.referenceRequestGeneration;app.lemmaField.stringValue=@"尚未完成的选词";
    for(NSUInteger length=1;length<=4;length++){
        app.learningSourceTextView.selectedRange=NSMakeRange(2,length);[app updateWordPickForSelection];
        Require(app.referenceRequestGeneration==queries && [app.lemmaField.stringValue isEqualToString:@"尚未完成的选词"],@"dragging cannot query or mutate cards/forms during tracking");
    }
    [app.learningSourceTextView setValue:@NO forKey:@"trackingSelection"];app.learningSourceTextView.didFinishSelection();
    Require(app.referenceRequestGeneration==queries && app.referenceActiveWord.length==0 && app.lemmaField.stringValue.length==0,@"mouse release clears old completion without issuing a dictionary query");
    Require([app selectedLearningText] && [[app selectedLearningText] isEqualToString:@"得意でも"],@"drag-picked phrase remains selected");
    Require(!app.wordPickArea.hidden && [app.wordPickSurfaceLabel.stringValue isEqualToString:@"遇到的词形：得意でも"],@"mouse release opens confirmation for the exact final phrase");
    [app.learningCoordinator recordText:@"新しい台詞" kind:FYSentenceKindDialogue];Drain(store);
    Require([app.learningSourceTextView.string containsString:@"得意でも"],@"new OCR does not replace frozen source while selecting");
    [app selectWordAtCharacterIndex:2];Pump(^BOOL{return [app.selectedLearningText isEqualToString:@"得意"];});
    Require(!app.wordPickArea.hidden && [app.wordPickSurfaceLabel.stringValue isEqualToString:@"遇到的词形：得意"] && app.referenceRequestGeneration==queries,@"single-click selection updates confirmation after drag without an implicit query");
    [app.mainWindow orderOut:nil];NSLog(@"PASS: deferred drag updates, exact phrase confirmation, frozen OCR source, pending-token invalidation and retained click selection");
}return 0;}
