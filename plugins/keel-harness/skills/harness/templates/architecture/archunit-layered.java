package <package>;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.library.Architectures.layeredArchitecture;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

// keel template: replace every <placeholder> with this repository's real path or package, then remove this line. Protect this file with config: in .agents/keel.yml.
// layered: web -> service -> repository; no upward calls.
// Use an ArchUnit release that supports your JDK: an older one imports no class and every rule passes without checking anything.
@AnalyzeClasses(packages = "<package>", importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {

    @ArchTest
    static final ArchRule layers = layeredArchitecture().consideringOnlyDependenciesInLayers()
            .layer("Web").definedBy("<package>.<web>..")
            .layer("Service").definedBy("<package>.<service>..")
            .layer("Repository").definedBy("<package>.<repository>..")
            .whereLayer("Web").mayNotBeAccessedByAnyLayer()
            .whereLayer("Service").mayOnlyBeAccessedByLayers("Web")
            .whereLayer("Repository").mayOnlyBeAccessedByLayers("Service");

    @ArchTest
    static final ArchRule classes_are_analysed = classes().that().resideInAPackage("<package>..").should().resideInAPackage("<package>..")
            .because("ArchUnit must see this project's classes; when it imports none, every other rule here passes without checking anything");
}
