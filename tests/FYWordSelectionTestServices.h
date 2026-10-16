#import <Foundation/Foundation.h>
#import "learning/FYLearningCoordinator.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface SelectionTokenizerFact : NSObject
@property(nonatomic,strong) NSMutableArray *replies;
@property(nonatomic,copy) NSString *text;
@property(nonatomic) NSUInteger location;
@end
@implementation SelectionTokenizerFact
- (instancetype)init{if((self=[super init]))self.replies=[NSMutableArray new];return self;}
- (void)rangeForLocation:(NSUInteger)location inText:(NSString *)text completion:(void (^)(NSRange))reply{self.location=location;self.text=text;[self.replies addObject:[reply copy]];}
@end
@interface SelectionLearningFact : NSObject
@property(nonatomic,copy) NSString *currentSentenceID,*currentSourceText,*currentTranslation;
@property(nonatomic) NSInteger currentVersion;
@property(nonatomic,getter=isPinned) BOOL pinned;
@property(nonatomic) NSUInteger pins,selects,bookmarks,completions,follows;
@property(nonatomic,strong) FYVocabularyEntry *submitted;
@property(nonatomic,copy) NSString *selectedText,*completionContext;
@property(nonatomic,copy) void (^bookmarkReply)(FYVocabularyEntry *,BOOL,NSError *);
@property(nonatomic,copy) void (^completionReply)(FYVocabularyEntry *,NSError *);
@property(nonatomic,copy) void (^followReply)(void);
@end
@implementation SelectionLearningFact
- (void)pinCurrent{self.pins++;self.pinned=YES;}
- (void)selectSentenceID:(NSString *)identity version:(NSInteger)v sourceText:(NSString *)s translation:(NSString *)t{self.selects++;self.currentSentenceID=identity;self.currentVersion=v;self.currentSourceText=s;self.currentTranslation=t;}
- (void)followLatestWithCompletion:(void (^)(void))reply{self.follows++;self.followReply=reply;}
- (void)bookmarkVocabulary:(FYVocabularyEntry *)entry selectedText:(NSString *)text completion:(void (^)(FYVocabularyEntry *,BOOL,NSError *))reply{self.bookmarks++;self.submitted=entry;self.selectedText=text;self.bookmarkReply=reply;}
- (void)completeVocabulary:(NSString *)selected context:(NSString *)context completion:(void (^)(FYVocabularyEntry *,NSError *))reply{self.completions++;self.selectedText=selected;self.completionContext=context;self.completionReply=reply;}
@end
static FYVocabularyEntry *Suggestion(void){FYVocabularyEntry *e=[FYVocabularyEntry new];e.surface=@"あ";e.lemma=@"原形";e.reading=@"読み";e.meaning=@"意思";return e;}
