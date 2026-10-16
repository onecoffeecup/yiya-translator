#import "inline/FYInlineTextMeasurer.h"
#import "FYLocalFont.h"
#import <objc/runtime.h>
// Explicitly exercise the existing invalid-style exception contract.
#pragma clang diagnostic ignored "-Wnonnull"
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(2);}}
// Count native calls while executing the real AppKit NSString implementation.
@interface MeasuredString : NSString
@property(nonatomic,copy) NSString *value;
@property(nonatomic) NSUInteger boundsCalls;
@end
@implementation MeasuredString
- (instancetype)initWithText:(NSString *)value {if((self=[super init]))_value=[value copy];return self;}
- (NSUInteger)length{return self.value.length;}
- (unichar)characterAtIndex:(NSUInteger)i{return [self.value characterAtIndex:i];}
- (void)getCharacters:(unichar *)buffer range:(NSRange)range{[self.value getCharacters:buffer range:range];}
- (id)copyWithZone:(NSZone *)zone{return self;}
- (NSRect)boundingRectWithSize:(NSSize)size options:(NSStringDrawingOptions)options attributes:(NSDictionary *)attributes {
    self.boundsCalls++;return [super boundingRectWithSize:size options:options attributes:attributes];
}
@end
@interface MeasurementSourceProbe : FYInlineTextMeasurer
@property(nonatomic) NSUInteger providerReads,cacheReads;
@end
@implementation MeasurementSourceProbe
- (NSFont * (^)(CGFloat,NSFontWeight))fontProvider{self.providerReads++;return [super fontProvider];}
- (NSMutableDictionary *)layoutHeightCache{self.cacheReads++;return [super layoutHeightCache];}
@end
int main(void){@autoreleasepool{
    FYInlineTextMeasurer *measurer=[FYInlineTextMeasurer new];
    Check(!measurer.fontProvider&&!measurer.layoutHeightCache&&!NSApp,@"cold native measurer creates no font/cache/application/window");
    MeasurementSourceProbe *source=[MeasurementSourceProbe new];__block NSUInteger fontCalls=0;
    source.fontProvider=^NSFont *(CGFloat size,NSFontWeight weight){fontCalls++;return [NSFont systemFontOfSize:size weight:weight];};
    NSFont *font=[measurer fontOfSize:17.35 weight:NSFontWeightRegular stateSource:source];
    Check(font&&font.pointSize==17.35&&fontCalls==1&&source.providerReads==2,@"real font provider called once after exactly two original getter reads");
    source.fontProvider=nil;source.providerReads=0;
    NSFont *fallback=[measurer fontOfSize:17 weight:NSFontWeightSemibold stateSource:source];
    NSFont *expectedFallback=FYLocalFontNamed(@"STYuanti-SC-Bold",17)?:[NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    Check([fallback isEqual:expectedFallback]&&source.providerReads==1,@"missing provider uses same local available-font/system fallback and single read");
    NSParagraphStyle *style=[measurer paragraphStyleWithLineSpacing:6];
    Check(style.lineBreakMode==NSLineBreakByCharWrapping&&style.lineSpacing==6,@"real paragraph factory preserves character wrapping and spacing");
    NSString *body=@"合成测量正文。これは本物の文字計測です。Repeated English words keep native wrapping and font leading.\n下一行保留。";
    NSDictionary *attributes=FYInlineTextAttributes(font,style);
    Check(attributes[NSFontAttributeName]==font&&attributes[NSParagraphStyleAttributeName]==style,@"measurement attributes retain same original font/style objects");
    NSSize limit=NSMakeSize(133,CGFLOAT_MAX);
    NSRect native=[body boundingRectWithSize:limit options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:attributes];
    Check(NSEqualRects(FYInlineMeasureTextWithAttributes(body,limit,attributes),native),@"standalone styled primitive equals real AppKit bounds exactly");
    NSRect nativePlain=[body boundingRectWithSize:NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:font}];
    Check(NSEqualRects(FYInlineMeasurePlainText(body,NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX),font),nativePlain),@"standalone plain primitive preserves original unconstrained bounds");
    Check(FYInlineCeiledFontLineHeight(font)==ceil(font.ascender-font.descender+font.leading),@"real glyph metrics retain ceil after ascender/descender/leading");
    Check(FYInlineCeiledFontLineHeight([NSFont systemFontOfSize:21.75])==ceil([NSFont systemFontOfSize:21.75].ascender-[NSFont systemFontOfSize:21.75].descender+[NSFont systemFontOfSize:21.75].leading),@"fractional font sizes preserve rounding rather than fixed line estimate");
    source.cacheReads=0;
    Check([measurer measuredHeightForText:body width:133 font:font style:style stateSource:source]==ceil(NSHeight(native))&&source.cacheReads==1,@"uncached real measurement returns same native ceil and original one state read");
    source.cacheReads=0;
    Check([measurer measuredHeightForText:nil width:133 font:font style:style stateSource:source]==0&&source.cacheReads==0,@"nil text short circuits before cache or native measurement");
    Check([measurer measuredHeightForText:body width:4 font:font style:style stateSource:source]==0&&source.cacheReads==0,@"original width<=4 gate avoids state reads");
    source.layoutHeightCache=[NSMutableDictionary new];MeasuredString *counted=[[MeasuredString alloc]initWithText:body];source.cacheReads=0;
    CGFloat height=[measurer measuredHeightForText:counted width:133 font:font style:style stateSource:source];
    Check(height==ceil(NSHeight(native))&&counted.boundsCalls==1&&source.cacheReads==3,@"cache miss invokes actual NSString once and original gate/read/write getters");
    Check(source.layoutHeightCache.count==1,@"one original composite key stored in sole cache");
    source.cacheReads=0;
    Check([measurer measuredHeightForText:counted width:133 font:font style:style stateSource:source]==height&&counted.boundsCalls==1&&source.cacheReads==2,@"cache hit avoids actual native remeasurement and preserves two getter reads");
    CGFloat wider=[measurer measuredHeightForText:counted width:250 font:font style:style stateSource:source];
    Check(wider<height&&source.layoutHeightCache.count==2&&counted.boundsCalls==2,@"width is part of original key and real native wrapping changes height");
    NSParagraphStyle *moreSpacing=[measurer paragraphStyleWithLineSpacing:14];
    CGFloat spaced=[measurer measuredHeightForText:counted width:133 font:font style:moreSpacing stateSource:source];
    Check(spaced>height&&source.layoutHeightCache.count==3&&counted.boundsCalls==3,@"paragraph style key prevents reuse of old native line spacing");
    NSFont *larger=[NSFont systemFontOfSize:24];
    CGFloat big=[measurer measuredHeightForText:counted width:133 font:larger style:style stateSource:source];
    Check(big>height&&source.layoutHeightCache.count==4&&counted.boundsCalls==4,@"actual font key prevents reuse across selected sizes");
    [measurer measuredHeightForText:@"不同合成正文。" width:133 font:font style:style stateSource:source];
    Check(source.layoutHeightCache.count==5,@"text remains part of original native measurement key");
    NSArray *key=@[counted,@133,font,style];Check(source.layoutHeightCache[key].doubleValue==height,@"independent consumer reads original array-key representation");
    NSMutableDictionary *external=source.layoutHeightCache;source.layoutHeightCache=nil;[measurer measuredHeightForText:counted width:133 font:font style:style stateSource:source];
    Check(counted.boundsCalls==5&&external.count==5&&!source.layoutHeightCache,@"nil cache disables retention and leaves previous mutable alias unchanged");
    BOOL raised=NO;
    @try { FYInlineTextAttributes(font,(NSParagraphStyle *)nil); } @catch(NSException *e){raised=[e.name isEqual:NSInvalidArgumentException];}
    Check(raised,@"invalid nil styled input retains original native dictionary exception");
    __weak NSObject *providerToken;
    @autoreleasepool {NSObject *token=[NSObject new];providerToken=token;measurer.fontProvider=^NSFont *(CGFloat size,NSFontWeight weight){(void)token;return [NSFont systemFontOfSize:size weight:weight];};}
    @autoreleasepool {Check(providerToken!=nil,@"measurer owns original copied font-provider closure lifetime");}
    measurer.fontProvider=nil;Check(!providerToken,@"clearing provider releases captured resource without native work");
    __weak MeasurementSourceProbe *releasedSource;
    @autoreleasepool {MeasurementSourceProbe *temporary=[MeasurementSourceProbe new];releasedSource=temporary;[measurer measuredHeightForText:body width:133 font:font style:style stateSource:temporary];}
    Check(!releasedSource&&!class_getInstanceVariable(FYInlineTextMeasurer.class,"_stateSource"),@"idle measurer saves no synchronous state source or caller lease");
    printf("PASS native text measurement: %lu checks; actual AppKit fonts/bounds/styles, canonical cache keys/reads, opaque state lifetime, no UI initialization\n",(unsigned long)checks);
}return 0;}
