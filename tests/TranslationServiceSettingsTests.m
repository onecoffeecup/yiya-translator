#import <Foundation/Foundation.h>
#import "FYTranslationServiceSettings.h"
#import "FYTranslationManager.h"
static NSUInteger checks;
static void Check(BOOL pass, NSString *message) { checks++; if(!pass) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); } }
int main(void) { @autoreleasepool {
    NSArray *presets=FYTranslationServicePresets(); Check(presets.count==10,@"eight official services and two platforms");
    NSMutableSet *identifiers=[NSMutableSet new];
    for(NSDictionary *preset in presets) {
        Check(![identifiers containsObject:preset[@"id"]],@"preset identities are unique"); [identifiers addObject:preset[@"id"]];
        NSError *error=nil; NSURL *url=FYTranslationServiceURLWithError(preset[@"url"],&error); Check(url && !error,@"preset endpoint passes production validation");
        NSString *model=[preset[@"model"] length] ? preset[@"model"] : @"fixture-model";
        NSURLRequest *request=[FYTranslationManager requestWithURL:url apiKey:@"synthetic-key" model:model
            sourceText:@"合成原文" systemPrompt:@"合成提示" maxTokens:240 disableReasoning:NO error:&error];
        Check(request && !error,@"every preset can build a production request offline");
        Check([request.URL.path hasSuffix:[preset[@"id"] isEqual:@"claude"] ? @"/messages" : @"/chat/completions"],@"protocol is selected internally by endpoint");
        NSDictionary *body=[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
        if([preset[@"id"] isEqual:@"claude"]) Check([body[@"thinking"][@"type"] isEqual:@"between_tools"] && [body[@"output_config"][@"effort"] isEqual:@"low"],@"default Sonnet leaves its small output budget for translation text");
        if([@[@"kimi",@"glm",@"gemini"] containsObject:preset[@"id"]]) Check([body[@"reasoning_effort"] isEqual:@"low"] && [body[@"max_tokens"] integerValue]>=4096 && !body[@"temperature"],@"always-thinking defaults receive a bounded thinking budget and supported generation parameters");
    }
    FYTranslationServiceSettings *settings=[FYTranslationServiceSettings new];
    [settings loadSettings:@{@"baseURL":@"https://example.invalid/v1",@"model":@"stored-model",@"realtimeModel":@"old-realtime-model"}];
    Check([settings.mode isEqual:@"custom"] && [settings.model isEqual:@"stored-model"],@"legacy custom URL and ordinary model retained");
    [settings loadSettings:@{@"baseURL":@"https://api.deepseek.com",@"model":@" ",@"realtimeModel":@"legacy-model"}];
    Check([settings.mode isEqual:@"preset"] && [settings.model isEqual:@"legacy-model"],@"legacy realtime model is used only when ordinary model is empty");
    settings.model=@"my-custom-deepseek"; [settings selectProvider:@"glm"]; settings.model=@"my-glm";
    [settings selectProvider:@"deepseek"]; Check([settings.model isEqual:@"my-custom-deepseek"],@"typed model retained independently for each provider");
    [settings switchToMode:@"custom" seedFromPreset:YES]; Check([settings.model isEqual:@"my-custom-deepseek"] && [settings.baseURL isEqual:@"https://api.deepseek.com"],@"customize seeds the current URL and edited model");
    settings.baseURL=@"http://localhost:1234/v1"; settings.model=@"local-model"; [settings switchToMode:@"preset" seedFromPreset:NO]; [settings selectProvider:@"claude"]; [settings switchToMode:@"custom" seedFromPreset:NO];
    Check([settings.baseURL isEqual:@"http://localhost:1234/v1"] && [settings.model isEqual:@"local-model"],@"switching mode and providers retains independent custom draft");
    NSDictionary *saved=[settings settingsDictionary]; FYTranslationServiceSettings *reopened=[FYTranslationServiceSettings new]; [reopened loadSettings:saved];
    Check([reopened.mode isEqual:@"custom"] && [reopened.baseURL isEqual:settings.baseURL] && [reopened.model isEqual:settings.model],@"custom settings restore after reopening");
    [reopened selectProvider:@"glm"]; Check([reopened.model isEqual:@"my-glm"],@"provider model edits restore after reopening");
    [reopened selectProvider:@"doubao"]; Check(reopened.model.length==0,@"providers needing an account-specific model do not invent one");
    NSDictionary *blank=[reopened settingsDictionary]; [reopened loadSettings:blank]; Check(reopened.model.length==0,@"explicitly empty new-model setting is not replaced by a different model");
    Check(!saved[@"apiKey"] && !saved[@"protocol"] && !saved[@"interfaceType"],@"configuration stores no credentials or player-facing protocol choice");
    NSError *error=nil;
    Check([FYTranslationServiceURLWithError(@"https://api.anthropic.com/",&error).absoluteString isEqual:@"https://api.anthropic.com/v1/messages"],@"Claude root URL normalizes internally");
    Check([FYTranslationServiceURLWithError(@"http://localhost:1234/v1/messages/",&error).path isEqual:@"/v1/messages"],@"explicit custom Messages endpoint stays available without another selector");
    Check(!FYUsesAnthropicMessagesAPI(FYTranslationServiceURLWithError(@"https://api.anthropic.com.example.invalid/v1",&error)),@"lookalike hosts do not select the official Claude adapter");
    Check(!FYTranslationServiceURLWithError(@"http://api.anthropic.com/v1",&error) && error.code==FYTranslationURLInsecureRemoteHTTP,@"new adapter cannot bypass remote HTTP credential protection");
    for(NSString *model in @[@"claude-haiku-5-5",@"claude-opus-5-5"]) {
        NSURLRequest *request=[FYTranslationManager requestWithURL:FYTranslationServiceURLWithError(@"https://api.anthropic.com/v1",NULL)
            apiKey:@"synthetic-key" model:model sourceText:@"合成原文" systemPrompt:@"合成提示" maxTokens:240 disableReasoning:NO error:NULL];
        NSDictionary *body=[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
        Check([body[@"output_config"][@"effort"] isEqual:@"low"],@"known Claude defaults use their supported low effort setting");
        Check([model containsString:@"haiku"] ? [body[@"thinking"][@"type"] isEqual:@"disabled"] : !body[@"thinking"] && [body[@"max_tokens"] integerValue]>=4096,
            @"Haiku can disable thinking while Opus retains mandatory thinking with room for its answer");
    }
    printf("PASS: %lu service settings checks (isolated, no credentials or requests)\n",(unsigned long)checks);
} return 0; }
