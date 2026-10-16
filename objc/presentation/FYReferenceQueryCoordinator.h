#pragma once
#import <Foundation/Foundation.h>
#import "../learning/FYReferenceDictionary.h"

@protocol FYReferenceQuerySource <NSObject>
@property(nonatomic) NSInteger referenceRequestGeneration;
@property(nonatomic, copy) NSString * referenceActiveWord;
@property(nonatomic, copy) NSArray<NSDictionary *> * referenceRecords;
@property(nonatomic, strong) FYReferenceDictionary * referenceDictionary;
- (BOOL)hasReferenceStack;
- (FYReferenceDictionary *)makeReferenceDictionary;
- (void)setReferenceSearchText:(NSString *)text;
- (void)clearReferenceRows;
- (void)showReferenceLoadingWord:(NSString *)word;
- (void)showReferenceEmptyWord:(NSString *)word error:(NSError *)error;
- (void)renderReferenceRecords:(NSArray<NSDictionary *> *)records;
@end

// Original query generation/snapshots and the single dictionary shared with hover.
@interface FYReferenceQueryCoordinator : NSObject
@property(nonatomic) NSInteger referenceRequestGeneration;
@property(nonatomic, copy) NSString * referenceActiveWord;
@property(nonatomic, copy) NSArray<NSDictionary *> * referenceRecords;
@property(nonatomic, strong) FYReferenceDictionary * referenceDictionary;
- (void)lookupWord:(NSString *)word reading:(NSString *)reading receiver:(id<FYReferenceQuerySource>)receiver;
@end
