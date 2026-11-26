#import "SurfaceViewController.h"

#include "jni.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <assert.h>
#include <dlfcn.h>

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>

#include "EGL/egl.h"
#include "EGL/eglext.h"
#include "GL/osmesa.h"

#include "glfw_keycodes.h"
#include "ctxbridges/bridge_tbl.h"
#include "ctxbridges/osmesa_internal.h"
#include "utils.h"

int clientAPI;
static BOOL vulkanSurfaceRequested;

static void configureVulkanSurfaceLayer(void) {
    CAMetalLayer *layer = (CAMetalLayer *)SurfaceViewController.surface.layer;
    if (![layer isKindOfClass:CAMetalLayer.class]) {
        NSLog(@"[Vulkan] Surface view did not provide a CAMetalLayer (%@)", layer);
        return;
    }
    layer.device = MTLCreateSystemDefaultDevice();
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.contentsScale = UIScreen.mainScreen.scale;
    layer.drawableSize = CGSizeMake(layer.bounds.size.width * layer.contentsScale,
                                    layer.bounds.size.height * layer.contentsScale);
    NSLog(@"[Vulkan] Configured CAMetalLayer device=%@ pixelFormat=%lu drawable=%@",
          layer.device.name, (unsigned long)layer.pixelFormat, NSStringFromCGSize(layer.drawableSize));
}

void JNI_LWJGL_changeRenderer(const char* value_c) {
    JNIEnv *env;
    (*runtimeJavaVMPtr)->GetEnv(runtimeJavaVMPtr, (void **)&env, JNI_VERSION_1_4);
    jstring key = (*env)->NewStringUTF(env, "org.lwjgl.opengl.libname");
    jstring value = (*env)->NewStringUTF(env, value_c);
    jclass clazz = (*env)->FindClass(env, "java/lang/System");
    jmethodID method = (*env)->GetStaticMethodID(env, clazz, "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    (*env)->CallStaticObjectMethod(env, clazz, method, key, value);
}

void pojavTerminate() {
    CallbackBridge_nativeSetInputReady(NO);
    if (!br_terminate) return;
    br_terminate();
}

void* pojavGetCurrentContext() {
    return br_get_current();
}

int pojavInit(BOOL useStackQueue) {
    clientAPI = GLFW_OPENGL_API;
    isInputReady = 1;
    // UIKit delivers touch callbacks on the main thread, while Minecraft's
    // GLFW callbacks must run on the render thread inside glfwPollEvents().
    // Keep callbacks queued even when a renderer requests direct dispatch.
    isUseStackQueueCall = YES;
    NSLog(@"[InputBridge] GLFW callbacks queued on render thread (requested=%d)", useStackQueue);
    return JNI_TRUE;
}

int pojavInitOpenGL() {
    NSString *renderer = NSProcessInfo.processInfo.environment[@"RENDERER"];
    BOOL isAuto = [renderer isEqualToString:@"auto"];
    if (isAuto || [renderer isEqualToString:@ RENDERER_NAME_GL4ES]) {
        // Modern Minecraft versions request a desktop OpenGL context.  Use
        // MobileGlues for the auto path so the native bridge and LWJGL's
        // org.lwjgl.opengl.libname resolve to the same backend.  GL4ES
        // remains available as an explicit compatibility renderer.
        if (isAuto) {
            renderer = @ RENDERER_NAME_MOBILEGLUES;
        } else {
            renderer = @ RENDERER_NAME_GL4ES;
        }
        setenv("RENDERER", renderer.UTF8String, 1);
        NSLog(@"[Renderer] Selected %@ for OpenGL context", renderer);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MOBILEGLUES]) {
        renderer = @ RENDERER_NAME_MOBILEGLUES;
        setenv("RENDERER", renderer.UTF8String, 1);
        set_gl_bridge_tbl();
    } else if ([renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE]) {
        set_gl_bridge_tbl();
    } else if ([renderer hasPrefix:@"libOSMesa"]) {
        setenv("GALLIUM_DRIVER","zink",1);
        set_osm_bridge_tbl();
    }
    JNI_LWJGL_changeRenderer(renderer.UTF8String);
    // Preload renderer library
    dlopen([NSString stringWithFormat:@"@rpath/%@", renderer].UTF8String, RTLD_GLOBAL);

    return !br_init();
    //return 0;
}

void pojavSetWindowHint(int hint, int value) {
    if (hint == GLFW_CLIENT_API) {
        clientAPI = value;
        vulkanSurfaceRequested = value == GLFW_NO_API;
        NSLog(@"[Renderer] GLFW client API=%s (0x%x)",
              vulkanSurfaceRequested ? "Vulkan/NO_API" : "OpenGL", value);
        if (vulkanSurfaceRequested) configureVulkanSurfaceLayer();
    } else if (strcmp(getenv("RENDERER"), "auto")==0 && hint == GLFW_CONTEXT_VERSION_MAJOR) {
        switch (value) {
            case 1:
            case 2:
                setenv("RENDERER", RENDERER_NAME_GL4ES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_GL4ES);
                break;
            // case 4: use Zink?
            default:
                setenv("RENDERER", RENDERER_NAME_MOBILEGLUES, 1);
                JNI_LWJGL_changeRenderer(RENDERER_NAME_MOBILEGLUES);
                break;
        }
    }
}

void pojavSwapBuffers() {
    static unsigned int swapCount = 0;
    if (swapCount < 5) NSLog(@"[LWJGL-GLFW] pojavSwapBuffers #%u", ++swapCount);
    if (!br_swap_buffers) {
        NSDebugLog(@"EGLBridge: SwapBuffers callback is unavailable");
        return;
    }
    br_swap_buffers();
}

void pojavMakeCurrent(basic_render_window_t* window) {
    NSDebugLog(@"EGLBridge: MakeCurrent called");
    if (!br_make_current) {
        NSDebugLog(@"EGLBridge: MakeCurrent callback is unavailable");
        return;
    }
    br_make_current(window);
}

void* pojavCreateContext(basic_render_window_t* contextSrc) {
    if (clientAPI == GLFW_NO_API || vulkanSurfaceRequested) {
        // Game has selected Vulkan API to render
        configureVulkanSurfaceLayer();
        return (__bridge void *)SurfaceViewController.surface.layer;
    }

    static BOOL inited = NO;
    if (!inited) {
        inited = YES;
        pojavInitOpenGL();
    }

    if (!br_init_context) {
        NSDebugLog(@"EGLBridge: renderer context callback is unavailable");
        return NULL;
    }
    NSDebugLog(@"EGLBridge: Creating renderer context");
    void *context = br_init_context(contextSrc);
    NSDebugLog(@"EGLBridge: Renderer context returned: %p", context);
    return context;
}

void pojavSwapInterval(int interval) {
    if (!br_swap_interval) return;
    br_swap_interval(interval);
}
