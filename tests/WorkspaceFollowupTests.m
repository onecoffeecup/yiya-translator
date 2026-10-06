#import "LearningAppTestSupport.h"
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    FYLearningStore *store = Store([directory stringByAppendingPathComponent:@"workspace.sqlite3"]);
    FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
    Require([catalog loadWithError:NULL], @"catalog missing");
    AppDelegate *app = App(store, Analyzer(catalog), catalog);
    FYRequestIdentity *identity = [app.learningCoordinator recordText:@"雨が降っても行きます。" kind:FYSentenceKindDialogue];
    [app refreshLearningSource];
    FYGrammarItem *item = [FYGrammarItem new]; item.name = @"〜ても"; item.matchedText = @"ても"; item.matchedRange = [identity.sourceText rangeOfString:@"ても"];
    FYAnalysisResult *analysis = [FYAnalysisResult new]; analysis.status = FYAnalysisStatusSuccess; analysis.sentenceID = identity.sentenceID; analysis.version = identity.version; analysis.grammar = @[item];
    app.currentAnalysis = analysis; [app refreshGrammarResults];
    NSMutableArray *callbacks = [NSMutableArray array]; __block NSDictionary *body;
    app.learningAnalyzer.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) {
        body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL]; [callbacks addObject:[done copy]];
    };
    app.grammarQuestionField.stringValue = @"说话人是什么语气？";
    [app askGrammarQuestion:nil];
    Require(callbacks.count == 1 && [body[@"messages"][1][@"content"] containsString:identity.sourceText] && [body[@"messages"][1][@"content"] containsString:@"说话人是什么语气"], @"question must include the selected original sentence, grammar and question");
    void (^done)(NSData *, NSURLResponse *, NSError *) = callbacks[0]; done(Envelope(@"这句表达坚定的态度。"), Response(), nil);
    Pump(^BOOL { return [app.grammarFollowupResultLabel.stringValue containsString:@"坚定"]; });
    [app askGrammarTone:nil]; Require(callbacks.count == 2, @"tone shortcut must issue an independent learning request");
    done = callbacks[1]; [app clearAnalysisDisplay];
    done(Envelope(@"过期回答"), Response(), nil); Tick();
    Require(app.grammarFollowupResultLabel.stringValue.length == 0, @"a late answer must not reappear after source or analysis changes");
    __block BOOL closed = NO; [store closeWithCompletion:^(NSError *error) { Require(!error, @"close failed"); closed = YES; }]; Pump(^BOOL { return closed; });
    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
    NSLog(@"PASS: integrated question/tone actions, request context, reply display and stale reply rejection; no real API or user data.");
} return 0; }
