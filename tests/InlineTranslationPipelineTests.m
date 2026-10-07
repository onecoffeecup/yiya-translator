#import "LearningAppTestSupport.h"
@interface PipelineApp : AppDelegate
@property(nonatomic) NSUInteger requestCount;
@property(nonatomic) BOOL holdsRequests;
@property(nonatomic,copy) void (^shortCompletion)(NSString *,NSError *);
@property(nonatomic,copy) void (^longCompletion)(NSString *,NSError *);
@property(nonatomic,strong) NSMutableArray<NSString *> *submittedSources;
@end
@implementation PipelineApp
- (void)translateTextRealtime:(NSString *)text systemPrompt:(NSString *)prompt maxTokens:(NSInteger)maxTokens completion:(void (^)(NSString *,NSError *))completion {
    self.requestCount++;
    [self.submittedSources addObject:text];
    BOOL longText=[prompt containsString:@"公告翻译器"];
    Require(maxTokens==(longText?320:240),@"single item route preserves token minimum");
    if(self.holdsRequests) { if(longText)self.longCompletion=completion;else self.shortCompletion=completion;return; }
    completion(longText?@"1. 长正文译文":@"1. 短标签译文",nil);
}
@end
static OCRTextItem *Item(NSString *text, NSInteger kind) {
    OCRTextItem *item=[OCRTextItem new]; item.text=text; item.blockKind=kind; return item;
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    PipelineApp *app=[PipelineApp new];
    app.inlineTranslationCache=[NSMutableDictionary new];
    app.submittedSources=[NSMutableArray new];
    app.languageControl=[[NSSegmentedControl alloc] init]; app.languageControl.segmentCount=3; app.languageControl.selectedSegment=0;
    OCRTextItem *cached=Item(@"保存",InlineBlockKindShort), *longItem=Item(@"これは長い本文です",InlineBlockKindLong), *shortItem=Item(@"開始",InlineBlockKindShort);
    app.inlineTranslationCache[[app inlineTranslationCacheKeyForItem:cached]]=@"已缓存";
    __block NSUInteger completions=0; __block NSArray *result=nil;
    [app translateInlineTextItems:@[cached] completion:^(NSArray *values,NSError *error){Require(!error,@"cache hit succeeds");completions++;result=values;}];
    Require(completions==1 && app.requestCount==0 && [result isEqual:@[@"已缓存"]],@"all cached items deliver synchronously without request");
    completions=0;
    [app translateInlineTextItems:@[cached,longItem,shortItem] completion:^(NSArray *values,NSError *error){Require(!error,@"mixed routes succeed");completions++;result=values;}];
    Require(completions==1 && app.requestCount==2,@"mixed pending routes complete once with two requests");
    Require([app.submittedSources isEqual:@[@"1. 開始\n",@"1. これは長い本文です\n"]],@"short request launches first with independent numbering");
    Require([result isEqual:@[@"已缓存",@"长正文译文",@"短标签译文"]],@"mixed route results map to original input slots");
    [app translateInlineTextItems:@[cached,longItem,shortItem] completion:^(NSArray *values,NSError *error){Require(!error && [values isEqual:result],@"second call reuses cached translations");}];
    Require(app.requestCount==2,@"successful mixed route translations cached without new requests");
    app.holdsRequests=YES; completions=0; app.requestCount=0;
    [app translateInlineTextItems:@[Item(@"新正文",InlineBlockKindLong),Item(@"新按钮",InlineBlockKindShort)] completion:^(NSArray *values,NSError *error){completions++; Require(!values && error.code==205,@"short route error has priority and suppresses values");}];
    Require(app.requestCount==2 && completions==0,@"failed mixed routes wait for both completions");
    app.longCompletion(nil,[NSError errorWithDomain:@"fixture" code:408 userInfo:nil]);
    Require(completions==0,@"long failure alone does not deliver");
    NSError *shortError=[NSError errorWithDomain:@"fixture" code:205 userInfo:nil];
    app.shortCompletion(nil,shortError);
    Require(completions==1,@"short failure wins after both routes finish");
    app.holdsRequests=NO; app.requestCount=0;
    [app translateInlineTextItems:@[Item(@"新按钮",InlineBlockKindShort)] completion:^(NSArray *values,NSError *error){Require(!error && [values isEqual:@[@"短标签译文"]],@"failed values remain retryable");}];
    Require(app.requestCount==1,@"failed route does not cache and can retry");
    NSLog(@"PASS InlineTranslationPipelineTests: production entry, isolated mock requests, cache and mixed routes");
} return 0; }
