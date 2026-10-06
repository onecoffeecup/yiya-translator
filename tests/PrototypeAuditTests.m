#import "LearningAppTestSupport.h"
static NSArray *Parts(void){return @[@{@"text":@"絵が得意でも",@"occurrence":@0,@"meaning_zh":@"即使擅长画画",@"role_zh":@"让步"},@{@"text":@"毎日練習しないと",@"occurrence":@0,@"meaning_zh":@"如果不每天练习",@"role_zh":@"条件"},@{@"text":@"上達しない",@"occurrence":@0,@"meaning_zh":@"不会进步",@"role_zh":@"结果"}];}
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];NSString *source=@"絵が得意でも、毎日練習しないと上達しない。";
    FYGrammarCatalog *catalog=[FYGrammarCatalog new];FYLearningAnalyzer *analyzer=Analyzer(catalog);
    __block NSArray *parts=Parts();analyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){
        NSDictionary *payload=[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];Require([payload[@"messages"][0][@"content"] containsString:@"structure_parts"],@"prompt requests whole-sentence structure");
        NSDictionary *json=@{@"schema_version":@1,@"grammar":@[],@"vocabulary":@[],@"structure_title_zh":@"先让步，再说条件和结果",@"structure_parts":parts};
        done(Envelope([[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:json options:0 error:NULL] encoding:NSUTF8StringEncoding]),Response(),nil);
    };
    __block FYAnalysisResult *result=nil;[analyzer analyzeSentence:source translation:nil completion:^(FYAnalysisResult *value,NSError *error){Require(!error,@"valid structure parsed");result=value;}];Pump(^BOOL{return result!=nil;});
    Require(result.structureParts.count==3 && [result.structureParts[2][@"text"] isEqualToString:@"上達しない"],@"result clause retained even without separate grammar match");
    FYAnalysisResult *good=result;
    for(NSArray *bad in @[@[Parts()[1],Parts()[0]],@[@{@"text":@"上達する",@"meaning_zh":@"会进步",@"role_zh":@"结果"},Parts()[0]],@[@{@"text":source,@"meaning_zh":@"整句",@"role_zh":@"主句"},Parts()[1]]]){
        parts=bad;result=nil;[analyzer analyzeSentence:source translation:nil completion:^(FYAnalysisResult *value,NSError *error){Require(!error,@"bad optional structure does not break analysis");result=value;}];Pump(^BOOL{return result!=nil;});Require(result.structureParts.count==0,@"out-of-order, invented or overlapping structure cannot be drawn");
    }
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".sqlite"]];FYLearningStore *store=Store(path);
    __block BOOL closed=NO;[store closeWithCompletion:^(NSError *error){Require(!error,@"close legacy fixture");closed=YES;}];Pump(^BOOL{return closed;});
    sqlite3 *legacy=NULL;Require(sqlite3_open(path.UTF8String,&legacy)==SQLITE_OK,@"legacy fixture open");Require(sqlite3_exec(legacy,"DROP TABLE sentence_bookmarks; PRAGMA user_version=1;",NULL,NULL,NULL)==SQLITE_OK,@"simulate installed version-one schema");sqlite3_close(legacy);
    store=Store(path);
    FYLearningCoordinator *coordinator=[[FYLearningCoordinator alloc] initWithStore:store analyzer:analyzer tokenizer:[FYJapaneseTokenizer new] catalog:catalog];
    FYRequestIdentity *identity=[coordinator recordText:source kind:FYSentenceKindDialogue];[coordinator setTranslation:@"即使擅长画画，不练习也不会进步。" forIdentity:identity];Drain(store);
    __block BOOL done=NO;[store saveAnalysisResult:good sentenceID:identity.sentenceID version:identity.version textHash:@"test" promptVersion:3 catalogVersion:1 modelConfig:@"mock" completion:^(NSError *error){Require(!error,@"structure cache save");done=YES;}];Pump(^BOOL{return done;});
    result=nil;[store fetchAnalysisForSentence:identity.sentenceID version:identity.version completion:^(FYAnalysisResult *value,NSString *config,NSError *error){Require(!error,@"structure cache read");result=value;}];Pump(^BOOL{return result!=nil;});Require(result.structureParts.count==3 && [result.structureTitle containsString:@"让步"],@"structure survives cache round trip");
    done=NO;[store toggleSentenceBookmark:identity completion:^(BOOL saved,NSError *error){Require(saved && !error,@"sentence bookmark saved");done=YES;}];Pump(^BOOL{return done;});
    FYLearningStore *reopened=Store(path);__block NSArray *saved=nil;[reopened fetchSentenceBookmarks:^(NSArray *values,NSError *error){Require(!error,@"persistent sentence bookmark read");saved=values;}];Pump(^BOOL{return saved!=nil;});Require(saved.count==1 && [((FYRequestIdentity *)saved[0]).sourceText isEqualToString:source],@"saved sentence survives reopen");
    AppDelegate *app=App(store,analyzer,catalog);app.learningSourceTextView.editable=NO;[app refreshSavedSentences];Pump(^BOOL{return app.savedSentences.count==1;});
    NSButton *open=[NSButton new];open.identifier=[NSString stringWithFormat:@"%@:%ld",identity.sentenceID,(long)identity.version];
    [app openSavedSentence:open];Pump(^BOOL{return app.currentAnalysis!=nil;});
    Require([app.learningCoordinator.currentSentenceID isEqualToString:identity.sentenceID] && app.learningCoordinator.isPinned && [app.learningSourceTextView.string isEqualToString:source],@"saved sentence entry returns to exact source and auto analyzes");
    [app.mainWindow orderOut:nil];
    done=NO;[store preserveSentenceForHistory:nil completion:^(NSError *error){done=YES;}];Pump(^BOOL{return done;});
    [store setValue:@1 forKey:@"historyRetentionLimit"];[coordinator recordText:@"新句です。" kind:FYSentenceKindDialogue];Drain(store);
    __block BOOL fetched=NO;[store fetchSentence:identity.sentenceID completion:^(FYSentenceRecord *record,NSError *error){Require(record!=nil,@"sentence bookmark protects source from history pruning");fetched=YES;}];Pump(^BOOL{return fetched;});
    done=NO;[store toggleSentenceBookmark:identity completion:^(BOOL saved,NSError *error){Require(!saved && !error,@"sentence bookmark cancelled");done=YES;}];Pump(^BOOL{return done;});
    [coordinator recordText:@"さらに新句です。" kind:FYSentenceKindDialogue];Drain(store);
    fetched=NO;[store fetchSentence:identity.sentenceID completion:^(FYSentenceRecord *record,NSError *error){Require(record==nil,@"cancelled bookmark no longer prevents pruning");fetched=YES;}];Pump(^BOOL{return fetched;});
    NSLog(@"PASS: structure validation, cache persistence, saved sentence reopen, retention and cancellation");
}return 0;}
