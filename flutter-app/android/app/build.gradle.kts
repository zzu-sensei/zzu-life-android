import java.util.Properties

plugins {
    id("com.android.application")
    id("com.chaquo.python")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 稳定的签名配置。默认的 debug 密钥库位于 ~/.android/debug.keystore，换机器或
// 改过 ANDROID_USER_HOME 时 Android 会重新生成一份**不同**的密钥，导致新包无法
// 覆盖安装（INSTALL_FAILED_UPDATE_INCOMPATIBLE）。因此这里优先读取
// keystore.properties 指定的固定密钥库，没有该文件才回退到默认 debug 签名。
//
// 本仓库不包含密钥库本体；请在 keystore.properties 里填写自己机器上的路径。
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { stream ->
        keystoreProperties.load(stream)
    }
}
val customKeystorePath: String? = keystoreProperties.getProperty("storeFile")
val hasCustomKeystore: Boolean =
    customKeystorePath != null && file(customKeystorePath).exists()

android {
    namespace = "cn.edu.zzu.life"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "cn.edu.zzu.life"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 35
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.clear()
            abiFilters += "arm64-v8a"
        }
    }

    if (hasCustomKeystore) {
        signingConfigs {
            create("release") {
                storeFile = file(customKeystorePath!!)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 固定签名优先；未配置时沿用默认 debug 签名，保证 `flutter run --release`
            // 在没有 keystore.properties 的机器上也能跑通。
            signingConfig = if (hasCustomKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

chaquopy {
    defaultConfig {
        version = "3.12"
        // Chaquopy normally discovers Python 3.12 from PATH. Override it for
        // unusual local setups without committing a machine-specific path.
        System.getenv("CHAQUOPY_BUILD_PYTHON")
            ?.takeIf { it.isNotBlank() }
            ?.let { buildPython(it) }
        pip {
            options("--no-deps")
            // 可选的本地 wheel 兜底目录。Chaquo 的 Android wheel 体积不小且只在
            // 其自有索引上，网络不稳时 pip 会长时间卡在下载上（本机实测可卡住
            // 数十分钟）。把 wheel 预先放到任意目录并设置 CHAQUOPY_WHEEL_DIR，
            // 构建即改为完全离线安装，几秒完成。
            System.getenv("CHAQUOPY_WHEEL_DIR")
                ?.takeIf { it.isNotBlank() && file(it).isDirectory }
                ?.let { options("--no-index", "--find-links", it) }
            install("cryptography==42.0.8")
            install("cffi==1.17.1")
            install("chaquopy-libffi==3.3")
        }
    }
}

tasks.matching { it.name == "installReleasePythonRequirements" }.configureEach {
    doFirst {
        val helper = file("$buildDir/python/env/release/Lib/site-packages/chaquopy/pip_install.py")
        if (helper.exists()) {
            var source = helper.readText(Charsets.UTF_8)
            source = source.replace("import re\nimport subprocess", "import re\nimport shutil\nimport subprocess")
            source = source.replace(
                "def renames(src, dst):\n    os.renames(src, dst)",
                "def renames(src, dst):\n" +
                    "    os.makedirs(dirname(dst), exist_ok=True)\n" +
                    "    if isdir(src):\n" +
                    "        shutil.copytree(src, dst, dirs_exist_ok=True)\n" +
                    "        rmtree(src)\n" +
                    "    else:\n" +
                    "        shutil.copy2(src, dst)\n" +
                    "        os.remove(src)"
            )
            helper.writeText(source, Charsets.UTF_8)
        }
    }
}
