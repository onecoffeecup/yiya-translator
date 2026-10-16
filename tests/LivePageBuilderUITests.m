#import "LearningAppTestSupport.h"
#import <objc/runtime.h>
#ifndef FY_LIVE_PAGE_EXTRACTED
#define FY_LIVE_PAGE_EXTRACTED 1
#endif
static NSView *AncestorCard(NSView *view){for(NSView *p=view.superview;p;p=p.superview)if([p isKindOfClass:FYAdventurePanel.class])return p;return nil;}
static NSUInteger VisibleCardIndex(NSView *document,NSView *card){NSUInteger i=0;for(NSView *view in document.subviews){if(view==card)return i;i++;}return NSNotFound;}
int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];NSString *directory=argc>1?[NSString stringWithUTF8String:argv[1]]:NSTemporaryDirectory();FYGrammarCatalog *catalog=[FYGrammarCatalog new];FYLearningStore *store=Store([directory stringByAppendingPathComponent:@"live-page-builder.sqlite"]);AppDelegate *app=App(store,Analyzer(catalog),catalog);[app.mainWindow.contentView layoutSubtreeIfNeeded];Tick();
    Require([app.framePreview isKindOfClass:FYCapturePreviewView.class],@"production native preview keeps canonical frame-driven class");Require(app.framePreview.imageScaling==NSImageScaleProportionallyUpOrDown,@"native preview proportional scaling unchanged");
    Require(app.learningTranslationLabel.selectable&&app.learningTranslationLabel.allowsEditingTextAttributes&&app.learningTranslationLabel.maximumNumberOfLines==0,@"Chinese translation retains native selection and attributed editing");Require(app.learningTranslationLabel.lineBreakMode==NSLineBreakByWordWrapping,@"translation native wrapping unchanged");
    Require(app.learningSourceTextView.defaultParagraphStyle.lineSpacing==0&&app.learningSourceTextView.font.pointSize==19,@"source native configuration uses original19/spacing0");Require(app.learningSourceTextView.willBeginSelection&&app.learningSourceTextView.didFinishSelection&&app.learningSourceTextView.didClickAtCharacterIndex,@"production native source keeps all three selection callbacks");
    Require(app.liveChipRecognition&&app.liveChipAutoTranslate&&app.liveChipPauseFollow,@"original status chip resources exist");Require(app.liveErrorLabel.maximumNumberOfLines==2&&app.liveErrorLabel.hidden,@"native error label preserves two-line hidden empty state");Require(app.liveLevelTag.hidden&&app.followLatestButton.hidden&&app.wordPickArea.hidden,@"original initial level/follow/form visibility unchanged");Require(app.inlineTranslationListCard.hidden&&app.inlineTranslationListSnapshots.count==0,@"list card starts hidden with empty copied snapshots");
    Require(app.pinSentenceButton.target==app&&app.pinSentenceButton.action==@selector(toggleLearningPin:),@"workspace button targets original Host selector");Require(app.followLatestButton.target==app&&app.followLatestButton.action==@selector(followLatestSentence:),@"native follow button keeps original target/action");
    for(NSTextField *field in @[app.lemmaField,app.readingField,app.meaningField])Require(field.action==@selector(vocabularyFormChanged:),@"native form fields retain original action");
    NSView *translation=AncestorCard(app.learningTranslationLabel),*source=AncestorCard(app.learningSourceTextView),*preview=AncestorCard(app.framePreview);Require(translation&&source&&preview&&translation!=source,@"production preview/translation/source cards remain independent");
    Require([((FYAdventurePanel *)translation).fillColor isEqual:FYAdventureColor(@"cream")]&&[((FYAdventurePanel *)source).fillColor isEqual:FYAdventureColor(@"paper")],@"original native card palette unchanged");
    NSInteger generation=app.vocabSelectionGeneration;app.learningSourceTextView.willBeginSelection();Require(app.vocabSelectionGeneration>generation,@"actual native selection callback reaches sole production Word3 owner");
#if FY_LIVE_PAGE_EXTRACTED
    unsigned int count=0;Ivar *ivars=class_copyIvarList(FYLivePageBuilder.class,&count);free(ivars);Require(app.mainWindowController.livePageBuilder&&count==0,@"native builder has no duplicate state or source/view lease");
#endif
    Require(app.mainWindowMinimumWidth.constant==1100||app.mainWindowMinimumWidth.constant==720,@"native builder introduces no new outer window width policy");
    [app.mainWindow close];Drain(store);printf("PASS LivePageBuilderUITests: real native production page graph/selection/resources; only valid when explicitly run in desktop slot\n");
}return 0;}
