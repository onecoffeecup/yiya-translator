#import "FYLiveReadingRenderer.h"

@implementation FYLiveReadingRenderer
- (NSAttributedString *)liveReadingText:(NSString *)text japanese:(BOOL)japanese receiver:(id<FYLiveReadingRenderSource>)receiver {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineSpacing = japanese ? 0 : 5;
    NSMutableAttributedString *reading = [[NSMutableAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName:japanese ? [receiver liveReadingJapaneseFontOfSize:19] : [receiver liveReadingUIFontOfSize:19],
        NSForegroundColorAttributeName:receiver.uiInk, NSParagraphStyleAttributeName:style}];
    NSString *speaker = nil, *body = nil;
    [receiver splitSpeakerAndBody:text speaker:&speaker body:&body];
    if (!japanese && speaker.length) {
        NSString *sourceSpeaker = nil;
        [receiver splitSpeakerAndBody:receiver.displayedSourceText speaker:&sourceSpeaker body:NULL];
        // Chinese short sentences also look like CJK names to the OCR helper.
        // Only a matching source label may receive secondary speaker styling.
        if (![speaker isEqualToString:sourceSpeaker]) { speaker = nil; }
    }
    if (speaker.length && body.length && body.length < text.length) {
        // Style the existing prefix without deleting or inserting characters.
        [reading addAttributes:@{NSFontAttributeName:[receiver liveReadingUIFontOfSize:13],
            NSForegroundColorAttributeName:receiver.uiMuted} range:NSMakeRange(0, text.length-body.length)];
    }
    return reading;
}

- (void)updateLiveSourceReadingHeightWithReceiver:(id<FYLiveReadingRenderSource>)receiver {
    NSScrollView *scroll = receiver.learningSourceTextView.enclosingScrollView;
    if (!scroll || NSWidth(scroll.contentView.bounds) <= 0) { return; }
    // Measure the actual styled text after layout; a pre-layout narrow width
    // must not leave a short sentence with a tall viewport after resizing.
    CGFloat width = MAX(1, NSWidth(scroll.contentView.bounds)-2*receiver.learningSourceTextView.textContainer.lineFragmentPadding);
    CGFloat height = [receiver.learningSourceTextView.textStorage boundingRectWithSize:NSMakeSize(width, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading].size.height;
    receiver.sourceReadingHeight.constant = MIN(190, MAX(42, ceil(height)+12));
}

- (void)refreshLiveDialoguePresentation:(NSString *)source receiver:(id<FYLiveReadingRenderSource>)receiver {
    NSString *speaker = nil;
    NSString *body = source ?: @"";
    [receiver splitSpeakerAndBody:source speaker:&speaker body:&body];
    if (receiver.liveScreenSpeakerLabel) {
        receiver.liveScreenSpeakerLabel.stringValue = speaker.length ? speaker : @"";
        receiver.liveScreenSpeakerLabel.hidden = speaker.length == 0;
    }
    if (receiver.liveScreenDialogueLabel) {
        receiver.liveScreenDialogueLabel.stringValue = body.length ? body : @"等待识别对白";
    }
    [receiver refreshLiveChips];
}

- (void)refreshLearningStatusWithReceiver:(id<FYLiveReadingRenderSource>)receiver {
    BOOL pinned = receiver.learningCoordinator.isPinned;
    receiver.learningPinnedLabel.stringValue = pinned ? (receiver.learningCoordinator.hasNewerSentence ? @"已固定 · 有新台词" : @"已固定") : @"跟随最新";
    receiver.learningPinnedLabel.textColor = receiver.uiAccent;
    receiver.grammarPinnedLabel.stringValue = receiver.learningPinnedLabel.stringValue;
    receiver.pinSentenceButton.title = pinned ? @"跟随最新" : @"固定此句";
    BOOL hasSentence = receiver.learningCoordinator.currentSentenceID.length > 0 && receiver.learningCoordinator.currentSourceText.length > 0;
    receiver.pinSentenceButton.enabled = hasSentence;
    receiver.analyzeButton.enabled = hasSentence && !receiver.learningAnalysisBusy;
    receiver.grammarPageAnalyzeButton.enabled = receiver.analyzeButton.enabled;
    [receiver applyGrammarTabSelection];
}
@end
