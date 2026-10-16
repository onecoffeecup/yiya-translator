#pragma once
#import <AppKit/AppKit.h>
#import "FYCollectionWorkflowTestFacts.h"
#import "presentation/FYCollectionRenderer.h"
#import "learning/FYSavedWordReferenceView.h"
@interface CollectionNodeFact : CollectionValueFact
@property(nonatomic,strong) NSMutableArray *arrangedSubviews;
@property(nonatomic,weak) CollectionNodeFact *superview;
@property(nonatomic) CGFloat spacing;
@property(nonatomic) NSInteger maximumNumberOfLines,lineBreakMode,alignment,state;
@property(nonatomic) NSUInteger bezelStyle;
@property(nonatomic) BOOL needsDisplay,active;
@property(nonatomic,strong) NSFont *font;
@property(nonatomic,strong) NSColor *color;
@property(nonatomic,weak) id target;
@property(nonatomic) SEL action;
@property(nonatomic) CGFloat constant;
- (void)addArrangedSubview:(id)node;
- (id)widthAnchor;
- (id)constraintGreaterThanOrEqualToConstant:(CGFloat)value;
@end
@implementation CollectionNodeFact
- (instancetype)init{if((self=[super init])){_arrangedSubviews=[NSMutableArray new];self.enabled=YES;self.items=[NSMutableArray new];}return self;}
- (void)addArrangedSubview:(CollectionNodeFact*)node{node.superview=self;[self.arrangedSubviews addObject:node];}
- (id)widthAnchor{return self;}
- (id)constraintGreaterThanOrEqualToConstant:(CGFloat)value{CollectionNodeFact*c=[CollectionNodeFact new];c.constant=value;return c;}
@end
static CollectionNodeFact*Node(void){return[CollectionNodeFact new];}
static CollectionNodeFact*Label(NSString*text,NSFont*font,NSColor*color){CollectionNodeFact*n=Node();n.stringValue=text;n.font=font;n.color=color;return n;}
static id ButtonFactory(id cls,SEL cmd,NSString*title,id target,SEL action){CollectionNodeFact*n=Node();n.title=title;n.target=target;n.action=action;return n;}
static id ReferenceFactory(id cls,SEL cmd) __attribute__((ns_returns_retained));
static id ReferenceFactory(id cls,SEL cmd){return Node();}
static IMP buttonIMP,referenceIMP;
static void InstallFactories(void){Method b=class_getClassMethod(NSButton.class,@selector(buttonWithTitle:target:action:));Method r=class_getClassMethod(FYSavedWordReferenceView.class,@selector(new));buttonIMP=method_setImplementation(b,(IMP)ButtonFactory);referenceIMP=method_getImplementation(r);class_addMethod(object_getClass(FYSavedWordReferenceView.class),@selector(new),(IMP)ReferenceFactory,method_getTypeEncoding(r));}
static void RestoreFactories(void){method_setImplementation(class_getClassMethod(NSButton.class,@selector(buttonWithTitle:target:action:)),buttonIMP);method_setImplementation(class_getClassMethod(FYSavedWordReferenceView.class,@selector(new)),referenceIMP);}
static CollectionNodeFact*FindTitle(CollectionNodeFact*n,NSString*title){if([n.title isEqual:title])return n;for(CollectionNodeFact*c in n.arrangedSubviews){CollectionNodeFact*f=FindTitle(c,title);if(f)return f;}return nil;}
static BOOL ContainsText(CollectionNodeFact*n,NSString*text){if([n.stringValue containsString:text])return YES;for(CollectionNodeFact*c in n.arrangedSubviews)if(ContainsText(c,text))return YES;return NO;}
