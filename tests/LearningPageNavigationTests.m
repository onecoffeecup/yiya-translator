#import "LearningAppTestSupport.h"
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,480,300)];
    NSView *first=[NSView new], *second=[NSView new];
    NSArray *pages=@[first,second];
    NSArray *buttons=@[[NSButton new],[NSButton new]];
    FYMountLearningPage(pages,host,0);
    Require(first.superview==host && !second.superview && !first.translatesAutoresizingMaskIntoConstraints,@"mount installs only chosen page using constraints");
    Require(host.constraints.count==4,@"mount uses exactly four host edge constraints");
    FYMountLearningPage(pages,host,0);
    Require(host.constraints.count==4 && host.subviews.count==1,@"repeated mount does not accumulate constraints or views");
    FYMountLearningPage(pages,host,1);
    Require(!first.superview && second.superview==host && host.constraints.count==4,@"switch removes old host constraints and mounts new page");
    FYUpdateLearningPageSelection(pages,buttons,1);
    Require(first.hidden && !second.hidden && [(NSButton *)buttons[0] state]==NSControlStateValueOff && [(NSButton *)buttons[1] state]==NSControlStateValueOn,@"visibility and navigation button states agree");
    FYMountLearningPage(pages,host,-1); FYMountLearningPage(pages,host,2);
    Require(second.superview==host && host.constraints.count==4,@"invalid page indexes leave host untouched");
    FYMountLearningPage(pages,host,0);
    FYUpdateLearningPageSelection(pages,buttons,0);
    Require(!first.hidden && second.hidden && host.constraints.count==4 && [(NSButton *)buttons[0] state]==NSControlStateValueOn,@"return navigation preserves single page and selected state");
    NSLog(@"PASS LearningPageNavigationTests: 7 contracts, isolated views, no preferences or user data");
} return 0; }
