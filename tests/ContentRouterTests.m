#import <Foundation/Foundation.h>
#import "FYContentRouter.h"
#import "FYOCRManager.h"
#import "learning/FYLearningModels.h"

static NSUInteger Checks;
static void Check(BOOL value, NSString *message) {
    Checks++;
    if (!value) { NSLog(@"FAIL ContentRouterTests: %@", message); exit(1); }
}
static OCRTextItem *Item(NSString *text, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    OCRTextItem *item = [OCRTextItem new];
    item.text = text;
    item.boundingBox = CGRectMake(x, y, w, h);
    return item;
}
static FYContentTextFilterReason Filter(NSString *text, CGRect box, BOOL strict) {
    return [FYContentRouter filterReasonForText:text normalized:FYNormalizeOCRTextForComparison(text)
                                  boundingBox:box strict:strict];
}

int main(void) {
    @autoreleasepool {
        OCRTextItem *body = Item(@"今日は図書館で待っています。", .20, .15, .38, .045);
        OCRTextItem *name = Item(@"青木", .20, .21, .06, .04);
        OCRTextItem *option = Item(@"先に行く", .20, .65, .18, .04);
        OCRTextItem *sign = Item(@"図書館入口", .03, .75, .10, .035);
        NSArray *mixed = @[option, name, body, sign];
        FYContentModeDecision *decision = [FYContentRouter modeDecisionForItems:mixed fallback:1];
        Check(decision.mode == 0 && [decision.reason isEqual:@"dialogue_band"],
              @"a supported mixed frame retains dialogue classification");
        FYContentRoute *route = [FYContentRouter dialogueRouteForItems:mixed
                                            optionsCanPasteInline:YES filterObserver:nil];
        Check([route.dialogueItems isEqual:@[name, body]] && [route.optionItems isEqual:@[option]],
              @"one result carries dialogue and distant aligned option, excluding the sign");
        Check([route.dialogueText isEqual:@"青木\n今日は図書館で待っています。"] &&
              !route.speakerLabelOnly && !route.usedFullFrameFallback &&
              [route.reason isEqual:@"dialogue_with_options"], @"mixed extraction preserves complete dialogue");
        Check([body.text isEqual:@"今日は図書館で待っています。"] &&
              CGRectEqualToRect(body.boundingBox, CGRectMake(.20,.15,.38,.045)),
              @"routing does not rewrite source text or geometry");
        route = [FYContentRouter dialogueRouteForItems:mixed optionsCanPasteInline:NO filterObserver:nil];
        Check(route.optionItems.count == 0 && [route.dialogueItems isEqual:@[name,body]] &&
              [route.reason isEqual:@"options_mapping_unavailable"],
              @"unavailable capture mapping preserves band-only dialogue and disables separate options");

        route = [FYContentRouter dialogueRouteForItems:@[sign] optionsCanPasteInline:YES filterObserver:nil];
        Check(route.usedFullFrameFallback && route.dialogueItems.count == 0 &&
              [route.dialogueText isEqual:sign.text] && route.speakerLabelOnly,
              @"empty band preserves the existing full-frame text and speaker-only learning guard");
        route = [FYContentRouter dialogueRouteForItems:@[] optionsCanPasteInline:YES filterObserver:nil];
        Check(route.dialogueText.length == 0 && route.optionItems.count == 0 && route.usedFullFrameFallback,
              @"empty route produces no translatable text");

        // OCR may split a quoted word horizontally from its spoken continuation.
        OCRTextItem *quotedWord = Item(@"友”",.314,.123,.034,.048);
        OCRTextItem *continuation = Item(@"って呼ばないで。",.354,.117,.183,.050);
        for (NSNumber *mapping in @[@NO,@YES]) {
            route = [FYContentRouter dialogueRouteForItems:@[continuation,quotedWord]
                optionsCanPasteInline:mapping.boolValue filterObserver:nil];
            Check([route.dialogueItems isEqual:@[quotedWord,continuation]] &&
                  [route.dialogueText isEqual:@"友”って呼ばないで。"] && route.optionItems.count == 0,
                  @"same-row quoted word survives narrow width and disjoint horizontal boxes in both inputs");
        }
        Check([quotedWord.text isEqual:@"友”"] && CGRectEqualToRect(quotedWord.boundingBox,CGRectMake(.314,.123,.034,.048)),
              @"recovering a row does not mutate its original observations");
        OCRTextItem *alignedOption = Item(@"先に行く",.354,.65,.18,.04);
        route = [FYContentRouter dialogueRouteForItems:@[alignedOption,continuation,quotedWord]
            optionsCanPasteInline:YES filterObserver:nil];
        Check([route.dialogueText isEqual:@"友”って呼ばないで。"] && [route.optionItems isEqual:@[alignedOption]],
              @"a distant choice stays a separate inline option beside a recovered dialogue row");
        for (NSString *word in @[@"「友」",@"『友』",@"“友”",@"友達",@"えっ"]) {
            OCRTextItem *piece = Item(word,.313,.123,.035,.048);
            route = [FYContentRouter dialogueRouteForItems:@[continuation,piece]
                optionsCanPasteInline:NO filterObserver:nil];
            Check([route.dialogueText isEqual:[word stringByAppendingString:continuation.text]],
                  @"same-baseline recovery is structural and preserves quoted or unquoted short speech");
        }
        OCRTextItem *before = Item(@"そう呼ぶのは",.19,.122,.118,.048);
        for (NSArray *pieces in @[@[continuation,quotedWord,before],@[before,continuation,quotedWord],
            @[quotedWord,before,continuation]]) {
            route = [FYContentRouter dialogueRouteForItems:pieces optionsCanPasteInline:NO filterObserver:nil];
            Check([route.dialogueText isEqual:@"そう呼ぶのは友”って呼ばないで。"],
                  @"three horizontal pieces are read left-to-right independently of observation order");
        }
        OCRTextItem *endingWord = Item(@"「友」",.543,.119,.039,.05);
        route = [FYContentRouter dialogueRouteForItems:@[endingWord,continuation]
            optionsCanPasteInline:NO filterObserver:nil];
        Check([route.dialogueText isEqual:[continuation.text stringByAppendingString:endingWord.text]],
              @"a quoted fragment at the right edge is not dropped or moved to the next line");
        for (OCRTextItem *unrelated in @[
            Item(@"「友」",.25,.123,.034,.048), // too far horizontally
            Item(@"「友」",.314,.19,.034,.048), // another row
            Item(@"とも",.314,.17,.034,.018), // small ruby
            Item(@"「友」",.36,.123,.034,.048), // competing overlapping observation
        ]) {
            route = [FYContentRouter dialogueRouteForItems:@[unrelated,continuation]
                optionsCanPasteInline:NO filterObserver:nil];
            Check([route.dialogueText isEqual:continuation.text] && route.dialogueItems.count == 1,
                  @"nearby labels, ruby, distant fields and competing observations cannot join the row");
        }
        quotedWord.speakerLabel = YES;
        route = [FYContentRouter dialogueRouteForItems:@[quotedWord,continuation]
            optionsCanPasteInline:NO filterObserver:nil];
        Check([route.dialogueItems isEqual:@[continuation]],@"a confirmed name plate is not a horizontal speech fragment");
        quotedWord.speakerLabel = NO;
        quotedWord.lineCount = 2;
        route = [FYContentRouter dialogueRouteForItems:@[quotedWord,continuation]
            optionsCanPasteInline:NO filterObserver:nil];
        Check([route.dialogueItems isEqual:@[continuation]],@"multi-line observations keep their existing field boundaries");
        quotedWord.lineCount = 0;

        OCRTextItem *punctuation = Item(@"……",.21,.10,.05,.04);
        __block NSUInteger drops = 0;
        route = [FYContentRouter dialogueRouteForItems:@[name,body,punctuation]
            optionsCanPasteInline:YES filterObserver:^(NSString *text, CGRect box, FYContentTextFilterReason reason) {
                Check([text isEqual:punctuation.text] && CGRectEqualToRect(box,punctuation.boundingBox) &&
                      reason == FYContentTextPunctuationOnly, @"filter diagnostic carries only its actual rejected item");
                drops++;
            }];
        Check(drops == 1 && [route.dialogueText isEqual:@"青木\n今日は図書館で待っています。"],
              @"pure punctuation filtering retains the old diagnostic seam and complete body");

        FYContentRouter *router = [FYContentRouter new];
        router.modeStability.detectedMode = 1;
        router.modeStability.candidateMode = -1;
        Check([router observeModeForItems:mixed locked:NO] == 1 &&
              router.modeStability.candidateHits == 1 && router.lastModeDecision.mode == 0,
              @"first new classification is evidence, not a committed switch");
        Check([router observeModeForItems:mixed locked:YES] == 1 &&
              router.modeStability.candidateHits == 1 &&
              [router.lastModeDecision.reason isEqual:@"mode_locked"],
              @"open interactions preserve committed mode and candidate evidence");
        Check([router observeModeForItems:mixed locked:NO] == 0 &&
              router.modeStability.candidateHits == 0, @"second observed vote commits after unlock");
        Check([router observeModeForItems:mixed locked:NO] == 0 &&
              router.modeStability.candidateMode == 0 && router.modeStability.candidateHits == 0,
              @"current-mode observation resets candidate evidence");
        FYContentRouter *other = [FYContentRouter new];
        router.modeStability.detectedMode = 1;
        Check(other.modeStability.detectedMode == 0, @"mode owners do not share capture-run state");

        OCRTextItem *fragment = Item(@"あの",.3,.2,.06,.04);
        decision = [FYContentRouter modeDecisionForItems:@[fragment] fallback:1];
        Check(decision.mode == 1 && [decision.reason isEqual:@"central_fragment"],
              @"ambiguous fragment keeps its explicit fallback");
        decision = [FYContentRouter modeDecisionForItems:@[] fallback:0];
        Check(decision.mode == 0 && [decision.reason isEqual:@"empty"], @"empty classifier preserves fallback");
        decision = [FYContentRouter modeDecisionForItems:@[sign] fallback:0];
        Check(decision.mode == 1 && [decision.reason isEqual:@"default_ui"], @"environmental fallback is unchanged");
        OCRTextItem *back = Item(@"戻る",.1,.5,.1,.03);
        OCRTextItem *menu = Item(@"メニュー",.1,.6,.1,.03);
        decision = [FYContentRouter modeDecisionForItems:@[body,back,menu] fallback:0];
        Check(decision.mode == 0 && [decision.reason isEqual:@"dialogue_band"],
              @"a distinct lower spoken region coexists with persistent UI controls");

        CGRect box = CGRectMake(.2,.2,.4,.07);
        Check(Filter(@"A complete English sentence.",box,YES) == FYContentTextKeep &&
              Filter(@"A complete English sentence.",box,NO) == FYContentTextKeep,
              @"English periods remain translatable in both existing filters");
        Check(Filter(@"え……",box,YES) == FYContentTextKeep, @"short kana with ellipsis remains valid dialogue");
        Check(Filter(@"…！？",box,YES) == FYContentTextPunctuationOnly, @"pure punctuation has an explicit reason");
        Check(Filter(@"",box,NO) == FYContentTextEmpty, @"empty text reason");
        Check(Filter(@"today",box,YES) == FYContentTextKeep, @"a central spoken control-like word is retained");
        Check(Filter(@"today",CGRectMake(.9,.8,.08,.03),YES) == FYContentTextDialogueControl,
              @"an isolated small peripheral control is still filtered");
        Check(Filter(@"Hello",box,NO) == FYContentTextShortUIFragment, @"Japanese OCR retains short Latin-noise filtering");
        Check([FYContentRouter filterReasonForText:@"Hello" normalized:@"Hello" boundingBox:box strict:NO japanese:NO] == FYContentTextKeep,
              @"English OCR keeps short UI words while Japanese OCR keeps its Latin-noise filter");
        Check(Filter(@"ｽﾀｰﾄ",box,NO) == FYContentTextKeep, @"halfwidth kana is valid UI text");
        for (NSString *text in @[@"I know.",@"Books are here.",@"戻らないで。",@"うん、約束",@"そう。約束"]) {
            Check(Filter(text,box,YES) == FYContentTextKeep, @"ordinary speech does not match a control substring");
            Check([[FYContentRouter dialogueTextWithoutTrailingButton:text] isEqual:text], @"ordinary trailing kanji remains complete");
        }
        Check([FYContentRouter textHitsUIToken:@"go back"] && ![FYContentRouter textHitsUIToken:@"goback"],
              @"Latin UI matching preserves actual word boundaries");
        Check([FYContentRouter filterReasonForText:@"No" normalized:@"No" boundingBox:box strict:NO japanese:NO] == FYContentTextKeep,
              @"English No is a valid menu choice, not a numbering decoration");
        OCRTextItem *longBody = Item(@"今日は図書館で待っています。",.2,.12,.38,.045);
        NSArray *choices = @[Item(@"先に行く",.2,.75,.14,.03),Item(@"ここで待つ",.2,.61,.14,.03),
            Item(@"話を聞く",.2,.47,.14,.03),Item(@"後で話す",.2,.33,.14,.03)];
        for (NSArray *observations in @[
            [choices arrayByAddingObjectsFromArray:@[name,longBody]],
            [@[longBody,name] arrayByAddingObjectsFromArray:choices.reverseObjectEnumerator.allObjects]]) {
            decision = [FYContentRouter modeDecisionForItems:observations fallback:1];
            route = [FYContentRouter dialogueRouteForItems:observations optionsCanPasteInline:YES filterObserver:nil];
            Check(decision.mode == 0 && [route.dialogueItems isEqual:@[name,longBody]] && [route.optionItems isEqual:choices],
                  @"four choices retain separate routing even when a name plate bridges the old .12 cluster gap");
        }
        NSMutableArray *list = [NSMutableArray array];
        for (NSUInteger row=0;row<6;row++) {
            [list addObject:Item(@"ここで待ちましょう。",.2,.75-row*.12,.25,.04)];
        }
        Check([FYContentRouter looksLikeUIFrame:list] && [FYContentRouter contentModeForItems:list fallback:0] == 1,
              @"six equal-sized sentence rows remain a pure menu rather than mixed speech");
        [list addObject:Item(@"利用方法についてのお知らせ",.12,.88,.55,.05)];
        Check([FYContentRouter contentModeForItems:list fallback:0] == 1,
              @"a broad announcement heading prevents a lower sentence from overriding dense UI");
        Check(Filter(@"2026/10/11",box,YES) == FYContentTextDateOrNumber, @"existing numeric filter is retained");
        Check(Filter(@"行くぞ。",CGRectMake(.01,.01,.08,.04),YES) == FYContentTextCorner,
              @"corner geometry filtering is retained");

        FYContentComparisonKey key = ^NSString *(NSString *text) { return FYDialogueComparisonKey(text); };
        for (NSArray<NSString *> *wrapper in @[@[@"", @""], @[@"「", @"」"], @[@"『", @"』"],
            @[@"（", @"）"], @[@"(", @")"], @[@"【", @"】"], @[@"“", @"”"], @[@"\"", @"\""],
            @[@"「（", @"）」"], @[@"…「", @"」"]]) {
            NSString *source = [NSString stringWithFormat:@"%@……待っている？%@", wrapper[0], wrapper[1]];
            for (NSString *marks in @[@"… …", @"　⋯ ⋯", @"… ⋯ ・", @"", @"......", @"．．．", @"‥", @"・", @"･", @"•"]) {
                NSString *variant = [NSString stringWithFormat:@"%@%@待っている？%@", wrapper[0], marks, wrapper[1]];
                Check([FYContentRouter isSameSubtitleText:source comparedTo:variant mode:0 japanese:YES comparisonKey:key],
                      @"leading ellipsis OCR variants after quotes or brackets retain one dialogue");
            }
        }
        Check([FYContentRouter isSameSubtitleText:@"え" comparedTo:@"……え" mode:0 japanese:YES comparisonKey:key],
              @"a canonical one-character Japanese reply still matches its leading-ellipsis source");
        Check(![FYContentRouter isSameSubtitleText:@"え" comparedTo:@"え" mode:1 japanese:YES comparisonKey:nil] &&
              ![FYContentRouter isSameSubtitleText:@"a" comparedTo:@"a" mode:0 japanese:NO comparisonKey:nil],
              @"one-character support does not change UI or English comparison");
        Check(![FYContentRouter isSameSubtitleText:@"……" comparedTo:@"⋯⋯" mode:0 japanese:YES comparisonKey:key],
              @"empty punctuation-only keys cannot confirm a dialogue");
        Check([FYDialogueComparisonKey(@"「… ⋯ｴ」") isEqualToString:FYDialogueComparisonKey(@"「ｴ」")],
              @"quoted half-width kana retains the same leading-ellipsis policy");
        for (NSArray<NSString *> *pair in @[@[@"「……待っている？」", @"「……待っている！」"],
            @[@"……三冊借りる。", @"……四冊借りる。"], @[@"「……行く」", @"「……行かない」"],
            @[@"「……待っている」", @"『……待っている』"], @[@"（.5）", @"（5）"],
            @[@"「a⋯b」", @"「a…b」"], @[@"「マリー・アン」", @"「マリー…アン」"]]) {
            Check(![FYDialogueComparisonKey(pair[0]) isEqualToString:FYDialogueComparisonKey(pair[1])],
                  @"leading normalization retains meaningful punctuation, numbers, words, wrappers and notation");
        }
        Check([FYContentRouter isSameSubtitleText:@"待っている……" comparedTo:@"待っている・・・"
            mode:0 japanese:YES comparisonKey:key], @"router reuses production punctuation identity");
        NSString *ellipsisSource = @"青木\n旅程、天気……\n詳しく知りたいなら、\nいつでも連絡して。";
        NSString *flatSource = FYNormalizeOCRTextForComparison(ellipsisSource);
        for (NSString *marks in @[@"…⋯⋯", @"⋯", @"⋯⋯⋯", @"・・・", @"......", @"．．．", @"‥", @"・…．"]) {
            NSString *variant = FYNormalizeOCRTextForComparison(
                [ellipsisSource stringByReplacingOccurrencesOfString:@"……" withString:marks]);
            Check([FYContentRouter isSameSubtitleText:variant comparedTo:flatSource
                mode:0 japanese:YES comparisonKey:key],
                @"frame comparison recognizes middle-line ellipsis variants after newline removal");
        }
        for (NSArray<NSString *> *pair in @[@[@"天気…良い", @"天気？良い"], @[@"天気…良い", @"天気！良い"],
            @[@"天気…良い", @"天気。良い"], @[@"天気…良い", @"天気…悪い"],
            @[@"1.5", @"15"], @[@"a⋯b", @"a…b"], @[@"マリー・アン", @"マリー…アン"],
            @[@"猫・犬", @"猫犬"], @[@"A...B", @"A…B"]]) {
            Check(![FYDialogueComparisonKey(pair[0]) isEqualToString:FYDialogueComparisonKey(pair[1])],
                  @"ellipsis folding preserves semantic punctuation, words, decimals, name separators and non-Japanese notation");
        }
        NSString *rendered = @"明日は図書館で本を三冊借ります。";
        NSString *corrected = @"明日は図書館で本を四冊借ります。";
        Check(![FYContentRouter isSameSubtitleText:rendered comparedTo:corrected mode:0 japanese:YES comparisonKey:key],
              @"a changed number cannot collapse into the rendered Japanese identity");
        Check(![FYContentRouter isSameSubtitleText:@"Hello" comparedTo:@"Hallo" mode:0 japanese:NO comparisonKey:nil],
              @"English short-text threshold is preserved without invoking a Japanese key");
        FYOCRStabilityOwner *stable = [FYOCRStabilityOwner new];
        Check(![FYContentRouter isStableText:corrected owner:stable mode:0 japanese:YES renderedText:rendered comparisonKey:key],
              @"correction first frame waits");
        Check(![FYContentRouter isStableText:corrected owner:stable mode:0 japanese:YES renderedText:rendered comparisonKey:key],
              @"similar correction second frame still waits");
        Check([FYContentRouter isStableText:corrected owner:stable mode:0 japanese:YES renderedText:rendered comparisonKey:key],
              @"similar correction third frame is accepted");
        [stable reset];
        Check(![FYContentRouter isStableText:rendered owner:stable mode:0 japanese:YES renderedText:nil comparisonKey:key] &&
              [FYContentRouter isStableText:rendered owner:stable mode:0 japanese:YES renderedText:nil comparisonKey:key],
              @"new dialogue retains two-frame confirmation");
        Check([FYContentRouter recognitionPollingIntervalForMode:0] == .5 &&
              [FYContentRouter recognitionPollingIntervalForMode:1] == 1.2 &&
              [FYContentRouter translationAttemptThrottleForMode:0] == 4.0 &&
              [FYContentRouter translationAttemptThrottleForMode:1] == 1.2,
              @"polling and same-text retry cadence are unchanged");
        NSLog(@"PASS ContentRouterTests: %lu assertions, no application, capture, Vision request or network",
              (unsigned long)Checks);
    }
    return 0;
}
