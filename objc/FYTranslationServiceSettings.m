#import "FYTranslationServiceSettings.h"

static NSString *FYServiceString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSString *FYServiceTrim(id value) { return [FYServiceString(value) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
static NSDictionary *FYPreset(NSString *identifier, NSString *name, NSString *subtitle, NSString *url,
    NSString *model, NSArray *models, NSString *platform, NSString *note, NSString *placeholder, BOOL aggregate) {
    return @{@"id":identifier,@"name":name,@"subtitle":subtitle,@"url":url,@"model":model,@"models":models,
        @"platform":platform,@"note":note,@"placeholder":placeholder,@"aggregate":@(aggregate)};
}
NSArray<NSDictionary *> *FYTranslationServicePresets(void) {
    static NSArray *presets; static dispatch_once_t once;
    dispatch_once(&once, ^{
        presets=@[
            FYPreset(@"deepseek",@"DeepSeek",@"深度求索",@"https://api.deepseek.com",@"deepseek-flash",@[@"deepseek-flash",@"deepseek-v4-pro"],@"https://platform.deepseek.com/",@"已填入 DeepSeek 官方地址。",@"",NO),
            FYPreset(@"openai",@"OpenAI",@"GPT 系列",@"https://api.openai.com/v1",@"gpt-4.1-mini",@[@"gpt-4.1-mini",@"gpt-4.1"],@"https://platform.openai.com/api-keys",@"已填入 OpenAI 官方地址。",@"",NO),
            FYPreset(@"glm",@"GLM",@"智谱开放平台",@"https://open.bigmodel.cn/api/paas/v4",@"glm-5.3-flash",@[@"glm-5.3-flash",@"glm-5.3"],@"https://open.bigmodel.cn/",@"已填入智谱通用 API 地址。",@"",NO),
            FYPreset(@"claude",@"Claude",@"Anthropic",@"https://api.anthropic.com/v1",@"claude-sonnet-5-5",@[@"claude-sonnet-5-5",@"claude-haiku-5-5",@"claude-opus-5-5"],@"https://platform.claude.com/",@"已填入 Anthropic 官方地址。",@"",NO),
            FYPreset(@"gemini",@"Gemini",@"Google AI Studio",@"https://generativelanguage.googleapis.com/v1beta/openai",@"gemini-3.8-flash",@[@"gemini-3.8-flash"],@"https://aistudio.google.com/",@"已填入 Google AI Studio 地址。",@"",NO),
            FYPreset(@"qwen",@"通义千问",@"阿里云百炼",@"https://dashscope.aliyuncs.com/compatible-mode/v1",@"qwen-plus",@[@"qwen-plus"],@"https://bailian.console.aliyun.com/",@"默认北京地域，其他地域请改为自定义地址。",@"",NO),
            FYPreset(@"kimi",@"Kimi",@"月之暗面",@"https://api.moonshot.cn/v1",@"kimi-k3",@[@"kimi-k3"],@"https://platform.kimi.com/",@"已填入 Kimi 国内开放平台地址。",@"",NO),
            FYPreset(@"doubao",@"豆包",@"火山方舟",@"https://ark.cn-beijing.volces.com/api/v3",@"",@[],@"https://ark.volcengine.com/",@"已填入火山方舟北京地域地址。",@"从方舟控制台复制模型 ID 或推理接入点 ID",NO),
            FYPreset(@"siliconflow",@"硅基流动",@"SiliconFlow",@"https://api.siliconflow.cn/v1",@"",@[],@"https://cloud.siliconflow.cn/",@"已填入硅基流动国内平台地址。",@"从硅基流动模型详情复制完整模型 ID",YES),
            FYPreset(@"openrouter",@"OpenRouter",@"多家模型，一处接入",@"https://openrouter.ai/api/v1",@"~anthropic/claude-sonnet-latest",@[@"~anthropic/claude-sonnet-latest",@"~openai/gpt-sol-latest"],@"https://openrouter.ai/keys",@"请使用 OpenRouter 的 Key，与模型厂商的 Key 不通用。",@"",YES)
        ];
    });
    return presets;
}
NSDictionary *FYTranslationServicePreset(NSString *identifier) {
    for (NSDictionary *preset in FYTranslationServicePresets()) if ([preset[@"id"] isEqual:identifier]) return preset;
    return nil;
}
NSString *FYTranslationModelFromSettings(NSDictionary *settings) {
    for (NSString *key in @[@"model",@"realtimeModel"]) if (FYServiceTrim(settings[key]).length) return FYServiceTrim(settings[key]);
    return @"gpt-4.1-mini";
}

@interface FYTranslationServiceSettings ()
@property(nonatomic, copy, readwrite) NSString *mode;
@property(nonatomic, copy, readwrite) NSString *provider;
@property(nonatomic, copy) NSString *customURL;
@property(nonatomic, copy) NSString *customModel;
@property(nonatomic, strong) NSMutableDictionary *providerModels;
@end
@implementation FYTranslationServiceSettings
- (instancetype)init { if ((self=[super init])) [self loadSettings:nil]; return self; }
- (void)rememberDraft {
    if ([self.mode isEqual:@"custom"]) { self.customURL=self.baseURL ?: @""; self.customModel=self.model ?: @""; }
    else self.providerModels[self.provider]=self.model ?: @"";
}
- (void)loadSettings:(NSDictionary *)settings {
    self.baseURL=[settings[@"baseURL"] isKindOfClass:NSString.class] ? settings[@"baseURL"] : @"https://api.openai.com/v1";
    BOOL hasMode=[@[@"preset",@"custom"] containsObject:settings[@"serviceMode"] ?: @""];
    self.model=hasMode && [settings[@"model"] isKindOfClass:NSString.class] ? settings[@"model"] : FYTranslationModelFromSettings(settings);
    self.providerModels=[NSMutableDictionary new];
    NSDictionary *saved=[settings[@"serviceProviderModels"] isKindOfClass:NSDictionary.class] ? settings[@"serviceProviderModels"] : nil;
    for (NSDictionary *preset in FYTranslationServicePresets()) if ([saved[preset[@"id"]] isKindOfClass:NSString.class]) self.providerModels[preset[@"id"]]=saved[preset[@"id"]];
    self.provider=FYTranslationServicePreset(settings[@"serviceProvider"]) ? settings[@"serviceProvider"] : @"openai";
    // Never replace a stored endpoint just because it resembles a preset.
    self.mode=@"custom";
    NSString *url=FYServiceTrim(self.baseURL); while ([url hasSuffix:@"/"]) url=[url substringToIndex:url.length-1];
    for (NSDictionary *preset in FYTranslationServicePresets()) if ([url isEqual:preset[@"url"]]) { self.provider=preset[@"id"]; self.mode=@"preset"; break; }
    if (hasMode && [settings[@"serviceMode"] isEqual:@"custom"]) self.mode=@"custom";
    self.customURL=[settings[@"serviceCustomURL"] isKindOfClass:NSString.class] ? settings[@"serviceCustomURL"] : self.baseURL;
    self.customModel=[settings[@"serviceCustomModel"] isKindOfClass:NSString.class] ? settings[@"serviceCustomModel"] : self.model;
    [self rememberDraft];
}
- (NSDictionary *)settingsDictionary {
    [self rememberDraft];
    return @{@"baseURL":self.baseURL ?: @"",@"model":self.model ?: @"",@"serviceMode":self.mode,@"serviceProvider":self.provider,
        @"serviceCustomURL":self.customURL ?: @"",@"serviceCustomModel":self.customModel ?: @"",@"serviceProviderModels":[self.providerModels copy]};
}
- (void)selectProvider:(NSString *)identifier {
    NSDictionary *preset=FYTranslationServicePreset(identifier); if (!preset) return;
    [self rememberDraft]; self.mode=@"preset"; self.provider=identifier; self.baseURL=preset[@"url"];
    self.model=self.providerModels[identifier] ?: preset[@"model"];
}
- (void)switchToMode:(NSString *)mode seedFromPreset:(BOOL)seed {
    if (![@[@"preset",@"custom"] containsObject:mode]) return;
    [self rememberDraft];
    if (seed && [self.mode isEqual:@"preset"]) { self.customURL=self.baseURL; self.customModel=self.model; }
    self.mode=mode;
    if ([mode isEqual:@"custom"]) { self.baseURL=self.customURL; self.model=self.customModel; }
    else { NSDictionary *p=FYTranslationServicePreset(self.provider); self.baseURL=p[@"url"]; self.model=self.providerModels[self.provider] ?: p[@"model"]; }
}
@end
