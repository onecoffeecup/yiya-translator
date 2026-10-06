#import "LearningAppTestSupport.h"
static NSString *CollectionText(NSView *view){
    if(view.hidden){return @"";}
    NSMutableString *text=[NSMutableString new];
    if([view isKindOfClass:NSTextField.class]){[text appendString:[(NSTextField *)view stringValue]];}
    for(NSView *child in view.subviews){[text appendString:CollectionText(child)];}return text;
}
static NSButton *CollectionButton(NSView *view,NSString *title){
    if([view isKindOfClass:NSButton.class] && [[(NSButton *)view title] isEqualToString:title]){return (NSButton *)view;}
    for(NSView *child in view.subviews){NSButton *button=CollectionButton(child,title);if(button){return button;}}return nil;
}
static void CollectionScreenshot(NSView *view,NSString *path){
    [view layoutSubtreeIfNeeded];NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];[view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"collection screenshot saved");
}
int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];
    FYLearningStore *store=Store([NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]);FYGrammarCatalog *catalog=[FYGrammarCatalog new];AppDelegate *app=App(store,Analyzer(catalog),catalog);
    NSString *source=@"絵が得意でも、毎日練習しないと上達しない。";
    FYRequestIdentity *original=[app.learningCoordinator recordText:source kind:FYSentenceKindDialogue];[app.learningCoordinator setTranslation:@"即使擅长画画，也要每天练习。" forIdentity:original];
    Bookmark(app,@"得意",@"得意",@"とくい",@"擅长；拿手");
    [app.learningCoordinator recordText:@"新しい台詞です。" kind:FYSentenceKindDialogue];Drain(store);
    [app selectPageAtIndex:2];Pump(^BOOL{return app.reviewList.count==1;});Tick();
    Require(app.learningCollectionHost.arrangedSubviews.count==1 && app.learningCollectionHost.arrangedSubviews.firstObject==app.learningCollectionSections[0],@"default collection page only presents words");
    NSString *summary=CollectionText(app.learningCollectionHost);
    Require([summary containsString:@"擅长；拿手"] && ![summary containsString:source] && ![summary containsString:@"简单复习"] && ![summary containsString:@"已收藏语法"],@"compact word list shows meaning and excludes long context and unrelated modules");
    Require([app.learningCollectionCount.stringValue isEqualToString:@"1 个收藏"],@"collection count matches stored words");
    Require(app.referenceCard==nil && CollectionButton(app.pages[0],@"用法与等级参考")==nil,@"live page no longer displays dictionary module or its entry point");
    NSButton *hide=CollectionButton(app.wordCardStack,@"遮住释义");
    NSButton *detail=CollectionButton(app.wordCardStack,@"查看详情");
    Require(hide.superview==detail.superview && !hide.superview.hidden,@"meaning toggle is a visible peer of details");
    [hide performClick:nil];Require([CollectionText(app.wordCardStack) containsString:@"释义已遮住"] && ![CollectionText(app.wordCardStack) containsString:@"擅长；拿手"],@"meaning can hide without opening details");
    [hide performClick:nil];Require([CollectionText(app.wordCardStack) containsString:@"擅长；拿手"],@"meaning can reveal from summary row");
    Require(detail!=nil,@"compact card offers details");
    [detail performClick:nil];Pump(^BOOL{return [CollectionText(app.wordCardStack) containsString:source];});
    Require([detail.title isEqualToString:@"收起详情"] && CollectionButton(app.wordCardStack,@"取消收藏")!=nil,@"details reveal source and retained management actions");
    app.referenceDictionary=[[FYReferenceDictionary alloc] initWithURL:[NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"resources/learning/reference/reference.sqlite"]]];
    NSString *liveSource=app.learningCoordinator.currentSourceText;NSInteger referenceGeneration=app.referenceRequestGeneration;
    NSButton *reference=CollectionButton(app.wordCardStack,@"用法与等级参考");[reference performClick:nil];
    Pump(^BOOL{return [CollectionText(app.wordCardStack) containsString:@"词典读音：とくい"];});
    Require(app.selectedPage==2 && app.learningCollectionIndex==0 && [app.learningCoordinator.currentSourceText isEqualToString:liveSource] && app.referenceRequestGeneration==referenceGeneration,@"saved-word reference stays in collection and leaves live sentence and lookup untouched");
    Require([CollectionText(app.wordCardStack) containsString:@"JLPT 参考"] && [CollectionText(app.wordCardStack) containsString:@"JMdict"],@"saved word renders real bundled dictionary and reference grades");
    FYSavedWordReferenceView *referenceView=(FYSavedWordReferenceView *)((NSStackView *)reference.superview.superview).arrangedSubviews.lastObject;
    NSSegmentedControl *referenceTabs=nil;for(NSView *child in referenceView.arrangedSubviews){if([child isKindOfClass:NSSegmentedControl.class]){referenceTabs=(NSSegmentedControl *)child;}}
    Require(referenceTabs!=nil,@"saved reference offers independent meaning examples and source tabs");
    referenceTabs.selectedSegment=2;[NSApp sendAction:referenceTabs.action to:referenceTabs.target from:referenceTabs];
    Require([CollectionText(referenceView) containsString:@"CC BY-SA 4.0"] && app.selectedPage==2,@"source tab preserves collection context and shows provenance");
    [hide performClick:nil];Require(!referenceView.hidden && [detail.title isEqualToString:@"收起详情"],@"hiding meaning preserves expanded detail and reference context");[hide performClick:nil];
    [reference performClick:nil];Require(referenceView.hidden,@"saved reference can collapse within word details");
    [detail performClick:nil];Require(![CollectionText(app.wordCardStack) containsString:source],@"closing details returns to compact list");
    for(NSUInteger index=1;index<4;index++){
        [app.learningCollectionTabs[index] performClick:nil];Tick();Require(app.learningCollectionHost.arrangedSubviews.count==1 && app.learningCollectionHost.arrangedSubviews.firstObject==app.learningCollectionSections[index],@"each collection/review tab displays exactly one section");
    }
    [app.learningCollectionTabs[0] performClick:nil];
    [app.mainWindow setFrame:NSMakeRect(50,50,980,660) display:NO];Tick();
    NSLog(@"COLLECTION MINIMUM: %@",NSStringFromRect(app.mainWindow.frame));
    Require(fabs(NSWidth(app.mainWindow.frame)-980)<1,@"compact collection supports minimum window width");
    Require(NSHeight(app.learningCollectionTitle.frame)<35,@"collection heading remains a readable line at minimum width");
    if(argc>1){CollectionScreenshot(app.mainWindow.contentView,[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"collection-narrow.png"]);}
    [detail performClick:nil];Tick();Require(fabs(NSWidth(app.mainWindow.frame)-980)<1,@"expanded details do not force a wider window");[detail performClick:nil];
    for(NSUInteger index=1;index<4;index++){[app.learningCollectionTabs[index] performClick:nil];Tick();Require(fabs(NSWidth(app.mainWindow.frame)-980)<1,@"all collection sections fit minimum window");}
    [app.learningCollectionTabs[0] performClick:nil];
    Require(CollectionButton(app.wordCardStack,@"回到原句")==nil,@"word cards no longer offer return-to-source navigation");
    [app.mainWindow orderOut:nil];NSLog(@"PASS: compact collection, hidden details, separate sections, minimum width and no return-to-source action");
}return 0;}
