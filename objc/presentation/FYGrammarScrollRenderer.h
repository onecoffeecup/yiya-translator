#pragma once
#import <AppKit/AppKit.h>
@class FYGrammarItem, FYStudyOverlayPanel;
// Native view facts and detail factory only; no task, application or persistence state.
@protocol FYGrammarScrollSource <NSObject>
@property(nonatomic,strong,readonly) NSScrollView *mainStructureScrollView;
@property(nonatomic,strong,readonly) NSScrollView *quickStructureScrollView;
@property(nonatomic,strong,readonly) NSStackView *quickGrammarStack;
- (NSView *)quickGrammarDetailCard;
- (void)setQuickGrammarDetailCard:(NSView *)card;
@property(nonatomic,strong,readonly) FYStudyOverlayPanel *quickSentencePanel;
@property(nonatomic,strong,readonly) NSButton *grammarReviewButton;
- (NSScrollView *)quickSentenceScrollView;
- (FYGrammarItem *)grammarActionItemForQuick:(BOOL)quick;
- (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item;
@end
// Stateless native renderer. The original controller and peer still own all views.
@interface FYGrammarScrollRenderer : NSObject
+ (CGFloat)structureScrollOffsetForQuick:(BOOL)quick source:(id<FYGrammarScrollSource>)source;
+ (void)restoreStructureScrollOffset:(CGFloat)offset quick:(BOOL)quick source:(id<FYGrammarScrollSource>)source;
+ (void)refreshQuickGrammarActionDetailWithSource:(id<FYGrammarScrollSource>)source;
+ (void)updateGrammarReviewDisplayForQuick:(BOOL)quick preservingPosition:(void (^)(void))updates source:(id<FYGrammarScrollSource>)source;
@end
