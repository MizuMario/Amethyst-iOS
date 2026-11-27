package net.kdt.patchjna;

import java.io.*;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.IllegalClassFormatException;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.InvocationTargetException;
import java.security.ProtectionDomain;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Label;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.Type;
import org.objectweb.asm.commons.AdviceAdapter;
import org.objectweb.asm.commons.Method;

public class PatchJNAAgent implements ClassFileTransformer {
    public byte[] transform(ClassLoader loader, String className, Class<?> classBeingRedefined,
    ProtectionDomain protectionDomain, byte[] classfileBuffer) throws IllegalClassFormatException {
        byte[] transformeredByteCode = classfileBuffer;
        if (className.equals("com/sun/jna/Platform")) {
            System.out.println("PatchJNAAgent: Replacing class");
            try {
                InputStream inputStream = PatchJNAAgent.class.getClassLoader().getResourceAsStream("com/sun/jna/Platform.class.patch");
                transformeredByteCode = new byte[inputStream.available()];
                DataInputStream dataInputStream = new DataInputStream(inputStream);
                dataInputStream.readFully(transformeredByteCode);
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        if ("oshi/util/platform/mac/SysctlUtil".equals(className)
                && System.getProperty("amethyst.ios.cpuName") != null) {
            try {
                transformeredByteCode = patchCPUName(transformeredByteCode);
            } catch (RuntimeException e) {
                System.err.println("[OSHI] CPU name fallback could not be installed: " + e);
            }
        }
        if ("com/mojang/renderpearl/frontend/shaders/GlslCompiler".equals(className)
                && Boolean.getBoolean("amethyst.shaderc.disableDebugInfo")) {
            try {
                disableShaderDebugInfo(transformeredByteCode);
                transformeredByteCode = addShaderCompileDiagnostics(transformeredByteCode);
            } catch (RuntimeException e) {
                System.err.println("[Shaderc] Instrumentation failed; retaining the available shader compiler bytecode");
                e.printStackTrace();
            }
        }
        return transformeredByteCode;
    }

    private static byte[] patchCPUName(byte[] bytes) {
        ClassReader reader = new ClassReader(bytes);
        ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override
            public MethodVisitor visitMethod(int access, String name, String descriptor, String signature, String[] exceptions) {
                MethodVisitor method = super.visitMethod(access, name, descriptor, signature, exceptions);
                if (!name.equals("sysctl") || !descriptor.equals("(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;")) {
                    return method;
                }
                return new AdviceAdapter(Opcodes.ASM9, method, access, name, descriptor) {
                    @Override
                    protected void onMethodEnter() {
                        Label original = new Label();
                        push("machdep.cpu.brand_string");
                        loadArg(0);
                        invokeVirtual(Type.getType(String.class), new Method("equals", "(Ljava/lang/Object;)Z"));
                        ifZCmp(EQ, original);
                        push("amethyst.ios.cpuName");
                        invokeStatic(Type.getType(System.class), new Method("getProperty", "(Ljava/lang/String;)Ljava/lang/String;"));
                        returnValue();
                        mark(original);
                    }
                };
            }
        }, ClassReader.EXPAND_FRAMES);
        return writer.toByteArray();
    }

    // Replace the optional debug-info call with POP2 + two NOPs. This consumes
    // the long options handle while preserving all instruction offsets/frames.
    private static void disableShaderDebugInfo(byte[] bytes) {
        int cpCount = u2(bytes, 8);
        String[] utf8 = new String[cpCount];
        int[] cpOffset = new int[cpCount];
        int p = 10;
        for (int i = 1; i < cpCount; i++) {
            cpOffset[i] = p;
            int tag = bytes[p++] & 255;
            switch (tag) {
                case 1:
                    int length = u2(bytes, p); p += 2;
                    try { utf8[i] = new String(bytes, p, length, "UTF-8"); }
                    catch (Exception ignored) { return; }
                    p += length; break;
                case 3: case 4: p += 4; break;
                case 5: case 6: p += 8; i++; break;
                case 7: case 8: case 16: case 19: case 20: p += 2; break;
                case 9: case 10: case 11: case 12: case 17: case 18: p += 4; break;
                case 15: p += 3; break;
                default: System.err.println("[Shaderc] Unknown constant-pool tag " + tag); return;
            }
        }
        int offset = p + 6;
        int interfaces = u2(bytes, offset); offset += 2 + interfaces * 2;
        int fields = u2(bytes, offset); offset += 2;
        for (int i = 0; i < fields; i++) offset = skipMember(bytes, offset);
        int methods = u2(bytes, offset); offset += 2;
        boolean replaced = false;
        for (int m = 0; m < methods; m++) {
            String name = utf8[u2(bytes, offset + 2)];
            int attributes = u2(bytes, offset + 6); offset += 8;
            for (int a = 0; a < attributes; a++) {
                int attributeName = u2(bytes, offset);
                int length = i4(bytes, offset + 2);
                int data = offset + 6;
                if ("Code".equals(utf8[attributeName]) && "createBaseShaderOptions".equals(name)) {
                    int codeLength = i4(bytes, data + 4);
                    int codeStart = data + 8;
                    int codeEnd = codeStart + codeLength;
                    for (int q = codeStart; q + 2 < codeEnd; q++) {
                        if ((bytes[q] & 255) != 0xb8) continue;
                        int ref = u2(bytes, q + 1);
                        if (methodName(bytes, cpOffset, utf8, ref, cpCount).equals("shaderc_compile_options_set_generate_debug_info")) {
                            bytes[q] = 0x58; bytes[q + 1] = 0; bytes[q + 2] = 0;
                            replaced = true;
                            break;
                        }
                    }
                }
                offset = data + length;
            }
        }
        System.out.println("[Shaderc] Optional debug metadata disabled=" + replaced);
    }

    private static String methodName(byte[] b, int[] offsets, String[] utf8, int ref, int count) {
        if (ref <= 0 || ref >= count) return "";
        int tag = b[offsets[ref]] & 255;
        if (tag != 10 && tag != 11) return "";
        int nt = u2(b, offsets[ref] + 3);
        if (nt <= 0 || nt >= count || (b[offsets[nt]] & 255) != 12) return "";
        int name = u2(b, offsets[nt] + 1);
        return name > 0 && name < count && utf8[name] != null ? utf8[name] : "";
    }
    private static int skipMember(byte[] b, int p) {
        int attrs = u2(b, p + 6); p += 8;
        for (int i = 0; i < attrs; i++) p += 6 + i4(b, p + 2);
        return p;
    }
    private static int u2(byte[] b, int p) { return ((b[p] & 255) << 8) | (b[p + 1] & 255); }
    private static int i4(byte[] b, int p) { return (b[p] << 24) | ((b[p + 1] & 255) << 16) | ((b[p + 2] & 255) << 8) | (b[p + 3] & 255); }

    private static byte[] addShaderCompileDiagnostics(byte[] input) {
        final boolean[] instrumented = {false};
        ClassReader reader = new ClassReader(input);
        ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS | ClassWriter.COMPUTE_FRAMES);
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override
            public MethodVisitor visitMethod(int access, String name, String descriptor, String signature, String[] exceptions) {
                MethodVisitor method = super.visitMethod(access, name, descriptor, signature, exceptions);
                if ("lambda$createIncludeResolver$0".equals(name)) {
                    instrumented[0] = true;
                    return new AdviceAdapter(Opcodes.ASM9, method, access, name, descriptor) {
                        @Override
                        protected void onMethodEnter() {
                            getStatic(Type.getType(System.class), "out", Type.getType(java.io.PrintStream.class));
                            push("[Shaderc] include callback begin requested=");
                            loadArg(2);
                            invokeStatic(Type.getObjectType("org/lwjgl/system/MemoryUtil"), new Method("memASCII", "(J)Ljava/lang/String;"));
                            invokeVirtual(Type.getType(String.class), new Method("concat", "(Ljava/lang/String;)Ljava/lang/String;"));
                            invokeVirtual(Type.getType(java.io.PrintStream.class), new Method("println", "(Ljava/lang/String;)V"));
                        }

                        @Override
                        protected void onMethodExit(int opcode) {
                            if (opcode == ATHROW) return;
                            getStatic(Type.getType(System.class), "out", Type.getType(java.io.PrintStream.class));
                            push("[Shaderc] include callback end");
                            invokeVirtual(Type.getType(java.io.PrintStream.class), new Method("println", "(Ljava/lang/String;)V"));
                        }
                    };
                }
                if (!"compileToSpv".equals(name)) return method;
                instrumented[0] = true;
                return new AdviceAdapter(Opcodes.ASM9, method, access, name, descriptor) {
                    private int startNanos;

                    @Override
                    protected void onMethodEnter() {
                        invokeStatic(Type.getType(System.class), new Method("nanoTime", "()J"));
                        startNanos = newLocal(Type.LONG_TYPE);
                        storeLocal(startNanos);
                        getStatic(Type.getType(System.class), "out", Type.getType(java.io.PrintStream.class));
                        newInstance(Type.getType(StringBuilder.class));
                        dup();
                        invokeConstructor(Type.getType(StringBuilder.class), new Method("<init>", "()V"));
                        push("[Shaderc] begin shader=");
                        invokeVirtual(Type.getType(StringBuilder.class), new Method("append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;"));
                        loadArg(0);
                        invokeVirtual(Type.getType(StringBuilder.class), new Method("append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;"));
                        push(" sourceChars=");
                        invokeVirtual(Type.getType(StringBuilder.class), new Method("append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;"));
                        loadArg(1);
                        invokeVirtual(Type.getType(String.class), new Method("length", "()I"));
                        invokeVirtual(Type.getType(StringBuilder.class), new Method("append", "(I)Ljava/lang/StringBuilder;"));
                        invokeVirtual(Type.getType(StringBuilder.class), new Method("toString", "()Ljava/lang/String;"));
                        invokeVirtual(Type.getType(java.io.PrintStream.class), new Method("println", "(Ljava/lang/String;)V"));
                    }

                    @Override
                    protected void onMethodExit(int opcode) {
                        if (opcode == ATHROW) return;
                        getStatic(Type.getType(System.class), "out", Type.getType(java.io.PrintStream.class));
                        newInstance(Type.getType(StringBuilder.class));
                        dup();
                        invokeConstructor(Type.getType(StringBuilder.class), new Method("<init>", "()V"));
                        push("[Shaderc] end shader=");
                        invokeVirtual(Type.getType(StringBuilder.class), new Method("append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;"));
                        loadArg(0);
                        invokeVirtual(Type.getType(StringBuilder.class), new Method("append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;"));
                        push(" elapsedMs=");
                        invokeVirtual(Type.getType(StringBuilder.class), new Method("append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;"));
                        invokeStatic(Type.getType(System.class), new Method("nanoTime", "()J"));
                        loadLocal(startNanos);
                        math(SUB, Type.LONG_TYPE);
                        push(1000000L);
                        math(DIV, Type.LONG_TYPE);
                        invokeVirtual(Type.getType(StringBuilder.class), new Method("append", "(J)Ljava/lang/StringBuilder;"));
                        invokeVirtual(Type.getType(StringBuilder.class), new Method("toString", "()Ljava/lang/String;"));
                        invokeVirtual(Type.getType(java.io.PrintStream.class), new Method("println", "(Ljava/lang/String;)V"));
                    }
                };
            }
        }, ClassReader.EXPAND_FRAMES);
        System.out.println("[Shaderc] compile diagnostics instrumented=" + instrumented[0]);
        return writer.toByteArray();
    }

    public static void premain(String args, Instrumentation instrumentation) {
        System.out.println("PatchJNAAgent: premain called");
        instrumentation.addTransformer(new PatchJNAAgent());
    }
}
