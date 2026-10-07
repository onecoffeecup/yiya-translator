#import <Foundation/Foundation.h>
#import "FYLearningModels.h"
#import "FYGrammarCatalog.h"

NS_ASSUME_NONNULL_BEGIN

// 传输抽象：默认用 NSURLSession，测试可注入 mock（不调用真实 API，不读真实 Key）。
typedef void (^FYLearningTransport)(NSURLRequest *request,
                                    void (^completion)(NSData *_Nullable data,
                                                       NSURLResponse *_Nullable response,
                                                       NSError *_Nullable error));

// 独立学习请求：拥有自己的任务与代际，绝不占用/取消实时翻译的 activeTranslationTask。
@interface FYLearningAnalyzer : NSObject

@property(nonatomic, copy) NSString *baseURL;
@property(nonatomic, copy) NSString *apiKey;
@property(nonatomic, copy) NSString *model;           // 使用设置中的学习模型；DeepSeek 学习请求默认关闭推理
@property(nonatomic, strong) FYGrammarCatalog *catalog;
@property(nonatomic, copy, nullable) FYLearningTransport transport;
@property(nonatomic, readonly) NSInteger generation;

- (void)cancelAll;
- (void)answerConversation:(NSArray<NSDictionary *> *)messages completion:(void (^)(NSString *answer, NSError *_Nullable error))completion;
- (void)answerQuestion:(NSString *)question grammar:(FYGrammarItem *)item sentenceText:(NSString *)sentenceText translation:(nullable NSString *)translation completion:(void (^)(NSString *answer, NSError *_Nullable error))completion;

// 句子语法/词汇分析：严格校验后返回；等级只由 catalog 补全。
- (void)analyzeSentence:(NSString *)text
            translation:(nullable NSString *)translation
             completion:(void (^)(FYAnalysisResult *result, NSError *_Nullable error))completion;

// Explicit, single-request review. Verified existing findings survive an empty review.
- (void)reviewSentence:(NSString *)text translation:(nullable NSString *)translation
       existingResult:(FYAnalysisResult *)existing
           completion:(void (^)(FYAnalysisResult *_Nullable result, NSError *_Nullable error))completion;
- (void)expandedExplanationForGrammar:(FYGrammarItem *)item sentenceText:(NSString *)text
                         translation:(nullable NSString *)translation
                          completion:(void (^)(NSString *_Nullable explanation, NSError *_Nullable error))completion;

// 词条补全（读音/原形/释义）。
- (void)completeVocabulary:(NSString *)surface
                   context:(nullable NSString *)context
                completion:(void (^)(FYVocabularyEntry *entry, NSError *_Nullable error))completion;

// 两个轻量追问。
- (void)simplerExplanationForGrammar:(FYGrammarItem *)item
                        sentenceText:(NSString *)sentenceText
                         translation:(nullable NSString *)translation
                          completion:(void (^)(NSString *explanation, NSError *_Nullable error))completion;

- (void)exampleSentenceForGrammar:(FYGrammarItem *)item
                     sentenceText:(NSString *)sentenceText
                      translation:(nullable NSString *)translation
                       completion:(void (^)(NSString *example, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
