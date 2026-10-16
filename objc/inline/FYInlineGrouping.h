#pragma once
#import "FYInlineTextModels.h"
NS_ASSUME_NONNULL_BEGIN
#pragma mark - 分组器

@interface FYInlineGrouper : NSObject
/// 一个块允许的最大高度（归一化）。超过就不再并——防止把整屏竖排条目并成一大段。
/// 真正的防跨栏/防菜单合并靠列间隙、字号与正文证据判定；这个上限只挡“整屏竖直全并”。
@property (nonatomic) CGFloat maxBlockHeightFraction;   // 默认 0.55
/// 小于这个字符数的行直接丢弃（OCR 噪声）。
@property (nonatomic) NSInteger minimumCharacters;      // 默认 2
/// 可选：调用方的“这是按钮/菜单词”判定（例如「戻る」「詳細」），命中即按短标签处理。
@property (nonatomic, copy, nullable) BOOL (^shortLabelDetector)(NSString *normalizedText);
+ (instancetype)defaultGrouper;

/// 文本 + 位置联合去重：同一处重复识别只留置信度更高的一条，
/// **不同位置**的相同文字必须都保留。
- (NSArray<FYInlineTextLine *> *)deduplicatedLines:(NSArray<FYInlineTextLine *> *)lines;
/// 分组主入口。返回按阅读顺序排列的块。
- (NSArray<FYInlineTextBlock *> *)blocksFromLines:(NSArray<FYInlineTextLine *> *)lines;
/// 单块分类（导出给调用方复用同一套判定）。
- (FYInlineBlockKind)kindForLines:(NSArray<FYInlineTextLine *> *)lines
                       normalized:(nullable NSString *)normalizedText;
@end

#pragma mark - 帧间块匹配

/// 帧间匹配：文本相似 + 位置重叠，避免一两像素抖动就换身份。
@interface FYInlineBlockMatcher : NSObject
/// 文本相似度 0..1（字符二元组 Dice 系数），对 OCR 小抖动稳健。
/// 稳定身份：文本 + 量化行框（同一文字出现在不同位置时身份不同）。
+ (NSString *)blockIDForText:(NSString *)text lineBoxes:(NSArray<NSValue *> *)lineBoxes;
+ (CGFloat)textSimilarity:(NSString *)left right:(NSString *)right;
/// 两个矩形（同一坐标系）的重叠比例，取相对较小面积的比例 0..1。
+ (CGFloat)overlapRatio:(CGRect)left right:(CGRect)right;
/// 判断新块是否对应上一帧的某个排版；是则返回上一帧的 blockID（稳定身份）。
+ (nullable NSString *)stableBlockIDForBlock:(FYInlineTextBlock *)block
                                        text:(NSString *)text
                                 sourceFrame:(CGRect)sourceFrame
                               previousResult:(nullable FYInlineLayoutResult *)previous;
@end

NS_ASSUME_NONNULL_END
