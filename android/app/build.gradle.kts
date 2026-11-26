import java.io.FileInputStream
import java.util.Properties
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()

if (hasKeystoreProperties) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

val requiredReleaseSigningKeys = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)

val missingReleaseSigningKeys = if (hasKeystoreProperties) {
    requiredReleaseSigningKeys.filter {
        keystoreProperties.getProperty(it).isNullOrBlank()
    }
} else {
    requiredReleaseSigningKeys
}

val hasCompleteReleaseSigning =
    hasKeystoreProperties && missingReleaseSigningKeys.isEmpty()

val wantsRelease = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}

// The ABIs this build was asked for (`flutter build apk --target-platform …`,
// which Flutter hands over as `-Ptarget-platform`). Flutter compiles its own
// code for those alone but lets plugins bring native libraries for every ABI it
// supports, so an APK built for arm64 would still carry armeabi-v7a folders: a
// 32-bit phone would install it and crash without Flutter's engine. The filter
// below keeps every package to the ABIs it was built for.
val flutterPlatformAbis = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
    "android-x86" to "x86",
)
val targetAbis = (findProperty("target-platform") as String?)
    ?.split(",")
    ?.mapNotNull { flutterPlatformAbis[it.trim()] }
    .orEmpty()

// A release is signed when android/key.properties exists, and then the file
// must be complete. Without it the release is built unsigned: that is how a
// rebuild from source runs (an app store's build server, a reproducibility
// check), which signs on its own or compares against our signed package.
// scripts/release.sh refuses to ship an unsigned package, so a missing file
// cannot reach a release.
if (wantsRelease) {
    if (!hasKeystoreProperties) {
        logger.warn(
            "android/key.properties not found: building an unsigned release. " +
                "Copy android/key.properties.example to sign.",
        )
    } else if (!hasCompleteReleaseSigning) {
        throw GradleException(
            "android/key.properties is missing required values: ${missingReleaseSigningKeys.joinToString(", ")}",
        )
    }
}

/**
 * Puts the app's font files where a widget can draw with them (Roboto, the
 * app's face, and Geist Mono).
 *
 * A widget is a `RemoteViews`, inflated by the launcher from this app's
 * resources, so its faces must be `res/font/`: a Flutter asset is out of its
 * reach. The files are the ones the app draws with (`assets/fonts/`, named in
 * `pubspec.yaml`) and the repo holds one copy of each: this copies them into a
 * generated resource directory under the names Android wants (lowercase, no
 * hyphen), on every build, through the variant API below.
 *
 * Their SIL OFL texts stay where they are, in `assets/fonts/` (bundled into the
 * same APK as Flutter assets and shown in the app's licence page by
 * `LicenseRegistry`, `main.dart`). The licence asks that its text travel with
 * the font software it covers; it does, in the one package that ships both,
 * and a second copy of each text as a raw resource would be a copy nobody
 * reads.
 */
abstract class OutsideFonts : DefaultTask() {
    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val fonts: DirectoryProperty

    /** The generated resource root: `font/` goes inside it. */
    @get:OutputDirectory
    abstract val resources: DirectoryProperty

    @TaskAction
    fun copy() {
        val font = resources.get().asFile.resolve("font")
        font.deleteRecursively()
        font.mkdirs()
        for ((source, name) in FACES) {
            fonts.get().file(source).asFile.copyTo(font.resolve(name))
        }
    }

    private companion object {
        /** `assets/fonts/` file to `res/font/` file. */
        val FACES = mapOf(
            "roboto/Roboto-Medium.ttf" to "roboto_medium.ttf",
            "roboto/Roboto-Bold.ttf" to "roboto_bold.ttf",
            "GeistMono.ttf" to "geist_mono.ttf",
        )
    }
}

val outsideFonts = tasks.register<OutsideFonts>("outsideFonts") {
    fonts.set(layout.projectDirectory.dir("../../assets/fonts"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.res?.addGeneratedSourceDirectory(outsideFonts, OutsideFonts::resources)
    }
}

android {
    namespace = "com.matthwlabs.cupola"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications requires this even when scheduled
        // notifications are never used: the plugin itself compiles against
        // java.time, which is API 26, so below that it needs the desugared
        // backport or the build fails at D8 with missing classes.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // This fork installs beside Cupola, and Stack 2 beside Stack 1.0
        // (com.matthwlabs.cupola.stack, tag stack-1.0): an app ID of its own.
        // The code's package (namespace) is unchanged.
        applicationId = "com.matthwlabs.cupola.stack2"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_secure_storage 10.x requires Android 23+;
        // flutter_local_notifications 22.x requires 24+. Costs nothing worth
        // keeping: 24 is Android 7.0, and everything below it is a rounding
        // error on any current distribution.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Replaces the Flutter plugin's list (every ABI Flutter supports) with
        // the ones asked for: see `targetAbis` above.
        if (targetAbis.isNotEmpty()) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(targetAbis)
            }
        }
    }

    signingConfigs {
        if (hasCompleteReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    // The Android Gradle plugin writes the dependency list into the APK's
    // signing block, encrypted with a key only Google holds. Nobody else can
    // read it, an app store that rebuilds from source flags it, and it stands
    // between our APK and a byte-for-byte rebuild. Play reads the same list from
    // the App Bundle, which keeps it.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = true
    }

    buildTypes {
        release {
            if (hasCompleteReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // Version matched to the one flutter_local_notifications 22.x declares, so
    // the app and the plugin never disagree on which backport is on the path.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // For MainActivity.pruneFinishedWork, which drops WorkManager's stored copy
    // of finished background searches. The arr API key travels in a job's
    // inputData and the plugin never prunes.
    //
    // background_downloader declares the same artifact, but as `implementation`,
    // so it is not on this module's compile path and the app has to ask for it
    // itself. Pinned to the plugin's own version rather than a newer one: two
    // WorkManager versions in one build is a runtime argument about which
    // database schema wins. Re-check this line whenever the plugin is upgraded.
    implementation("androidx.work:work-runtime-ktx:2.11.0")
}

flutter {
    source = "../.."
}
