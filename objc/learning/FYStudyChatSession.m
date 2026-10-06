#import "FYStudyChatSession.h"
@interface FYStudyChatSession ()
@property(nonatomic,copy) NSString *source;
@property(nonatomic,copy) NSString *translation;
@property(nonatomic,copy) NSArray<NSDictionary *> *messages;
@property(nonatomic) BOOL sending;
@property(nonatomic) NSInteger generation;
@end
@implementation FYStudyChatSession
- (instancetype)init {if((self=[super init])){_analyzer=[FYLearningAnalyzer new];_source=@"";_translation=@"";_messages=@[];}return self;}
- (void)changed {if(self.onChange){self.onChange();}}
- (void)cancel {self.generation++;self.sending=NO;[self.analyzer cancelAll];[self changed];}
- (void)referenceSource:(NSString *)source translation:(NSString *)translation {
    [self cancel];self.source=source ?: @"";self.translation=translation ?: @"";[self changed];
}
- (void)startNewConversationWithSource:(NSString *)source translation:(NSString *)translation {
    self.generation++;self.sending=NO;[self.analyzer cancelAll];
    self.messages=@[];self.source=source ?: @"";self.translation=translation ?: @"";[self changed];
}
- (void)send:(NSString *)question {
    NSString *q=[question stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!q.length || self.sending){return;}
    if(!self.source.length){self.messages=[self.messages arrayByAddingObject:@{@"role":@"assistant",@"content":@"还没有可引用的句子。先识别一条对白，或选择最近台词。",@"status":@"error"}];[self changed];return;}
    NSDictionary *user=@{@"role":@"user",@"content":q,@"source":self.source,@"translation":self.translation};
    self.messages=[self.messages arrayByAddingObject:user];self.sending=YES;NSInteger generation=++self.generation;
    NSMutableArray *request=[NSMutableArray array];NSUInteger start=self.messages.count>20?self.messages.count-20:0;
    for(NSUInteger i=start;i<self.messages.count;i++){
        NSDictionary *m=self.messages[i];if([m[@"status"] isEqualToString:@"error"]){continue;}
        NSString *content=m[@"content"];
        if([m[@"role"] isEqualToString:@"user"]){NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"question":content,@"source":m[@"source"] ?: @"",@"translation":m[@"translation"] ?: @""} options:0 error:NULL];content=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];}
        [request addObject:@{@"role":m[@"role"],@"content":content ?: @""}];
    }
    [self changed];
    __weak typeof(self) weakSelf=self;
    [self.analyzer answerConversation:request completion:^(NSString *answer,NSError *error){
        typeof(self) strongSelf=weakSelf;if(!strongSelf || generation!=strongSelf.generation){return;}
        strongSelf.sending=NO;
        NSDictionary *reply=@{@"role":@"assistant",@"content":error?[NSString stringWithFormat:@"发送失败：%@。可以重新发送问题。",error.localizedDescription]:(answer ?: @"未返回内容。"),@"status":error?@"error":@"complete"};
        strongSelf.messages=[strongSelf.messages arrayByAddingObject:reply];[strongSelf changed];
    }];
}
@end
