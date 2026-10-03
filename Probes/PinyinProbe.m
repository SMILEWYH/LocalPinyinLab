#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@interface NSObject (VerifiedCCE)
- (id)initWithInputModeName:(NSString *)name scriptType:(NSUInteger)script;
- (void)setAdjustsWordFrequency:(BOOL)value;
- (void)setAddressBookEntries:(NSArray *)entries;
- (void)setAdditionalDictionaryPaths:(NSArray *)paths;
- (BOOL)addInput:(NSString *)text;
- (NSArray *)candidates;
- (void)reset;
- (void)setAutocorrectionEnabled:(BOOL)value;
- (NSString *)reading;
- (void)setStringContext:(NSString *)context;
- (NSString *)surface;
@end

static BOOL verify(Class cls, NSString *name, const char *encoding) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

static BOOL validRequest(id request) {
    if (![request isKindOfClass:[NSDictionary class]] ||
        ![request[@"pinyin"] isKindOfClass:[NSString class]] ||
        ![request[@"context"] isKindOfClass:[NSString class]]) return NO;
    NSString *query = request[@"pinyin"];
    return query.length <= 128 && [request[@"context"] length] <= 512 &&
        [query rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz'"] invertedSet]].location == NSNotFound;
}

static NSArray *queryEngine(id engine, NSString *input, NSString *context, BOOL records) {
    [engine reset];
    [engine setStringContext:context];
    [engine addInput:input];
    NSMutableArray *texts = [NSMutableArray array];
    for (id candidate in [engine candidates]) {
        if (verify([candidate class], @"surface", "@16@0:8") && verify([candidate class], @"reading", "@16@0:8")) {
            NSString *reading = [candidate reading] ?: @"";
            NSString *surface = [candidate surface];
            if (surface.length) [texts addObject:records ? @{@"text":surface, @"reading":reading} : surface];
        }
    }
    // Reuse dictionaries/engine initialization, not document or composition state.
    [engine reset];
    [engine setStringContext:@""];
    return texts;
}

static void emitJSON(id object, BOOL newline) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    fwrite(data.bytes, 1, data.length, stdout);
    if (newline) putchar('\n');
    fflush(stdout);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL serve = argc == 2 && strcmp(argv[1], "--serve") == 0;
        BOOL requestMode = argc == 2 && strcmp(argv[1], "--request") == 0;
        BOOL jsonMode = argc == 3 && strcmp(argv[1], "--json") == 0;
        alarm(15);
        void *handle = dlopen("/System/Library/PrivateFrameworks/CoreChineseEngine.framework/CoreChineseEngine", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) return 1;
        Class cls = NSClassFromString(@"CIMMecabraEngine");
        if (!verify(cls, @"initWithInputModeName:scriptType:", "@32@0:8@16Q24") ||
            !verify(cls, @"addInput:", "B24@0:8@16") ||
            !verify(cls, @"candidates", "@16@0:8") ||
            !verify(cls, @"reset", "v16@0:8") ||
            !verify(cls, @"setStringContext:", "v24@0:8@16") ||
            !verify(cls, @"setAutocorrectionEnabled:", "v20@0:8B16") ||
            !verify(cls, @"setAdjustsWordFrequency:", "v20@0:8B16") ||
            !verify(cls, @"setAddressBookEntries:", "v24@0:8@16") ||
            !verify(cls, @"setAdditionalDictionaryPaths:", "v24@0:8@16")) return 2;
        NSString * __unsafe_unretained *mode = (NSString * __unsafe_unretained *)dlsym(handle, "CIMInputModeIdentifierSimplifiedChinesePinyin");
        if (!mode || !*mode) return 3;
        @try {
            id engine = [[cls alloc] initWithInputModeName:*mode scriptType:0];
            [engine setAdjustsWordFrequency:NO];
            [engine setAutocorrectionEnabled:YES];
            [engine setAddressBookEntries:@[]];
            [engine setAdditionalDictionaryPaths:@[]];
            if (serve) {
                emitJSON(@{@"ready":@YES}, YES);
                alarm(0);
                // Bounded newline frames on anonymous pipes; EOF ends with the parent.
                char buffer[16386];
                while (fgets(buffer, sizeof(buffer), stdin)) {
                    @autoreleasepool {
                        alarm(15);
                        size_t length = strlen(buffer);
                        if (length == 0 || buffer[length - 1] != '\n') return 5;
                        NSData *data = [NSData dataWithBytes:buffer length:length];
                        id request = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                        if (!validRequest(request)) return 5;
                        emitJSON(queryEngine(engine, request[@"pinyin"], request[@"context"], YES), YES);
                        memset(buffer, 0, sizeof(buffer));
                        alarm(0);
                    }
                }
            } else if (requestMode || jsonMode) {
                id request;
                if (requestMode) {
                    NSData *data = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
                    if (data.length > 16384) return 5;
                    request = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                } else {
                    request = @{@"pinyin":[NSString stringWithUTF8String:argv[2]] ?: @"", @"context":@""};
                }
                if (!validRequest(request)) return 5;
                emitJSON(queryEngine(engine, request[@"pinyin"], request[@"context"], requestMode), NO);
            } else {
                for (NSString *input in @[@"nihao", @"xiexie", @"xuexi"]) {
                    NSArray *texts = queryEngine(engine, input, @"", NO);
                    printf("%s count=%lu\n", input.UTF8String, (unsigned long)texts.count);
                    for (NSString *text in [texts subarrayWithRange:NSMakeRange(0, MIN(9, texts.count))]) printf("  %s\n", text.UTF8String);
                }
            }
        } @catch (NSException *exception) {
            // Do not print exception descriptions: engine errors can contain input.
            return 4;
        }
    }
    return 0;
}
