#import <AppKit/AppKit.h>
#import "FYInlineLayout.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface CardLayerFact : NSObject
@property(nonatomic) CGColorRef backgroundColor,borderColor,shadowColor;
@property(nonatomic) CGFloat cornerRadius,borderWidth,shadowRadius;
@property(nonatomic) float shadowOpacity;
@property(nonatomic) CGSize shadowOffset;
@property(nonatomic) BOOL masksToBounds;
@end
@implementation CardLayerFact @end
@interface CardLabelFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic,strong) NSFont *font;
@property(nonatomic,strong) NSColor *textColor;
@property(nonatomic,copy) NSAttributedString *attributedStringValue;
@property(nonatomic,copy) NSString *stringValue;
@property(nonatomic,strong) NSShadow *shadow;
@property(nonatomic,strong) NSArray *subviews;
@end
@implementation CardLabelFact
- (BOOL)isKindOfClass:(Class)c{return c==NSTextField.class?YES:[super isKindOfClass:c];}
@end
@interface CardClipFact : NSObject
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGPoint lastPoint;
@property(nonatomic) NSUInteger scrolls;
@end
@implementation CardClipFact
- (void)scrollToPoint:(CGPoint)p{self.lastPoint=p;self.bounds=CGRectMake(p.x,p.y,self.bounds.size.width,self.bounds.size.height);self.scrolls++;}
@end
@interface CardScrollFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic,strong) CardLabelFact *documentView;
@property(nonatomic,strong) CardClipFact *contentView;
@property(nonatomic) NSUInteger reflects;
@end
@implementation CardScrollFact
- (BOOL)isKindOfClass:(Class)c{return c==NSScrollView.class?YES:[super isKindOfClass:c];}
- (void)reflectScrolledClipView:(id)clip{self.reflects++;}
@end
@interface CardContentFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic) BOOL longCard,patch,compactEntry,showsSelectedBadge,wantsLayer,showsDragHint;
@property(nonatomic,strong) NSArray *subviews;
@property(nonatomic,strong) CardLayerFact *layer;
@property(nonatomic,strong) CardLabelFact *foldedEntryHintLabel;
@property(nonatomic,strong) NSView *selectedBadgeBox;
@property(nonatomic,strong) NSColor *normalBorderColor,*dragHintColor;
@end
@implementation CardContentFact
- (BOOL)isKindOfClass:(Class)c{if(c==FYInlineLongCardView.class)return self.longCard;if(c==FYInlinePatchView.class)return self.patch;return [super isKindOfClass:c];}
@end
@interface CardPanelFact : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic,strong) CardContentFact *contentView;
@property(nonatomic) BOOL display;
@property(nonatomic) NSUInteger writes,displays;
@end
@implementation CardPanelFact
- (void)setFrame:(CGRect)f display:(BOOL)d{_frame=f;self.display=d;self.writes++;}
- (void)displayIfNeeded{self.displays++;}
@end
static CardContentFact *LongContent(CGRect frame,FYInlinePlacement *p){CardContentFact *c=[CardContentFact new];c.longCard=YES;c.frame=CGRectMake(0,0,frame.size.width,frame.size.height);c.layer=[CardLayerFact new];CardScrollFact *s=[CardScrollFact new];s.frame=FYInlineLongCardBodyFrame(frame.size.width,frame.size.height,p.panelPadding,p.titleBandHeight);s.documentView=[CardLabelFact new];s.documentView.frame=CGRectMake(0,0,100,500);s.contentView=[CardClipFact new];s.contentView.bounds=CGRectMake(0,450,s.frame.size.width,s.frame.size.height);c.subviews=@[s];return c;}
static CGFloat ExpectedBodyHeight(NSString *text,CGFloat width,CGFloat padding,NSFont *font,NSParagraphStyle *style){NSString *normalized=FYInlineNormalizeTranslationParagraphs(text);CGRect actual=FYInlineMeasureTextWithAttributes(normalized,CGSizeMake(MAX((CGFloat)80,width-2*padding),CGFLOAT_MAX),FYInlineTextAttributes(font,style));return MAX((CGFloat)22,ceil(actual.size.height)+4);}
