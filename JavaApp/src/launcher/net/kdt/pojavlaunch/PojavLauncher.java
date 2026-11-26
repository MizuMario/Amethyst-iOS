package net.kdt.pojavlaunch;

import java.beans.Beans;
import java.io.*;
import java.lang.reflect.Field;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

import org.lwjgl.glfw.CallbackBridge;
import org.lwjgl.glfw.GLFW;

import net.kdt.pojavlaunch.uikit.*;
import net.kdt.pojavlaunch.utils.*;
import net.kdt.pojavlaunch.value.*;

public class PojavLauncher {
    private static float currProgress, maxProgress;

    private static volatile boolean hangWatchdogRunning;
    private static final java.io.FileOutputStream HANG_LOG =
        new java.io.FileOutputStream(java.io.FileDescriptor.err);

    private static synchronized void hangLog(String line) {
        try {
            HANG_LOG.write((line + "\n").getBytes("UTF-8"));
            HANG_LOG.flush();
        } catch (Throwable ignored) {
        }
    }

    private static void startHangWatchdog() {
        if (!Boolean.getBoolean("amethyst.hangwatchdog")) {
            hangLog("[HangWatchdog] disabled; property=" + System.getProperty("amethyst.hangwatchdog"));
            return;
        }
        hangWatchdogRunning = true;
        hangLog("[HangWatchdog] started");
        Thread watchdog = new Thread(() -> {
            for (int sample = 1; hangWatchdogRunning && sample <= 12; sample++) {
                try {
                    Thread.sleep(15000L);
                } catch (InterruptedException ignored) {
                    return;
                }
                if (!hangWatchdogRunning) return;
                hangLog("[HangWatchdog] sample=" + sample + " after=" + (sample * 15) + "s");
                for (java.util.Map.Entry<Thread, StackTraceElement[]> entry : Thread.getAllStackTraces().entrySet()) {
                    Thread thread = entry.getKey();
                    String name = thread.getName();
                    String lowerName = name.toLowerCase(java.util.Locale.ROOT);
                    boolean startupWorker = lowerName.contains("worker") || lowerName.contains("reload")
                        || lowerName.contains("resource") || lowerName.contains("forkjoin")
                        || lowerName.contains("pool-") || lowerName.contains("modloading")
                        || lowerName.contains("background");
                    boolean fullDiagnosticSample = sample == 2 || sample == 8 || sample == 12;
                    if (!(name.equals("main") || name.equals("Render thread") || name.equals("Server thread")
                        || lowerName.contains("sdl") || ((sample == 1 || fullDiagnosticSample) && startupWorker)
                        || fullDiagnosticSample)) continue;
                    hangLog("[HangWatchdog] thread=" + name + " state=" + thread.getState());
                    StackTraceElement[] stack = entry.getValue();
                    int frameLimit = fullDiagnosticSample ? 10 : (startupWorker ? 12 : 18);
                    for (int i = 0; i < stack.length && i < frameLimit; i++) {
                        hangLog("    at " + stack[i]);
                    }
                }
            }
        }, "Amethyst-HangWatchdog");
        watchdog.setDaemon(true);
        watchdog.start();
    }

    private static String ensureLoggingConfig(JMinecraftVersionList.Version version) throws Exception {
        JMinecraftVersionList.FileProperties metadata = version.logging.client.file;
        File config = new File(Tools.DIR_GAME_NEW, metadata.id);
        if (!config.isFile() || !matchesSha1(config, metadata.sha1)) {
            HttpURLConnection connection = (HttpURLConnection) new URL(metadata.url).openConnection();
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(15000);
            connection.setInstanceFollowRedirects(true);
            try {
                int status = connection.getResponseCode();
                if (status < 200 || status >= 300) {
                    throw new IOException("HTTP " + status + " downloading " + metadata.id);
                }
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                InputStream input = connection.getInputStream();
                try {
                    byte[] buffer = new byte[8192];
                    int count;
                    while ((count = input.read(buffer)) != -1) {
                        bytes.write(buffer, 0, count);
                    }
                } finally {
                    input.close();
                }
                byte[] content = bytes.toByteArray();
                if (metadata.size > 0 && content.length != metadata.size) {
                    throw new IOException("Unexpected size for " + metadata.id + ": " + content.length);
                }
                String actualSha1 = sha1(content);
                if (metadata.sha1 != null && !metadata.sha1.equalsIgnoreCase(actualSha1)) {
                    throw new IOException("SHA-1 mismatch for " + metadata.id + ": " + actualSha1);
                }
                Tools.write(config.getAbsolutePath(), content);
                System.err.println("[Logging] Downloaded and verified " + metadata.id);
            } finally {
                connection.disconnect();
            }
        } else {
            System.err.println("[Logging] Using verified " + metadata.id);
        }
        return config.getAbsolutePath();
    }

    private static boolean matchesSha1(File file, String expected) throws Exception {
        if (expected == null || expected.isEmpty()) return file.isFile();
        InputStream input = new FileInputStream(file);
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-1");
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
            return expected.equalsIgnoreCase(toHex(digest.digest()));
        } finally {
            input.close();
        }
    }

    private static String sha1(byte[] content) throws Exception {
        return toHex(MessageDigest.getInstance("SHA-1").digest(content));
    }

    private static String toHex(byte[] bytes) {
        StringBuilder result = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) result.append(String.format(java.util.Locale.ROOT, "%02x", value & 0xff));
        return result.toString();
    }

    public static void main(String[] args) throws Throwable {
        if (args.length > 1 && args[1].startsWith("26.")) {
            System.setProperty("amethyst.hangwatchdog", "true");
        }
        startHangWatchdog();
        // The selected versioned LWJGL archive is appended before Minecraft can
        // resolve any LWJGL classes. Legacy LWJGL remains out of this archive.
        String bundledLwjgl = System.getProperty("amethyst.lwjgl.jar");
        if (bundledLwjgl != null && !bundledLwjgl.isEmpty()) {
            ClassLoader system = ClassLoader.getSystemClassLoader();
            if (system instanceof PojavClassLoader) {
                ((PojavClassLoader) system).addURL(new File(bundledLwjgl).toURI().toURL());
                System.out.println("[LWJGL] Added bundled archive " + bundledLwjgl);
            } else {
                throw new IllegalStateException("Bundled LWJGL needs PojavClassLoader, got " + system);
            }
        }
        // Skip calling to com.apple.eawt.Application.nativeInitializeApplicationDelegate()
        Beans.setDesignTime(true);
        try {
            // Some places use macOS-specific code, which is unavailable on iOS
            // In this case, try to get it to use Linux-specific code instead.
            com.apple.eawt.Application.getApplication();
            Class clazz = Class.forName("com.apple.eawt.Application");
            Field field = clazz.getDeclaredField("sApplication");
            field.setAccessible(true);
            field.set(null, null);
            sun.font.FontUtilities.isLinux = true;
            System.setProperty("java.util.prefs.PreferencesFactory", "java.util.prefs.FileSystemPreferencesFactory");
        } catch (Throwable th) {
            // Not on JRE8, ignore exception
            //Tools.showError(th);
        }

        Thread.currentThread().setUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {

            public void uncaughtException(Thread t, Throwable th) {
                th.printStackTrace();
                System.exit(1);
            }
        });

        try {
            // Try to initialize Caciocavallo17
            Class.forName("com.github.caciocavallosilano.cacio.ctc.CTCPreloadClassLoader");
        } catch (ClassNotFoundException e) {}

        if (args[0].equals("-jar")) {
            UIKit.callback_JavaGUIViewController_launchJarFile(args[1], Arrays.copyOfRange(args, 2, args.length));
        } else {
            launchMinecraft(args);
        }
        hangWatchdogRunning = false;
    }

    public static void launchMinecraft(String[] args) throws Throwable {
        // Args for Spiral Knights
        System.setProperty("appdir", "./spiral");
        System.setProperty("resource_dir", "./spiral/rsrc");

        String sizeStr = System.getProperty("cacio.managed.screensize");
        System.setProperty("glfw.windowSize", sizeStr);

        // Setup Forge splash.properties
        File forgeSplashFile = new File(Tools.DIR_GAME_NEW, "config/splash.properties");
        if (System.getProperty("pojav.internal.keepForgeSplash") == null) {
            forgeSplashFile.getParentFile().mkdir();
            if (forgeSplashFile.exists()) {
                Tools.write(forgeSplashFile.getAbsolutePath(), Tools.read(forgeSplashFile.getAbsolutePath().replace("enabled=true", "enabled=false")));
            } else {
                Tools.write(forgeSplashFile.getAbsolutePath(), "enabled=false");
            }
        }

        System.setProperty("org.lwjgl.vulkan.libname", "libMoltenVK.dylib");

        MinecraftAccount account = MinecraftAccount.load(args[0]);
        JMinecraftVersionList.Version version = Tools.getVersionInfo(args[1]);
        System.out.println("Launching Minecraft " + version.id);
        String configPath;
        if (version.logging != null) {
            if (version.logging.client.file.id.equals("client-1.12.xml")) {
                configPath = Tools.DIR_BUNDLE + "/log4j-rce-patch-1.12.xml";
            } else if (version.logging.client.file.id.equals("client-1.7.xml")) {
                configPath = Tools.DIR_BUNDLE + "/log4j-rce-patch-1.7.xml";
            } else {
                try {
                    configPath = ensureLoggingConfig(version);
                } catch (Throwable error) {
                    System.err.println("[Logging] Could not prepare " + version.logging.client.file.id + ": " + error);
                    configPath = null;
                }
            }
            if (configPath != null) {
                System.setProperty("log4j.configurationFile", configPath);
                System.err.println("[Logging] log4j.configurationFile=" + configPath);
            }
        }

        Tools.launchMinecraft(account, version);
    }
}
