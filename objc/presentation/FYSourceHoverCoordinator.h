#pragma once
#import <Foundation/Foundation.h>
#import "../learning/FYLearningModels.h"
#import "../learning/FYReferenceDictionary.h"
#import "../learning/FYJapaneseTokenizer.h"

// View handles stay opaque; text/editability and native attributes cross explicit adapters.
@protocol FYSourceHoverSource <NSObject>
@property(nonatomic) NSUInteger sourceHoverGeneration;
@property(nonatomic) NSUInteger quickSourceHoverGeneration;
@property(nonatomic, strong) NSCache<NSString *,NSString *> * sourceHoverCache;
@property(nonatomic) BOOL sourceHoverSuspended;
- (FYReferenceDictionary *)referenceDictionary;
- (void)setReferenceDictionary:(FYReferenceDictionary *)value;
- (FYReferenceDictionary *)makeReferenceDictionary;
- (FYJapaneseTokenizer *)japaneseTokenizer;
- (void)setJapaneseTokenizer:(FYJapaneseTokenizer *)value;
- (NSString *)mainHoverText;
- (BOOL)mainHoverEditable;
- (NSArray *)mainHoverViews;
- (id<NSObject>)quickHoverView;
- (NSString *)hoverTextForView:(id<NSObject>)view;
- (BOOL)hoverEditableForView:(id<NSObject>)view;
- (NSString *)quickSentenceID;
- (NSInteger)quickSentenceVersion;
- (BOOL)quickSentenceRequested;
- (NSString *)quickSentenceSource;
- (NSString *)quickSentenceAnalysisSource;
- (FYAnalysisResult *)quickSentenceAnalysis;
- (FYAnalysisResult *)currentAnalysis;
- (BOOL)analysisMatchesCurrentSentence;
- (void)clearSourceHoverAttributes:(NSArray *)views;
- (void)setSourceHoverTip:(NSString *)tip range:(NSRange)range source:(NSString *)source views:(NSArray *)views;
- (void)applyAnalysisHoverTips:(FYAnalysisResult *)analysis source:(NSString *)source views:(NSArray *)views;
- (void)populateSourceHoverTips:(NSString *)source views:(NSArray *)views analysis:(FYAnalysisResult *)analysis fallback:(NSString *)fallback isCurrent:(BOOL(^)(void))isCurrent;
@end

@interface FYSourceHoverCoordinator : NSObject
@property(nonatomic) NSUInteger sourceHoverGeneration;
@property(nonatomic) NSUInteger quickSourceHoverGeneration;
@property(nonatomic, strong) NSCache<NSString *,NSString *> * sourceHoverCache;
@property(nonatomic) BOOL sourceHoverSuspended;
- (void)applyAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source views:(NSArray *)views receiver:(id<FYSourceHoverSource>)receiver;
- (void)populateSource:(NSString *)source views:(NSArray *)views analysis:(FYAnalysisResult *)analysis fallback:(NSString *)fallback isCurrent:(BOOL(^)(void))isCurrent receiver:(id<FYSourceHoverSource>)receiver;
- (void)refreshMainWithReceiver:(id<FYSourceHoverSource>)receiver;
- (void)refreshQuickWithReceiver:(id<FYSourceHoverSource>)receiver;
@end
