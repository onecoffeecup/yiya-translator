#import "FYGrammarScrollTestFacts.h"
#import "presentation/FYStudyChatRenderer.h"
#import "presentation/FYQuickSentenceRenderer.h"
#import "presentation/FYStudyScrollRenderer.h"
#import "learning/FYStudyChatView.h"
#import "learning/FYStudyChatSession.h"
#import "learning/FYStudyOverlayPanel.h"
#import "learning/FYLearningViews.h"
#import <QuartzCore/QuartzCore.h>
@interface StudyAnchorFact:NSObject
@property(nonatomic,copy) NSString*name;
@property(nonatomic,strong) NSMutableArray*constraints;
- (id)constraintEqualToAnchor:(id)anchor constant:(CGFloat)c;
@end
@interface StudyConstraintFact:NSObject
@property(nonatomic,strong) id first,second;
@property(nonatomic) CGFloat constant;
@property(nonatomic) BOOL active;
@end
@implementation StudyConstraintFact @end
@implementation StudyAnchorFact
- (id)constraintEqualToAnchor:(id)anchor constant:(CGFloat)c{StudyConstraintFact*n=[StudyConstraintFact new];n.first=self;n.second=anchor;n.constant=c;[self.constraints addObject:n];return n;}
@end
@interface StudyLayerFact:NSObject
@property(nonatomic) CGColorRef backgroundColor;
@end
@implementation StudyLayerFact @end
@interface StudyNodeFact:GrammarScrollNodeFact
@property(nonatomic) BOOL isScroll,isChat,translatesAutoresizingMaskIntoConstraints,selectable,enabled,closeVisible,returnVisible,sending,hidesOnDeactivate,releasedWhenClosed,movableByWindowBackground;
@property(nonatomic) NSInteger tag,state,maximumNumberOfLines;
@property(nonatomic) NSWindowLevel level;
@property(nonatomic) NSWindowCollectionBehavior collectionBehavior;
@property(nonatomic) CGFloat spacing;
@property(nonatomic,strong) NSFont*font;
@property(nonatomic,strong) NSColor*textColor,*backgroundColor,*fillColor,*edgeColor;
@property(nonatomic,copy) NSAttributedString*attributedStringValue;
@property(nonatomic,copy) NSString*title,*stringValue,*context,*contextLabel,*sentText;
@property(nonatomic,strong) NSArray*messages;
@property(nonatomic,strong) id returnButton,firstResponder;
@property(nonatomic,strong) StudyLayerFact*layer;
@property(nonatomic,strong) StudyAnchorFact *leadingAnchor,*trailingAnchor,*topAnchor,*bottomAnchor;
@property(nonatomic,strong) NSArray*subviews;
@property(nonatomic,copy) void(^onSend)(NSString*);
@property(nonatomic,copy) void(^onClose)(void);
@property(nonatomic,copy) void(^onLatest)(void);
@property(nonatomic,copy) void(^onReturn)(void);
@property(nonatomic,copy) void(^onContext)(void);
@property(nonatomic) NSLayoutPriority compressionPriority;
- (void)setCloseVisible:(BOOL)v;
- (void)setReturnVisible:(BOOL)v;
- (void)setContextText:(NSString*)text label:(NSString*)label;
- (void)setMessages:(NSArray*)messages;
- (void)setSending:(BOOL)sending;
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o;
- (void)makeFirstResponder:(id)sender;
- (void)addSubview:(id)view;
@end
@implementation StudyNodeFact
- (BOOL)isKindOfClass:(Class)c{if(c==NSScrollView.class)return self.isScroll;if(c==FYStudyChatView.class)return self.isChat;return [super isKindOfClass:c];}
- (void)setCloseVisible:(BOOL)v{_closeVisible=v;[self.trace addObject:@"close-visible"];}
- (void)setReturnVisible:(BOOL)v{_returnVisible=v;[self.trace addObject:@"return-visible"];}
- (void)setContextText:(NSString*)text label:(NSString*)label{self.context=text;self.contextLabel=label;[self.trace addObject:[self.name stringByAppendingString:@"-context"]];if(self.onContext)self.onContext();}
- (void)setMessages:(NSArray*)m{_messages=m;[self.trace addObject:[self.name stringByAppendingString:@"-messages"]];}
- (void)setSending:(BOOL)v{_sending=v;[self.trace addObject:[self.name stringByAppendingString:@"-sending"]];}
- (void)setContentCompressionResistancePriority:(NSLayoutPriority)p forOrientation:(NSLayoutConstraintOrientation)o{self.compressionPriority=p;Check(o==NSLayoutConstraintOrientationHorizontal,@"label keeps original horizontal compression axis");}
- (void)makeFirstResponder:(id)sender{self.firstResponder=sender;[self.trace addObject:@"first-responder"];}
- (void)addSubview:(id)view{[self.arrangedSubviews addObject:view];}
@end
static StudyNodeFact*SNode(NSString*n,NSMutableArray*t){StudyNodeFact*v=[StudyNodeFact new];v.name=n;v.trace=t;v.arrangedSubviews=[NSMutableArray new];v.layer=[StudyLayerFact new];v.closeVisible=YES;v.translatesAutoresizingMaskIntoConstraints=YES;return v;}
@interface StudySessionFact:NSObject
@property(nonatomic,copy) NSString*source;
@property(nonatomic,strong) NSArray*messages;
@property(nonatomic) BOOL sending;
@end
@implementation StudySessionFact @end
@interface StudyRendererFacts:NSObject
@property(nonatomic,strong) NSMutableArray*trace,*constraints,*labels;
@property(nonatomic,strong) StudyNodeFact*madeChat,*main,*overlay,*panel,*scroll,*stack,*detail,*replacement,*bookmarkButton,*status,*selected,*card,*expand;
@property(nonatomic,strong) NSArray*choices,*structure;
@property(nonatomic,strong) FYInlineBlockSnapshot*returnSnapshot;
@property(nonatomic,strong) id returnButton;
@property(nonatomic,strong) StudySessionFact*session;
@property(nonatomic,strong) FYAnalysisResult*analysis;
@property(nonatomic,strong) FYGrammarBookmark*bookmark;
@property(nonatomic,strong) FYGrammarActionState*actions;
@property(nonatomic,copy) NSString*sentenceID;
@property(nonatomic) BOOL resolving,pending;
@property(nonatomic) CGFloat offset;
@property(nonatomic) NSInteger index;
@property(nonatomic) NSUInteger ensures,sends,latest,returns,closes,selects,factories,actionUpdates;
@property(nonatomic,copy) NSString*sent;
@property(nonatomic,strong) id selectedItem;
@end
@implementation StudyRendererFacts
- (instancetype)init{if((self=[super init])){_trace=[NSMutableArray new];_constraints=[NSMutableArray new];_labels=[NSMutableArray new];_madeChat=SNode(@"made",_trace);_madeChat.isChat=YES;_session=[StudySessionFact new];_session.source=@"source";_session.messages=@[@{@"content":@"message"}];_main=SNode(@"main",_trace);_main.isChat=YES;_overlay=SNode(@"overlay",_trace);_overlay.isChat=YES;_overlay.returnButton=[NSObject new];_panel=SNode(@"panel",_trace);_panel.contentView=SNode(@"panel-content",_trace);_status=SNode(@"status",_trace);_bookmarkButton=SNode(@"bookmark",_trace);_card=SNode(@"card",_trace);_actions=[FYGrammarActionState new];_sentenceID=@"sentence";}return self;}
@end
static StudyRendererFacts*activeStudyFacts;
@interface StudyPrimitiveHooks:NSObject
+ (id)newChatFact;
+ (id)wrappingLabelWithString:(NSString*)text;
+ (void)activateConstraints:(NSArray*)constraints;
@end
@implementation StudyPrimitiveHooks
+ (id)newChatFact{return (id)activeStudyFacts.madeChat;}
+ (id)wrappingLabelWithString:(NSString*)text{StudyNodeFact*n=SNode(@"label",activeStudyFacts.trace);n.stringValue=text;[activeStudyFacts.labels addObject:n];return n;}
+ (void)activateConstraints:(NSArray*)constraints{for(StudyConstraintFact*c in constraints)c.active=YES;}
@end
static IMP SwapClass(Class c,SEL sel,Class from,SEL replacement){Class meta=object_getClass(c);Method m=class_getClassMethod(c,sel);IMP old=method_getImplementation(m);class_replaceMethod(meta,sel,method_getImplementation(class_getClassMethod(from,replacement)),method_getTypeEncoding(m));return old;}
static void RestoreClass(Class c,SEL sel,IMP old){Method m=class_getClassMethod(c,sel);class_replaceMethod(object_getClass(c),sel,old,method_getTypeEncoding(m));}
@protocol StudyRendererDriver<NSObject>
- (FYStudyChatView*)makeStudyChatViewForOverlay:(BOOL)overlay;
- (void)refreshStudyChatViews;
- (void)configureStudyOverlay:(NSPanel*)panel;
- (void)updateInlineReturnButtonVisibility;
- (NSScrollView*)quickSentenceScrollView;
- (void)captureQuickSentenceScrollPosition;
- (void)restoreQuickSentenceScrollPosition;
- (void)selectQuickStructure:(NSButton*)sender;
- (void)updateQuickGrammarBookmark;
- (void)performQuickGrammar:(NSButton*)sender;
- (NSTextField*)quickReadingLabel:(NSString*)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor*)color;
- (NSView*)quickReadingCard:(NSStackView*)stack tinted:(BOOL)tinted;
- (NSView*)performQuickDetail:(FYGrammarItem*)item;
@end
typedef id<StudyRendererDriver>(^StudyRendererFactory)(StudyRendererFacts*f);
static void RunStudyRendererFixture(id<StudyRendererDriver>d,StudyRendererFacts*f){
 Check(NSApp==nil,@"native renderer fixture creates no application/view/control/window");activeStudyFacts=f;IMP chatNew=SwapClass(FYStudyChatView.class,@selector(new),StudyPrimitiveHooks.class,@selector(newChatFact));
 @try{StudyNodeFact*v=(id)[d makeStudyChatViewForOverlay:NO];Check(v==f.madeChat&&!v.translatesAutoresizingMaskIntoConstraints&&!v.closeVisible&&!v.onClose&&v.onSend&&v.onLatest&&v.onReturn,@"main Chat factory executes original body with same primitive view and correct callbacks/hidden close");v.onSend(@"question");v.onLatest();v.onReturn();Check(f.ensures==1&&f.sends==1&&f.latest==1&&f.returns==1&&[f.sent isEqual:@"question"],@"actual weak callbacks call original concrete receiver actions and preserve text");f.madeChat=SNode(@"overlay-made",f.trace);f.madeChat.isChat=YES;v=(id)[d makeStudyChatViewForOverlay:YES];Check(v.closeVisible&&v.onClose&&v.onSend&&v.onReturn,@"overlay constructor binds close without hiding it");v.onClose();Check(f.closes==1,@"overlay close callback reaches original receiver");}@finally{RestoreClass(FYStudyChatView.class,@selector(new),chatNew);}Check(method_getImplementation(class_getClassMethod(FYStudyChatView.class,@selector(new)))==chatNew,@"private chat primitive factory IMP restored");
 [f.trace removeAllObjects];[d refreshStudyChatViews];Check([f.trace isEqual:@[@"main-context",@"main-messages",@"main-sending",@"overlay-context",@"overlay-messages",@"overlay-sending"]]&&f.main.messages==f.session.messages&&!f.main.sending&&[f.main.context isEqual:@"source"]&&[f.main.contextLabel isEqual:@"当前讨论句 · 点击引用最新句可更新"],@"two real refresh algorithms keep context/messages/sending sequence and same messages alias");f.resolving=YES;[d refreshStudyChatViews];Check(f.main.sending&&[f.main.contextLabel isEqual:@"正在识别当前画面的对白…"],@"context resolving preserves busy label and sending gate");f.resolving=NO;f.session.sending=YES;[d refreshStudyChatViews];Check(f.overlay.sending,@"session network busy independently keeps sending UI state");f.main=nil;f.overlay=nil;[f.trace removeAllObjects];[d refreshStudyChatViews];Check(f.trace.count==0,@"nil main/overlay use original NSNull/type guard without messages");f.main=SNode(@"main",f.trace);f.main.isChat=YES;f.overlay=SNode(@"overlay",f.trace);f.overlay.isChat=YES;f.overlay.returnButton=[NSObject new];
 [d configureStudyOverlay:(id)f.panel];Check(!f.panel.hidesOnDeactivate&&!f.panel.releasedWhenClosed&&f.panel.level==NSFloatingWindowLevel&&f.panel.collectionBehavior==(NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary)&&f.panel.movableByWindowBackground&&[f.panel.backgroundColor isEqual:FYAdventureColor(@"paper")],@"panel configuration keeps original native level/Space/style values");[d updateInlineReturnButtonVisibility];Check(!f.overlay.returnVisible&&!f.returnButton,@"missing snapshot hides overlay return and clears alias");f.returnSnapshot=[FYInlineBlockSnapshot new];f.returnSnapshot.sourceText=@"";[d updateInlineReturnButtonVisibility];Check(!f.overlay.returnVisible,@"empty snapshot does not show return");f.returnSnapshot.sourceText=@"valid";[d updateInlineReturnButtonVisibility];Check(f.overlay.returnVisible&&f.returnButton==f.overlay.returnButton&&!f.main.returnVisible,@"return is overlay-only and points to original view button identity");
 f.panel=nil;Check(![d quickSentenceScrollView],@"missing panel returns no scroll");f.panel=SNode(@"panel",f.trace);f.panel.contentView=SNode(@"panel-content",f.trace);StudyNodeFact*container=(id)f.panel.contentView;container.subviews=@[[NSObject new]];Check(![d quickSentenceScrollView],@"native subview search ignores non-scroll objects");StudyNodeFact*scroll=SNode(@"scroll",f.trace);scroll.isScroll=YES;scroll.contentView=Node(@"clip",f.trace);scroll.contentView.bounds=NSMakeRect(5,41,100,80);scroll.documentView=Node(@"doc",f.trace);scroll.documentView.frame=NSMakeRect(0,0,300,400);container.subviews=@[[NSObject new],scroll];f.scroll=scroll;Check([d quickSentenceScrollView]==(id)scroll,@"search returns exact first native scroll subview");[d captureQuickSentenceScrollPosition];Check(f.offset==41,@"capture saves actual current vertical origin");__weak StudyRendererFacts*wf=f;scroll.documentView.onLayout=^{wf.offset=120;wf.scroll.documentView.frame=NSMakeRect(0,0,300,180);};[f.trace removeAllObjects];[d restoreQuickSentenceScrollPosition];Check(NSEqualPoints(scroll.contentView.lastPoint,NSMakePoint(0,100))&&[f.trace isEqual:@[@"doc-layout",@"scroll",@"reflect"]],@"restore reads offset/geometry after original layout, clamps vertical and resets horizontal zero");scroll.documentView.onLayout=nil;f.offset=-7;[d restoreQuickSentenceScrollPosition];Check(scroll.contentView.lastPoint.y==0,@"negative saved scroll clamps to zero");scroll.documentView.frame=NSMakeRect(0,0,50,20);f.offset=90;[d restoreQuickSentenceScrollPosition];Check(scroll.contentView.lastPoint.y==0,@"document smaller than clip clamps to zero");
 StudyNodeFact*button=SNode(@"button",f.trace);button.tag=-1;[d selectQuickStructure:(id)button];Check([f.status.stringValue isEqual:@"该片段的含义见结构图，未对应独立的语法条目。"]&&!f.selects,@"negative structure tag preserves original explanatory status");StudyNodeFact*a=SNode(@"a",f.trace),*b=SNode(@"b",f.trace);a.tag=0;b.tag=1;f.choices=@[a,b];button.tag=1;[d selectQuickStructure:(id)button];Check(f.selects==1&&f.selected==b,@"structure row dispatches exact original grammar-choice object through override");
 f.bookmark=nil;[d updateQuickGrammarBookmark];Check([f.bookmarkButton.title isEqual:@"＋ 收藏语法"]&&f.bookmarkButton.enabled,@"unbookmarked valid identity shows original enabled action");f.bookmark=[FYGrammarBookmark new];f.pending=YES;[d updateQuickGrammarBookmark];Check([f.bookmarkButton.title isEqual:@"已收藏 · 取消收藏"]&&!f.bookmarkButton.enabled,@"existing bookmark title and pending disable are independent");f.pending=NO;f.sentenceID=@"";[d updateQuickGrammarBookmark];Check(!f.bookmarkButton.enabled,@"missing sentence ID disables bookmark action");f.sentenceID=@"id";
 // Native selection body is invoked explicitly, not through the override used above.
 f.analysis=[FYAnalysisResult new];FYGrammarItem*item=[FYGrammarItem new];f.analysis.grammar=@[item,item];f.stack=nil;button.tag=-1;[d performQuickGrammar:(id)button];button.tag=2;[d performQuickGrammar:(id)button];button.tag=1;[d performQuickGrammar:(id)button];Check(!f.factories,@"selection guards skip invalid index/missing stack before factory");f.stack=SNode(@"stack",f.trace);f.stack.enclosingScrollView=scroll;f.detail=SNode(@"old-detail",f.trace);[f.stack.arrangedSubviews addObject:f.detail];f.replacement=SNode(@"replacement",f.trace);f.structure=@[a,b];f.actions.expandedItem=item;scroll.contentView.bounds=NSMakeRect(22,320,100,80);scroll.documentView.frame=NSMakeRect(0,0,300,600);f.panel.contentView.onLayout=^{wf.scroll.documentView.frame=NSMakeRect(0,0,300,180);};[f.trace removeAllObjects];[d performQuickGrammar:(id)button];Check(f.index==1&&!f.actions.expandedItem&&f.selected==button&&a.state==NSControlStateValueOff&&b.state==NSControlStateValueOn&&f.detail==f.replacement&&[f.stack.arrangedSubviews isEqual:@[f.replacement]],@"selection keeps one index/action cache/button and exact replacement detail owner");Check(NSEqualPoints(scroll.contentView.lastPoint,NSMakePoint(22,100))&&f.panel.firstResponder==button&&[f.trace isEqual:@[@"remove-arranged",@"remove-view",@"factory",@"add-arranged",@"panel-content-layout",@"doc-layout",@"first-responder",@"scroll",@"reflect"]],@"native selected detail preserves removal/factory/layout/focus and post-layout clamp/read order");f.panel.contentView.onLayout=nil;
 IMP labelFactory=SwapClass(NSTextField.class,@selector(wrappingLabelWithString:),StudyPrimitiveHooks.class,@selector(wrappingLabelWithString:));IMP constraints=SwapClass(NSLayoutConstraint.class,@selector(activateConstraints:),StudyPrimitiveHooks.class,@selector(activateConstraints:));
 @try{StudyNodeFact*label=(id)[d quickReadingLabel:@"原文🙂\n次行" size:19 weight:NSFontWeightRegular color:NSColor.brownColor];NSParagraphStyle*p=[label.attributedStringValue attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];Check([label.attributedStringValue.string isEqual:@"原文🙂\n次行"]&&label.selectable&&!label.translatesAutoresizingMaskIntoConstraints&&label.maximumNumberOfLines==0&&label.font.pointSize==19&&p.lineSpacing==6&&label.compressionPriority==249,@"actual native label uses real font/paragraph/attributed UTF16 text and float priority without changing characters");label=(id)[d quickReadingLabel:nil size:12 weight:NSFontWeightRegular color:NSColor.brownColor];Check([label.stringValue isEqual:@""]&&label.attributedStringValue.length==0,@"nil label retains original empty text fallback");StudyNodeFact*stack=SNode(@"card-stack",f.trace);for(StudyNodeFact*n in @[f.card,stack]){n.leadingAnchor=[StudyAnchorFact new];n.trailingAnchor=[StudyAnchorFact new];n.topAnchor=[StudyAnchorFact new];n.bottomAnchor=[StudyAnchorFact new];for(StudyAnchorFact*a in @[n.leadingAnchor,n.trailingAnchor,n.topAnchor,n.bottomAnchor])a.constraints=f.constraints;}[d quickReadingCard:(id)stack tinted:YES];Check([f.card.fillColor isEqual:FYAdventureColor(@"reading")]&&[f.card.edgeColor isEqual:FYAdventureColor(@"reading")]&&[f.card.arrangedSubviews containsObject:stack]&&!stack.translatesAutoresizingMaskIntoConstraints&&f.constraints.count==4,@"native card keeps exact stack/color and four original constraints");Check([(StudyConstraintFact*)f.constraints[0] constant]==14&&[(StudyConstraintFact*)f.constraints[1] constant]==-14&&[(StudyConstraintFact*)f.constraints[2] constant]==12&&[(StudyConstraintFact*)f.constraints[3] constant]==-12,@"card padding constants and signs remain exact");for(StudyConstraintFact*c in f.constraints)Check(c.active,@"original constraint activation reaches each boundary object");item.name=@"助词";item.meaning=@"短义";item.matchedText=@"原句";item.explanation=@"解释";item.connection=@"接续";item.registerNote=@"书面";f.actions.expandedItem=item;[f.actions.explanations setObject:@"扩展说明" forKey:item];[f.labels removeAllObjects];NSView*detail=[d performQuickDetail:item];NSArray*texts=[f.labels valueForKey:@"stringValue"];Check(detail==(id)f.card&&[texts containsObject:@"助词 · 短义"]&&[texts containsObject:@"原句 · 原句"]&&[texts containsObject:@"解释"]&&[texts containsObject:@"接续 · 接续\n书面"]&&[texts containsObject:@"扩展说明"],@"complete native detail body preserves heading/match/explanation/notes and real expanded-state text");Check(f.expand.tag==1&&[f.expand.title isEqual:@"展开解释"]&&f.actionUpdates==1,@"detail retains original quick action tag/title and update-before-status flow");item.meaning=@"这是一段超过十六个字符的长含义用于保留独立行";item.matchedText=nil;item.explanation=nil;item.connection=nil;item.registerNote=nil;[f.actions.explanations removeObjectForKey:item];[f.actions.errors setObject:@"扩展失败" forKey:item];[f.labels removeAllObjects];[d performQuickDetail:item];texts=[f.labels valueForKey:@"stringValue"];Check([texts.firstObject isEqual:@"助词"]&&[texts containsObject:item.meaning]&&[texts containsObject:@"扩展失败"],@"long meaning keeps original separate line and expanded error fallback");}@finally{RestoreClass(NSTextField.class,@selector(wrappingLabelWithString:),labelFactory);RestoreClass(NSLayoutConstraint.class,@selector(activateConstraints:),constraints);}Check(method_getImplementation(class_getClassMethod(NSTextField.class,@selector(wrappingLabelWithString:)))==labelFactory&&method_getImplementation(class_getClassMethod(NSLayoutConstraint.class,@selector(activateConstraints:)))==constraints,@"private label/constraint factory IMPs restored");Check(NSApp==nil,@"all tested native bodies remain headless; full Quick graph not executed");activeStudyFacts=nil;
}
static void RunStudyRendererLeases(StudyRendererFactory factory){StudyRendererFacts*f=[StudyRendererFacts new];activeStudyFacts=f;IMP prior=SwapClass(FYStudyChatView.class,@selector(new),StudyPrimitiveHooks.class,@selector(newChatFact));__weak id weakReceiver;@try{@autoreleasepool{id<StudyRendererDriver>d=factory(f);weakReceiver=d;[d makeStudyChatViewForOverlay:YES];}Check(!weakReceiver,@"real chat callback blocks do not retain their concrete receiver");f.madeChat.onSend(@"late");f.madeChat.onLatest();f.madeChat.onReturn();f.madeChat.onClose();Check(!f.sends&&!f.latest&&!f.returns&&!f.closes,@"late actual weak callbacks safely ignore released receiver");}@finally{RestoreClass(FYStudyChatView.class,@selector(new),prior);activeStudyFacts=nil;}}
