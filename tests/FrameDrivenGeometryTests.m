#import "presentation/FYFrameDrivenContentView.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface DimensionFact : NSObject
@property(nonatomic) CGFloat constant;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic,copy) void (^onSet)(void);
@end
@implementation DimensionFact
@synthesize constant=_constant;
- (void)setConstant:(CGFloat)value{_constant=value;[self.trace addObject:self.name];if(self.onSet)self.onSet();}
@end
@interface CanvasFact : NSObject
@property(nonatomic) NSRect frame;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@end
@implementation CanvasFact
@synthesize frame=_frame;
- (void)setFrame:(NSRect)value{_frame=value;[self.trace addObject:@"frame-set"];}
@end
@interface FrameSourceFact : NSObject <FYFrameDrivenGeometrySource>
@property(nonatomic) NSRect currentBounds;
@property(nonatomic,strong) DimensionFact *width,*height;
@property(nonatomic,strong) CanvasFact *canvas;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic) NSUInteger boundsReads;
@end
@implementation FrameSourceFact
- (instancetype)init{if((self=[super init])){self.trace=[NSMutableArray new];self.width=[DimensionFact new];self.height=[DimensionFact new];self.canvas=[CanvasFact new];self.width.name=@"width-set";self.height.name=@"height-set";self.width.trace=self.trace;self.height.trace=self.trace;self.canvas.trace=self.trace;}return self;}
- (NSRect)bounds{self.boundsReads++;[self.trace addObject:@"bounds"];return self.currentBounds;}
- (NSLayoutConstraint *)layoutWidth{[self.trace addObject:@"width-get"];return (NSLayoutConstraint *)self.width;}
- (NSLayoutConstraint *)layoutHeight{[self.trace addObject:@"height-get"];return (NSLayoutConstraint *)self.height;}
- (NSView *)layoutContent{[self.trace addObject:@"canvas-get"];return (NSView *)self.canvas;}
@end
static void Sync(FrameSourceFact *source){
#if FY_FRAME_DRIVEN_ORIGINAL
#include "OriginalFrameGeometryBody.inc"
#else
FYSyncFrameDrivenContentGeometry(source);
#endif
}
int main(void){@autoreleasepool{
    Check(NSApp==nil,@"native geometry fixture creates no NSApplication/view/window/control");unsigned int n=0;Ivar *v=class_copyIvarList(FYFrameDrivenContentView.class,&n);free(v);Check(n==3,@"same native frame class keeps only original three strong resource fields");FrameSourceFact *s=[FrameSourceFact new];s.currentBounds=NSMakeRect(3,7,1120,800);Sync(s);Check(s.width.constant==1120&&s.height.constant==800&&NSEqualRects(s.canvas.frame,s.currentBounds),@"actual original native sync copies actual bounds width/height/frame exactly");
    Check(s.boundsReads==3,@"original bounds read independently three times, no frozen early snapshot");Check([[s.trace componentsJoinedByString:@","]isEqual:@"bounds,width-get,width-set,bounds,height-get,height-set,bounds,canvas-get,frame-set"],@"native assignment reads bounds before destination getter, original write order preserved");
    [s.trace removeAllObjects];s.currentBounds=NSMakeRect(1,2,720,660);Sync(s);Check(s.width.constant==720&&s.height.constant==660&&NSEqualRects(s.canvas.frame,s.currentBounds),@"actual smaller dimensions retained without arbitrary UI floor or width lock");s.currentBounds=NSMakeRect(0,0,0,0);Sync(s);Check(s.width.constant==0&&s.height.constant==0&&NSEqualRects(s.canvas.frame,NSZeroRect),@"original zero geometry retained without unrequested fallback");
    s.currentBounds=NSMakeRect(5,6,900,700);__weak FrameSourceFact *weak=s;s.width.onSet=^{weak.currentBounds=NSMakeRect(8,9,1300,990);};Sync(s);Check(s.width.constant==900&&s.height.constant==990&&NSEqualRects(s.canvas.frame,NSMakeRect(8,9,1300,990)),@"reentrant native setter changes later bounds reads just as original, no captured size cache");s.width.onSet=nil;
    __weak FrameSourceFact *released;@autoreleasepool{FrameSourceFact *temporary=[FrameSourceFact new];released=temporary;Sync(temporary);}Check(!released,@"synchronous native adapter retains no idle source/canvas");Sync(nil);Check(NSApp==nil,@"nil receiver sync remains safe with no native initialization");printf("PASS FrameDrivenGeometryTests: %lu checks; actual original/native SDK expression order/geometry/leases, real view initialization and layout compiled only\n",(unsigned long)checks);
}return 0;}
