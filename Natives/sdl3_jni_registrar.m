#import <dlfcn.h>
#import <Foundation/Foundation.h>
#import <stdio.h>
#import "jni.h"

static void *AMResolveMainJNISymbol(const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol) return symbol;
    static void *mainImage;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mainImage = dlopen(NULL, RTLD_NOW);
    });
    return mainImage ? dlsym(mainImage, name) : NULL;
}

static BOOL AMRegisterClass(JNIEnv *env, const char *className,
                            const JNINativeMethod *methods, jint count) {
    jclass cls = (*env)->FindClass(env, className);
    if (!cls) return NO;
    if ((*env)->RegisterNatives(env, cls, (JNINativeMethod *)methods, count) != JNI_OK) {
        (*env)->DeleteLocalRef(env, cls);
        return NO;
    }
    (*env)->DeleteLocalRef(env, cls);
    return YES;
}

static BOOL AMRegisterResolved(JNIEnv *env, const char *className,
                               JNINativeMethod *methods, jint count) {
    for (jint i = 0; i < count; i++) {
        char symbolName[256];
        size_t prefixLength = (size_t)snprintf(symbolName, sizeof(symbolName), "Java_%s_%s", className, methods[i].name);
        for (size_t j = 5; j < prefixLength && j < sizeof(symbolName); j++) {
            if (symbolName[j] == '/') symbolName[j] = '_';
        }
        methods[i].fnPtr = AMResolveMainJNISymbol(symbolName);
        if (!methods[i].fnPtr) {
            fprintf(stderr, "[SDL3 JNI] missing executable symbol %s\n", symbolName);
            return NO;
        }
    }
    if (!AMRegisterClass(env, className, methods, count)) {
        fprintf(stderr, "[SDL3 JNI] RegisterNatives failed for %s\n", className);
        return NO;
    }
    fprintf(stderr, "[SDL3 JNI] registered %d methods for %s\n", count, className);
    return YES;
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    JNIEnv *env = NULL;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_4) != JNI_OK || !env) {
        return JNI_ERR;
    }

    JNINativeMethod bridgeMethods[] = {
        {"nativePrepare", "()V", NULL},
        {"nativeLoaded", "()V", NULL},
        {"nativeInit", "(JI)Z", NULL},
        {"nativeInitSubSystem", "(JI)Z", NULL},
        {"nativeCreateWindow", "(JJIIJ)J", NULL},
        {"nativeCreateWindowWithProperties", "(JI)J", NULL},
        {"nativeAttachWindow", "(JJ)V", NULL},
        {"nativeInvokeOnMain", "(JJJJJ)J", NULL},
        {"nativeRegisterInput", "()V", NULL},
        {"nativeSetInputReady", "()V", NULL},
        {"nativeSetGrabbing", "(Z)V", NULL},
        {"nativeSetControllerPassthrough", "(Z)V", NULL},
        {"nativeLastMainError", "()Ljava/lang/String;", NULL},
    };
    if (!AMRegisterResolved(env, "org/lwjgl/sdl/SDL3Bridge", bridgeMethods,
                            (jint)(sizeof(bridgeMethods) / sizeof(bridgeMethods[0])))) {
        return JNI_ERR;
    }

    JNINativeMethod glMethods[] = {
        {"nativeSetDrawableSize", "(JII)V", NULL},
    };
    if (!AMRegisterResolved(env, "org/lwjgl/sdl/SDL3GLContext", glMethods,
                            (jint)(sizeof(glMethods) / sizeof(glMethods[0])))) {
        return JNI_ERR;
    }

    JNINativeMethod lifecycleMethods[] = {
        {"nativeIsBackground", "()Z", NULL},
    };
    if (!AMRegisterResolved(env, "org/lwjgl/sdl/SDL3Lifecycle", lifecycleMethods,
                            (jint)(sizeof(lifecycleMethods) / sizeof(lifecycleMethods[0])))) {
        return JNI_ERR;
    }

    return JNI_VERSION_1_4;
}
