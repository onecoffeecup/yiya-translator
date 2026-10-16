#import <AppKit/AppKit.h>
#import "learning/FYLearningModels.h"
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface ReadingLearningFact : NSObject
@property(nonatomic,copy) NSString *currentSentenceID,*currentSourceText,*currentTranslation;
@property(nonatomic) NSInteger currentVersion;
@property(nonatomic,getter=isPinned) BOOL pinned;
@property(nonatomic) BOOL hasNewerSentence;
@end
@implementation ReadingLearningFact @end
@interface ReadingBoundsFact : NSObject
@property(nonatomic) CGRect bounds;
@property(nonatomic,getter=isHidden) BOOL hidden;
@property(nonatomic) NSUInteger layouts;
@end
@implementation ReadingBoundsFact
- (void)layoutSubtreeIfNeeded{self.layouts++;}
@end
@interface ReadingScrollFact : NSObject
@property(nonatomic,strong) ReadingBoundsFact *contentView;
@property(nonatomic,getter=isHidden) BOOL hidden;
@end
@implementation ReadingScrollFact @end
@interface ReadingContainerFact : NSObject
@property(nonatomic) CGFloat lineFragmentPadding;
@end
@implementation ReadingContainerFact @end
@interface ReadingTextFact : NSObject
@property(nonatomic,copy) NSString *string;
@property(nonatomic,strong) NSMutableAttributedString *textStorage;
@property(nonatomic,strong) ReadingContainerFact *textContainer;
@property(nonatomic,strong) ReadingScrollFact *enclosingScrollView;
@end
@implementation ReadingTextFact
@synthesize string=_string;
- (NSString *)string{return self.textStorage?self.textStorage.string:_string;}
- (void)setString:(NSString *)s{_string=[s copy];if(self.textStorage)[self.textStorage replaceCharactersInRange:NSMakeRange(0,self.textStorage.length) withString:s?:@" "];}
@end
@interface ReadingConstraintFact : NSObject
@property(nonatomic) CGFloat constant;
@end
@implementation ReadingConstraintFact @end
@interface ReadingLabelFact : NSObject
@property(nonatomic,copy) NSString *stringValue;
@property(nonatomic,copy) NSAttributedString *attributedStringValue;
@property(nonatomic,strong) NSColor *textColor;
@property(nonatomic,getter=isHidden) BOOL hidden;
@end
@implementation ReadingLabelFact @end
@interface ReadingButtonFact : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic,getter=isEnabled) BOOL enabled;
@end
@implementation ReadingButtonFact @end
@interface ReadingWindowFact : NSObject
@property(nonatomic,strong) ReadingBoundsFact *contentView;
@end
@implementation ReadingWindowFact @end
static ReadingTextFact *TextFact(NSString *s){ReadingTextFact *t=[ReadingTextFact new];t.string=s;t.textStorage=[[NSMutableAttributedString alloc]initWithString:s attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:19]}];t.textContainer=[ReadingContainerFact new];t.textContainer.lineFragmentPadding=5;t.enclosingScrollView=[ReadingScrollFact new];t.enclosingScrollView.contentView=[ReadingBoundsFact new];t.enclosingScrollView.contentView.bounds=CGRectMake(0,0,200,80);return t;}
static CGFloat ExpectedReadingHeight(ReadingTextFact *t){CGFloat width=MAX(1,t.enclosingScrollView.contentView.bounds.size.width-2*t.textContainer.lineFragmentPadding);CGFloat h=[t.textStorage boundingRectWithSize:CGSizeMake(width,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading].size.height;return MIN(190,MAX(42,ceil(h)+12));}
