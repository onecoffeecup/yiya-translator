#pragma once
#import <AppKit/AppKit.h>
#import "FYReferenceWorkflowTestFacts.h"
#import "presentation/FYReferenceRenderer.h"
#import "learning/FYLearningViews.h"
#import "learning/FYSavedWordReferenceView.h"
#import <QuartzCore/QuartzCore.h>
@implementation ReferenceTextFact (NativeFacts)
- (BOOL)isKindOfClass:(Class)cls{if(cls==NSTextView.class)return YES;if(cls==FYSelectableSourceTextView.class)return self.selectable;return[super isKindOfClass:cls];}
@end
@interface ReferenceNodeFact : ReferenceValueFact
@property(nonatomic,strong) NSMutableArray *arrangedSubviews;
@property(nonatomic,weak) ReferenceNodeFact *superview;
@property(nonatomic,strong) ReferenceNodeFact *documentView,*contentView;
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) NSFont *font;
@property(nonatomic,strong) NSColor *color;
@property(nonatomic) CGFloat spacing,leftFraction,compactWidth,constant;
@property(nonatomic) BOOL hidden,bezeled,wantsLayer,active;
@property(nonatomic) NSInteger state,selectedSegment;
@property(nonatomic) NSRect frame,bounds;
@property(nonatomic) NSPoint scrolledPoint;
@property(nonatomic) NSUInteger layouts,reflects;
- (void)addArrangedSubview:(ReferenceNodeFact*)node;
- (id)heightAnchor;
- (id)constraintEqualToConstant:(CGFloat)value;
- (void)setAccessibilityLabel:(NSString*)label;
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)orientation;
- (void)setButtonType:(NSButtonType)type;
- (void)layoutSubtreeIfNeeded;
- (void)makeKeyAndOrderFront:(id)sender;
- (NSRect)convertRect:(NSRect)rect toView:(id)view;
- (void)scrollToPoint:(NSPoint)point;
- (void)reflectScrolledClipView:(id)view;
@end
@implementation ReferenceNodeFact
- (instancetype)init{if((self=[super init])){_arrangedSubviews=[NSMutableArray new];_layer=[CALayer new];}return self;}
- (void)addArrangedSubview:(ReferenceNodeFact*)node{node.superview=self;[self.arrangedSubviews addObject:node];}
- (BOOL)isHidden{return self.hidden;}
- (id)heightAnchor{return self;}
- (id)constraintEqualToConstant:(CGFloat)value{ReferenceNodeFact*n=[ReferenceNodeFact new];n.constant=value;return n;}
- (void)setAccessibilityLabel:(NSString*)label{}
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)orientation{}
- (void)setButtonType:(NSButtonType)type{}
- (void)layoutSubtreeIfNeeded{self.layouts++;}
- (void)makeKeyAndOrderFront:(id)sender{}
- (NSRect)convertRect:(NSRect)rect toView:(id)view{return rect;}
- (void)scrollToPoint:(NSPoint)point{self.scrolledPoint=point;}
- (void)reflectScrolledClipView:(id)view{self.reflects++;}
@end
static ReferenceNodeFact*Node(void){return[ReferenceNodeFact new];}
static id NewNode(id cls,SEL cmd) __attribute__((ns_returns_retained));
static id NewNode(id cls,SEL cmd){return Node();}
static NSMutableDictionary<NSString*,NSValue*>*factoryIMPs;
static void InstallNativeFactories(void){factoryIMPs=[NSMutableDictionary new];for(Class cls in@[NSPopUpButton.class,FYLearningColumnsView.class]){Method method=class_getClassMethod(cls,@selector(new));IMP prior=method_getImplementation(method);factoryIMPs[NSStringFromClass(cls)]=[NSValue valueWithPointer:prior];if(!class_addMethod(object_getClass(cls),@selector(new),(IMP)NewNode,method_getTypeEncoding(method)))method_setImplementation(class_getClassMethod(cls,@selector(new)),(IMP)NewNode);}}
static void RestoreNativeFactories(void){for(Class cls in@[NSPopUpButton.class,FYLearningColumnsView.class])method_setImplementation(class_getClassMethod(cls,@selector(new)),[factoryIMPs[NSStringFromClass(cls)]pointerValue]);factoryIMPs=nil;}
static BOOL Contains(ReferenceNodeFact*n,NSString*text){if([n.stringValue containsString:text]||[n.title containsString:text])return YES;for(ReferenceNodeFact*c in n.arrangedSubviews)if(Contains(c,text))return YES;return NO;}
