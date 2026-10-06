#import <Foundation/Foundation.h>
#include <unistd.h>
#import "FYLearningModels.h"
#import "FYLearningStore.h"
#import "FYLearningAnalyzer.h"
#import "FYJapaneseTokenizer.h"
#import "FYGrammarCatalog.h"
#import "FYLearningCoordinator.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static void PumpUntil(BOOL (^finished)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished() && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
}

static NSHTTPURLResponse *OKResponse(void) {
    return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com/v1"]
                                       statusCode:200
                                      HTTPVersion:@"HTTP/1.1"
                                     headerFields:@{}];
}

static FYLearningAnalyzer *MockAnalyzerWithJSON(NSString *json) {
    FYLearningAnalyzer *analyzer = [[FYLearningAnalyzer alloc] init];
    analyzer.baseURL = @"https://example.com/v1";
    analyzer.apiKey = @"test-key-not-real";
    analyzer.model = @"deepseek-v4-pro";
    NSDictionary *envelope = @{
        @"choices": @[@{@"message": @{@"content": json}, @"finish_reason": @"stop"}]
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:NULL];
    analyzer.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) {
        done(data, OKResponse(), nil);
    };
    return analyzer;
}

static FYGrammarCatalog *LoadCatalog(void) {
    NSURL *url = [NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"];
    FYGrammarCatalog *catalog = [[FYGrammarCatalog alloc] initWithURL:url];
    [catalog loadWithError:NULL];
    return catalog;
}

int main(void) {
    @autoreleasepool {
        // 1. SQLite 关闭重开、版本追加、译文回填
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                              [NSString stringWithFormat:@"fuyi-learning-test-%@.sqlite3", NSUUID.UUID.UUIDString]];
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];

        FYLearningStore *store = [[FYLearningStore alloc] initWithDatabasePath:tempPath];
        store.completionQueue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);

        __block NSError *err = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [store openWithCompletion:^(NSError *e) { err = e; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(err == nil, @"store should open");

        [store ensureSessionWithID:@"sess" displayName:@"" language:@"日文" completion:^(NSError *e) { dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

        __block NSInteger appendedVersion = 0;
        [store insertSentenceWithID:@"s1" sessionID:@"sess" kind:FYSentenceKindDialogue originalText:@"こんにちは" occurredAt:[NSDate date] completion:^(NSError *e) { dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        [store updateTranslation:@"你好" forSentence:@"s1" version:1 completion:^(NSError *e) { dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        __block FYSentenceRecord *beforeAppend = nil;
        [store fetchSentence:@"s1" completion:^(FYSentenceRecord *r, NSError *e) { beforeAppend = r; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(beforeAppend.latestVersion == 1, @"latest version should be 1 before append");
        Check([beforeAppend.latestTranslation isEqualToString:@"你好"], @"translation should be saved");
        [store appendVersionForSentence:@"s1" text:@"こんにちは。" translation:nil completion:^(NSInteger v, NSError *e) { appendedVersion = v; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(appendedVersion == 2, @"append version should be 2");

        [store closeWithCompletion:^(NSError *e) { dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

        FYLearningStore *reopened = [[FYLearningStore alloc] initWithDatabasePath:tempPath];
        reopened.completionQueue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
        [reopened openWithCompletion:^(NSError *e) { dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

        __block FYSentenceRecord *record = nil;
        [reopened fetchSentence:@"s1" completion:^(FYSentenceRecord *r, NSError *e) { record = r; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(record != nil, @"sentence should persist across reopen");
        Check(record.latestVersion == 2, @"latest version should persist");
        __block NSArray<FYSentenceVersion *> *versions = nil;
        [reopened fetchVersionsForSentence:@"s1" completion:^(NSArray<FYSentenceVersion *> *v, NSError *e) { versions = v; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(versions.count == 2, @"both versions should persist");
        Check([versions[0].translation isEqualToString:@"你好"], @"version 1 translation should persist");

        // 2. coordinator 连续画面去重 + 固定句子
        FYLearningAnalyzer *analyzer = [[FYLearningAnalyzer alloc] init];
        FYJapaneseTokenizer *tokenizer = [[FYJapaneseTokenizer alloc] init];
        [tokenizer setCompletionQueue:dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)];
        FYGrammarCatalog *catalog = LoadCatalog();
        FYLearningCoordinator *coordinator = [[FYLearningCoordinator alloc] initWithStore:reopened
                                                                                 analyzer:analyzer
                                                                                tokenizer:tokenizer
                                                                                  catalog:catalog];
        coordinator.learningEnabled = YES;
        coordinator.japaneseMode = YES;
        FYRequestIdentity *a1 = [coordinator recordText:@"進まざるを得ない" kind:FYSentenceKindDialogue];
        FYRequestIdentity *a2 = [coordinator recordText:@"進まざるを得ない" kind:FYSentenceKindDialogue];
        Check([a1.sentenceID isEqualToString:a2.sentenceID], @"adjacent duplicate should reuse the same sentence");
        Check([coordinator.currentSentenceID isEqualToString:a1.sentenceID], @"follow-latest should track the new sentence");
        [coordinator pinCurrent];
        NSString *pinnedID = coordinator.currentSentenceID;
        [coordinator recordText:@"別の文" kind:FYSentenceKindDialogue];
        Check([coordinator.currentSentenceID isEqualToString:pinnedID], @"pin should keep current sentence");
        Check(coordinator.hasNewerSentence, @"pin should report a newer sentence");

        // 2b. OCR 修正：追加版本，旧版本不覆盖
        __block BOOL correctedDone = NO;
        [coordinator correctCurrentSentenceText:@"進まざるを得ない（修正）" completion:^(NSError *e) { correctedDone = YES; }];
        PumpUntil(^BOOL { return correctedDone; });
        Check(coordinator.currentVersion == 2, @"correct should bump version to 2");
        Check([coordinator.currentSourceText isEqualToString:@"進まざるを得ない（修正）"], @"correct should update source text");

        // 3. 逐条配对
        NSArray<FYRequestIdentity *> *items = [coordinator recordItems:@[@"戻る", @"詳細"] kind:FYSentenceKindOption];
        Check(items.count == 2, @"should record two item identities");
        Check(![items[0].sentenceID isEqualToString:items[1].sentenceID], @"each item should have its own sentence");
        [coordinator setTranslation:@"返回" forIdentity:items[0]];
        [coordinator setTranslation:@"详情" forIdentity:items[1]];

        // 4. 词条去重：相同原形+读音为重复，不同读音分开
        FYVocabularyEntry *v1 = [[FYVocabularyEntry alloc] init];
        v1.surface = @"進ま"; v1.lemma = @"進む"; v1.reading = @"すすむ"; v1.meaning = @"前进";
        __block BOOL wasDup = NO;
        [coordinator bookmarkVocabulary:v1 selectedText:@"進ま" completion:^(FYVocabularyEntry *s, BOOL dup, NSError *e) { wasDup = dup; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(!wasDup, @"first bookmark should not be duplicate");
        [coordinator bookmarkVocabulary:v1 selectedText:@"進ま" completion:^(FYVocabularyEntry *s, BOOL dup, NSError *e) { wasDup = dup; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(wasDup, @"same lemma+reading should be duplicate");

        // 5. 分析器解析与校验
        NSString *goodJSON = @"{\"schema_version\":1,\"grammar\":[{\"catalog_id\":\"zaru_wo_enai\",\"name\":\"〜ざるを得ない\",\"matched_text\":\"進まざるを得ない\",\"occurrence\":0,\"connection\":\"ない形\",\"meaning_zh\":\"不得不\",\"explanation_zh\":\"没有选择\"}],\"vocabulary\":[{\"surface\":\"進ま\",\"lemma\":\"進む\",\"reading\":\"すすむ\",\"meaning_zh\":\"前进\"}],\"sentence_note_zh\":\"不得不前进\"}";
        FYLearningAnalyzer *goodAnalyzer = MockAnalyzerWithJSON(goodJSON);
        goodAnalyzer.catalog = LoadCatalog();
        __block FYAnalysisResult *goodResult = nil;
        [goodAnalyzer analyzeSentence:@"仲間のために進まざるを得ない。" translation:@"为了同伴不得不前进。" completion:^(FYAnalysisResult *r, NSError *e) {
            goodResult = r; (void)e;
        }];
        PumpUntil(^BOOL { return goodResult != nil; });
        Check(goodResult.status == FYAnalysisStatusSuccess, @"analysis should succeed");
        Check(goodResult.grammar.count == 1, @"should parse one grammar");
        Check([goodResult.grammar[0].referenceLevel isEqualToString:@"N2"], @"catalog should supply N2 level");
        Check(goodResult.grammar[0].matchedRange.location != NSNotFound, @"matched text should be located");
        Check(!goodResult.grammar[0].levelVerified, @"catalog level should be pending (not verified)");

        NSString *badSubstrJSON = @"{\"schema_version\":1,\"grammar\":[{\"name\":\"〜ざるを得ない\",\"matched_text\":\"不存在\",\"occurrence\":0}],\"vocabulary\":[],\"sentence_note_zh\":null}";
        FYLearningAnalyzer *badSubstr = MockAnalyzerWithJSON(badSubstrJSON);
        badSubstr.catalog = LoadCatalog();
        __block FYAnalysisResult *badResult = nil;
        __block NSError *badSubstringError = nil;
        [badSubstr analyzeSentence:@"仲間のために進まざるを得ない。" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { badResult = r; badSubstringError = e; }];
        PumpUntil(^BOOL { return badSubstringError != nil; });
        Check(badResult == nil && badSubstringError != nil, @"invented grammar substring must fail and must not be highlighted or cached");

        NSString *unknownCatalogJSON = @"{\"schema_version\":1,\"grammar\":[{\"catalog_id\":\"does_not_exist\",\"name\":\"X\",\"matched_text\":\"仲間\",\"occurrence\":0}],\"vocabulary\":[],\"sentence_note_zh\":null}";
        FYLearningAnalyzer *unknownCatalog = MockAnalyzerWithJSON(unknownCatalogJSON);
        unknownCatalog.catalog = LoadCatalog();
        __block FYAnalysisResult *unknownResult = nil;
        [unknownCatalog analyzeSentence:@"仲間" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { unknownResult = r; (void)e; }];
        PumpUntil(^BOOL { return unknownResult != nil; });
        Check(unknownResult.grammar[0].referenceLevel == nil, @"unknown catalog id should not get a level");
        Check(!unknownResult.grammar[0].levelVerified, @"unknown catalog id should not be verified");

        NSString *emptyGrammarJSON = @"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[],\"sentence_note_zh\":null}";
        FYLearningAnalyzer *emptyAnalyzer = MockAnalyzerWithJSON(emptyGrammarJSON);
        emptyAnalyzer.catalog = LoadCatalog();
        __block FYAnalysisResult *emptyResult = nil;
        [emptyAnalyzer analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { emptyResult = r; (void)e; }];
        PumpUntil(^BOOL { return emptyResult != nil; });
        Check(emptyResult.status == FYAnalysisStatusNoResult, @"empty grammar should be no-result, not success");

        // 回归（2026-10-04 线上故障）：模型把活用形写成辞书形时，只丢弃该词条，不得让整句分析失败。
        // 原句只有「高くて」，模型给了 surface「高い」；旧逻辑在这里报 214，用户永远看不到结果。
        NSString *lemmaFormJSON = @"{\"schema_version\":1,\"grammar\":[{\"name\":\"形容词て形连接\",\"matched_text\":\"高くて\",\"occurrence\":0}],\"vocabulary\":[{\"surface\":\"高い\",\"lemma\":\"高い\",\"reading\":\"たかい\",\"meaning_zh\":\"高的\"},{\"surface\":\"人\",\"meaning_zh\":\"人\"}],\"sentence_note_zh\":null}";
        FYLearningAnalyzer *lemmaForm = MockAnalyzerWithJSON(lemmaFormJSON);
        lemmaForm.catalog = LoadCatalog();
        __block FYAnalysisResult *lemmaResult = nil;
        __block NSError *lemmaError = nil;
        [lemmaForm analyzeSentence:@"背が高くてきれいな人" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { lemmaResult = r; lemmaError = e; }];
        PumpUntil(^BOOL { return lemmaResult != nil || lemmaError != nil; });
        Check(lemmaError == nil && lemmaResult != nil, @"dictionary-form vocabulary must not fail the whole analysis");
        Check(lemmaResult.grammar.count == 1, @"grammar must survive a dropped vocabulary entry");
        Check(lemmaResult.vocabulary.count == 1 && [lemmaResult.vocabulary[0].surface isEqualToString:@"人"],
              @"out-of-source surface must be dropped, in-source surface kept");

        // 回归：occurrence 为 JSON null（NSNull）等价于未提供，不得判成字段无效。
        NSString *nullOccurrenceJSON = @"{\"schema_version\":1,\"grammar\":[{\"name\":\"て形\",\"matched_text\":\"高くて\",\"occurrence\":null}],\"vocabulary\":[],\"sentence_note_zh\":null}";
        FYLearningAnalyzer *nullOccurrence = MockAnalyzerWithJSON(nullOccurrenceJSON);
        nullOccurrence.catalog = LoadCatalog();
        __block FYAnalysisResult *nullOccurrenceResult = nil;
        __block NSError *nullOccurrenceError = nil;
        [nullOccurrence analyzeSentence:@"背が高くてきれいな人" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { nullOccurrenceResult = r; nullOccurrenceError = e; }];
        PumpUntil(^BOOL { return nullOccurrenceResult != nil || nullOccurrenceError != nil; });
        Check(nullOccurrenceError == nil && nullOccurrenceResult.grammar.count == 1, @"null occurrence must be treated as absent");

        // Grammar response anchoring: whitespace, unique ordinal and invented fragments.
        FYLearningAnalyzer *anchor0 = MockAnalyzerWithJSON(@"{\"schema_version\": 1, \"grammar\": [{\"name\": \"test\", \"matched_text\": \"来てくれたら\", \"occurrence\": 1}], \"vocabulary\": []}");
        __block FYAnalysisResult *anchorResult0=nil; __block NSError *anchorError0=nil;
        [anchor0 analyzeSentence:@"何でも聞いて？お店に来て\nくれたらサービスしちゃう！" translation:nil completion:^(FYAnalysisResult *r,NSError *e){anchorResult0=r;anchorError0=e;}];
        PumpUntil(^BOOL{return anchorResult0!=nil || anchorError0!=nil;});
        Check(!anchorError0 && anchorResult0.grammar.count==1, @"valid real fragment survives anchoring");
        Check([[@"何でも聞いて？お店に来て\nくれたらサービスしちゃう！" substringWithRange:anchorResult0.grammar[0].matchedRange] isEqualToString:anchorResult0.grammar[0].matchedText], @"highlight uses original source span");
        FYLearningAnalyzer *anchor1 = MockAnalyzerWithJSON(@"{\"schema_version\": 1, \"grammar\": [{\"name\": \"test\", \"matched_text\": \"なら\", \"occurrence\": 3}], \"vocabulary\": []}");
        __block FYAnalysisResult *anchorResult1=nil; __block NSError *anchorError1=nil;
        [anchor1 analyzeSentence:@"雨なら帰る。晴れなら出かける。" translation:nil completion:^(FYAnalysisResult *r,NSError *e){anchorResult1=r;anchorError1=e;}];
        PumpUntil(^BOOL{return anchorResult1!=nil || anchorError1!=nil;});
        Check(anchorError1!=nil && anchorResult1==nil, @"ambiguous ordinal or invented words stay rejected");
        FYLearningAnalyzer *anchor2 = MockAnalyzerWithJSON(@"{\"schema_version\": 1, \"grammar\": [{\"name\": \"test\", \"matched_text\": \"来る\", \"occurrence\": 0}], \"vocabulary\": []}");
        __block FYAnalysisResult *anchorResult2=nil; __block NSError *anchorError2=nil;
        [anchor2 analyzeSentence:@"来ない。" translation:nil completion:^(FYAnalysisResult *r,NSError *e){anchorResult2=r;anchorError2=e;}];
        PumpUntil(^BOOL{return anchorResult2!=nil || anchorError2!=nil;});
        Check(anchorError2!=nil && anchorResult2==nil, @"ambiguous ordinal or invented words stay rejected");
        FYLearningAnalyzer *anchor3 = MockAnalyzerWithJSON(@"{\"schema_version\": 1, \"grammar\": [{\"name\": \"test\", \"matched_text\": \"あったら\", \"occurrence\": 0}, {\"name\": \"invented\", \"matched_text\": \"〜たら\"}], \"vocabulary\": []}");
        __block FYAnalysisResult *anchorResult3=nil; __block NSError *anchorError3=nil;
        [anchor3 analyzeSentence:@"相談あったら何でも聞いて？" translation:nil completion:^(FYAnalysisResult *r,NSError *e){anchorResult3=r;anchorError3=e;}];
        PumpUntil(^BOOL{return anchorResult3!=nil || anchorError3!=nil;});
        Check(!anchorError3 && anchorResult3.grammar.count==1, @"valid real fragment survives anchoring");
        Check([[@"相談あったら何でも聞いて？" substringWithRange:anchorResult3.grammar[0].matchedRange] isEqualToString:anchorResult3.grammar[0].matchedText], @"highlight uses original source span");
        Check([anchorResult3.sentenceNote containsString:@"已省略 1 条"], @"partial grammar omissions are disclosed");

        // 放宽词表不等于放宽类型：非字符串 surface 仍然失败。
        FYLearningAnalyzer *badSurfaceType = MockAnalyzerWithJSON(@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[{\"surface\":123}],\"sentence_note_zh\":null}");
        __block NSError *badSurfaceTypeError = nil;
        [badSurfaceType analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { badSurfaceTypeError = e; (void)r; }];
        PumpUntil(^BOOL { return badSurfaceTypeError != nil; });
        Check(badSurfaceTypeError != nil, @"non-string vocabulary surface must still be rejected");

        FYLearningAnalyzer *malformed = MockAnalyzerWithJSON(@"not json at all");
        malformed.catalog = LoadCatalog();
        __block NSError *malformedError = nil;
        [malformed analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { malformedError = e; (void)r; }];
        PumpUntil(^BOOL { return malformedError != nil; });
        Check(malformedError != nil, @"malformed output should be an error");

        // 截断（content 为空 + finish_reason=length）
        FYLearningAnalyzer *truncated = [[FYLearningAnalyzer alloc] init];
        truncated.baseURL = @"https://example.com/v1";
        truncated.apiKey = @"test-key-not-real";
        truncated.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) {
            NSDictionary *body = @{@"choices": @[@{@"message": @{@"content": @""}, @"finish_reason": @"length"}]};
            done([NSJSONSerialization dataWithJSONObject:body options:0 error:NULL], OKResponse(), nil);
        };
        __block NSError *truncatedError = nil;
        [truncated analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { truncatedError = e; (void)r; }];
        PumpUntil(^BOOL { return truncatedError != nil; });
        Check(truncatedError != nil, @"truncated output should be an error");

        // R05 回归：畸形 HTTP envelope 返回 NSError，不抛 NSException；截断(非空 content + length)也报错
        NSArray *badEnvelopes = @[@[], @{@"choices": @{}}, @{@"choices": @[@{@"message": NSNull.null}]}];
        for (id object in badEnvelopes) {
            FYLearningAnalyzer *bad = [[FYLearningAnalyzer alloc] init];
            bad.baseURL = @"https://example.com/v1"; bad.apiKey = @"test-key-not-real";
            bad.transport = ^(NSURLRequest *req, void (^done)(NSData *, NSURLResponse *, NSError *)) {
                done([NSJSONSerialization dataWithJSONObject:object options:0 error:NULL], OKResponse(), nil);
            };
            __block NSError *badEnvelopeError = nil;
            [bad analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { badEnvelopeError = e; (void)r; }];
            PumpUntil(^BOOL { return badEnvelopeError != nil; });
            Check(badEnvelopeError != nil, @"malformed envelope should return NSError, not throw");
        }
        FYLearningAnalyzer *nonEmptyTruncated = [[FYLearningAnalyzer alloc] init];
        nonEmptyTruncated.baseURL = @"https://example.com/v1"; nonEmptyTruncated.apiKey = @"test-key-not-real";
        nonEmptyTruncated.transport = ^(NSURLRequest *req, void (^done)(NSData *, NSURLResponse *, NSError *)) {
            NSDictionary *body = @{@"choices": @[@{@"message": @{@"content": @"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}"}, @"finish_reason": @"length"}]};
            done([NSJSONSerialization dataWithJSONObject:body options:0 error:NULL], OKResponse(), nil);
        };
        __block NSError *nonEmptyTruncatedError = nil;
        [nonEmptyTruncated analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { nonEmptyTruncatedError = e; (void)r; }];
        PumpUntil(^BOOL { return nonEmptyTruncatedError != nil; });
        Check(nonEmptyTruncatedError != nil, @"truncated (length) response should error even with nonempty content");

        // R11 回归：catalog_id 与 matched_text 不匹配时不得授予等级
        FYLearningAnalyzer *unrelated = MockAnalyzerWithJSON(@"{\"schema_version\":1,\"grammar\":[{\"catalog_id\":\"zaru_wo_enai\",\"name\":\"〜ざるを得ない\",\"matched_text\":\"猫\"}],\"vocabulary\":[]}");
        unrelated.catalog = LoadCatalog();
        __block FYAnalysisResult *unrelatedResult = nil;
        [unrelated analyzeSentence:@"猫がいる。" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { unrelatedResult = r; (void)e; }];
        PumpUntil(^BOOL { return unrelatedResult != nil; });
        Check(unrelatedResult.grammar[0].referenceLevel == nil, @"unrelated matched_text should not get a verified level");
        Check(!unrelatedResult.grammar[0].levelVerified, @"unrelated matched_text should not be verified");

        // 6. 分析器取消：cancelAll 后旧请求应回调取消错误，而非结果（显式结束忙碌状态）。
        __block BOOL cancelledDelivered = NO;
        __block FYAnalysisResult *cancelledResult = nil;
        __block NSError *cancelledError = nil;
        __block void (^capturedDone)(NSData *, NSURLResponse *, NSError *) = nil;
        FYLearningAnalyzer *cancellable = [[FYLearningAnalyzer alloc] init];
        cancellable.baseURL = @"https://example.com/v1";
        cancellable.apiKey = @"test-key-not-real";
        cancellable.transport = ^(NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) {
            capturedDone = done;
        };
        [cancellable analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *r, NSError *e) {
            cancelledDelivered = YES; cancelledResult = r; cancelledError = e;
        }];
        [cancellable cancelAll];
        NSData *jsonData = [@"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
        capturedDone(jsonData, OKResponse(), nil);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        Check(cancelledDelivered && cancelledResult == nil && cancelledError != nil,
              @"cancelled request should deliver a cancellation error, not a result");

        // 7. 分词 UTF-16 边界（含 emoji）
        __block NSArray<NSValue *> *tokenRanges = nil;
        dispatch_semaphore_t tsem = dispatch_semaphore_create(0);
        [tokenizer rangesInText:@"仲間😀を救う" completion:^(NSArray<NSValue *> *ranges) { tokenRanges = ranges; dispatch_semaphore_signal(tsem); }];
        dispatch_semaphore_wait(tsem, DISPATCH_TIME_FOREVER);
        Check(tokenRanges.count > 0, @"tokenizer should return at least one token");
        for (NSValue *value in tokenRanges) {
            NSRange range = value.rangeValue;
            Check(range.location + range.length <= [@"仲間😀を救う" length], @"token range must be within UTF-16 bounds");
        }

        // 8. 逐条去重区分 kind（R14）
        FYLearningCoordinator *itemCoord = [[FYLearningCoordinator alloc] initWithStore:reopened analyzer:analyzer tokenizer:tokenizer catalog:catalog];
        itemCoord.learningEnabled = YES; itemCoord.japaneseMode = YES;
        NSArray *uiIds = [itemCoord recordItems:@[@"戻る"] kind:FYSentenceKindUI];
        NSArray *optIds = [itemCoord recordItems:@[@"戻る"] kind:FYSentenceKindOption];
        Check(![((FYRequestIdentity *)uiIds[0]).sentenceID isEqualToString:((FYRequestIdentity *)optIds[0]).sentenceID],
              @"UI and option with same text should have different identities");

        // 9. 同词不同义项保留为独立词条（R13）
        FYVocabularyEntry *sense1 = [[FYVocabularyEntry alloc] init];
        sense1.surface = @"掛ける"; sense1.lemma = @"掛ける"; sense1.reading = @"かける"; sense1.meaning = @"悬挂";
        __block BOOL sense1Dup = NO;
        [coordinator bookmarkVocabulary:sense1 selectedText:@"掛ける" completion:^(FYVocabularyEntry *s, BOOL dup, NSError *e) { sense1Dup = dup; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(!sense1Dup, @"first sense should not be duplicate");
        FYVocabularyEntry *sense2 = [[FYVocabularyEntry alloc] init];
        sense2.surface = @"掛ける"; sense2.lemma = @"掛ける"; sense2.reading = @"かける"; sense2.meaning = @"打电话";
        __block BOOL sense2Dup = NO;
        [coordinator bookmarkVocabulary:sense2 selectedText:@"掛ける" completion:^(FYVocabularyEntry *s, BOOL dup, NSError *e) { sense2Dup = dup; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(!sense2Dup, @"different sense should not be merged as duplicate");

        // 10. 写库失败应返回错误，不冒充成功（R08）
        NSString *blockedParent = [NSTemporaryDirectory() stringByAppendingPathComponent:@"not-a-directory"];
        Check([@"fixture" writeToFile:blockedParent atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"failure fixture created");
        FYLearningStore *brokenStore = [[FYLearningStore alloc] initWithDatabasePath:[blockedParent stringByAppendingPathComponent:@"review.sqlite3"]];
        brokenStore.completionQueue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
        FYLearningCoordinator *brokenCoord = [[FYLearningCoordinator alloc] initWithStore:brokenStore analyzer:analyzer tokenizer:tokenizer catalog:catalog];
        __block NSError *brokenBookmarkError = nil;
        [brokenCoord bookmarkVocabulary:sense1 selectedText:@"掛ける" completion:^(FYVocabularyEntry *s, BOOL dup, NSError *e) { brokenBookmarkError = e; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(brokenBookmarkError != nil, @"bookmark on a broken store should return an error");

        // 11. 网络结果回主线程（R04）
        FYLearningAnalyzer *backgroundAnalyzer = [[FYLearningAnalyzer alloc] init];
        backgroundAnalyzer.baseURL = @"https://example.com/v1"; backgroundAnalyzer.apiKey = @"test-key-not-real";
        backgroundAnalyzer.transport = ^(NSURLRequest *req, void (^done)(NSData *, NSURLResponse *, NSError *)) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                NSDictionary *body = @{@"choices": @[@{@"message": @{@"content": @"{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}"}, @"finish_reason": @"stop"}]};
                done([NSJSONSerialization dataWithJSONObject:body options:0 error:NULL], OKResponse(), nil);
            });
        };
        __block BOOL deliveredOnMain = NO;
        [backgroundAnalyzer analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { deliveredOnMain = NSThread.isMainThread; (void)r; (void)e; }];
        PumpUntil(^BOOL { return deliveredOnMain; });
        Check(deliveredOnMain, @"analyzer completion should be delivered on main thread");

        // 12. 分析缓存往返保留命中范围（R15）
        FYGrammarItem *cacheGrammar = [[FYGrammarItem alloc] init];
        cacheGrammar.name = @"test"; cacheGrammar.matchedText = @"OCR"; cacheGrammar.matchedRange = NSMakeRange(2, 3);
        FYAnalysisResult *cacheAnalysis = [[FYAnalysisResult alloc] init];
        cacheAnalysis.grammar = @[cacheGrammar]; cacheAnalysis.vocabulary = @[]; cacheAnalysis.status = FYAnalysisStatusSuccess;
        __block BOOL cacheSaved = NO;
        [reopened saveAnalysisResult:cacheAnalysis sentenceID:coordinator.currentSentenceID version:coordinator.currentVersion textHash:@"h" promptVersion:1 catalogVersion:1 modelConfig:@"m" completion:^(NSError *e) { cacheSaved = YES; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(cacheSaved, @"cache save should complete");
        __block FYAnalysisResult *cacheLoaded = nil;
        [reopened fetchAnalysisForSentence:coordinator.currentSentenceID version:coordinator.currentVersion completion:^(FYAnalysisResult *r, NSString *m, NSError *e) { cacheLoaded = r; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(cacheLoaded.grammar[0].matchedRange.location == 2, @"cached analysis should preserve matched range");

        // 13. Q06 回归：已有词条的空字段被补全后合并持久化
        FYVocabularyEntry *pending = [[FYVocabularyEntry alloc] init];
        pending.surface = @"救う"; pending.lemma = @"救う"; pending.reading = @"すくう";
        __block BOOL pendingDup = NO;
        [coordinator bookmarkVocabulary:pending selectedText:@"救う" completion:^(FYVocabularyEntry *s, BOOL dup, NSError *e) { pendingDup = dup; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(!pendingDup, @"first pending bookmark should not be duplicate");
        FYVocabularyEntry *completed = [[FYVocabularyEntry alloc] init];
        completed.surface = @"救う"; completed.lemma = @"救う"; completed.reading = @"すくう"; completed.meaning = @"拯救";
        __block FYVocabularyEntry *merged = nil; __block BOOL mergedDup = NO;
        [coordinator bookmarkVocabulary:completed selectedText:@"救う" completion:^(FYVocabularyEntry *s, BOOL dup, NSError *e) { merged = s; mergedDup = dup; dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        Check(mergedDup && [merged.meaning isEqualToString:@"拯救"], @"re-bookmarking with meaning should merge into existing entry");

        // 14. Q08 回归：未知 catalog ID 不得按名称回退授级/带来源
        FYLearningAnalyzer *unknownID = MockAnalyzerWithJSON(@"{\"schema_version\":1,\"grammar\":[{\"catalog_id\":\"not_a_real_catalog_id\",\"name\":\"〜ざるを得ない\",\"matched_text\":\"ざるを得ない\",\"occurrence\":0}],\"vocabulary\":[]}");
        unknownID.catalog = LoadCatalog();
        __block FYAnalysisResult *unknownIDResult = nil;
        [unknownID analyzeSentence:@"進まざるを得ない。" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { unknownIDResult = r; (void)e; }];
        PumpUntil(^BOOL { return unknownIDResult != nil; });
        Check(unknownIDResult.grammar[0].referenceLevel == nil && unknownIDResult.grammar[0].levelSourceURL == nil,
              @"unknown catalog ID must not gain a level or source by name fallback");

        // 15. Q09 回归：code fence 后仍有额外正文应判失败
        FYLearningAnalyzer *fence = MockAnalyzerWithJSON(@"```json\n{\"schema_version\":1,\"grammar\":[],\"vocabulary\":[]}\n```\nextra output");
        __block FYAnalysisResult *fenceResult = nil; __block NSError *fenceError = nil;
        [fence analyzeSentence:@"テスト" translation:nil completion:^(FYAnalysisResult *r, NSError *e) { fenceResult = r; fenceError = e; }];
        PumpUntil(^BOOL { return fenceResult != nil || fenceError != nil; });
        Check(fenceResult == nil && fenceError != nil, @"fence with trailing prose must be rejected as an error");

        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];
        NSLog(@"Learning tests passed");
    }
    return 0;
}
