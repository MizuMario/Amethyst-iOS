package net.kdt.pojavlaunch;

import java.io.File;
import java.io.IOException;
import java.net.*;

/**
 * This class loader is used as system class loader
 * as a workaround to modded libraries for Java 8
 * compatibility that safety casting to URLClassLoader:
 * ((URLClassLoader) ClassLoader.getSystemClassLoader())
 */
public class PojavClassLoader extends URLClassLoader {
    public PojavClassLoader(ClassLoader parent) {
        super(initialUrls(), parent);
    }

    private static URL[] initialUrls() {
        String bundledLwjgl = System.getProperty("amethyst.lwjgl.jar");
        return bundledLwjgl == null || bundledLwjgl.isEmpty()
            ? new URL[0]
            : new URL[] { getFileURL(new File(bundledLwjgl)) };
    }

    @Override
    public void addURL(URL url) {
        super.addURL(url);
        try {
            System.setProperty("java.class.path", System.getProperty("java.class.path") + ":" + new File(url.toURI()).getAbsolutePath());
        } catch (URISyntaxException e) {
            e.printStackTrace();
        }
    }

    @Override
    protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
        if (name.startsWith("org.lwjgl.")) {
            synchronized (getClassLoadingLock(name)) {
                Class<?> loaded = findLoadedClass(name);
                if (loaded == null) {
                    try {
                        loaded = findClass(name);
                    } catch (ClassNotFoundException ignored) {
                        // Fall back to the game's LWJGL when this release does
                        // not bundle a class from an optional LWJGL module.
                    }
                }
                if (loaded == null) loaded = super.loadClass(name, false);
                if (resolve) resolveClass(loaded);
                return loaded;
            }
        }
        return super.loadClass(name, resolve);
    }

    static URL getFileURL(File file) {
        try {
            file = file.getCanonicalFile();
        } catch (IOException e) {}

        try {
            return file.toURL();
        } catch (MalformedURLException e) {
            // Should never happen since we specify the protocol...
            throw new InternalError(e);
        }
    }

    /**
     * This class loader supports dynamic additions to the class path
     * at runtime.
     *
     * @see java.lang.instrument.Instrumentation#appendToSystemClassPathSearch
     */
    protected void appendToClassPathForInstrumentation(String path) {
        assert(Thread.holdsLock(this));

        // addURL is a no-op if path already contains the URL
        super.addURL(getFileURL(new File(path)));
    }
}
