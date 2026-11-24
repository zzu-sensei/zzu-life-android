import java.io.File
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

val pythonRequirements = listOf(
    "cryptography==42.0.8",
    "cffi==1.17.1",
    "chaquopy-libffi==3.3",
)

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
            pythonRequirements.forEach { install(it) }
        }
    }
}

fun patchPipInstallRenames(helper: File) {
    if (!helper.exists()) return
    var source = helper.readText(Charsets.UTF_8).replace("\r\n", "\n")
    if (!source.contains("shutil.copytree(src, dst, dirs_exist_ok=True)")) {
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

fun runPythonCommand(
    cmd: List<String>,
    sitePackages: File,
    label: String,
) {
    val pb = ProcessBuilder(cmd).redirectErrorStream(true)
    val env = pb.environment()
    env.remove("__PYVENV_LAUNCHER__")
    val existingPp = env["PYTHONPATH"]
    env["PYTHONPATH"] = if (existingPp.isNullOrBlank()) {
        sitePackages.absolutePath
    } else {
        "${sitePackages.absolutePath}${File.pathSeparator}$existingPp"
    }
    val process = pb.start()
    val output = process.inputStream.bufferedReader(Charsets.UTF_8).readText()
    val exitCode = process.waitFor()
    if (output.isNotBlank()) {
        println(output.trimEnd())
    }
    if (exitCode != 0) {
        throw org.gradle.api.GradleException("$label failed with exit code $exitCode")
    }
}

val isWindowsHost = System.getProperty("os.name").lowercase().contains("win")

afterEvaluate {
    tasks.matching { it.name.startsWith("install") && it.name.endsWith("PythonRequirements") }
        .configureEach {
            if (!isWindowsHost) return@configureEach
            val originalActions = actions.toList()
            actions.clear()
            doLast {
                val envName = if (name.contains("Debug")) "debug" else "release"
                val envDir = file("$buildDir/python/env/$envName")
                val venvPython = file("$envDir/Scripts/python.exe")
                val sitePackages = file("$envDir/Lib/site-packages")

                patchPipInstallRenames(file("$sitePackages/chaquopy/pip_install.py"))

                val venvHealthy = venvPython.exists() && try {
                    ProcessBuilder(venvPython.absolutePath, "-c", "import ssl, ctypes")
                        .redirectErrorStream(true)
                        .start()
                        .waitFor() == 0
                } catch (_: Exception) {
                    false
                }

                if (venvHealthy && originalActions.isNotEmpty()) {
                    originalActions.forEach { it.execute(this) }
                    return@doLast
                }

                // Windows 某些环境下 venvlauncher.exe 无法加载 _ssl/_ctypes DLL，此时改由
                // 真实基础 Python 3.12 解释器搭配 PYTHONPATH 直接执行 Chaquopy 安装与编译。
                val pyvenvCfg = file("$envDir/pyvenv.cfg")
                val cfgPython = if (pyvenvCfg.exists()) {
                    pyvenvCfg.readLines(Charsets.UTF_8)
                        .firstOrNull { it.trim().startsWith("executable") }
                        ?.substringAfter("=", "")
                        ?.trim()
                } else {
                    null
                }
                val basePython = cfgPython?.takeIf { it.isNotBlank() && file(it).exists() }
                    ?: System.getenv("CHAQUOPY_BUILD_PYTHON")?.takeIf { it.isNotBlank() }
                    ?: throw org.gradle.api.GradleException("Cannot locate base Python 3.12 executable for $envDir")

                val outDir = (this as com.chaquo.python.OutputDirTask).outputDir.get().asFile
                outDir.deleteRecursively()
                outDir.mkdirs()

                val abis = android.defaultConfig.ndk.abiFilters.ifEmpty { setOf("arm64-v8a") }
                val minSdk = (android.defaultConfig.minSdk ?: 26).toString()

                val pipCmd = mutableListOf(
                    basePython, "-m", "chaquopy.pip_install",
                    "--target", outDir.absolutePath,
                    "--android-abis",
                )
                pipCmd.addAll(abis)
                pipCmd.add("--min-api-level")
                pipCmd.add(minSdk)
                pythonRequirements.forEach { req ->
                    pipCmd.add("--req")
                    pipCmd.add(req)
                }
                pipCmd.add("--")
                pipCmd.add("--no-deps")
                val wheelDir = System.getenv("CHAQUOPY_WHEEL_DIR")
                    ?.takeIf { it.isNotBlank() && file(it).isDirectory }
                if (wheelDir != null) {
                    pipCmd.add("--no-index")
                    pipCmd.add("--find-links")
                    pipCmd.add(wheelDir)
                }

                runPythonCommand(pipCmd, sitePackages, "chaquopy.pip_install")

                val pycCmd = listOf(
                    basePython, "-m", "chaquopy.pyc",
                    "--python", "3.12",
                    "--quiet", "--warning",
                    outDir.absolutePath,
                )
                runPythonCommand(pycCmd, sitePackages, "chaquopy.pyc")

                if (!File(outDir, "common").isDirectory ||
                    abis.any { !File(outDir, it).isDirectory }
                ) {
                    throw org.gradle.api.GradleException("Chaquopy requirements output missing under $outDir")
                }
            }
        }
}
