#!/usr/bin/env bash
# Host prerequisites: a JDK 17+ and network access (the Gradle wrapper downloads Gradle).
# A small Spring Boot repository with the Gradle Kotlin DSL, one class and one test. No AGENTS.md,
# no docs/, no CI. A cold Java compile usually blows the 30 s fast budget on small CI hosts; when it
# does, build must name the measured compile time under not_installed instead of installing the sensor.
set -euo pipefail
base=src/main/java/com/acme
mkdir -p $base src/test/java/com/acme
cat > settings.gradle.kts <<'KTS'
rootProject.name = "ledger"
KTS
cat > build.gradle.kts <<'KTS'
plugins {
    java
    id("org.springframework.boot") version "3.3.4"
    id("io.spring.dependency-management") version "1.1.6"
}
group = "com.acme"
java { toolchain { languageVersion = JavaLanguageVersion.of(17) } }
repositories { mavenCentral() }
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    testImplementation("org.springframework.boot:spring-boot-starter-test")
}
tasks.withType<Test> { useJUnitPlatform() }
KTS
cat > $base/Posting.java <<'JAVA'
package com.acme;

public class Posting {
    public long applyFee(long cents) { return Math.round(cents * 0.98); }
}
JAVA
cat > src/test/java/com/acme/PostingTest.java <<'JAVA'
package com.acme;

import static org.junit.jupiter.api.Assertions.assertEquals;
import org.junit.jupiter.api.Test;

class PostingTest {
    @Test
    void appliesTheFee() { assertEquals(1200L, new Posting().applyFee(1224L)); }
}
JAVA
printf 'build/\n.gradle/\n' > .gitignore
if command -v gradle >/dev/null 2>&1; then gradle wrapper --quiet; fi
git init -q && git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "initial"
