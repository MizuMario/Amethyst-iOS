package org.lwjgl.sdl;

import org.lwjgl.system.Library;
import org.lwjgl.system.Platform;
import org.lwjgl.system.SharedLibrary;

public final class SDL {
    private static final SharedLibrary SDL;

    public static SharedLibrary getLibrary() {
        return SDL;
    }

    private SDL() {
        throw new UnsupportedOperationException();
    }

    static {
        System.out.println("[SDL3 TRACE] SDL class init BEGIN");
        System.out.println("[SDL3 TRACE] loading Amethyst JNI registrar");
        System.loadLibrary("amethyst_sdl3_jni");
        System.out.println("[SDL3 TRACE] nativePrepare BEGIN");
        SDL3Bridge.nativePrepare();
        System.out.println("[SDL3 TRACE] nativePrepare END");
        System.out.println("[SDL3 TRACE] Library.loadNative BEGIN");
        SDL = Library.loadNative(
            SDL.class,
            "org.lwjgl.sdl",
            Platform.mapLibraryNameBundled(System.getProperty("org.lwjgl.sdl.libname", "SDL3")),
            true
        );
        System.out.println("[SDL3 TRACE] Library.loadNative END");
        System.out.println("[SDL3 TRACE] nativeLoaded BEGIN");
        SDL3Bridge.nativeLoaded();
        System.out.println("[SDL3 TRACE] nativeLoaded END");
        System.out.println("[SDL3 TRACE] SDL class init END");
    }
}
