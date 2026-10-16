#import "FYLearningAnalysisCacheRepository.h"
#import "FYLearningDatabaseSession.h"
#import "FYLearningSQLite.h"

// 把 FYAnalysisResult 序列化成可存库的 JSON 字典；反向解析用于读取缓存。
static NSDictionary *FYDictionaryFromAnalysisResult(FYAnalysisResult *result) {
    NSMutableArray *grammar = [NSMutableArray arrayWithCapacity:result.grammar.count];
    for (FYGrammarItem *item in result.grammar) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"catalog_id"] = item.catalogID ?: [NSNull null];
        dict[@"name"] = item.name ?: @"";
        dict[@"matched_text"] = item.matchedText ?: @"";
        dict[@"connection"] = item.connection ?: [NSNull null];
        dict[@"meaning_zh"] = item.meaning ?: [NSNull null];
        dict[@"explanation_zh"] = item.explanation ?: [NSNull null];
        dict[@"register_note"] = item.registerNote ?: [NSNull null];
        dict[@"reference_level"] = item.referenceLevel ?: [NSNull null];
        dict[@"level_source_title"] = item.levelSourceTitle ?: [NSNull null];
        dict[@"level_source_url"] = item.levelSourceURL ?: [NSNull null];
        dict[@"level_verified"] = @(item.levelVerified);
        dict[@"matched_range_location"] = @(item.matchedRange.location == NSNotFound ? -1 : (NSInteger)item.matchedRange.location);
        dict[@"matched_range_length"] = @(item.matchedRange.length);
        [grammar addObject:dict];
    }

    NSMutableArray *vocabulary = [NSMutableArray arrayWithCapacity:result.vocabulary.count];
    for (FYVocabularyEntry *entry in result.vocabulary) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"surface"] = entry.surface ?: @"";
        dict[@"lemma"] = entry.lemma ?: [NSNull null];
        dict[@"reading"] = entry.reading ?: [NSNull null];
        dict[@"meaning_zh"] = entry.meaning ?: [NSNull null];
        [vocabulary addObject:dict];
    }

    return @{
        @"schema_version": @(result.schemaVersion),
        @"grammar": grammar,
        @"vocabulary": vocabulary,
        @"sentence_note_zh": result.sentenceNote ?: [NSNull null],
        @"structure_parts": result.structureParts ?: @[],
        @"structure_title_zh": result.structureTitle ?: [NSNull null],
    };
}

static NSString *FYStringOrEmpty(id value) {
    if ([value isKindOfClass:NSString.class]) { return value; }
    return @"";
}

static NSString *FYOptionalString(id value) {
    if ([value isKindOfClass:NSString.class]) { return value; }
    return nil;
}

static FYAnalysisResult *FYAnalysisResultFromDictionary(NSDictionary *dict) {
    // Corrupt/old cache data is a cache miss, not an exception or a fabricated no-result.
    if (![dict[@"schema_version"] isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)dict[@"schema_version"]) == CFBooleanGetTypeID() || [dict[@"schema_version"] doubleValue] != 1 ||
        ![dict[@"grammar"] isKindOfClass:NSArray.class] || ![dict[@"vocabulary"] isKindOfClass:NSArray.class]) { return nil; }
    for (id raw in dict[@"grammar"]) {
        if (![raw isKindOfClass:NSDictionary.class]) { return nil; }
        NSDictionary *g = raw;
        if (![g[@"name"] isKindOfClass:NSString.class] || ![g[@"matched_text"] isKindOfClass:NSString.class] ||
            [g[@"name"] length] == 0 || [g[@"matched_text"] length] == 0 ||
            ![g[@"level_verified"] isKindOfClass:NSNumber.class] ||
            ![g[@"matched_range_location"] isKindOfClass:NSNumber.class] ||
            ![g[@"matched_range_length"] isKindOfClass:NSNumber.class] ||
            [g[@"matched_range_location"] integerValue] < -1 || [g[@"matched_range_length"] integerValue] < 0) { return nil; }
    }
    for (id raw in dict[@"vocabulary"]) {
        if (![raw isKindOfClass:NSDictionary.class] || ![raw[@"surface"] isKindOfClass:NSString.class] || [raw[@"surface"] length] == 0) { return nil; }
    }
    FYAnalysisResult *result = [[FYAnalysisResult alloc] init];
    result.status = FYAnalysisStatusSuccess;
    result.schemaVersion = [dict[@"schema_version"] integerValue];
    result.sentenceNote = FYOptionalString(dict[@"sentence_note_zh"]);
    NSArray *parts=[dict[@"structure_parts"] isKindOfClass:NSArray.class]?dict[@"structure_parts"]:@[];
    BOOL validParts=parts.count>=2 && parts.count<=8;
    for(id part in parts){
        if(![part isKindOfClass:NSDictionary.class] || ![part[@"text"] isKindOfClass:NSString.class] || ![part[@"meaning"] isKindOfClass:NSString.class] || ![part[@"role"] isKindOfClass:NSString.class] || ![part[@"location"] isKindOfClass:NSNumber.class] || ![part[@"length"] isKindOfClass:NSNumber.class] || [part[@"location"] integerValue]<0 || [part[@"length"] integerValue]<=0){validParts=NO;break;}
    }
    result.structureParts=validParts?parts:@[];result.structureTitle=validParts?FYOptionalString(dict[@"structure_title_zh"]):nil;

    NSMutableArray<FYGrammarItem *> *grammar = [NSMutableArray array];
    for (id raw in dict[@"grammar"]) {
        if (![raw isKindOfClass:NSDictionary.class]) { continue; }
        NSDictionary *g = raw;
        FYGrammarItem *item = [[FYGrammarItem alloc] init];
        item.catalogID = FYOptionalString(g[@"catalog_id"]);
        item.name = FYStringOrEmpty(g[@"name"]);
        item.matchedText = FYStringOrEmpty(g[@"matched_text"]);
        item.connection = FYOptionalString(g[@"connection"]);
        item.meaning = FYOptionalString(g[@"meaning_zh"]);
        item.explanation = FYOptionalString(g[@"explanation_zh"]);
        item.registerNote = FYOptionalString(g[@"register_note"]);
        item.referenceLevel = FYOptionalString(g[@"reference_level"]);
        item.levelSourceTitle = FYOptionalString(g[@"level_source_title"]);
        item.levelSourceURL = FYOptionalString(g[@"level_source_url"]);
        item.levelVerified = [g[@"level_verified"] boolValue];
        NSInteger location = [g[@"matched_range_location"] isKindOfClass:NSNumber.class] ? [g[@"matched_range_location"] integerValue] : NSNotFound;
        NSInteger length = [g[@"matched_range_length"] isKindOfClass:NSNumber.class] ? [g[@"matched_range_length"] integerValue] : 0;
        item.matchedRange = location >= 0 ? NSMakeRange(location, length) : NSMakeRange(NSNotFound, 0);
        [grammar addObject:item];
    }
    result.grammar = grammar;

    NSMutableArray<FYVocabularyEntry *> *vocabulary = [NSMutableArray array];
    for (id raw in dict[@"vocabulary"]) {
        if (![raw isKindOfClass:NSDictionary.class]) { continue; }
        NSDictionary *v = raw;
        FYVocabularyEntry *entry = [[FYVocabularyEntry alloc] init];
        entry.kind = FYVocabularyKindWord;
        entry.surface = FYStringOrEmpty(v[@"surface"]);
        entry.lemma = FYOptionalString(v[@"lemma"]);
        entry.reading = FYOptionalString(v[@"reading"]);
        entry.meaning = FYOptionalString(v[@"meaning_zh"]);
        entry.completionSource = FYCompletionSourceAI;
        [vocabulary addObject:entry];
    }
    result.vocabulary = vocabulary;

    return result;
}

@interface FYLearningAnalysisCacheRepository ()
@property(nonatomic, strong) FYLearningDatabaseSession *session;
@end

@implementation FYLearningAnalysisCacheRepository
- (instancetype)initWithSession:(FYLearningDatabaseSession *)session {
    self = [super init];
    if (self) { _session = session; }
    return self;
}

- (NSError *)saveAnalysisResult:(FYAnalysisResult *)result
    sentenceID:(NSString *)sentenceID
    version:(NSInteger)version
    textHash:(NSString *)textHash
    promptVersion:(NSInteger)promptVersion
    catalogVersion:(NSInteger)catalogVersion
    modelConfig:(NSString *)modelConfig {
    NSError *error = [self.session ensureOpened];
    if (!error) {
        NSDictionary *dict = FYDictionaryFromAnalysisResult(result);
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        const char *sql = "INSERT OR REPLACE INTO analyses (sentence_id, version, text_hash, prompt_version, catalog_version, model_config, status, result_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 2, (int)version);
            sqlite3_bind_text(stmt, 3, FYTrimmed(textHash).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 4, (int)promptVersion);
            sqlite3_bind_int(stmt, 5, (int)catalogVersion);
            sqlite3_bind_text(stmt, 6, FYTrimmed(modelConfig).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 7, (int)result.status);
            sqlite3_bind_text(stmt, 8, FYTrimmed(jsonString).UTF8String, -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) != SQLITE_DONE) { error = FYStoreError(self.session.db, @"保存分析结果失败"); }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"准备分析结果语句失败");
        }
    }
    return error;
}

- (FYAnalysisResult *)fetchAnalysisForSentence:(NSString *)sentenceID
    version:(NSInteger)version
    modelConfig:(NSString **)outModelConfig
    error:(NSError **)outError {
    NSError *error = [self.session ensureOpened];
    FYAnalysisResult *result = nil;
    NSString *modelConfig = nil;
    if (!error) {
        const char *sql = "SELECT result_json, model_config, status FROM analyses WHERE sentence_id = ? AND version = ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self.session.db, sql, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, FYTrimmed(sentenceID).UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 2, (int)version);
            if (sqlite3_step(stmt) == SQLITE_ROW) {
                const unsigned char *json = sqlite3_column_text(stmt, 0);
                const unsigned char *model = sqlite3_column_text(stmt, 1);
                int status = sqlite3_column_int(stmt, 2);
                if (json) {
                    NSData *data = [[NSString stringWithUTF8String:(const char *)json] dataUsingEncoding:NSUTF8StringEncoding];
                    NSDictionary *dict = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
                    if ([dict isKindOfClass:NSDictionary.class]) {
                        result = FYAnalysisResultFromDictionary(dict);
                    }
                }
                if (result && (status == FYAnalysisStatusSuccess || status == FYAnalysisStatusNoResult)) { result.status = (FYAnalysisStatus)status; }
                else { result = nil; }
                if (model) { modelConfig = [NSString stringWithUTF8String:(const char *)model]; }
            }
            sqlite3_finalize(stmt);
        } else {
            error = FYStoreError(self.session.db, @"读取分析结果失败");
        }
    }
    if (outError) { *outError = error; }
    if (outModelConfig) { *outModelConfig = modelConfig; }
    return result;
}

@end
