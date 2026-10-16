#import "presentation/FYInlineOverflowCoordinator.h"
#import "presentation/FYPresentationText.h"
#import "inline/FYInlineLayoutCalculator.h"
#import <objc/runtime.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *m){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",m.UTF8String);exit(2);}}
@interface OverflowPolicyFacts : NSObject <FYInlineOverflowSource>
@property(nonatomic,strong) FYInlineOverflowCoordinator *owner;
@property(nonatomic,strong) NSPanel *inlineOverflowPanel;
@property(nonatomic,strong) NSPanel *inlineOverflowChoicePanel;
@property(nonatomic,strong) id inlineOverflowChoiceKeyMonitor;
@property(nonatomic,strong) NSPanel *inlineExpandedReadingPanel;
@property(nonatomic,strong) NSMutableArray<NSString *> *trace;
@property(nonatomic,strong) OCRTextItem *openedItem;
@property(nonatomic,strong) NSString *openedTranslation,*openedID;
@property(nonatomic,copy) NSString *fallback;
@property(nonatomic) BOOL visible,ignores,failBuild,clearOnClose;
@property(nonatomic) NSTimeInterval now;
@property(nonatomic) NSUInteger titleCalls,timeCalls,hostExpires,builds,resizes,positions,fronts,entryCloses,choiceCloses,lists,opens,entriesReads;
@property(nonatomic,weak) NSMutableDictionary *mutateOnClose;
@end
@implementation OverflowPolicyFacts
@dynamic inlineOverflowEntries,inlineOverflowCount,inlineOverflowPanelCount,inlineOverflowCandidateCount,inlineOverflowCandidateFrames,inlineOverflowEmptySince;
- (instancetype)init{if((self=[super init])){self.owner=[FYInlineOverflowCoordinator new];self.trace=[NSMutableArray new];self.now=100;}return self;}
- (NSArray *)inlineOverflowEntries{self.entriesReads++;return self.owner.inlineOverflowEntries;}
- (void)setInlineOverflowEntries:(NSArray *)v{self.owner.inlineOverflowEntries=v;}
- (NSUInteger)inlineOverflowCount{return self.owner.inlineOverflowCount;}
- (void)setInlineOverflowCount:(NSUInteger)v{self.owner.inlineOverflowCount=v;}
- (NSUInteger)inlineOverflowPanelCount{return self.owner.inlineOverflowPanelCount;}
- (void)setInlineOverflowPanelCount:(NSUInteger)v{self.owner.inlineOverflowPanelCount=v;}
- (NSUInteger)inlineOverflowCandidateCount{return self.owner.inlineOverflowCandidateCount;}
- (void)setInlineOverflowCandidateCount:(NSUInteger)v{self.owner.inlineOverflowCandidateCount=v;}
- (NSUInteger)inlineOverflowCandidateFrames{return self.owner.inlineOverflowCandidateFrames;}
- (void)setInlineOverflowCandidateFrames:(NSUInteger)v{self.owner.inlineOverflowCandidateFrames=v;}
- (NSTimeInterval)inlineOverflowEmptySince{return self.owner.inlineOverflowEmptySince;}
- (void)setInlineOverflowEmptySince:(NSTimeInterval)v{self.owner.inlineOverflowEmptySince=v;}
- (NSString *)inlineOverflowTitleForBlockText:(NSString *)t{self.titleCalls++;return [FYInlineLayoutCalculator shortTitleForBlockText:t];}
- (NSString *)inlineOverflowFallbackTitle{return self.fallback;}
- (NSTimeInterval)inlineOverflowTime{self.timeCalls++;return self.now;}
- (void)inlineHostExpireInlineOverflowEntryIfNeeded{self.hostExpires++;[self.owner expireInlineOverflowEntryIfNeededWithSource:self];}
- (void)hideInlineOverflowEntryForExpandedReading{self.visible=NO;self.ignores=YES;[self.trace addObject:@"hide-expanded"];}
- (void)buildInlineOverflowEntryForViewport:(CGRect)v{self.builds++;[self.trace addObject:@"build"];if(!self.failBuild)self.inlineOverflowPanel=(NSPanel *)[NSObject new];}
- (void)resizeInlineOverflowEntryWithTitle:(NSString *)t viewport:(CGRect)v{self.resizes++;[self.trace addObject:t];}
- (void)positionInlineOverflowEntryInViewport:(CGRect)v{self.positions++;[self.trace addObject:@"position"];}
- (BOOL)inlineOverflowEntryIsVisible{return self.visible;}
- (void)orderInlineOverflowEntryFront{self.fronts++;self.visible=YES;[self.trace addObject:@"front"];}
- (void)setInlineOverflowEntryIgnoresMouseEvents:(BOOL)v{self.ignores=v;[self.trace addObject:@"passthrough"];}
- (void)closeInlineOverflowEntryPanel{self.entryCloses++;[self.trace addObject:@"entry-close"];}
- (void)showInlineOverflowList{self.lists++;[self.trace addObject:@"list"];}
- (void)closeInlineOverflowChoice{self.choiceCloses++;[self.trace addObject:@"choice-close"];self.inlineOverflowChoicePanel=nil;if(self.clearOnClose)self.inlineOverflowEntries=@[];self.mutateOnClose[@"translation"]=@"changed-during-close";}
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)identity{self.opens++;self.openedItem=item;self.openedTranslation=translation;self.openedID=identity;[self.trace addObject:@"open"];}
@end
static FYInlinePlacement *OverflowPlacement(NSString *identity,NSString *text,NSString *translation,FYInlineDisplayMode mode){FYInlinePlacement *p=[FYInlinePlacement new];p.blockID=identity;p.sourceBlockID=identity;p.block=[FYInlineTextBlock new];p.block.text=text;p.translation=translation;p.mode=mode;return p;}
static void UpdateOverflow(OverflowPolicyFacts *f,NSArray *p,NSDictionary *items){[f.owner updateInlineOverflowEntryWithPlacements:p items:items viewport:CGRectMake(0,0,600,400) unplaceable:99 source:f];}
