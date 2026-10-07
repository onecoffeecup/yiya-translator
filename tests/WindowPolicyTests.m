#import "FYWindowManager.h"
static void Check(BOOL ok,NSString *message){if(!ok){NSLog(@"FAIL %@",message);exit(1);}}
int main(void){@autoreleasepool{
    Check(FYTargetQualifiesForOverlay(100,100,NO,YES,NO),@"foreground projector owner keeps overlay");
    Check(!FYTargetQualifiesForOverlay(200,100,YES,YES,NO),@"other foreground app hides overlay");
    Check(!FYTargetQualifiesForOverlay(100,100,NO,NO,NO),@"no visible owner window hides overlay");
    Check(FYTargetQualifiesForOverlay(0,0,NO,NO,YES),@"auxiliary interaction takes precedence over missing PID");
    NSArray *windows=@[@{(id)kCGWindowOwnerPID:@100,(id)kCGWindowLayer:@101},@{(id)kCGWindowOwnerPID:@200,(id)kCGWindowLayer:@200}];
    Check(FYOverlayLevelForTarget(100,windows)==NSPopUpMenuWindowLevel+1,@"target popup window raises overlay");
    Check(FYOverlayLevelForTarget(200,windows)==NSPopUpMenuWindowLevel+1,@"high target layer capped below system alerts");
    Check(FYOverlayLevelForTarget(0,windows)==NSFloatingWindowLevel && FYOverlayLevelForTarget(300,windows)==NSFloatingWindowLevel,@"missing target falls back to floating layer");
    Check(FYOverlayShouldShow(YES,YES,YES) && !FYOverlayShouldShow(YES,YES,NO) && !FYOverlayShouldShow(NO,NO,NO),@"expanded reading and inactive target visibility policy");
    NSArray *visible=@[@{(id)kCGWindowNumber:@10,(id)kCGWindowOwnerPID:@100},@{(id)kCGWindowNumber:@20,(id)kCGWindowOwnerPID:@200}];
    FYWindowVisibilitySnapshot found=FYWindowVisibilityInList(10,0,visible);
    Check(found.targetPID==100 && found.targetOnScreen && found.ownerHasOnScreenWindow,@"visible target resolves missing owner PID");
    FYWindowVisibilitySnapshot known=FYWindowVisibilityInList(10,200,visible);
    Check(known.targetPID==200 && known.targetOnScreen && known.ownerHasOnScreenWindow,@"known owner preserved even when target dictionary differs");
    FYWindowVisibilitySnapshot projector=FYWindowVisibilityInList(99,100,visible);
    Check(!projector.targetOnScreen && projector.ownerHasOnScreenWindow,@"missing target still recognizes another owner window");
    FYWindowVisibilitySnapshot missing=FYWindowVisibilityInList(99,0,visible);
    Check(!missing.targetOnScreen && !missing.ownerHasOnScreenWindow && missing.targetPID==0,@"missing target with unknown owner stays unavailable");
    NSArray *duplicates=@[@{(id)kCGWindowNumber:@10,(id)kCGWindowOwnerPID:@0},@{(id)kCGWindowNumber:@10,(id)kCGWindowOwnerPID:@200}];
    FYWindowVisibilitySnapshot duplicate=FYWindowVisibilityInList(10,0,duplicates);
    Check(duplicate.targetOnScreen && duplicate.targetPID==0 && !duplicate.ownerHasOnScreenWindow,@"first target with missing owner is not replaced by later duplicate");
    FYWindowVisibilitySnapshot prefix=FYWindowVisibilityInList(20,100,visible);
    Check(prefix.targetOnScreen && prefix.targetPID==100 && prefix.ownerHasOnScreenWindow,@"known owner appearing before target remains visible in single pass");
    NSLog(@"PASS WindowPolicyTests: 14 assertions, no AppDelegate or UI initialization");
}return 0;}
