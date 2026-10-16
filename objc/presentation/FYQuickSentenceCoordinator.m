#import "FYQuickSentenceCoordinator.h"

@implementation FYQuickSentenceCoordinator
- (void)cancelAnalysisWithReceiver:(id<FYQuickSentenceAnalysisSource>)receiver {
    [receiver.quickGrammarActions reset];
    receiver.quickAnalysisGeneration++;
    receiver.quickSentenceAnalyzing=NO;
    [receiver.quickSentenceAnalyzer cancelAll];
}

- (void)analyzeWithReceiver:(id<FYQuickSentenceAnalysisSource>)receiver {
    if(!receiver.quickSentenceRequested || !receiver.quickSentenceSource.length || receiver.quickSentenceAnalyzing){return;}
    [receiver cancelQuickSentenceAnalysis];
    receiver.quickSentenceAnalysis=nil;receiver.quickSentenceAnalysisError=nil;receiver.quickSelectedGrammarIndex=0;
    receiver.quickSentenceAnalysisSource=receiver.quickSentenceSource;
    receiver.quickSentenceAnalysisTranslation=receiver.quickSentenceTranslation ?: @"";
    if(!receiver.quickSentenceAnalyzer){receiver.quickSentenceAnalyzer=[FYLearningAnalyzer new];}
    FYLearningAnalyzer *analyzer=receiver.quickSentenceAnalyzer;
    [receiver configureQuickSentenceAnalyzer:analyzer];
    NSString *source=receiver.quickSentenceSource;NSString *translation=receiver.quickSentenceTranslation;
    NSInteger generation=receiver.quickAnalysisGeneration;
    receiver.quickSentenceAnalyzing=YES;[receiver renderQuickSentence];
    [analyzer analyzeSentence:source translation:translation completion:^(FYAnalysisResult *result,NSError *error){
        if(generation!=receiver.quickAnalysisGeneration || !receiver.quickSentenceRequested ||
           ![source isEqualToString:receiver.quickSentenceSource]){return;}
        receiver.quickSentenceAnalyzing=NO;
        receiver.quickSentenceAnalysis=error?nil:result;
        receiver.quickSentenceAnalysisError=error.localizedDescription;
        [receiver renderQuickSentence];
    }];
}

- (BOOL)sentenceIsBookmarkedWithReceiver:(id<FYQuickSentenceBookmarkSource>)receiver {
    for(FYRequestIdentity *identity in receiver.savedSentences){if([identity.sentenceID isEqualToString:receiver.quickSentenceID] && identity.version==receiver.quickSentenceVersion){return YES;}}return NO;
}

- (void)bookmarkSentenceWithReceiver:(id<FYQuickSentenceBookmarkSource>)receiver {
    if(receiver.sentenceBookmarkPending || !receiver.quickSentenceID.length){return;}
    FYRequestIdentity *identity=[FYRequestIdentity identityWithSentenceID:receiver.quickSentenceID version:receiver.quickSentenceVersion requestID:NSUUID.UUID.UUIDString sourceText:receiver.quickSentenceSource translation:receiver.quickSentenceTranslation];
    receiver.sentenceBookmarkPending=YES;[receiver disableQuickSentenceBookmarkAction];
    [receiver.learningStore toggleSentenceBookmark:identity completion:^(BOOL saved,NSError *error){
        receiver.sentenceBookmarkPending=NO;if(error){[receiver setQuickBookmarkStatusText:[@"句子收藏失败：" stringByAppendingString:error.localizedDescription]];}
        [receiver refreshSavedSentences];
    }];
}

- (FYGrammarBookmark *)grammarBookmarkWithReceiver:(id<FYQuickSentenceBookmarkSource>)receiver {
    if(receiver.quickSelectedGrammarIndex>=(NSInteger)receiver.quickSentenceAnalysis.grammar.count){return nil;}
    FYGrammarItem *item=receiver.quickSentenceAnalysis.grammar[receiver.quickSelectedGrammarIndex];
    for(FYGrammarBookmark *bookmark in receiver.grammarBookmarks){if([bookmark.sentenceID isEqualToString:receiver.quickSentenceID] && bookmark.version==receiver.quickSentenceVersion && [bookmark.name isEqualToString:item.name]){return bookmark;}}
    return nil;
}

- (void)bookmarkGrammarWithReceiver:(id<FYQuickSentenceBookmarkSource>)receiver {
    if(receiver.quickGrammarBookmarkPending || !receiver.quickSentenceID.length || receiver.quickSelectedGrammarIndex>=(NSInteger)receiver.quickSentenceAnalysis.grammar.count){return;}
    FYGrammarItem *item=receiver.quickSentenceAnalysis.grammar[receiver.quickSelectedGrammarIndex];
    NSString *sentenceID=receiver.quickSentenceID;NSInteger version=receiver.quickSentenceVersion;
    NSString *source=receiver.quickSentenceSource,*translation=receiver.quickSentenceTranslation;
    receiver.quickGrammarBookmarkPending=YES;[receiver updateQuickGrammarBookmark];
    void (^finish)(NSError *)=^(NSError *error){
        receiver.quickGrammarBookmarkPending=NO;
        if([sentenceID isEqualToString:receiver.quickSentenceID] && version==receiver.quickSentenceVersion){[receiver setQuickBookmarkStatusText:error?[@"收藏失败：" stringByAppendingString:error.localizedDescription]:@"收藏已更新，可在单词学习的语法收藏中查看。"];}
        [receiver refreshGrammarBookmarks:nil];[receiver updateQuickGrammarBookmark];
    };
    [receiver.learningStore fetchGrammarBookmarksWithCompletion:^(NSArray<FYGrammarBookmark *> *bookmarks,NSError *error){
        if(error){finish(error);return;}
        FYGrammarBookmark *existing=nil;
        for(FYGrammarBookmark *bookmark in bookmarks){if([bookmark.sentenceID isEqualToString:sentenceID] && bookmark.version==version && [bookmark.name isEqualToString:item.name]){existing=bookmark;break;}}
        if(existing){[receiver.learningStore deleteGrammarBookmark:existing.bookmarkID completion:finish];}
        else{FYGrammarBookmark *bookmark=[FYGrammarBookmark new];bookmark.name=item.name;bookmark.catalogID=item.catalogID;bookmark.sentenceID=sentenceID;bookmark.version=version;bookmark.sourceTextSnapshot=source;bookmark.translationSnapshot=translation;[receiver.learningStore addGrammarBookmark:bookmark completion:finish];}
    }];
}
@end
