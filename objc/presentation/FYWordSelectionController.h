#pragma once
#import <Foundation/Foundation.h>
#import "FYDisplayedSentenceState.h"
#import "../learning/FYLearningCoordinator.h"
@protocol FYWordSelectionStateSource <NSObject>
@property(nonatomic, copy) NSString *displayedSentenceID;
@property(nonatomic, copy) NSString *displayedSourceText;
@property(nonatomic, copy, nullable) NSString *displayedTranslation;
@property(nonatomic) NSInteger displayedVersion;
@property(nonatomic) NSInteger vocabSelectionGeneration;
@property(nonatomic) BOOL savingVocabulary;
@property(nonatomic) BOOL vocabCompletionFromAI;
@property(nonatomic) NSInteger referenceRequestGeneration;
@property(nonatomic,copy) NSString *referenceActiveWord;
@end
@protocol FYWordSelectionServices <NSObject>
@property(nonatomic,strong,readonly) FYLearningCoordinator *learningCoordinator;
@property(nonatomic,strong,readonly) FYJapaneseTokenizer *japaneseTokenizer;
@end
@protocol FYWordSelectionTextSource <NSObject>
- (NSString *)wordSelectionText;
- (NSRange)wordSelectionRange;
- (BOOL)wordSelectionTracking;
- (NSString *)wordLemmaInput;
- (NSString *)wordReadingInput;
- (NSString *)wordMeaningInput;
@end
@protocol FYWordSelectionNativeActions <NSObject>
- (void)setWordSelectionRange:(NSRange)range;
- (void)setWordPickHidden:(BOOL)hidden;
- (void)setWordLemma:(NSString *)value;
- (void)setWordReading:(NSString *)value;
- (void)setWordMeaning:(NSString *)value;
- (void)setWordStatus:(NSString *)value;
- (void)setWordSelectionLabel:(NSString *)value;
- (void)setWordSurfaceLabel:(NSString *)value;
@end
@protocol FYWordSelectionPeerActions <NSObject>
- (void)pinLearningSentence:(id)sender;
- (void)followLatestSentence:(id)sender;
- (void)syncCoordinatorToDisplayed;
- (NSString *)selectedLearningText;
- (void)clearAnalysisDisplay;
- (void)refreshVocabularyList;
- (void)wordHostRefreshLearningStatus;
- (void)wordHostRefreshLearningSource;
@end
@protocol FYWordSelectionSource <FYWordSelectionStateSource,FYWordSelectionServices,FYWordSelectionTextSource,FYWordSelectionNativeActions,FYWordSelectionPeerActions>
@end
@interface FYWordSelectionController : NSObject
@property(nonatomic) NSInteger vocabSelectionGeneration;
@property(nonatomic) BOOL savingVocabulary;
@property(nonatomic) BOOL vocabCompletionFromAI;
- (void)toggleLearningPin:(id)sender source:(id<FYWordSelectionSource>)source;
- (void)vocabularyFormChanged:(id)sender source:(id<FYWordSelectionSource>)source;
- (void)freezeLearningSentenceForSelectionWithSource:(id<FYWordSelectionSource>)source;
- (void)selectWordAtCharacterIndex:(NSUInteger)characterIndex source:(id<FYWordSelectionSource>)source;
- (void)updateWordPickForSelectionWithSource:(id<FYWordSelectionSource>)source;
- (void)closeWordPick:(id)sender source:(id<FYWordSelectionSource>)source;
- (void)pinLearningSentence:(id)sender source:(id<FYWordSelectionSource>)source;
- (void)followLatestSentence:(id)sender source:(id<FYWordSelectionSource>)source;
- (NSString *)selectedLearningTextWithSource:(id<FYWordSelectionSource>)source;
- (void)bookmarkSelectedVocabulary:(id)sender source:(id<FYWordSelectionSource>)source;
- (void)completeSelectedVocabulary:(id)sender source:(id<FYWordSelectionSource>)source;
- (void)syncCoordinatorToDisplayedWithSource:(id<FYWordSelectionSource>)source;
@end
