#import <Foundation/Foundation.h>
#import "FYTranslationManager.h"
static NSUInteger checks;
static void Check(BOOL pass, NSString *message) { checks++; if(!pass) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); } }
int main(void) { @autoreleasepool {
    NSError *error=nil;
    NSURLRequest *request=[FYTranslationManager requestWithURL:[NSURL URLWithString:@"https://api.anthropic.com/v1/messages"]
        apiKey:@"synthetic-key" model:@"fixture-claude" sourceText:@" 合成原文 " systemPrompt:@"合成系统提示"
        maxTokens:240 disableReasoning:NO error:&error];
    Check(request && !error,@"Claude request can be constructed offline");
    Check([[request valueForHTTPHeaderField:@"x-api-key"] isEqual:@"synthetic-key"] &&
        [[request valueForHTTPHeaderField:@"anthropic-version"] isEqual:@"2023-06-01"] && ![request valueForHTTPHeaderField:@"Authorization"],
        @"Claude uses its own authentication and version headers");
    NSDictionary *payload=[NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
    Check([payload[@"system"] isEqual:@"合成系统提示"] && [payload[@"messages"] count]==1 &&
        [payload[@"messages"][0][@"role"] isEqual:@"user"] && [payload[@"messages"][0][@"content"] isEqual:@"合成原文"],
        @"system prompt is separate from user and assistant messages");
    Check(!payload[@"temperature"] && !payload[@"response_format"] && !payload[@"reasoning_effort"],@"Claude receives no OpenAI-only generation fields");
    Check(request.timeoutInterval==15 && [payload[@"max_tokens"] integerValue]==240,@"existing realtime timeout and output budget retained");
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"type":@"message",@"content":@[@{@"type":@"thinking",@"thinking":@"hidden"},@{@"type":@"text",@"text":@"第一段"},@{@"type":@"text",@"text":@"第二段"}]} options:0 error:NULL];
    Check([[FYTranslationManager translationFromData:data statusCode:200 error:&error] isEqual:@"第一段\n第二段"],@"Claude text blocks are joined without exposing thinking");
    error=nil; data=[NSJSONSerialization dataWithJSONObject:@{@"type":@"message",@"content":@[@{@"type":@"thinking",@"thinking":@"hidden"}]} options:0 error:NULL];
    Check(![FYTranslationManager translationFromData:data statusCode:200 error:&error] && error.code==204,@"thinking-only Claude response remains a failure");
    error=nil; data=[NSJSONSerialization dataWithJSONObject:@{@"content":@[@"malformed",@{@"type":@"text",@"text":@42}]} options:0 error:NULL];
    Check(![FYTranslationManager translationFromData:data statusCode:200 error:&error],@"malformed content blocks do not crash or succeed");
    printf("PASS: %lu Claude translation checks (synthetic, no requests)\n",(unsigned long)checks);
} return 0; }
