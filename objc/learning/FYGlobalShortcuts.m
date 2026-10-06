#import "FYGlobalShortcuts.h"
#import <Carbon/Carbon.h>
@interface FYGlobalShortcuts () {EventHandlerRef _handler;EventHotKeyRef _keys[3];}
@property(nonatomic,copy) NSArray<NSString *> *unavailable;
@end
static OSStatus FYHandleHotkey(EventHandlerCallRef next,EventRef event,void *context) {
    EventHotKeyID identity;OSStatus result=GetEventParameter(event,kEventParamDirectObject,typeEventHotKeyID,NULL,sizeof(identity),NULL,&identity);
    if(result!=noErr || identity.signature!='FYHK'){return eventNotHandledErr;}
    FYGlobalShortcuts *owner=(__bridge FYGlobalShortcuts *)context;
    if(owner.onAction){owner.onAction(identity.id);}return noErr;
}
@implementation FYGlobalShortcuts
- (void)start {
    [self stop];NSMutableArray *failed=[NSMutableArray array];
    EventTypeSpec type={kEventClassKeyboard,kEventHotKeyPressed};
    OSStatus result=InstallApplicationEventHandler(FYHandleHotkey,1,&type,(__bridge void *)self,&_handler);
    if(result!=noErr){self.unavailable=@[@"⌃⌥T",@"⌃⌥S",@"⌃⌥A"];return;}
    UInt32 codes[3]={kVK_ANSI_T,kVK_ANSI_S,kVK_ANSI_A};NSArray *names=@[@"⌃⌥T",@"⌃⌥S",@"⌃⌥A"];
    for(UInt32 i=0;i<3;i++){EventHotKeyID identity={'FYHK',i+1};if(RegisterEventHotKey(codes[i],controlKey|optionKey,identity,GetApplicationEventTarget(),0,&_keys[i])!=noErr){[failed addObject:names[i]];}}
    self.unavailable=failed;
}
- (void)stop {for(int i=0;i<3;i++){if(_keys[i]){UnregisterEventHotKey(_keys[i]);_keys[i]=NULL;}}if(_handler){RemoveEventHandler(_handler);_handler=NULL;}}
- (void)dealloc {[self stop];}
@end
