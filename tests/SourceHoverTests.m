#import "LearningAppTestSupport.h"
static NSString *Tip(AppDelegate *app,NSUInteger location){return [app.learningSourceTextView.textStorage attribute:FYSourceHoverAttributeName atIndex:location effectiveRange:NULL];}
int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];FYLearningStore *store=Store([NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]);FYGrammarCatalog *catalog=[FYGrammarCatalog new];AppDelegate *app=App(store,Analyzer(catalog),catalog);app.japaneseTokenizer=[FYJapaneseTokenizer new];
    app.referenceDictionary=[[FYReferenceDictionary alloc] initWithURL:[NSURL fileURLWithPath:[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"resources/learning/reference/reference.sqlite"]]];
    NSString *source=@"絵が得意でも、毎日練習しないと上達しない。";FYRequestIdentity *identity=[app.learningCoordinator recordText:source kind:FYSentenceKindDialogue];Drain(store);[app refreshLearningSource];
    NSUInteger word=[source rangeOfString:@"得意"].location;NSLog(@"stage: dictionary");Pump(^BOOL{return [Tip(app,word) containsString:@"JMdict"];});
    Require([Tip(app,word) containsString:@"とくい"] && app.learningSourceTextView.selectedRange.length==0 && !app.learningCoordinator.isPinned,@"word hover metadata includes actual dictionary reading without selecting or pinning sentence");
    NSUInteger generation=app.sourceHoverGeneration;[app refreshLearningSource];Require(app.sourceHoverGeneration==generation,@"unchanged live refresh does not reset hovering hints");
    FYGrammarItem *grammar=[FYGrammarItem new];grammar.name=@"〜ても";grammar.matchedText=@"得意でも";grammar.matchedRange=[source rangeOfString:grammar.matchedText];grammar.meaning=@"即使……也……";grammar.explanation=@"这里让步说明擅长也仍需练习。";
    FYAnalysisResult *analysis=[FYAnalysisResult new];analysis.sentenceID=identity.sentenceID;analysis.version=identity.version;analysis.status=FYAnalysisStatusSuccess;analysis.grammar=@[grammar];app.currentAnalysis=analysis;[app highlightGrammarMatches];
    NSLog(@"stage: grammar");Pump(^BOOL{return [Tip(app,word) containsString:@"〜ても"];});Tick();Require([Tip(app,word) containsString:@"即使"] && [Tip(app,word) containsString:@"仍需练习"],@"grammar tooltip overrides overlapping word lookup and includes current sentence explanation");
    // Drive the actual mouse-move handler with a glyph-local event; no API calls or user data.
    [app.mainWindow makeKeyAndOrderFront:nil];[app.mainWindow.contentView layoutSubtreeIfNeeded];Tick();
    FYSelectableSourceTextView *view=(FYSelectableSourceTextView *)app.learningSourceTextView;
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    NSRange glyphRange=[view.layoutManager glyphRangeForCharacterRange:NSMakeRange(word,1) actualCharacterRange:NULL];
    NSRect glyphRect=[view.layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:view.textContainer];
    NSPoint point=NSMakePoint(NSMidX(glyphRect)+view.textContainerOrigin.x,NSMidY(glyphRect)+view.textContainerOrigin.y);
    point=[view convertPoint:point toView:nil];
    NSEvent *move=[NSEvent mouseEventWithType:NSEventTypeMouseMoved location:point modifierFlags:0 timestamp:0 windowNumber:app.mainWindow.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
    [view mouseMoved:move];
    Pump(^BOOL{return [[view valueForKey:@"sourceHoverPanel"] isVisible];});
    NSPanel *panel=[view valueForKey:@"sourceHoverPanel"];
    Require([panel.contentView isKindOfClass:FYAdventurePanel.class] && panel.ignoresMouseEvents && !panel.canBecomeKeyWindow,@"hover uses themed card and cannot capture game/text focus or clicks");
    Require([view.textStorage attribute:NSToolTipAttributeName atIndex:word effectiveRange:NULL]==nil,@"native tooltip cannot appear alongside themed hover");
    if(argc>1){NSView *card=panel.contentView;[card displayIfNeeded];NSBitmapImageRep *bitmap=[card bitmapImageRepForCachingDisplayInRect:card.bounds];[card cacheDisplayInRect:card.bounds toBitmapImageRep:bitmap];Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"grammar-hover.png"] atomically:YES],@"themed card snapshot");}
    NSEvent *exitEvent=[NSEvent enterExitEventWithType:NSEventTypeMouseExited location:point modifierFlags:0 timestamp:0 windowNumber:app.mainWindow.windowNumber context:nil eventNumber:0 trackingNumber:0 userData:NULL];
    [view mouseExited:exitEvent];Require(!panel.isVisible,@"exiting original text dismisses themed hover");
    [view mouseMoved:move];[view dismissSourceHover];Tick();Require(!panel.isVisible,@"cancelled dwell cannot reopen card");
    app.learningSourceTextView.selectedRange=NSMakeRange(word,4);[app refreshSourceHoverTips];Tick();Require(NSEqualRanges(app.learningSourceTextView.selectedRange,NSMakeRange(word,4)),@"hover annotations preserve native selection");
    [app clearAnalysisDisplay];NSLog(@"stage: clear analysis");Pump(^BOOL{return [Tip(app,word) containsString:@"JMdict"];});Require(![Tip(app,word) containsString:@"〜ても"],@"clearing analysis removes old grammar tooltip");
    [app.learningCoordinator recordText:@"新しい台詞。" kind:FYSentenceKindDialogue];[app.learningCoordinator followLatest];Drain(store);[app refreshLearningSource];Tick();
    Require(![[app.learningSourceTextView.textStorage description] containsString:@"即使"] && ![[app.learningSourceTextView.textStorage description] containsString:@"とくい"],@"new sentence cannot inherit previous word or grammar tooltip");
    [app.mainWindow orderOut:nil];NSLog(@"PASS: native source hover, dictionary readings, verified grammar, stable refresh, selection/edit and sentence isolation");
}return 0;}
