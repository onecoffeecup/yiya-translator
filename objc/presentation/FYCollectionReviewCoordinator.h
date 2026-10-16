#pragma once
#import <Foundation/Foundation.h>
#import "../learning/FYLearningCoordinator.h"

// Native actions preserve the original individual label writes and refresh order.
@protocol FYCollectionReviewSource <NSObject>
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> * reviewList;
@property(nonatomic) NSInteger reviewIndex;
@property(nonatomic, strong) FYVocabularyEntry * reviewingEntry;
- (FYLearningStore *)learningStore;
- (void)refreshVocabularyList;
- (void)updateLearningCollectionSummary;
- (void)rebuildWordCards;
- (void)refreshGrammarBookmarks:(id)sender;
- (void)setReviewStatus:(FYReviewStatus)status;
- (void)setReviewPromptText:(NSString *)value;
- (void)setReviewWordText:(NSString *)value;
- (void)setReviewMeaningText:(NSString *)value;
- (void)setReviewWordHidden:(BOOL)value;
- (void)setReviewMeaningHidden:(BOOL)value;
- (void)setVocabularyEmptyHidden:(BOOL)value;
- (void)setVocabularyListHidden:(BOOL)value;
- (void)setVocabularyListText:(NSString *)value;
@end

// Sole owner of the existing review state; no idle host, UI or store reference.
@interface FYCollectionReviewCoordinator : NSObject
@property(nonatomic, strong) NSArray<FYVocabularyEntry *> * reviewList;
@property(nonatomic) NSInteger reviewIndex;
@property(nonatomic, strong) FYVocabularyEntry * reviewingEntry;
- (void)refreshVocabularyWithReceiver:(id<FYCollectionReviewSource>)receiver;
- (void)nextWordWithReceiver:(id<FYCollectionReviewSource>)receiver;
- (void)revealMeaningWithReceiver:(id<FYCollectionReviewSource>)receiver;
- (void)markKnownWithReceiver:(id<FYCollectionReviewSource>)receiver;
- (void)markLearningWithReceiver:(id<FYCollectionReviewSource>)receiver;
- (void)setStatus:(FYReviewStatus)status receiver:(id<FYCollectionReviewSource>)receiver;
- (void)removeWordWithReceiver:(id<FYCollectionReviewSource>)receiver;
@end
