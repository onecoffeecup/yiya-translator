#import <Foundation/Foundation.h>
#import "FYLearningAnalyzer.h"

static void Require(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void Pump(BOOL (^finished)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished() && end.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    }
    Require(finished(), @"async completion timed out");
}
static NSDictionary *Grammar(NSString *name, NSString *span) {
    return @{@"name":name, @"matched_text":span, @"occurrence":@0, @"explanation_zh":@"测试语境说明"};
}
static NSData *Envelope(NSArray *grammar) {
    NSDictionary *root = @{@"schema_version":@1, @"grammar":grammar, @"vocabulary":@[], @"sentence_note_zh":@"原有整句说明"};
    NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:root options:0 error:NULL] encoding:NSUTF8StringEncoding];
    return [NSJSONSerialization dataWithJSONObject:@{@"choices":@[@{@"message":@{@"content":json}, @"finish_reason":@"stop"}]} options:0 error:NULL];
}
static NSHTTPURLResponse *Response(void) {
    return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.invalid/v1/chat/completions"] statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
}
static NSArray *ReadingCues(NSDictionary *payload) {
    NSString *user=payload[@"messages"][1][@"content"];
    NSString *marker=@"词形扫描候选（资料，需要结合原文判断）：";
    NSRange range=[user rangeOfString:marker];
    if(range.location==NSNotFound)return @[];
    NSString *json=[user substringFromIndex:NSMaxRange(range)];
    return [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] ?: @[];
}
static FYLearningAnalyzer *Analyzer(void) {
    FYLearningAnalyzer *a = [FYLearningAnalyzer new];
    a.baseURL=@"https://example.invalid/v1"; a.apiKey=@"dummy-test-key"; a.model=@"test-model";
    return a;
}

int main(void) { @autoreleasepool {
    NSString *source=@"昨日は行かないといけなかった。";
    NSArray *initial=@[Grammar(@"と",@"と"),Grammar(@"〜ないといけない",@"ないといけない")];
    NSArray *corrected=@[Grammar(@"〜ないといけない",@"行かないといけなかった")];
    // Real HTTP parsing and request generation, with all responses mocked.
    FYLearningAnalyzer *a=Analyzer();__block NSUInteger calls=0;
    a.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
        calls++;
        NSDictionary *payload=[NSJSONSerialization JSONObjectWithData:req.HTTPBody options:0 error:NULL];
        NSString *prompt=payload[@"messages"][0][@"content"];
        Require([prompt containsString:@"复合句型"] && [prompt containsString:@"口语缩略"] && [prompt containsString:@"不强凑"],@"coverage prompt describes compound forms without inventing a quota");
        Require([payload[@"max_tokens"] integerValue]>=2800,@"structure and grammar have enough output budget");
        if(calls==2) Require([prompt containsString:@"仅核对"] && [payload[@"messages"][1][@"content"] containsString:@"ないといけない"],@"repair is targeted at rejected spans");
        done(Envelope(calls==1?initial:corrected),Response(),nil);
    };
    __block FYAnalysisResult *result=nil;__block NSError *error=nil;__block BOOL finished=NO;
    [a analyzeSentence:source translation:nil completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
    Pump(^BOOL{return finished;});
    Require(!error && result.grammar.count==2 && calls==2,@"tense-mismatched compound is recovered with one repair");
    Require([result.grammar[0].name isEqual:@"と"] && [result.grammar[1].matchedText isEqual:@"行かないといけなかった"],@"valid original entry and corrected inflection both survive");
    Require([result.sentenceNote isEqual:@"原有整句说明"],@"successful repair does not leave a false omission warning");
    Require(result.grammar[1].referenceLevel==nil,@"uncatalogued compound is retained without invented level");

    // The same path handles contracted forms and OCR newlines without changing
    // the actual selected/highlighted characters.
    FYLearningAnalyzer *contract=Analyzer();__block NSUInteger contractCalls=0;
    contract.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
        contractCalls++;done(Envelope(@[Grammar(@"〜てしまう",contractCalls==1?@"読んでしまった":@"読んじゃった")]),Response(),nil);
    };
    finished=NO;
    [contract analyzeSentence:@"もう読ん\nじゃった。" translation:nil completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
    Pump(^BOOL{return finished;});
    Require(!error && result.grammar.count==1 && [result.grammar[0].matchedText isEqual:@"読ん\nじゃった"] && contractCalls==2,@"all-rejected first pass can recover a real contraction across OCR newline");

    // A valid response takes one request; sparse/simple output is not forced to
    // invent extra grammar. Failed repairs cannot erase already valid entries.
    for(NSInteger scenario=0;scenario<5;scenario++) {
        FYLearningAnalyzer *probe=Analyzer();__block NSUInteger count=0;finished=NO;result=nil;error=nil;
        probe.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
            count++;
            if(scenario==0) {done(Envelope(@[Grammar(@"と",@"と")]),Response(),nil);return;}
            if(count==1) {done(Envelope(initial),Response(),nil);return;}
            if(scenario==1) {done(nil,nil,[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]);return;}
            if(scenario==2) {done(Envelope(@[Grammar(@"〜ないといけない",@"原句没有这段")]),Response(),nil);return;}
            if(scenario==3) {done(Envelope(@[Grammar(@"不相关的语法",@"昨日")]),Response(),nil);return;}
            done([@"not JSON" dataUsingEncoding:NSUTF8StringEncoding],Response(),nil);
        };
        [probe analyzeSentence:source translation:nil completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
        Pump(^BOOL{return finished;});
        Require(!error && result.grammar.count==1 && [result.grammar[0].name isEqual:@"と"],@"valid grammar survives sparse result, failed, invalid or unrelated repair");
        Require(count==(scenario==0?1:2),@"at most one repair, no retry loop");
        if(scenario) Require([result.sentenceNote containsString:@"已省略 1 条"],@"remaining omissions are disclosed");
    }

    FYLearningAnalyzer *cancel=Analyzer();__block NSUInteger cancelCalls=0,completions=0;
    __block void (^pending)(NSData *,NSURLResponse *,NSError *)=nil;
    cancel.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
        cancelCalls++;if(cancelCalls==1)done(Envelope(initial),Response(),nil);else pending=[done copy];
    };
    [cancel analyzeSentence:source translation:nil completion:^(FYAnalysisResult *r,NSError *e){completions++;result=r;error=e;}];
    Pump(^BOOL{return pending!=nil;});[cancel cancelAll];
    Require(completions==1 && !result && error.code==499,@"cancelling repair cannot surface the stale partial success");
    pending(Envelope(corrected),Response(),nil);
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.03]];
    Require(completions==1,@"late repaired response completes only once");

    // Paragraph layout must not truncate a compound at an OCR line break.
    FYGrammarCatalog *catalog=[[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
    Require([catalog loadWithError:NULL] && catalog.catalogVersion==3,@"updated level catalog loads");
    FYLearningAnalyzer *paragraph=Analyzer();paragraph.catalog=catalog;
    NSString *shop=@"着やすくカジュアルな服がメインだからおすすめ。シーズンによって\nは水着や浴衣等もあって便利ですよ。";
    __block NSUInteger paragraphCalls=0;finished=NO;
    paragraph.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
        paragraphCalls++;
        NSDictionary *payload=[NSJSONSerialization JSONObjectWithData:req.HTTPBody options:0 error:NULL];
        NSArray *forms=[ReadingCues(payload) valueForKey:@"observed_form"];
        for(NSString *form in @[@"やすく",@"によっては",@"だから",@"もあって",@"や浴衣等"]) {
            Require([forms containsObject:form],@"paragraph cues cover inflection, full cross-line compound and connections");
        }
        done(Envelope(@[Grammar(@"〜やすい",@"着やすく"),Grammar(@"〜によっては",@"によっては"),Grammar(@"〜もあって",@"もあって"),Grammar(@"〜から（原因）",@"だから"),Grammar(@"列举",@"や浴衣等")]),Response(),nil);
    };
    [paragraph analyzeSentence:shop translation:nil completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
    Pump(^BOOL{return finished;});
    Require(!error && paragraphCalls==1 && result.grammar.count==5,@"fully covered paragraph needs no extra review request");
    Require([result.grammar[0].referenceLevel isEqual:@"N4"] && result.grammar[0].levelVerified,@"inflected yasui retains checked reference level");
    Require([result.grammar[1].matchedText isEqual:@"によって\nは"] && [result.grammar[1].referenceLevel isEqual:@"N3"] && result.grammar[1].levelVerified,@"OCR newline preserves source and compound reference level");
    Require(result.grammar[2].referenceLevel==nil,@"ordinary additive existence connection is not given an advanced level");

    NSString *person=@"強面で近寄り難い雰囲気だ\nけど、中身は普通の男\n子。遊びに誘うなら、男の\n子が好む場所がよさそう。でも煩いのは苦手みたい。";
    // Surface cues are hints; sparse/empty/repeated findings never launch a review automatically.
    for (NSString *text in @[person, @"普通のはなし。", @"誘うなら予定を聞く。出かけるなら天気を確認する。", @"映画を見たい。でも人混みは苦手みたい。"] ) {
        FYLearningAnalyzer *fast=Analyzer();fast.catalog=catalog;finished=NO;__block NSUInteger count=0;
        fast.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
            count++; done(Envelope([text containsString:@"よさそう"] ? @[Grammar(@"〜そうだ（様態）",@"よさそう")] : @[]),Response(),nil);
        };
        [fast analyzeSentence:text translation:nil completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
        Pump(^BOOL{return finished;});
        Require(!error && count==1,@"sparse/empty results and repeated candidates use exactly one fast request");
        Require(![result.sentenceNote containsString:@"已省略"],@"unconfirmed candidates are never reported as rejected findings");
    }

    FYLearningAnalyzer *reviewer=Analyzer();reviewer.catalog=catalog;finished=NO;__block NSUInteger reviewCalls=0;
    FYAnalysisResult *first=[FYAnalysisResult new];first.schemaVersion=1;first.sentenceNote=@"已有说明";
    FYGrammarItem *known=[FYGrammarItem new];known.name=@"〜なら";known.matchedText=@"誘うなら";known.matchedRange=[person rangeOfString:known.matchedText];first.grammar=@[known];
    reviewer.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
        reviewCalls++;NSDictionary *payload=[NSJSONSerialization JSONObjectWithData:req.HTTPBody options:0 error:NULL];
        Require([payload[@"messages"][0][@"content"] containsString:@"用户主动深度复核"] && [payload[@"messages"][1][@"content"] containsString:@"已有语法"],@"manual review includes explicit scope and existing findings");
        done(Envelope(@[Grammar(@"〜なら",@"誘うなら"),Grammar(@"〜がたい",@"近寄り難い"),Grammar(@"连体修饰",@"男の子が好む場所")]),Response(),nil);
    };
    [reviewer reviewSentence:person translation:nil existingResult:first completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
    Pump(^BOOL{return finished;});
    Require(!error && reviewCalls==1 && result.grammar.count==3 && result.grammar[0]==known,@"manual review merges verified findings without duplicating or replacing initial objects");
    Require([result.grammar[1].referenceLevel isEqual:@"N2"] && [result.sentenceNote isEqual:@"已有说明"],@"review still validates levels and preserves initial explanation");
    for (NSInteger scenario=0;scenario<3;scenario++) {
        finished=NO;reviewCalls=0;
        reviewer.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
            reviewCalls++;if(scenario==1){done(nil,nil,[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]);return;}
            done(Envelope(scenario==2?@[Grammar(@"〜がたい",@"原文中没有")]:@[]),Response(),nil);
        };
        [reviewer reviewSentence:person translation:nil existingResult:first completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
        Pump(^BOOL{return finished;});
        Require(reviewCalls==1 && first.grammar.count==1,@"manual review does not recursively repair or mutate the original");
        Require(scenario==0?(!error && result.grammar[0]==known):error!=nil,@"empty manual review preserves findings; network/invalid span fails for UI fallback");
    }

    finished=NO;reviewCalls=0;
    reviewer.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
        reviewCalls++; NSDictionary *payload=[NSJSONSerialization JSONObjectWithData:req.HTTPBody options:0 error:NULL];
        Require([payload[@"max_tokens"] integerValue]==650 && [payload[@"messages"][1][@"content"] containsString:@"誘うなら"],@"expanded explanation has bounded output and a selected source anchor");
        NSString *answer=@"接续与用法。例句及中文译文。";
        done([NSJSONSerialization dataWithJSONObject:@{@"choices":@[@{@"message":@{@"content":answer},@"finish_reason":@"stop"}]} options:0 error:NULL],Response(),nil);
    };
    [reviewer expandedExplanationForGrammar:known sentenceText:person translation:nil completion:^(NSString *answer,NSError *e){error=e;finished=YES;}];
    Pump(^BOOL{return finished;});Require(!error && reviewCalls==1,@"expanded explanation uses one targeted request");
    finished=NO;
    [reviewer expandedExplanationForGrammar:known sentenceText:@"别的句子" translation:nil completion:^(NSString *answer,NSError *e){error=e;finished=YES;}];
    Require(finished && error.code==217 && reviewCalls==1,@"stale grammar cannot request an explanation for a different sentence");

    // Cues are not results: lexically similar words may be rejected by the
    // contextual analysis. Advanced catalog forms are considered too.
    for(NSString *text in @[@"やすい店だ。",@"この仕事は断りかねるが、失敗は避けるべく準備する。"]){
        FYLearningAnalyzer *context=Analyzer();context.catalog=catalog;finished=NO;
        __block NSUInteger contextCalls=0;
        context.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
            contextCalls++;
            if(contextCalls==1 && [text containsString:@"かねる"]){
                NSDictionary *payload=[NSJSONSerialization JSONObjectWithData:req.HTTPBody options:0 error:NULL];
                NSArray *forms=[ReadingCues(payload) valueForKey:@"observed_form"];
                Require([forms containsObject:@"かねる"] && [forms containsObject:@"べく"],@"reading cues do not restrict analysis to beginner forms");
            }
            done(Envelope(@[]),Response(),nil);
        };
        [context analyzeSentence:text translation:nil completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
        Pump(^BOOL{return finished;});
        Require(!error && result.grammar.count==0,@"reading cues never force unconfirmed grammar into results");
    }
    // These first-pass mistakes must be rejected by the program, even if the
    // model confidently claims the marker and supplies a real source substring.
    for (NSDictionary *fixture in @[
        @{@"source":@"苦手みたい。",@"grammar":@[Grammar(@"〜たい",@"たい")],@"expected":@0},
        @{@"source":@"冷たい水。",@"grammar":@[Grammar(@"〜たい",@"冷たい")],@"expected":@0},
        @{@"source":@"おな\nらが出た。",@"grammar":@[Grammar(@"〜なら",@"なら")],@"expected":@0},
        @{@"source":@"映画を見たい。でも苦手みたい。",@"grammar":@[Grammar(@"〜たい",@"見たい"),Grammar(@"〜たい",@"苦手みたい")],@"expected":@1},
        @{@"source":@"本を読みたい。",@"grammar":@[Grammar(@"〜たい",@"読みたい")],@"expected":@1},
        @{@"source":@"おならをしたなら謝る。",@"grammar":@[Grammar(@"〜なら",@"おなら"),Grammar(@"〜なら",@"したなら")],@"expected":@1}
    ]) {
        FYLearningAnalyzer *checked=Analyzer();checked.catalog=catalog;finished=NO;__block NSUInteger count=0;
        checked.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
            count++;done(Envelope(count==1?fixture[@"grammar"]:@[]),Response(),nil);
        };
        [checked analyzeSentence:fixture[@"source"] translation:nil completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
        Pump(^BOOL{return finished;});
        Require(!error && result.grammar.count==[fixture[@"expected"] unsignedIntegerValue] && count<=2,@"lexical containment rejected without losing a separate genuine marker");
    }
    FYLearningAnalyzer *duplicates=Analyzer();duplicates.catalog=catalog;finished=NO;
    duplicates.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
        done(Envelope(@[Grammar(@"〜たい",@"見たい"),Grammar(@"〜たい",@"見たい")]),Response(),nil);
    };
    [duplicates analyzeSentence:@"見たい。" translation:nil completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
    Pump(^BOOL{return finished;});Require(!error && result.grammar.count==1,@"identical finding at the same source range is not duplicated");

    for (NSString *model in @[@"deepseek-flash",@"deepseek-v4-pro",@"deepseek-v4-flash",@"deepseek-unknown",@"test-model"]) {
        FYLearningAnalyzer *quality=Analyzer();quality.model=model;finished=NO;
        BOOL supported=[@[@"deepseek-flash",@"deepseek-v4-pro",@"deepseek-v4-flash"] containsObject:model];
        quality.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
            NSDictionary *payload=[NSJSONSerialization JSONObjectWithData:req.HTTPBody options:0 error:NULL];
            if(supported) {
                Require([payload[@"thinking"][@"type"] isEqual:@"disabled"] && [payload[@"reasoning_effort"] isEqual:@"none"],@"default grammar analysis disables hidden reasoning");
                Require([payload[@"max_tokens"] integerValue]<=4200 && req.timeoutInterval==30,@"fast analysis has a bounded output budget and deadline");
                Require([payload[@"response_format"][@"type"] isEqual:@"json_object"],@"supported grammar model requests structured JSON");
            } else {
                Require(!payload[@"response_format"] && req.timeoutInterval==30,@"unknown services retain compatible request shape");
            }
            NSString *user=payload[@"messages"][1][@"content"];
            Require([user containsString:@"逐句核对单元"] && [user containsString:@"男\\n子"],@"sentence checking preserves OCR line layout inside a unit");
            done(Envelope(@[]),Response(),nil);
        };
        [quality analyzeSentence:@"普通的男\n子。うん。" translation:nil completion:^(FYAnalysisResult *r,NSError *e){result=r;error=e;finished=YES;}];
        Pump(^BOOL{return finished;});Require(!error,@"quality request parses final JSON normally");
        if(supported) {
            finished=NO;
            quality.transport=^(NSURLRequest *req,void (^done)(NSData *,NSURLResponse *,NSError *)) {
                NSDictionary *payload=[NSJSONSerialization JSONObjectWithData:req.HTTPBody options:0 error:NULL];
                Require([payload[@"thinking"][@"type"] isEqual:@"disabled"] && [payload[@"reasoning_effort"] isEqual:@"none"] && !payload[@"response_format"] && req.timeoutInterval==30,@"ordinary learning chat retains its existing request policy");
                done([NSJSONSerialization dataWithJSONObject:@{@"choices":@[@{@"message":@{@"content":@"好的"},@"finish_reason":@"stop"}]} options:0 error:NULL],Response(),nil);
            };
            [quality answerConversation:@[@{@"role":@"user",@"content":@"你好"}] completion:^(NSString *answer,NSError *e){error=e;finished=YES;}];
            Pump(^BOOL{return finished;});Require(!error,@"non-grammar chat request still completes");
        }
    }
    NSLog(@"PASS: compound/contracted grammar, source highlighting, repair bounds, fallback and cancellation");
} return 0; }
