#pragma once
#import "FYOCRTextModels.h"
@interface FYOCRTextProcessing : NSObject
+ (NSString *)postprocessedTextForItems:(NSArray<OCRTextItem *> *)items renderedTexts:(NSSet<NSString *> *)renderedTexts blocks:(NSArray<OCRTextItem *> **)outBlocks;
+ (NSString *)sourceTextForItems:(NSArray<OCRTextItem *> *)items blocks:(NSArray<OCRTextItem *> **)outBlocks;
+ (BOOL)isOwnOverlayText:(NSString *)raw;
+ (NSArray<OCRTextItem *> *)itemsExcludingOwnOverlay:(NSArray<OCRTextItem *> *)items
                                     renderedTexts:(NSSet<NSString *> *)renderedTexts;
+ (NSSet<NSString *> *)renderedTranslationSetForCaption:(NSString *)captionText inlineCache:(NSDictionary *)inlineCache;
+ (NSArray<OCRTextItem *> *)splitMultilineItems:(NSArray<OCRTextItem *> *)items;
+ (NSString *)textFromRecognizedLines:(NSArray<NSString *> *)lines;
@end
