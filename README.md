# Lumaris Maven repository

Published artifacts for the Lumaris AR makeup SDK. Served at
**https://maven.apimastudio.com**.

```kotlin
repositories {
    maven { url = uri("https://maven.apimastudio.com") }
}

dependencies {
    implementation("com.apima.lumaris:lumaris:0.3.1")          // the SDK
    implementation("com.apima.lumaris:lumaris-agora:0.3.1")    // optional: Agora calls
}
```

No credentials needed. `lumaris-agora` brings `lumaris` with it; the core
SDK links no call provider.

This repository holds release artifacts only -- it is written by
`tools/publish-maven.sh` in the SDK repository and should not be edited by
hand. Every published version is permanent: consumers cache by coordinate,
so a version's bytes must never change.

Docs: https://apimastudio.com/docs
