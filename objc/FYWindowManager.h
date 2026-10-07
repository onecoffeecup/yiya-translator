#import <Cocoa/Cocoa.h>

// Candidate snapshot; legacy displayName remains supported.
@interface WindowItem : NSObject
@property(nonatomic) uint32_t windowID;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic) CGRect bounds;
@property(nonatomic, copy) NSString *ownerName;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, readonly) NSInteger suggestionRank;
@property(nonatomic, readonly) NSString *effectiveOwnerName;
@property(nonatomic, readonly) NSString *effectiveTitle;
@end

typedef struct {
    pid_t targetPID;
    BOOL targetOnScreen;
    BOOL ownerHasOnScreenWindow;
} FYWindowVisibilitySnapshot;
FOUNDATION_EXPORT FYWindowVisibilitySnapshot FYWindowVisibilityInList(uint32_t windowID, pid_t knownPID, NSArray<NSDictionary *> *windows);

// Shared policies also used by isolated fixture tests.
FOUNDATION_EXPORT BOOL FYTargetQualifiesForOverlay(pid_t frontPID, pid_t targetPID, BOOL targetOnScreen, BOOL ownerHasOnScreenWindow, BOOL interactingWithOverlay);
FOUNDATION_EXPORT NSWindowLevel FYOverlayLevelForTarget(pid_t targetPID, NSArray<NSDictionary *> *windows);
FOUNDATION_EXPORT BOOL FYOverlayShouldShow(BOOL targetActive, BOOL expanded, BOOL isExpandedPanel);
FOUNDATION_EXPORT BOOL FYWindowOwnerIsYiya(NSString *owner);
FOUNDATION_EXPORT NSComparisonResult FYWindowItemSort(WindowItem *left, WindowItem *right);
FOUNDATION_EXPORT WindowItem *FYWindowItemFromInfo(NSDictionary *info);

// No AppDelegate/UI ownership: every policy receives an explicit snapshot.
@interface FYWindowManager : NSObject
- (NSArray<WindowItem *> *)availableWindowItems;
- (NSArray<WindowItem *> *)displayedWindowItems:(NSArray<WindowItem *> *)windows
                                  showingAll:(BOOL)showAll selectedID:(uint32_t)selectedID;
- (BOOL)hasRecommendedWindowItems:(NSArray<WindowItem *> *)windows;
- (NSString *)windowBaseTitleForItem:(WindowItem *)item;
- (NSString *)windowMenuTitleForItem:(WindowItem *)item occurrence:(NSUInteger)occurrence;
- (BOOL)liveBoundsForWindowID:(uint32_t)windowID outBounds:(CGRect *)outBounds;
- (WindowItem *)windowItemForID:(uint32_t)windowID;
- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                       selectedID:(uint32_t)selectedID ownerPID:(pid_t)ownerPID
                                        ambiguous:(BOOL *)ambiguous note:(NSString **)note;
@end
