package <package>;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.library.dependencies.SlicesRuleDefinition.slices;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

// Baymax template: replace every <placeholder> with this repository's real path or package, then remove this line. Protect this file with config: in .agents/bmax.yml.
// modular: modules depend only on each other's public API (index).
// Use an ArchUnit release that supports your JDK: an older one imports no class and every rule passes without checking anything.
@AnalyzeClasses(packages = "<package>", importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {

    @ArchTest
    static final ArchRule modules_are_independent = slices().matching("<package>.<modules>.(*)..").should().notDependOnEachOther();

    @ArchTest
    static final ArchRule classes_are_analysed = classes().that().resideInAPackage("<package>..").should().resideInAPackage("<package>..")
            .because("ArchUnit must see this project's classes; when it imports none, every other rule here passes without checking anything");
}
