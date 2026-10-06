#import "FYJapaneseTokenizer.h"
#import <NaturalLanguage/NaturalLanguage.h>

@interface FYJapaneseTokenizer ()
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) dispatch_queue_t completionQueue;
@end

@implementation FYJapaneseTokenizer

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.nanami.fuyi.japanese-tokenizer", DISPATCH_QUEUE_SERIAL);
        _completionQueue = dispatch_get_main_queue();
    }
    return self;
}

- (void)setCompletionQueue:(dispatch_queue_t)queue {
    _completionQueue = queue ?: dispatch_get_main_queue();
}

- (NSArray<NSValue *> *)rangesInText:(NSString *)text {
    if (text.length == 0) { return @[]; }
    NLTokenizer *tokenizer = [[NLTokenizer alloc] initWithUnit:NLTokenUnitWord];
    tokenizer.string = text;
    [tokenizer setLanguage:NLLanguageJapanese];
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    [tokenizer enumerateTokensInRange:NSMakeRange(0, text.length)
                           usingBlock:^(NSRange range, NLTokenizerAttributes attributes, BOOL *stop) {
        if (range.location + range.length <= text.length) {
            [ranges addObject:[NSValue valueWithRange:range]];
        }
    }];
    return ranges;
}

- (void)rangesInText:(NSString *)text
          completion:(void (^)(NSArray<NSValue *> *))completion {
    if (!completion) { return; }
    dispatch_async(self.queue, ^{
        NSArray<NSValue *> *ranges = [self rangesInText:text];
        dispatch_async(self.completionQueue, ^{ completion(ranges); });
    });
}

- (void)rangeForLocation:(NSUInteger)location
                  inText:(NSString *)text
              completion:(void (^)(NSRange))completion {
    if (!completion) { return; }
    dispatch_async(self.queue, ^{
        NSRange found = NSMakeRange(NSNotFound, 0);
        if (location < text.length) {
            for (NSValue *value in [self rangesInText:text]) {
                NSRange range = value.rangeValue;
                if (location >= range.location && location < NSMaxRange(range)) {
                    found = range;
                    break;
                }
            }
        }
        dispatch_async(self.completionQueue, ^{ completion(found); });
    });
}

@end
