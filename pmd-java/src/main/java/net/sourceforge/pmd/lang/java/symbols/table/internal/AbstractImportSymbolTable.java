/**
 * BSD-style license; for more info see http://pmd.sourceforge.net/license.html
 */

package net.sourceforge.pmd.lang.java.symbols.table.internal;

import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Stream;

import net.sourceforge.pmd.lang.java.symbols.refs.JFieldSymbol;
import net.sourceforge.pmd.lang.java.symbols.refs.JMethodSymbol;
import net.sourceforge.pmd.lang.java.symbols.refs.JResolvableClassDeclarationSymbol;
import net.sourceforge.pmd.lang.java.symbols.refs.JValueSymbol;
import net.sourceforge.pmd.lang.java.symbols.table.JSymbolTable;


/**
 * Base class for import scopes.
 *
 * <p>Rules for shadowing of imports: bottom of https://docs.oracle.com/javase/specs/jls/se8/html/jls-6.html#jls-6.4.1
 *
 * <p>The simplest way to implement that is to layer the imports into several scopes.
 * See doc on {@link JSymbolTable} about the higher level scopes of the scope stacks.
 *
 * @author Clément Fournier
 * @since 7.0.0
 */
abstract class AbstractImportSymbolTable extends AbstractSymbolTable {

    final Map<String, JResolvableClassDeclarationSymbol> importedTypes = new HashMap<>();
    final Map<String, List<JMethodSymbol>> importedStaticMethods = new HashMap<>();
    final Map<String, JFieldSymbol> importedStaticFields = new HashMap<>();


    /**
     * Constructor with the parent table and the auxclasspath classloader.
     *
     * @param parent      Parent table
     * @param helper Resolve helper
     */
    AbstractImportSymbolTable(JSymbolTable parent, SymbolTableResolveHelper helper) {
        super(parent, helper);
    }


    @Override
    protected Optional<JResolvableClassDeclarationSymbol> resolveTypeNameImpl(String simpleName) {
        return Optional.ofNullable(importedTypes.get(simpleName));
    }


    @Override
    protected Stream<JMethodSymbol> resolveMethodNameImpl(String simpleName) {
        return importedStaticMethods.getOrDefault(simpleName, Collections.emptyList()).stream();
    }


    @Override
    protected Optional<JValueSymbol> resolveValueNameImpl(String simpleName) {
        return Optional.ofNullable(importedStaticFields.get(simpleName));
    }
}
