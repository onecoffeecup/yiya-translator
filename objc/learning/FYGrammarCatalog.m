#import "FYGrammarCatalog.h"

static NSString *FYTrim(NSString *value) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@interface FYGrammarCatalog ()
@property(nonatomic, copy) NSURL *url;
@property(nonatomic, strong) NSMutableArray<FYGrammarCatalogEntry *> *entries;
@property(nonatomic, strong) NSMutableDictionary<NSString *, FYGrammarCatalogEntry *> *byID;
@property(nonatomic, strong) NSMutableDictionary<NSString *, FYGrammarCatalogEntry *> *byName;
@property(nonatomic) NSInteger loadedCatalogVersion;
@end

@implementation FYGrammarCatalog

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _url = url;
        _entries = [NSMutableArray array];
        _byID = [NSMutableDictionary dictionary];
        _byName = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSInteger)catalogVersion {
    return self.loadedCatalogVersion;
}

- (NSArray<FYGrammarCatalogEntry *> *)allEntries {
    return [_entries copy];
}

- (BOOL)loadWithError:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:self.url];
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"FYGrammarCatalog" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无法读取语法目录文件"}];
        }
        return NO;
    }
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![root isKindOfClass:NSDictionary.class]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"FYGrammarCatalog" code:2 userInfo:@{NSLocalizedDescriptionKey: @"语法目录格式错误"}];
        }
        return NO;
    }

    NSArray *rawEntries = root[@"entries"];
    if (![rawEntries isKindOfClass:NSArray.class]) {
        if (error) {
            *error = [NSError errorWithDomain:@"FYGrammarCatalog" code:3 userInfo:@{NSLocalizedDescriptionKey: @"语法目录缺少 entries"}];
        }
        return NO;
    }

    [self.entries removeAllObjects];
    [self.byID removeAllObjects];
    [self.byName removeAllObjects];
    self.loadedCatalogVersion = [root[@"catalog_version"] isKindOfClass:NSNumber.class] ? [root[@"catalog_version"] integerValue] : 1;

    for (id raw in rawEntries) {
        if (![raw isKindOfClass:NSDictionary.class]) { continue; }
        NSDictionary *dict = raw;
        FYGrammarCatalogEntry *entry = [[FYGrammarCatalogEntry alloc] init];
        entry.catalogID = FYTrim(dict[@"catalog_id"] ?: @"");
        entry.name = FYTrim(dict[@"name"] ?: @"");
        entry.referenceLevel = FYTrim(dict[@"reference_level"] ?: @"");
        entry.connection = dict[@"connection"];
        entry.meaning = dict[@"meaning"];
        entry.contentOrigin = FYTrim(dict[@"content_origin"] ?: @"project_original");
        entry.levelReviewStatus = FYTrim(dict[@"level_review_status"] ?: @"pending");
        entry.reviewedAt = dict[@"reviewed_at"];
        entry.sourceURL = dict[@"source_url"];
        entry.sourceTitle = dict[@"source_title"];

        NSArray *aliases = dict[@"aliases"];
        if ([aliases isKindOfClass:NSArray.class]) {
            NSMutableArray<NSString *> *aliasList = [NSMutableArray array];
            for (id alias in aliases) {
                if ([alias isKindOfClass:NSString.class]) { [aliasList addObject:FYTrim(alias)]; }
            }
            entry.aliases = aliasList;
        }
        NSArray *contentIDs = dict[@"content_source_ids"];
        NSMutableArray *signatureForms = [NSMutableArray new];
        if ([dict[@"signature_forms"] isKindOfClass:NSArray.class]) {
            for (id form in dict[@"signature_forms"]) {
                if ([form isKindOfClass:NSString.class] && FYTrim(form).length) { [signatureForms addObject:FYTrim(form)]; }
            }
        }
        entry.signatureForms = signatureForms;
        if ([contentIDs isKindOfClass:NSArray.class]) { entry.contentSourceIDs = contentIDs; }
        NSArray *references = dict[@"reference_sources"];
        if ([references isKindOfClass:NSArray.class]) { entry.referenceSources = references; }

        if (entry.catalogID.length == 0 || entry.name.length == 0) { continue; }
        [self.entries addObject:entry];
        self.byID[entry.catalogID] = entry;
        self.byName[entry.name] = entry;
        for (NSString *alias in entry.aliases) {
            if (alias.length > 0) { self.byName[alias] = entry; }
        }
    }
    return YES;
}

- (FYGrammarCatalogEntry *)entryForID:(NSString *)catalogID {
    NSString *key = FYTrim(catalogID);
    if (key.length == 0) { return nil; }
    return self.byID[key];
}

- (FYGrammarCatalogEntry *)entryForName:(NSString *)name {
    NSString *key = FYTrim(name);
    if (key.length == 0) { return nil; }
    return self.byName[key];
}

@end
