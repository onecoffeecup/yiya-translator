#import "FYOCRManager.h"
#import "FYInlineLayoutDebug.h"


@implementation FYOCRManager
@synthesize visionEngine = _visionEngine;
@dynamic configurationObserver;
- (FYOCRVisionEngine *)visionEngine {
    if (!_visionEngine) _visionEngine = [FYOCRVisionEngine new];
    return _visionEngine;
}
- (void (^)(BOOL,NSInteger,size_t,size_t,CGFloat))configurationObserver { return self.visionEngine.configurationObserver; }
- (void)setConfigurationObserver:(void (^)(BOOL,NSInteger,size_t,size_t,CGFloat))value { self.visionEngine.configurationObserver = value; }

// A structural label needs both a separate filled backdrop and a following
// dialogue body. Text length/script alone must never suppress spoken lines.
// This operates on the existing downsampled source pixels; no extra OCR,
// screenshots, stored images or game-specific colors are used.
+ (NSArray<OCRTextItem *> *)itemsByMarkingSpeakerLabels:(NSArray<OCRTextItem *> *)items inImage:(CGImageRef)image { return [FYOCRPixelAnalysis itemsByMarkingSpeakerLabels:items inImage:image]; }
+ (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString **)outSpeaker body:(NSString **)outBody {
    NSString *speaker=nil,*body=text ?: @"";
    NSArray<NSString *> *lines=[body componentsSeparatedByString:@"\n"];
    if (lines.count>=2) {
        NSString *first=[lines.firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (first.length>0 && ([self looksLikeSpeakerName:first] || [self looksLikeSpeakerFurigana:first])) {
            NSUInteger consumed=1;speaker=first;
            if (lines.count>=3) {
                NSString *second=[lines[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if ([self looksLikeSpeakerFurigana:first] && [self looksLikeSpeakerName:second]) {
                    speaker=[NSString stringWithFormat:@"%@ %@",first,second];consumed=2;
                }
            }
            body=[[lines subarrayWithRange:NSMakeRange(consumed,lines.count-consumed)] componentsJoinedByString:@"\n"];
        }
    }
    if (outSpeaker) *outSpeaker=speaker;
    if (outBody) *outBody=body;
}
+ (NSString *)postprocessedTextForItems:(NSArray<OCRTextItem *> *)items renderedTexts:(NSSet<NSString *> *)renderedTexts blocks:(NSArray<OCRTextItem *> **)outBlocks { return [FYOCRTextProcessing postprocessedTextForItems:items renderedTexts:renderedTexts blocks:outBlocks]; }
+ (NSString *)sourceTextForItems:(NSArray<OCRTextItem *> *)items blocks:(NSArray<OCRTextItem *> **)outBlocks { return [FYOCRTextProcessing sourceTextForItems:items blocks:outBlocks]; }
+ (NSString *)recognizeEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region recognizer:(NSString *(^)(CGImageRef,NSArray<OCRTextItem *> **,NSError **))recognizer blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error {
    return [FYOCRImageGeometry recognizeEnlargedImage:image visionRegion:region recognizer:recognizer cropScope:^(CGRect crop,CGSize size,void(^work)(void)) { FYLayoutDebugPerformCrop(crop,size,work); } blocks:outBlocks error:error];
}
+ (NSArray<OCRTextItem *> *)items:(NSArray<OCRTextItem *> *)items scopedToModalInImage:(CGImageRef)image exclusions:(NSArray<NSValue *> *)exclusions { return [FYOCRPixelAnalysis items:items scopedToModalInImage:image exclusions:exclusions]; }

+ (NSArray<OCRTextItem *> *)items:(NSArray<OCRTextItem *> *)items inModalRegion:(CGRect)region exclusions:(NSArray<NSValue *> *)exclusions { return [FYOCRPixelAnalysis items:items inModalRegion:region exclusions:exclusions]; }

// Compatibility content-policy API delegates to FYContentRouter.
+ (NSInteger)contentModeForItems:(NSArray<OCRTextItem *> *)blocks fallback:(NSInteger)fallbackSegment {
    return [FYContentRouter contentModeForItems:blocks fallback:fallbackSegment];
}

+ (BOOL)looksLikeSpeakerName:(NSString *)raw {
    return [FYContentRouter looksLikeSpeakerName:raw];
}

+ (BOOL)looksLikeSpeakerFurigana:(NSString *)raw {
    return [FYContentRouter looksLikeSpeakerFurigana:raw];
}

+ (BOOL)looksLikeSpeakerLabelCluster:(NSArray<OCRTextItem *> *)cluster {
    return [FYContentRouter looksLikeSpeakerLabelCluster:cluster];
}

+ (BOOL)isSpeakerLabelItem:(OCRTextItem *)item inPool:(NSArray<OCRTextItem *> *)pool {
    return [FYContentRouter isSpeakerLabelItem:item inPool:pool];
}

+ (BOOL)dialogueFrameIsSpeakerLabelOnly:(NSArray<NSString *> *)lines {
    return [FYContentRouter dialogueFrameIsSpeakerLabelOnly:lines];
}

+ (void)splitDialogueAndOptions:(NSArray<OCRTextItem *> *)band
                     allBlocks:(NSArray<OCRTextItem *> *)allBlocks
                      dialogue:(NSMutableArray<OCRTextItem *> *)outDialogue
                       options:(NSMutableArray<OCRTextItem *> *)outOptions {
    [FYContentRouter splitDialogueAndOptions:band allBlocks:allBlocks dialogue:outDialogue options:outOptions];
}

+ (BOOL)containsJapaneseKana:(NSString *)value {
    return [FYContentRouter containsJapaneseKana:value];
}

+ (BOOL)isFormedTextLine:(OCRTextItem *)block {
    return [FYContentRouter isFormedTextLine:block];
}

+ (BOOL)isShortDialogueAnchor:(OCRTextItem *)block {
    return [FYContentRouter isShortDialogueAnchor:block];
}

+ (BOOL)isUnpunctuatedSingleLineDialogue:(NSString *)text box:(CGRect)box {
    return [FYContentRouter isUnpunctuatedSingleLineDialogue:text box:box];
}

+ (BOOL)isCornerHelpButton:(OCRTextItem *)block {
    return [FYContentRouter isCornerHelpButton:block];
}

+ (BOOL)isSingleLineDialogue:(OCRTextItem *)block {
    return [FYContentRouter isSingleLineDialogue:block];
}

+ (BOOL)isDialogueAnchor:(OCRTextItem *)block {
    return [FYContentRouter isDialogueAnchor:block];
}

+ (NSArray<OCRTextItem *> *)subtitleBandItems:(NSArray<OCRTextItem *> *)blocks {
    return [FYContentRouter subtitleBandItems:blocks];
}

+ (BOOL)textHitsUIToken:(NSString *)text {
    return [FYContentRouter textHitsUIToken:text];
}

+ (NSUInteger)UITokenHitCount:(NSArray<OCRTextItem *> *)blocks {
    return [FYContentRouter UITokenHitCount:blocks];
}

+ (BOOL)isFurigana:(OCRTextItem *)small nearLargerLineInItems:(NSArray<OCRTextItem *> *)blocks {
    return [FYContentRouter isFurigana:small nearLargerLineInItems:blocks];
}

+ (BOOL)looksLikeUIFrame:(NSArray<OCRTextItem *> *)blocks {
    return [FYContentRouter looksLikeUIFrame:blocks];
}

+ (NSString *)dialogueTextWithoutTrailingButton:(NSString *)text {
    return [FYContentRouter dialogueTextWithoutTrailingButton:text];
}

+ (CGImageRef)copyEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region pixelCrop:(CGRect *)outCrop { return [FYOCRImageGeometry copyEnlargedImage:image visionRegion:region pixelCrop:outCrop]; }

+ (void)remapItems:(NSArray<OCRTextItem *> *)items fromPixelCrop:(CGRect)crop imageSize:(CGSize)size { [FYOCRImageGeometry remapItems:items fromPixelCrop:crop imageSize:size]; }

// 这两串是「译芽」自己画在屏幕上的状态栏文字（状态行 + 句数行）。
// 它们常常正好压在目标窗口上（实测在左下角），于是被下一轮 OCR 读回来当成正文：
// 混进字幕带、占住锚点位置，把真正的对白行挤出字幕带（实测「平気。」就是这么丢的）。
+ (BOOL)isOwnOverlayText:(NSString *)raw { return [FYOCRTextProcessing isOwnOverlayText:raw]; }

// 从 OCR 结果里剔除我们自己的浮窗文字。
// 两种来源：
//   ① 形状可辨的状态栏（IsOwnOverlayText）
//   ② 我们刚画上去的译文（由调用方传入已渲染过的文本）——
//      贴译面板会盖住原文，下一轮 OCR 必然把它们读回来；
//      若不过滤，这些中文会被当成“原文”再翻一次，对白框里就会混进重复/错位的句子。
+ (NSArray<OCRTextItem *> *)itemsExcludingOwnOverlay:(NSArray<OCRTextItem *> *)items
                                     renderedTexts:(NSSet<NSString *> *)renderedTexts { return [FYOCRTextProcessing itemsExcludingOwnOverlay:items renderedTexts:renderedTexts]; }

// 我们画过的所有译文（字幕窗 + 贴译面板），归一化后供 OCR 去重
+ (NSSet<NSString *> *)renderedTranslationSetForCaption:(NSString *)captionText inlineCache:(NSDictionary *)inlineCache { return [FYOCRTextProcessing renderedTranslationSetForCaption:captionText inlineCache:inlineCache]; }

// Deduplication needs geometry AND bidirectional character coverage, never text alone.
// Inner blocks must lie >=85% inside and cover >=85% of the outer area;
// both character coverages must reach 80%. Same-sized duplicates retain the first.
// These are the existing thresholds, including summed (not union) covered area.
+ (NSArray<OCRTextItem *> *)resolveOverlappingItems:(NSArray<OCRTextItem *> *)items {
    return [FYOCRRefinement resolveOverlappingItems:items];
}
+ (NSArray<OCRTextItem *> *)mergeCoarseItems:(NSArray<OCRTextItem *> *)coarse refinedItems:(NSArray<OCRTextItem *> *)refined {
    return [FYOCRRefinement mergeCoarseItems:coarse refinedItems:refined];
}
+ (NSArray<OCRTextItem *> *)splitMultilineItems:(NSArray<OCRTextItem *> *)items { return [FYOCRTextProcessing splitMultilineItems:items]; }
+ (NSString *)textFromRecognizedLines:(NSArray<NSString *> *)lines { return [FYOCRTextProcessing textFromRecognizedLines:lines]; }

+ (NSArray<OCRTextItem *> *)recognizeImage:(CGImageRef)image topLeftScope:(CGRect)scope recognizer:(NSArray<OCRTextItem *> *(^)(CGImageRef,NSError **))recognizer error:(NSError **)error {
    return [FYOCRImageGeometry recognizeImage:image topLeftScope:scope recognizer:recognizer cropScope:^(CGRect crop,CGSize size,void(^work)(void)) { FYLayoutDebugPerformCrop(crop,size,work); } error:error];
}

- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)language error:(NSError **)error {
    NSMutableDictionary *local=[FYCurrentLayoutDebug() mutableCopy];
    if (local) local[@"vision_image_size"]=@[@(CGImageGetWidth(image)),@(CGImageGetHeight(image))];
    NSDictionary *context=[local copy];
    FYOCRVisionRawObserver raw=nil;
    if (context) raw=^(NSArray<OCRTextItem *> *items) { [[FYInlineLayoutDebug shared] recordItems:items stage:@"vision_raw" context:context]; };
    return [self.visionEngine recognizeTextItemsInImage:image fastOCR:fastOCR languageSegment:language rawObserver:raw error:error];
}
@end
