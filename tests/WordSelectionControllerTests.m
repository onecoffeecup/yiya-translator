#import "presentation/FYWordSelectionController.h"
#import "FYWordSelectionTestServices.h"
#import <objc/runtime.h>
@interface SelectionSourceFact : NSObject <FYWordSelectionSource>
@property(nonatomic,strong) FYDisplayedSentenceState *display;
@property(nonatomic,strong) FYWordSelectionController *words;
@property(nonatomic,strong) SelectionLearningFact *learning;
@property(nonatomic,strong) SelectionTokenizerFact *tokenizer;
@property(nonatomic) NSInteger referenceRequestGeneration;
@property(nonatomic,copy) NSString *referenceActiveWord;
@property(nonatomic,strong) NSString *text;
@property(nonatomic) NSRange range;
@property(nonatomic) BOOL tracking,hidden;
@property(nonatomic,copy) NSString *lemma,*reading,*meaning,*status,*selectionLabel,*surfaceLabel;
@property(nonatomic) NSUInteger rangeWrites,historyRefreshes,statusRefreshes,clears,listRefreshes,textReads;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@end
@implementation SelectionSourceFact
@dynamic displayedSentenceID,displayedSourceText,displayedTranslation,displayedVersion,vocabSelectionGeneration,savingVocabulary,vocabCompletionFromAI;
- (instancetype)init{if((self=[super init])){self.display=[FYDisplayedSentenceState new];self.words=[FYWordSelectionController new];self.learning=[SelectionLearningFact new];self.tokenizer=[SelectionTokenizerFact new];self.trace=[NSMutableArray new];self.displayedSentenceID=@"sentence";self.displayedVersion=1;self.displayedSourceText=@"ああ";self.displayedTranslation=@"synthetic";self.learning.currentSentenceID=@"sentence";self.learning.currentVersion=1;self.learning.currentSourceText=@"ああ";self.text=@"ああ";self.range=NSMakeRange(0,1);}return self;}
- (NSString *)displayedSentenceID{return self.display.displayedSentenceID;}
- (void)setDisplayedSentenceID:(NSString *)v{self.display.displayedSentenceID=v;}
- (NSString *)displayedSourceText{return self.display.displayedSourceText;}
- (void)setDisplayedSourceText:(NSString *)v{self.display.displayedSourceText=v;}
- (NSString *)displayedTranslation{return self.display.displayedTranslation;}
- (void)setDisplayedTranslation:(NSString *)v{self.display.displayedTranslation=v;}
- (NSInteger)displayedVersion{return self.display.displayedVersion;}
- (void)setDisplayedVersion:(NSInteger)v{self.display.displayedVersion=v;}
- (NSInteger)vocabSelectionGeneration{return self.words.vocabSelectionGeneration;}
- (void)setVocabSelectionGeneration:(NSInteger)v{self.words.vocabSelectionGeneration=v;[self.trace addObject:@"generation"];}
- (BOOL)savingVocabulary{return self.words.savingVocabulary;}
- (void)setSavingVocabulary:(BOOL)v{self.words.savingVocabulary=v;[self.trace addObject:v?@"saving-yes":@"saving-no"];}
- (BOOL)vocabCompletionFromAI{return self.words.vocabCompletionFromAI;}
- (void)setVocabCompletionFromAI:(BOOL)v{self.words.vocabCompletionFromAI=v;}
- (FYLearningCoordinator *)learningCoordinator{return (FYLearningCoordinator *)self.learning;}
- (FYJapaneseTokenizer *)japaneseTokenizer{return (FYJapaneseTokenizer *)self.tokenizer;}
- (NSString *)wordSelectionText{self.textReads++;return self.text;}
- (NSRange)wordSelectionRange{return self.range;}
- (BOOL)wordSelectionTracking{return self.tracking;}
- (NSString *)wordLemmaInput{return self.lemma;}
- (NSString *)wordReadingInput{return self.reading;}
- (NSString *)wordMeaningInput{return self.meaning;}
- (void)setWordSelectionRange:(NSRange)v{self.range=v;self.rangeWrites++;}
- (void)setWordPickHidden:(BOOL)v{self.hidden=v;[self.trace addObject:v?@"hide":@"show"];}
- (void)setWordLemma:(NSString *)v{self.lemma=v;[self.trace addObject:@"lemma"];}
- (void)setWordReading:(NSString *)v{self.reading=v;[self.trace addObject:@"reading"];}
- (void)setWordMeaning:(NSString *)v{self.meaning=v;[self.trace addObject:@"meaning"];}
- (void)setWordStatus:(NSString *)v{self.status=v;[self.trace addObject:@"status"];}
- (void)setWordSelectionLabel:(NSString *)v{self.selectionLabel=v;}
- (void)setWordSurfaceLabel:(NSString *)v{self.surfaceLabel=v;}
- (void)pinLearningSentence:(id)sender{[self.words pinLearningSentence:sender source:self];}
- (void)followLatestSentence:(id)sender{[self.words followLatestSentence:sender source:self];}
- (void)syncCoordinatorToDisplayed{[self.trace addObject:@"sync"];[self.words syncCoordinatorToDisplayedWithSource:self];}
- (NSString *)selectedLearningText{return [self.words selectedLearningTextWithSource:self];}
- (void)clearAnalysisDisplay{self.clears++;[self.trace addObject:@"clear"];}
- (void)refreshVocabularyList{self.listRefreshes++;[self.trace addObject:@"list"];}
- (void)wordHostRefreshLearningStatus{self.statusRefreshes++;[self.trace addObject:@"host-status"];}
- (void)wordHostRefreshLearningSource{self.historyRefreshes++;[self.trace addObject:@"host-source"];}
@end
static void ReplyToken(SelectionTokenizerFact *t,NSUInteger index,NSRange range){void (^reply)(NSRange)=[t.replies[index]copy];[t.replies removeObjectAtIndex:index];reply(range);}
int main(void){@autoreleasepool{
 Check(NSClassFromString(@"NSPanel")==Nil,@"Foundation interaction minimum link excludes AppKit/UI");unsigned int displayCount=0,wordCount=0;Ivar *di=class_copyIvarList(FYDisplayedSentenceState.class,&displayCount);Ivar *wi=class_copyIvarList(FYWordSelectionController.class,&wordCount);free(di);free(wi);FYDisplayedSentenceState *cold=[FYDisplayedSentenceState new];FYWordSelectionController *empty=[FYWordSelectionController new];Check(displayCount==4&&wordCount==3&&!cold.displayedSentenceID&&!cold.displayedVersion&&!empty.vocabSelectionGeneration&&!empty.savingVocabulary&&!empty.vocabCompletionFromAI,@"cold exact displayed4/word3 original states with no retained source/services");NSMutableString *mutable=[@"copy"mutableCopy];cold.displayedSentenceID=mutable;cold.displayedSourceText=mutable;cold.displayedTranslation=mutable;[mutable appendString:@"changed"];Check([cold.displayedSentenceID isEqual:@"copy"]&&[cold.displayedSourceText isEqual:@"copy"]&&[cold.displayedTranslation isEqual:@"copy"],@"display model preserves all three original copy properties");
 SelectionSourceFact *s=[SelectionSourceFact new];s.range=NSMakeRange(NSNotFound,1);s.textReads=0;Check([[s selectedLearningText]isEqual:@""]&&s.textReads==0,@"NotFound selection returns before text read");s.range=NSMakeRange(0,0);Check([[s selectedLearningText]isEqual:@""]&&s.textReads==0,@"empty selection returns before text read");s.range=NSMakeRange(2,1);Check([[s selectedLearningText]isEqual:@""],@"out-of-bounds selection returns empty");s.range=NSMakeRange(1,1);Check([[s selectedLearningText]isEqual:@"あ"],@"selection uses original UTF16 range and substring");
 s.tracking=YES;s.lemma=@"held";[s.words updateWordPickForSelectionWithSource:s];Check([s.lemma isEqual:@"held"]&&!s.trace.count,@"tracking guard precedes form clearing");s.tracking=NO;s.vocabCompletionFromAI=YES;[s.words updateWordPickForSelectionWithSource:s];Check([[s.trace componentsJoinedByString:@","]isEqual:@"lemma,reading,meaning,show"]&&!s.vocabCompletionFromAI&&[s.surfaceLabel isEqual:@"遇到的词形：あ"],@"pick clears three form values/AI before showing original selected shape");[s.words closeWordPick:nil source:s];Check(s.hidden&&s.range.location==1&&!s.range.length&&s.rangeWrites==1,@"close clears length while keeping original location");
 s.displayedSentenceID=@"";s.range=NSMakeRange(0,1);s.referenceActiveWord=@"old";[s.words freezeLearningSentenceForSelectionWithSource:s];Check(s.vocabSelectionGeneration==1&&s.referenceRequestGeneration==1&&[s.referenceActiveWord isEqual:@""]&&!s.learning.pins,@"empty freeze still advances both generations/clears reference before guard");s.displayedSentenceID=@"visible";s.displayedVersion=2;[s.words freezeLearningSentenceForSelectionWithSource:s];Check(s.learning.selects==1&&[s.learning.currentSentenceID isEqual:@"visible"]&&s.learning.currentVersion==2&&s.learning.pins==1&&s.statusRefreshes==1,@"valid freeze syncs exact displayed identity/version then pin/Host status");[s.words syncCoordinatorToDisplayedWithSource:s];Check(s.learning.selects==1,@"already matching display avoids reselection");s.learning.pinned=NO;[s.words toggleLearningPin:nil source:s];Check(s.learning.pins==2,@"toggle not pinned delegates original pin helper");s.learning.pinned=YES;[s.trace removeAllObjects];[s.words toggleLearningPin:nil source:s];Check(s.clears==1&&s.learning.follows==1&&[s.trace.firstObject isEqual:@"clear"],@"toggle pinned clears analysis then starts original follow");s.learning.followReply();s.learning.followReply=nil;Check(s.historyRefreshes==1&&s.statusRefreshes==3,@"follow weak callback invokes original Host source then status");
 [s.words vocabularyFormChanged:nil source:s];Check(!s.vocabCompletionFromAI&&[s.selectionLabel isEqual:@"手动填写；原形、读音和释义均可留空。"],@"manual form invalidates AI state and retains original hint");
 NSMutableString *original=[@"ああ"mutableCopy];s.text=original;s.displayedSentenceID=s.learning.currentSentenceID;s.displayedVersion=s.learning.currentVersion;[s.words selectWordAtCharacterIndex:1 source:s];Check([s.tokenizer.text isEqual:@"ああ"]&&s.tokenizer.location==1,@"tokenizer receives copied submitted text and original char location");[original appendString:@"変"];ReplyToken(s.tokenizer,0,NSMakeRange(1,1));Check(s.rangeWrites==1,@"changed current text rejects stale tokenizer range");s.text=@"ああ";[s.words selectWordAtCharacterIndex:0 source:s];[s.words selectWordAtCharacterIndex:1 source:s];ReplyToken(s.tokenizer,0,NSMakeRange(0,1));Check(s.rangeWrites==1,@"older tokenizer generation rejected");ReplyToken(s.tokenizer,0,NSMakeRange(1,1));Check(s.rangeWrites==2&&s.range.location==1,@"latest same sentence/version/text token range applies through actual learning gate");
 s.range=NSMakeRange(0,0);[s.words bookmarkSelectedVocabulary:nil source:s];Check(!s.savingVocabulary&&s.learning.bookmarks==0&&[s.status hasPrefix:@"请先"],@"empty bookmark reports original hint without busy/submission");s.range=NSMakeRange(0,1);s.lemma=@"  lemma \n";s.reading=@" read ";s.meaning=@" mean ";s.vocabCompletionFromAI=YES;[s.words bookmarkSelectedVocabulary:nil source:s];Check(s.savingVocabulary&&s.learning.bookmarks==1&&[s.learning.submitted.surface isEqual:@"あ"]&&[s.learning.submitted.lemma isEqual:@"lemma"]&&[s.learning.submitted.reading isEqual:@"read"]&&[s.learning.submitted.meaning isEqual:@"mean"]&&s.learning.submitted.kind==FYVocabularyKindWord&&s.learning.submitted.reviewStatus==FYReviewStatusNew&&s.learning.submitted.completionSource==FYCompletionSourceAI,@"actual bookmark builds original trimmed model/enums and busy lease");[s.words bookmarkSelectedVocabulary:nil source:s];Check(s.learning.bookmarks==1,@"busy bookmark does not create second task");s.vocabSelectionGeneration++;[s.trace removeAllObjects];s.learning.bookmarkReply(Suggestion(),NO,nil);s.learning.bookmarkReply=nil;Check(!s.savingVocabulary&&[[s.trace componentsJoinedByString:@","]isEqual:@"saving-no,list"],@"stale bookmark first clears original busy then only refreshes list");[s.words bookmarkSelectedVocabulary:nil source:s];s.learning.bookmarkReply(Suggestion(),YES,nil);s.learning.bookmarkReply=nil;Check([s.status isEqual:@"已有词条「あ」，已追加例句。"]&&!s.savingVocabulary,@"current duplicate completion preserves original success text");
 s.range=NSMakeRange(0,1);BOOL oldAI=s.vocabCompletionFromAI;[s.words completeSelectedVocabulary:nil source:s];Check(s.learning.completions==1&&[s.learning.completionContext isEqual:s.learning.currentSourceText]&&[s.status isEqual:@"正在补全读音与释义…"],@"AI uses original current sentence context and captures range/generation");s.range=NSMakeRange(1,1);s.learning.completionReply(Suggestion(),nil);s.learning.completionReply=nil;Check(![s.lemma isEqual:@"原形"]&&s.vocabCompletionFromAI==oldAI,@"different occurrence range rejects same-text AI response");
 s.range=NSMakeRange(0,1);[s.words completeSelectedVocabulary:nil source:s];s.learning.completionReply(Suggestion(),nil);s.learning.completionReply=nil;Check([s.lemma isEqual:@"原形"]&&[s.reading isEqual:@"読み"]&&[s.meaning isEqual:@"意思"]&&s.vocabCompletionFromAI&&[s.selectionLabel hasPrefix:@"あ（AI 建议"],@"current AI result fills original three fields/AI state/hints");[s.words completeSelectedVocabulary:nil source:s];s.vocabSelectionGeneration++;NSString *held=s.status;s.learning.completionReply(Suggestion(),nil);s.learning.completionReply=nil;Check(s.status==held,@"changed generation rejects late AI without UI writes");
 SelectionTokenizerFact *token=[SelectionTokenizerFact new];__weak SelectionSourceFact *strongTokenSource;@autoreleasepool{SelectionSourceFact *q=[SelectionSourceFact new];q.tokenizer=token;strongTokenSource=q;[q.words selectWordAtCharacterIndex:0 source:q];}@autoreleasepool{Check(strongTokenSource!=nil,@"tokenizer callback preserves original strong concrete source task lease");ReplyToken(token,0,NSMakeRange(0,1));}Check(!strongTokenSource,@"tokenizer source lease releases after held callback finishes");
 SelectionLearningFact *learning=[SelectionLearningFact new];__weak SelectionSourceFact *strongSaveSource;@autoreleasepool{SelectionSourceFact *q=[SelectionSourceFact new];q.learning=learning;strongSaveSource=q;[q.words bookmarkSelectedVocabulary:nil source:q];}@autoreleasepool{Check(strongSaveSource!=nil,@"bookmark callback preserves original strong source lease");void (^reply)(FYVocabularyEntry *,BOOL,NSError *)=[learning.bookmarkReply copy];learning.bookmarkReply=nil;reply(Suggestion(),NO,nil);}Check(!strongSaveSource,@"bookmark lease releases after callback finishes");
 __weak SelectionSourceFact *weakAI;@autoreleasepool{SelectionSourceFact *q=[SelectionSourceFact new];q.learning=learning;learning.currentSentenceID=q.displayedSentenceID;learning.currentVersion=q.displayedVersion;learning.currentSourceText=q.text;weakAI=q;[q.words completeSelectedVocabulary:nil source:q];}Check(!weakAI,@"AI callback remains weak and does not retain source");learning.completionReply(Suggestion(),nil);learning.completionReply=nil;
 __weak SelectionSourceFact *weakFollow;@autoreleasepool{SelectionSourceFact *q=[SelectionSourceFact new];q.learning=learning;weakFollow=q;[q.words followLatestSentence:nil source:q];}Check(!weakFollow,@"follow callback remains weak and does not retain source");learning.followReply();learning.followReply=nil;
 Check(NSClassFromString(@"NSPanel")==Nil,@"all actual interaction algorithms remain Foundation only,synthetic services,no UI/database/API");printf("PASS WordSelectionControllerTests: %lu checks;actual state/range/generation/entry/callback algorithms and learning gates,no UI/services\n",(unsigned long)checks);
}return 0;}
