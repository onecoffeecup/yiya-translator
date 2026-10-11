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
        Check(decision.mode == 1 && [decision.reason isEqual:@"ui_evidence"],
              @"extraction preserves the existing UI-first priority instead of silently fixing it");

        CGRect box = CGRectMake(.2,.2,.4,.07);
        Check(Filter(@"A complete English sentence.",box,YES) == FYContentTextKeep &&
              Filter(@"A complete English sentence.",box,NO) == FYContentTextKeep,
              @"English periods remain translatable in both existing filters");
        Check(Filter(@"え……",box,YES) == FYContentTextKeep, @"short kana with ellipsis remains valid dialogue");
        Check(Filter(@"…！？",box,YES) == FYContentTextPunctuationOnly, @"pure punctuation has an explicit reason");
        Check(Filter(@"",box,NO) == FYContentTextEmpty, @"empty text reason");
        Check(Filter(@"today",box,YES) == FYContentTextDialogueControl, @"existing dialogue token filtering is retained");
        Check(Filter(@"Hello",box,NO) == FYContentTextShortUIFragment, @"existing short English UI gap is not changed");
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
