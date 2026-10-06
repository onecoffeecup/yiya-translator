#import "LearningAppTestSupport.h"
static NSArray *Lookup(FYReferenceDictionary *dictionary,NSString *word,NSString *reading) {
    __block BOOL done=NO;__block NSArray *found=nil;
    [dictionary lookupWord:word reading:reading completion:^(NSArray *records,NSError *error){Require(!error,@"reference lookup failed");Require(NSThread.isMainThread,@"reference results must return on main thread");found=records;done=YES;}];
    Pump(^BOOL{return done;});return found;
}
static NSString *ReferenceText(NSView *view) {
    NSMutableString *text=[NSMutableString new];
    if([view isKindOfClass:NSTextField.class]){[text appendString:[(NSTextField *)view stringValue]];}
    for(NSView *child in view.subviews){[text appendString:ReferenceText(child)];}
    return text;
}
int main(int argc,const char *argv[]){@autoreleasepool{
    [NSApplication sharedApplication];
    NSString *root=NSFileManager.defaultManager.currentDirectoryPath;
    NSURL *url=[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"resources/learning/reference/reference.sqlite"]];
    FYReferenceDictionary *dictionary=[[FYReferenceDictionary alloc] initWithURL:url];
    NSArray *records=Lookup(dictionary,@"得意",@"");
    Require(records.count==1,@"得意 must match exactly once");
    NSDictionary *tokui=records[0];Require([tokui[@"reference_levels"] isEqual:@[@"N3"]],@"actual reference level must not be replaced by prototype N1/N2 training labels");
    Require([tokui[@"readings"] containsObject:@"とくい"],@"dictionary reading must be retained");
    Require([tokui[@"senses"] count]>=3,@"separate senses must remain separate");
    NSUInteger exCount=0;
    for(NSDictionary *sense in tokui[@"senses"]){for(NSDictionary *example in sense[@"examples"]){exCount++;Require([example[@"author"] length]>0 && [example[@"sentence_id"] length]>0 && [example[@"url"] hasPrefix:@"https://tatoeba.org/"],@"every example needs author and source");}}
    Require(exCount>0,@"得意 must have a dictionary-linked example");
    Require(Lookup(dictionary,@"生物",@"").count==2,@"homographs must not be guessed or merged");
    records=Lookup(dictionary,@"生物",@"なまもの");Require(records.count==1 && [records[0][@"readings"] isEqual:@[@"なまもの"]],@"reading must disambiguate homographs");
    Require(Lookup(dictionary,@"生物",@"invalid").count==0,@"conflicting reading must not silently pick a meaning");
    Require(Lookup(dictionary,@"これは未登録の架空単語です",@"").count==0,@"missing words must not fabricate content");
    Require(Lookup(dictionary,@"得意だ",@"").count==0,@"inflection cannot silently choose a dictionary entry");
    Require(Lookup(dictionary,@"あくまで",@"").count==1,@"known dictionary word missing");
    for(NSDictionary *sense in Lookup(dictionary,@"あくまで",@"")[0][@"senses"]){for(NSDictionary *example in sense[@"examples"]){Require(![example[@"ja"] containsString:@"席があくまで"],@"OpenJLPT lexical mismatch must not enter imported examples");}}
    Require([Lookup(dictionary,@"遭う",@"")[0][@"reference_levels"] isEqual:@[@"N2"]],@"会う N5 must not leak into 遭う N2 via a shared JMdict ID");
    FYReferenceDictionary *missing=[[FYReferenceDictionary alloc] initWithURL:nil];__block BOOL done=NO;
    [missing lookupWord:@"得意" reading:nil completion:^(NSArray *found,NSError *e){Require(e && !found.count,@"missing data is an explicit error");done=YES;}];Pump(^BOOL{return done;});
    // 词典现位于收藏词详情，实时页集成/不跳页行为由 CollectionLayoutTests 验证。
    FYSavedWordReferenceView *view=[[FYSavedWordReferenceView alloc] initWithFrame:NSMakeRect(0,0,440,500)];
    [view loadWord:@"得意" reading:@"とくい" dictionary:dictionary];
    Pump(^BOOL{return [ReferenceText(view) containsString:@"词典读音：とくい"];});
    Require([ReferenceText(view) containsString:@"JLPT 参考 N3"] && [ReferenceText(view) containsString:@"英文释义"],@"saved reference renders actual reading, grade and dictionary origin");
    NSSegmentedControl *tabs=nil;NSPopUpButton *senses=nil;
    for(NSView *child in view.arrangedSubviews){
        if([child isKindOfClass:NSSegmentedControl.class]){tabs=(NSSegmentedControl *)child;}
        if([child isKindOfClass:NSPopUpButton.class]){senses=(NSPopUpButton *)child;}
    }
    Require(tabs.segmentCount==3 && senses.numberOfItems>=3,@"saved reference exposes senses and three detail tabs");
    NSUInteger exampleSense=0;
    for(NSDictionary *sense in tokui[@"senses"]){if([sense[@"examples"] count]){break;}exampleSense++;}
    [senses selectItemAtIndex:exampleSense];tabs.selectedSegment=1;
    [NSApp sendAction:tabs.action to:tabs.target from:tabs];
    Require([ReferenceText(view) containsString:@"Tatoeba #"] && [ReferenceText(view) containsString:@"作者"],@"saved examples preserve per-sentence attribution");
    tabs.selectedSegment=2;[NSApp sendAction:tabs.action to:tabs.target from:tabs];
    Require([ReferenceText(view) containsString:@"CC BY-SA 4.0"] && [ReferenceText(view) containsString:@"Jonathan Waller"],@"saved reference exposes data licenses and level source");
    [view loadWord:@"得意" reading:@"とくい" dictionary:dictionary];
    [view loadWord:@"遭う" reading:@"あう" dictionary:dictionary];
    Pump(^BOOL{return [ReferenceText(view) containsString:@"JLPT 参考 N2"];});
    Tick();Require(![ReferenceText(view) containsString:@"JLPT 参考 N3"],@"late lookup cannot replace newer saved reference");
    [view loadWord:@"这是不存在的词" reading:@"" dictionary:dictionary];
    Pump(^BOOL{return [ReferenceText(view) containsString:@"没有匹配到"];});
    Require(![ReferenceText(view) containsString:@"JLPT 参考"],@"missing lookup clears old dictionary data");
    NSLog(@"PASS: offline dictionary, attributed examples, exact grades, homographs, missing data, saved-word tabs and stale response protection");
}return 0;}
