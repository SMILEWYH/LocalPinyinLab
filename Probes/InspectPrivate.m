#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// 只加载框架并打印运行时签名；不创建引擎、不访问词库、不调用候选/学习。
int main(void) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/CoreChineseEngine.framework/CoreChineseEngine", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) { puts(dlerror()); return 1; }
        for (NSString *name in @[@"CIMMecabraEngine", @"CIMMecabraController", @"CIMMecabraCandidate", @"CIMCandidate"]) {
            Class cls = NSClassFromString(name);
            printf("CLASS %s superclass=%s\n", name.UTF8String, class_getName(class_getSuperclass(cls)));
            unsigned int count = 0;
            Method *methods = class_copyMethodList(cls, &count);
            for (unsigned int i = 0; i < count; i++) {
                printf("- %s : %s\n", sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i]));
            }
            free(methods);
            methods = class_copyMethodList(object_getClass(cls), &count);
            for (unsigned int i = 0; i < count; i++) {
                printf("+ %s : %s\n", sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i]));
            }
            free(methods);
        }
        for (const char **symbol = (const char *[]){"MecabraCreate", "MecabraCreateWithOptions", "MecabraAnalyzeString", "MecabraGetCandidateCount", "MecabraGetCandidateAtIndex", NULL}; *symbol; symbol++) {
            printf("SYMBOL %s: %s\n", *symbol, dlsym(handle, *symbol) ? "present" : "absent");
        }
        dlclose(handle);
    }
    return 0;
}
