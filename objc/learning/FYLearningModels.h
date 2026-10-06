#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Compare OCR dialogue variants without changing the saved source text.
FOUNDATION_EXPORT NSString *FYDialogueComparisonKey(NSString *text);
// A frame that keeps the head or the tail of a longer, already-seen dialogue
// (missing speaker box, missing last lines) without adding new content.
FOUNDATION_EXPORT BOOL FYDialogueIsFragmentOfDialogue(NSString *candidate, NSString *complete);
FOUNDATION_EXPORT BOOL FYDialogueIsSpeakerAnchoredFragment(NSString *candidate, NSString *complete);
FOUNDATION_EXPORT BOOL FYDialogueIsIncompleteFrame(NSString *candidate, NSString *complete);
// Symmetric relation used to group equivalent rows in the recent-dialogue list.
FOUNDATION_EXPORT BOOL FYDialogueTextsAreEquivalent(NSString *first, NSString *second);

typedef NS_ENUM(NSInteger, FYSentenceKind) {
    FYSentenceKindDialogue = 0,
    FYSentenceKindOption = 1,
    FYSentenceKindUI = 2,
    FYSentenceKindSnapshot = 3,
};

typedef NS_ENUM(NSInteger, FYVocabularyKind) {
    FYVocabularyKindWord = 0,
    FYVocabularyKindPhrase = 1,
};

typedef NS_ENUM(NSInteger, FYCompletionSource) {
    FYCompletionSourceManual = 0,
    FYCompletionSourceAI = 1,
};

typedef NS_ENUM(NSInteger, FYReviewStatus) {
    FYReviewStatusNew = 0,
    FYReviewStatusLearning = 1,
    FYReviewStatusKnown = 2,
};

typedef NS_ENUM(NSInteger, FYAnalysisStatus) {
    FYAnalysisStatusNone = 0,
    FYAnalysisStatusSuccess = 1,
    FYAnalysisStatusFailed = 2,
    FYAnalysisStatusNoResult = 3,
};

// 供分析/请求闭包携带的不可变身份。绝不使用实时变化的 UI 文本或 latestSourceLabel 来推断归属。
@interface FYRequestIdentity : NSObject
@property(nonatomic, copy) NSString *sentenceID;
@property(nonatomic) NSInteger version;
@property(nonatomic, copy) NSString *requestID;
@property(nonatomic, copy) NSString *sourceText;
@property(nonatomic, copy, nullable) NSString *translation;
+ (instancetype)identityWithSentenceID:(NSString *)sentenceID
                               version:(NSInteger)version
                             requestID:(NSString *)requestID
                            sourceText:(NSString *)sourceText
                           translation:(nullable NSString *)translation;
@end

@interface FYSentenceRecord : NSObject
@property(nonatomic, copy) NSString *sentenceID;
@property(nonatomic, copy) NSString *sessionID;
@property(nonatomic) FYSentenceKind kind;
@property(nonatomic, copy) NSString *originalText;
@property(nonatomic) NSInteger latestVersion;
@property(nonatomic, copy, nullable) NSString *latestTranslation;
@property(nonatomic, copy) NSString *latestText;   // 最新版本对应的文本
@property(nonatomic, strong) NSDate *occurredAt;
@property(nonatomic, copy, nullable) NSString *displayName;
@end

@interface FYSentenceVersion : NSObject
@property(nonatomic, copy) NSString *sentenceID;
@property(nonatomic) NSInteger version;
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy, nullable) NSString *translation;
@property(nonatomic, strong) NSDate *createdAt;
@end

@interface FYVocabularyEntry : NSObject
@property(nonatomic, copy) NSString *vocabularyID;
@property(nonatomic) FYVocabularyKind kind;
@property(nonatomic, copy) NSString *surface;   // 实际遇到的词形
@property(nonatomic, copy, nullable) NSString *lemma;    // 原形，未知时为空
@property(nonatomic, copy, nullable) NSString *reading;  // 读音，未知时为空
@property(nonatomic, copy, nullable) NSString *meaning;
@property(nonatomic) FYCompletionSource completionSource;
@property(nonatomic) FYReviewStatus reviewStatus;
@property(nonatomic, strong) NSDate *bookmarkedAt;
@end

@interface FYVocabularyExample : NSObject
@property(nonatomic, copy) NSString *vocabularyID;
@property(nonatomic, copy) NSString *sentenceID;
@property(nonatomic) NSInteger version;
@property(nonatomic, copy) NSString *sourceTextSnapshot;
@property(nonatomic, copy, nullable) NSString *translationSnapshot;
@property(nonatomic, copy) NSString *selectedRangeText;
@end

@interface FYGrammarItem : NSObject
@property(nonatomic, copy) NSString *catalogID;      // 可空，未知时为 nil
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *matchedText;
@property(nonatomic) NSRange matchedRange;           // 在原文中的 UTF-16 范围，location==NSNotFound 表示未命中
@property(nonatomic, copy, nullable) NSString *connection;
@property(nonatomic, copy, nullable) NSString *meaning;
@property(nonatomic, copy, nullable) NSString *explanation;
@property(nonatomic, copy, nullable) NSString *registerNote;
@property(nonatomic, copy, nullable) NSString *referenceLevel; // 仅来自 catalog，例如 "N2"
@property(nonatomic, copy, nullable) NSString *levelSourceTitle;
@property(nonatomic, copy, nullable) NSString *levelSourceURL;
@property(nonatomic) BOOL levelVerified;
@end

@interface FYAnalysisResult : NSObject
@property(nonatomic) NSInteger schemaVersion;
@property(nonatomic, copy) NSArray<FYGrammarItem *> *grammar;
@property(nonatomic, copy) NSArray<FYVocabularyEntry *> *vocabulary;
@property(nonatomic, copy, nullable) NSString *sentenceNote;
@property(nonatomic, copy) NSArray<NSDictionary *> *structureParts;
@property(nonatomic, copy, nullable) NSString *structureTitle;
@property(nonatomic) FYAnalysisStatus status;
@property(nonatomic, copy, nullable) NSString *errorMessage;
// 分析结果携带其归属的句子身份，显示/收藏/追问都据此核对，防止旧结果串到新句。
@property(nonatomic, copy) NSString *sentenceID;
@property(nonatomic) NSInteger version;
@end

@interface FYGrammarBookmark : NSObject
@property(nonatomic, copy) NSString *bookmarkID;
@property(nonatomic, copy, nullable) NSString *catalogID;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *sentenceID;
@property(nonatomic) NSInteger version;
@property(nonatomic, copy) NSString *sourceTextSnapshot;
@property(nonatomic, copy, nullable) NSString *translationSnapshot;
@property(nonatomic, strong) NSDate *bookmarkedAt;
@end

@interface FYGrammarCatalogEntry : NSObject
@property(nonatomic, copy) NSString *catalogID;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSArray<NSString *> *aliases;
@property(nonatomic, copy, nullable) NSString *referenceLevel;
@property(nonatomic, copy, nullable) NSString *connection;
@property(nonatomic, copy, nullable) NSString *meaning;
@property(nonatomic, copy) NSString *contentOrigin;      // project_original / ...
@property(nonatomic, copy) NSArray<NSString *> *contentSourceIDs;
@property(nonatomic, copy) NSArray<NSString *> *referenceSources;
@property(nonatomic, copy) NSString *levelReviewStatus;  // verified / pending
@property(nonatomic, copy, nullable) NSString *reviewedAt;
@property(nonatomic, copy, nullable) NSString *sourceURL;
@property(nonatomic, copy, nullable) NSString *sourceTitle;
@end

NS_ASSUME_NONNULL_END
