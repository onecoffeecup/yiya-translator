#pragma once
#import <AppKit/AppKit.h>
#import "../learning/FYLearningModels.h"
@class FYReferenceDictionary;

@protocol FYReferenceRenderSource <NSObject>
@property(nonatomic, strong) NSView *referenceCard;
@property(nonatomic, strong) NSStackView *referenceDetailStack;
@property(nonatomic, strong) NSPopUpButton *referenceEntryPopup;
@property(nonatomic, strong) NSStackView *referenceMoreExamples;
@property(nonatomic, strong) NSTextField *referenceSearchField;
@property(nonatomic, strong) NSPopUpButton *referenceSensePopup;
@property(nonatomic, strong) NSStackView *referenceStack;
@property(nonatomic, strong) NSSegmentedControl *referenceTabs;
- (id)referenceActionTarget;
- (NSString *)referenceActiveWord;
- (NSArray<NSDictionary *> *)referenceRecords;
- (FYReferenceDictionary *)referenceDictionary;
- (void)setReferenceDictionary:(FYReferenceDictionary *)value;
- (FYReferenceDictionary *)makeReferenceDictionary;
- (NSWindow *)mainWindow;
- (NSArray<NSView *> *)pages;
- (FYVocabularyEntry *)wordForCardButton:(NSButton *)sender;
- (void)selectPageAtIndex:(NSInteger)index;
- (void)referenceEntryChanged:(id)sender;
- (void)referenceTabChanged:(id)sender;
- (void)addReferenceDisclosure:(NSString *)title content:(NSView *)content;
- (NSButton *)referenceLink:(NSString *)title URL:(NSString *)url;
- (void)clearArrangedSubviews:(NSStackView *)stack;
- (NSStackView *)verticalStack;
- (NSStackView *)horizontalStack;
- (NSTextField *)label:(NSString *)text font:(NSFont *)font color:(NSColor *)color;
- (NSTextField *)textField:(NSString *)placeholder;
- (NSSegmentedControl *)segmentedWithLabels:(NSArray<NSString *> *)labels action:(SEL)action;
- (NSColor *)uiInk;
- (NSColor *)uiMuted;
- (NSColor *)uiBorder;
- (NSColor *)uiAccent;
- (NSColor *)uiSurface;
- (NSView *)cardWithStack:(NSStackView *)stack;
- (NSTextField *)cardTitle:(NSString *)text;
- (NSTextField *)mutedLabel:(NSString *)text;
- (NSView *)workspaceSection:(NSStackView *)stack;
- (NSButton *)workspaceButton:(NSString *)title action:(SEL)action primary:(BOOL)primary;
@end

// Native factories/attributes only; no idle source, state or owned views.
@interface FYReferenceRenderer : NSObject
+ (NSView *)makeReferenceCardWithReceiver:(id<FYReferenceRenderSource>)receiver;
+ (NSButton *)referenceLink:(NSString *)title URL:(NSString *)url receiver:(id<FYReferenceRenderSource>)receiver;
+ (void)revealReferenceCardWithReceiver:(id<FYReferenceRenderSource>)receiver;
+ (void)showSavedWordReference:(NSButton *)sender receiver:(id<FYReferenceRenderSource>)receiver;
+ (void)referenceEntryChangedWithReceiver:(id<FYReferenceRenderSource>)receiver;
+ (void)referenceTabChangedWithReceiver:(id<FYReferenceRenderSource>)receiver;
+ (void)addDisclosure:(NSString *)title content:(NSView *)content receiver:(id<FYReferenceRenderSource>)receiver;
+ (void)toggleExtra:(NSButton *)sender receiver:(id<FYReferenceRenderSource>)receiver;
+ (void)setHoverTip:(NSString *)tip range:(NSRange)range source:(NSString *)source views:(NSArray *)views receiver:(id<FYReferenceRenderSource>)receiver;
+ (void)clearHoverAttributes:(NSArray *)views;
+ (void)showEmptyWord:(NSString *)word error:(NSError *)error receiver:(id<FYReferenceRenderSource>)receiver;
+ (void)renderRecords:(NSArray<NSDictionary *> *)records receiver:(id<FYReferenceRenderSource>)receiver;
@end
