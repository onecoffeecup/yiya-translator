#pragma once
#import <Foundation/Foundation.h>
#import "../learning/FYLearningCoordinator.h"

@protocol FYCollectionCardSource <NSObject>
@property(nonatomic, strong) NSMutableSet<NSString *> * expandedWordCards;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> * revealedMeanings;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> * wordExampleIndices;
- (NSArray<FYVocabularyEntry *> *)reviewList;
- (FYLearningStore *)learningStore;
- (void)setReviewPromptText:(NSString *)text;
- (void)refreshVocabularyList;
- (void)rebuildWordCards;
@end

// Original state and algorithms, with synchronous input providers; no idle receiver/store.
@interface FYCollectionCardCoordinator : NSObject
@property(nonatomic, strong) NSMutableSet<NSString *> * expandedWordCards;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> * revealedMeanings;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> * wordExampleIndices;
- (FYVocabularyEntry *)wordWithReceiver:(id<FYCollectionCardSource>)receiver identifier:(NSString *(^)(void))identifier tag:(NSInteger(^)(void))tag;
- (void)nextExampleWithReceiver:(id<FYCollectionCardSource>)receiver identifier:(NSString *(^)(void))identifier;
- (void)toggleDetailsWithReceiver:(id<FYCollectionCardSource>)receiver word:(FYVocabularyEntry *(^)(void))word update:(void(^)(BOOL))update;
- (void)toggleMeaningWithReceiver:(id<FYCollectionCardSource>)receiver word:(FYVocabularyEntry *(^)(void))word update:(void(^)(FYVocabularyEntry *,BOOL))update;
- (void)toggleMasteredWithReceiver:(id<FYCollectionCardSource>)receiver word:(FYVocabularyEntry *(^)(void))word;
- (void)removeWordWithReceiver:(id<FYCollectionCardSource>)receiver word:(FYVocabularyEntry *(^)(void))word;
@end
