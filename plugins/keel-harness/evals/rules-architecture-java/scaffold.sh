#!/usr/bin/env bash
# Host prerequisites: a JDK and network access for the Gradle wrapper.
# A Spring Boot (Gradle Kotlin DSL) layout: domain/, application/, adapter/{web,persistence}/. One
# domain class imports org.springframework.stereotype.Service. The harness comes from the bundled assets.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$here/../rules-brownfield/harness.sh"
base=src/main/java/com/acme
mkdir -p $base/domain $base/application $base/adapter/web $base/adapter/persistence src/test/java/com/acme
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
cat > $base/Application.java <<'JAVA'
package com.acme;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Application {
    public static void main(String[] args) { SpringApplication.run(Application.class, args); }
}
JAVA
cat > $base/domain/Posting.java <<'JAVA'
package com.acme.domain;

import org.springframework.stereotype.Service;

@Service
public class Posting {
    public long applyFee(long cents) { return Math.round(cents * 0.98); }
}
JAVA
cat > $base/application/PostingService.java <<'JAVA'
package com.acme.application;

import com.acme.domain.Posting;

public class PostingService {
    private final Posting posting = new Posting();
    public long fee(long cents) { return posting.applyFee(cents); }
}
JAVA
cat > $base/adapter/web/PostingController.java <<'JAVA'
package com.acme.adapter.web;

import com.acme.application.PostingService;

public class PostingController {
    private final PostingService service = new PostingService();
    public long fee(long cents) { return service.fee(cents); }
}
JAVA
cat > $base/adapter/persistence/PostingRepository.java <<'JAVA'
package com.acme.adapter.persistence;

import com.acme.domain.Posting;

public class PostingRepository {
    public Posting load() { return new Posting(); }
}
JAVA
printf 'build/\n.gradle/\n' > .gitignore
install_harness
sed -i 's/^\tnpm install/\t.\/gradlew build/' Makefile
git init -q && git add -A && git -c user.email=eval@local -c user.name=eval commit -qm "initial"
