package com.mojang.blaze3d.platform;

/**
 * iOS compatibility shim for Minecraft 26.x. The game calls these macOS UI
 * hooks while creating its SDL window, but Cocoa.framework is not available on
 * iOS. The window and input behavior are provided by Amethyst instead.
 */
public final class MacosUtil {
    public static final boolean IS_MACOS = false;

    private MacosUtil() {
    }

    public static void disableCloseWindowMenuItem() {
    }

    public static void setFullscreenMenuVisibility(boolean visible) {
    }

    public static void setCtrlClickEmulatesRightClick(boolean enabled) {
    }
}
