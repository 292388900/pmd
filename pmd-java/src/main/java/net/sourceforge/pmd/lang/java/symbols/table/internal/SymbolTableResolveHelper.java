/**
 * BSD-style license; for more info see http://pmd.sourceforge.net/license.html
 */

package net.sourceforge.pmd.lang.java.symbols.table.internal;

import java.lang.reflect.Member;
import java.lang.reflect.Modifier;
import java.util.function.Consumer;


/**
 * Object passing around config for {@link AbstractSymbolTable}.
 *
 * @author Clément Fournier
 * @since 7.0.0
 */
public final class SymbolTableResolveHelper {

    private final String thisPackage;
    private final ClassLoader classLoader;
    private final int jdkVersion;


    public SymbolTableResolveHelper(String thisPackage,
                                    ClassLoader classLoader,
                                    int jdkVersion) {
        this.thisPackage = thisPackage;
        this.classLoader = classLoader;
        this.jdkVersion = jdkVersion;
    }


    /** Analysed language version. */
    public int getJdkVersion() {
        return jdkVersion;
    }


    /** Package name of the current compilation unit, used to check for accessibility. */
    String getThisPackage() {
        return thisPackage;
    }


    /** Classloader with analysis classpath. */
    public ClassLoader getClassLoader() {
        return classLoader;
    }


    boolean isAccessible(Class<?> c) {
        return isAccessible(c.getModifiers(), c.getPackage().getName());
    }


    boolean isAccessible(Member member) {
        return isAccessible(member.getModifiers(), member.getDeclaringClass().getPackage().getName());
    }


    /**
     * Returns true if a member is accessible from the current ACU.
     *
     * <p>We consider protected members inaccessible outside of the package they were declared in,
     * which is an approximation but won't cause problems in practice.
     * In an ACU in another package, the name is accessible only inside classes that inherit
     * from the declaring class. But inheriting from a class makes its static members
     * accessible via simple name too. So this will actually be picked up by InheritedScope
     * when in the subclass. Usages outside of the subclass would have made the compilation failed.
     */
    private boolean isAccessible(int modifiers, String memberPackageName) {
        if (Modifier.isPublic(modifiers)) {
            return true;
        } else if (Modifier.isPrivate(modifiers)) {
            return false;
        } else {
            // then it's package private, or protected
            return thisPackage.equals(memberPackageName);
        }
    }

    public Class<?> loadClass(String fqcn, Consumer<Throwable> failureHandler) {
        try {
            return getClassLoader().loadClass(fqcn);
            // ClassTypeResolver used to just ignore ClassNotFoundException, was there a reason for that?
        } catch (ClassNotFoundException | LinkageError e2) {
            failureHandler.accept(e2);
            return null;
        }
    }
}
