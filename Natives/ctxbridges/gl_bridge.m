#import <Foundation/Foundation.h>
#import "SurfaceViewController.h"

#include <dlfcn.h>
#include "bridge_tbl.h"
#include "environ.h"
#include "gl_bridge.h"
#include "utils.h"

static EGLDisplay g_EglDisplay;
static egl_library handle;
static void *g_renderer_handle;

void dlsym_EGL() {
    // EGL and GL must come from the same renderer.  Loading EGL from
    // TinyGL4ANGLE while MobileGlues supplies the GL entry points creates a
    // context that MobileGlues cannot see; glGetString then returns NULL and
    // LWJGL stops during capability initialization.
    const char *renderer = getenv("RENDERER");
    const char *eglLibrary = (renderer && !strcmp(renderer, RENDERER_NAME_MOBILEGLUES))
        ? RENDERER_NAME_MOBILEGLUES
        : RENDERER_NAME_MTL_ANGLE;
    g_renderer_handle = dlopen([NSString stringWithFormat:@"@rpath/%s", eglLibrary].UTF8String, RTLD_GLOBAL);
    NSCAssert(g_renderer_handle, @(dlerror()));
    handle.eglBindAPI = dlsym(g_renderer_handle, "eglBindAPI");
    handle.eglChooseConfig = dlsym(g_renderer_handle, "eglChooseConfig");
    handle.eglCreateContext = dlsym(g_renderer_handle, "eglCreateContext");
    handle.eglCreateWindowSurface = dlsym(g_renderer_handle, "eglCreateWindowSurface");
    handle.eglDestroyContext = dlsym(g_renderer_handle, "eglDestroyContext");
    handle.eglDestroySurface = dlsym(g_renderer_handle, "eglDestroySurface");
    handle.eglGetConfigAttrib = dlsym(g_renderer_handle, "eglGetConfigAttrib");
    handle.eglGetCurrentContext = dlsym(g_renderer_handle, "eglGetCurrentContext");
    handle.eglGetDisplay = dlsym(g_renderer_handle, "eglGetDisplay");
    handle.eglGetError = dlsym(g_renderer_handle, "eglGetError");
    handle.eglGetPlatformDisplay = dlsym(g_renderer_handle, "eglGetPlatformDisplay");
    handle.eglInitialize = dlsym(g_renderer_handle, "eglInitialize");
    handle.eglMakeCurrent = dlsym(g_renderer_handle, "eglMakeCurrent");
    handle.eglSwapBuffers = dlsym(g_renderer_handle, "eglSwapBuffers");
    handle.eglReleaseThread = dlsym(g_renderer_handle, "eglReleaseThread");
    handle.eglSwapInterval = dlsym(g_renderer_handle, "eglSwapInterval");
    handle.eglTerminate = dlsym(g_renderer_handle, "eglTerminate");
    handle.eglGetCurrentSurface = dlsym(g_renderer_handle, "eglGetCurrentSurface");
}

static bool gl_init() {
    dlsym_EGL();

    g_EglDisplay = handle.eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (g_EglDisplay == EGL_NO_DISPLAY) {
        NSDebugLog(@"EGLBridge: eglGetDisplay(EGL_DEFAULT_DISPLAY) returned EGL_NO_DISPLAY");
        return false;
    }
    if (!handle.eglInitialize(g_EglDisplay, NULL, NULL)) {
        NSDebugLog(@"EGLBridge: Error eglInitialize() failed: 0x%x", handle.eglGetError());
        return false;
    }
    return true;
}

gl_render_window_t* gl_init_context(gl_render_window_t *share) {
    gl_render_window_t* bundle = calloc(1, sizeof(gl_render_window_t));

    NSString *renderer = NSProcessInfo.processInfo.environment[@"RENDERER"];
    BOOL angleDesktopGL = [renderer isEqualToString:@ RENDERER_NAME_MTL_ANGLE];

    const EGLint attribs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT|EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, angleDesktopGL ? EGL_OPENGL_BIT : EGL_OPENGL_ES3_BIT,
        EGL_NONE
    };

    EGLint num_configs;
    EGLint vid;
    if (!handle.eglChooseConfig(g_EglDisplay, attribs, &bundle->config, 1, &num_configs)) {
        NSDebugLog(@"EGLBridge: Error couldn't get an EGL visual config: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    assert(bundle->config);
    assert(num_configs > 0);

    if (!handle.eglGetConfigAttrib(g_EglDisplay, bundle->config, EGL_NATIVE_VISUAL_ID, &vid)) {
        NSDebugLog(@"EGLBridge: Error eglGetConfigAttrib() failed: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }

    EGLBoolean bindResult;
    if (angleDesktopGL) {
        NSDebugLog(@"EGLBridge: Binding to desktop OpenGL");
        bindResult = handle.eglBindAPI(EGL_OPENGL_API);
    } else {
        NSDebugLog(@"EGLBridge: Binding to OpenGL ES");
        bindResult = handle.eglBindAPI(EGL_OPENGL_ES_API);
    }
    if (!bindResult) NSDebugLog(@"EGLBridge: bind failed: 0x%x", handle.eglGetError());
    NSDebugLog(@"EGLBridge: Creating window surface");

    bundle->surface = handle.eglCreateWindowSurface(g_EglDisplay, bundle->config, (__bridge EGLNativeWindowType)SurfaceViewController.surface.layer, NULL);
    if (!bundle->surface) {
        NSDebugLog(@"EGLBridge: eglCreateWindowSurface finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    NSDebugLog(@"EGLBridge: Window surface created");

    const EGLint ctx_attribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    bundle->context = handle.eglCreateContext(g_EglDisplay, bundle->config, share ? share->context : EGL_NO_CONTEXT, ctx_attribs);
    if (!bundle->context) {
        NSDebugLog(@"EGLBridge: Error eglCreateContext finished with error: 0x%x", handle.eglGetError());
        free(bundle);
        return NULL;
    }
    NSDebugLog(@"EGLBridge: Context created");
    //NSDebugLog(@"EGLBridge: Created CTX pointer = %p (source = %p)", bundle->context, share?share->context:0);

    return bundle;
}

void gl_make_current(gl_render_window_t* bundle) {
    if(!bundle) {
        if(handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT)) {
            currentBundle = NULL;
        }
        return;
    }

    if(handle.eglMakeCurrent(g_EglDisplay, bundle->surface, bundle->surface, bundle->context)) {
        currentBundle = (basic_render_window_t *)bundle;
        NSDebugLog(@"EGLBridge: Context made current");

        // Validate the renderer entry points before control returns to LWJGL.
        // If this blocks, the failure is inside the MobileGlues GL dispatch;
        // if it succeeds, the remaining initialization is on the Java side.
        typedef const GLubyte *(*gl_get_string_fn)(GLenum);
        gl_get_string_fn getString = (gl_get_string_fn)dlsym(g_renderer_handle, "glGetString");
        if (getString) {
            const GLubyte *version = getString(GL_VERSION);
            const GLubyte *vendor = getString(GL_VENDOR);
            NSDebugLog(@"EGLBridge: GL_VERSION=%s GL_VENDOR=%s",
                       version ? (const char *)version : "(null)",
                       vendor ? (const char *)vendor : "(null)");
            typedef void (*gl_get_integer_fn)(GLenum, GLint *);
            typedef const GLubyte *(*gl_get_string_i_fn)(GLenum, GLuint);
            gl_get_integer_fn getInteger = (gl_get_integer_fn)dlsym(g_renderer_handle, "glGetIntegerv");
            gl_get_string_i_fn getStringI = (gl_get_string_i_fn)dlsym(g_renderer_handle, "glGetStringi");
            if (getInteger) {
                GLint major = 0, minor = 0, profile = 0, extensionCount = 0;
                getInteger(GL_MAJOR_VERSION, &major);
                getInteger(GL_MINOR_VERSION, &minor);
                getInteger(GL_CONTEXT_PROFILE_MASK, &profile);
                getInteger(GL_NUM_EXTENSIONS, &extensionCount);
                NSDebugLog(@"EGLBridge: GL_CONTEXT=%d.%d profile=0x%x extensions=%d",
                           major, minor, profile, extensionCount);
                NSArray<NSString *> *sodiumExtensions = @[
                    @"GL_ARB_buffer_storage", @"GL_ARB_direct_state_access",
                    @"GL_ARB_vertex_attrib_binding", @"GL_ARB_multi_draw_indirect",
                    @"GL_ARB_shader_storage_buffer_object", @"GL_ARB_compute_shader",
                    @"GL_ARB_timer_query", @"GL_ARB_texture_storage",
                    @"GL_ARB_invalidate_subdata"
                ];
                NSMutableArray<NSString *> *reportedSodiumExtensions = [NSMutableArray array];
                NSMutableArray<NSString *> *missingSodiumExtensions = sodiumExtensions.mutableCopy;
                if (getStringI && extensionCount > 0 && extensionCount <= 4096) {
                    for (GLint i = 0; i < extensionCount; i++) {
                        const GLubyte *extension = getStringI(GL_EXTENSIONS, (GLuint)i);
                        if (!extension) continue;
                        NSString *name = @((const char *)extension);
                        if ([sodiumExtensions containsObject:name]) {
                            [reportedSodiumExtensions addObject:name];
                            [missingSodiumExtensions removeObject:name];
                        }
                    }
                    NSDebugLog(@"EGLBridge: Sodium GL extensions present=%@ missing=%@",
                               [reportedSodiumExtensions componentsJoinedByString:@" "],
                               [missingSodiumExtensions componentsJoinedByString:@" "]);
                } else {
                    NSDebugLog(@"EGLBridge: glGetStringi unavailable or extension count invalid");
                }
            } else {
                NSDebugLog(@"EGLBridge: glGetIntegerv entry point is unavailable");
            }

            NSArray<NSString *> *probeSymbols = @[
                @"glBufferStorage", @"glMapBufferRange", @"glDrawElementsBaseVertex",
                @"glBindVertexArray", @"glVertexAttribDivisor", @"glGetIntegeri_v",
                @"glDispatchCompute", @"glMemoryBarrier", @"glBindBufferRange",
                @"glTexStorage2D", @"glBlitFramebuffer", @"glGetStringi"
            ];
            NSMutableArray<NSString *> *availableSymbols = [NSMutableArray array];
            NSMutableArray<NSString *> *missingSymbols = [NSMutableArray array];
            for (NSString *symbol in probeSymbols) {
                if (dlsym(g_renderer_handle, symbol.UTF8String)) {
                    [availableSymbols addObject:symbol];
                } else {
                    [missingSymbols addObject:symbol];
                }
            }
            NSDebugLog(@"EGLBridge: GL symbol probe available=%@ missing=%@",
                       [availableSymbols componentsJoinedByString:@" "],
                       [missingSymbols componentsJoinedByString:@" "]);
        } else {
            NSDebugLog(@"EGLBridge: glGetString entry point is unavailable");
        }
    } else {
        NSLog(@"EGLBridge: eglMakeCurrent returned with error: 0x%x", handle.eglGetError());
    }
}

void gl_swap_buffers() {
    if (!g_EglDisplay || !currentBundle || !handle.eglSwapBuffers || !handle.eglGetError) {
        NSDebugLog(@"EGLBridge: SwapBuffers skipped (display/context/function unavailable)");
        return;
    }
    EGLBoolean result = handle.eglSwapBuffers(g_EglDisplay, currentBundle->gl.surface);
    if (!result) {
        EGLint error = handle.eglGetError();
        NSLog(@"EGLBridge: eglSwapBuffers failed: 0x%x", error);
        if (error == EGL_BAD_SURFACE) {
            NSDebugLog(@"EGLBridge: SwapBuffers surface is invalid");
        }
        //stopSwapBuffers = true;
        //closeGLFWWindow();
    }
}

void gl_swap_interval(int swapInterval) {
    handle.eglSwapInterval(g_EglDisplay, swapInterval);
}

void gl_terminate() {
    handle.eglMakeCurrent(g_EglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    handle.eglDestroySurface(g_EglDisplay, currentBundle->gl.surface);
    handle.eglDestroyContext(g_EglDisplay, currentBundle->gl.context);
    handle.eglTerminate(g_EglDisplay);
    handle.eglReleaseThread();
    free(currentBundle);
    currentBundle = nil;
}

void set_gl_bridge_tbl() {
    br_init = gl_init;
    br_init_context = (br_init_context_t) gl_init_context;
    br_make_current = (br_make_current_t) gl_make_current;
    br_swap_buffers = gl_swap_buffers;
    br_swap_interval = gl_swap_interval;
    br_terminate = gl_terminate;
}
