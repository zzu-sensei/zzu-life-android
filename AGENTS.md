# AGENTS

## Project Overview

- This repository is the **Android client only** for Zhengzhou University services.
- The Flutter UI lives in `flutter-app/lib/main.dart` (one large file; page classes are top level).
- Business logic runs in an embedded **Chaquopy Python 3.12** runtime under `flutter-app/android/app/src/main/python/`. All requests go from the phone straight to the school services; there is no backend in this repository.
- Android/Java side: `flutter-app/android/app/src/main/java/cn/edu/zzu/life/`.

## Layout

| Path | What it is |
| --- | --- |
| `flutter-app/lib/main.dart` | The entire Flutter UI. All page classes are top level here — put a new page in this file rather than a new one, so it can use the shared theme constants and helper widgets (`GlassPanel`, `LiquidBackground`, `Loader`, `ErrorState`, `number`, …) without extracting them. `DrainChartPage` (energy-drain chart) is the most recent addition. |
| `flutter-app/android/app/src/main/python/mobile_bridge.py` | Channel entry points called from Java |
| `flutter-app/android/app/src/main/python/mobile_zzupy.py` | School service clients (CAS, EAMS, e-card) |
| `flutter-app/android/app/src/main/python/mobile_plan_page.py` | Training-plan page parsing |
| `flutter-app/android/app/src/main/python/mobile_exam_page.py` | Exam-schedule page parsing; reuses `mobile_plan_page`'s data-literal JS parser and deliberately avoids `gmalg`, so it can be imported by the offline check |
| `flutter-app/android/app/src/main/python/mobile_network_page.py` | Campus self-service (校园网) account + login-history parsing; same reuse/avoidance rules as above |
| `flutter-app/android/app/src/main/java/cn/edu/zzu/life/MainActivity.java` | Platform-channel dispatch |
| `flutter-app/android/app/src/main/java/cn/edu/zzu/life/MonitorScheduler.java` | Background jobs (grade / energy checks) |
| `flutter-app/android/app/src/main/java/cn/edu/zzu/life/MonitorSettings.java` | SharedPreferences-backed settings |
| `flutter-app/android/app/src/main/java/cn/edu/zzu/life/UpdateChecker.java` | In-app update: queries the GitHub Release, downloads the APK via an optional URL prefix, hands it to the system installer |
| `.github/workflows/build-apk.yaml` | Builds and publishes the APK on `v*` tags; `workflow_dispatch` also does one-click releases (bump version → commit → tag → build → publish) |
| `.github/workflows/ci.yaml` | `flutter analyze` on push/PR |
| `scripts/test_mobile_plan.py` | Offline regression check for the plan parser |

## Offline Self-Checks (read this first)

- There is **no pytest suite**. Tests are standalone scripts under `scripts/` using plain `assert` and a `main()` function.
- Run them before considering a change to the Python parsing logic done:

  ```bash
  python scripts/run_tests.py
  python scripts/run_tests.py plan   # only files matching "plan"
  python scripts/run_tests.py -v     # show full output
  ```

- `scripts/test_mobile_plan.py` covers the training-plan parser: JS-literal parsing, `UNREPAIRED` classification, credit-weighted GPA, and semester grouping. Its fixtures mirror real EAMS responses.
- `scripts/test_mobile_exam.py` covers the exam parser: field mapping, time splitting, status fallback, semester-dropdown parsing, and the empty-list-is-normal rule.
- `scripts/test_mobile_network.py` covers the campus self-service parser: account field mapping, millisecond-timestamp conversion, the "never parse the password" rule, and the positional login-history array.
- When you add a checker, name it `scripts/test_<feature>.py` with a `main()` that calls each case explicitly; the runner auto-discovers it.
- **A test that cannot fail is worthless.** When fixing a bug, first reproduce the failure (temporarily revert the fix, confirm the new assertion fails), then restore the fix.
- These checks only cover the Python side. The UI, the Java channel, and anything needing a real login still require `flutter analyze`, a build, and a device run.

## Adding a Channel Method

Four edits are required, and missing one fails at runtime rather than compile time:

1. `mobile_bridge.py` — the Python function that returns a JSON string.
2. `MainActivity.java` — a `case` in the dispatch that calls it.
3. Dart — `NativeApi.call('methodName')`.
4. The UI itself.

## Python Runtime Constraints

- `zzupy.logging` needs `loguru`, which is **not** bundled into the app. Never import it, or anything that pulls it in, from `android/app/src/main/python/`.
- Dependencies are pinned in `flutter-app/android/app/build.gradle.kts` under `chaquopy { pip { ... } }`. Adding one requires a matching entry there.
- `flutter-app/android/app/src/main/python/zzupy/` is a trimmed copy of the school API clients used by the app. It is separate from any host-side Python.

## Traps Already Paid For

Discovered against live responses. Do not "simplify" these away:

- **EAMS pages inline data as JavaScript object literals, not JSON.** Single quotes, unquoted keys, and `$`-prefixed keys (`{'$type':'ResultType'}`), so `json.loads` can never work. `mobile_plan_page.py` contains a parser that accepts **data literals only** and raises on functions or variable references instead of evaluating them.
- **The school's "not passed" course result is `UNREPAIRED`**, not `FAILED`. Matching only `FAILED` silently lists zero failed courses. The three real values are `PASSED`, `UNREPAIRED`, `TAKING`.
- **Plan credit fields are `credits` / `subModuleNum`**, not `requiredCredits` / `requiredCourseNum`.
- **Grade point averages must be credit-weighted.** A plain arithmetic mean is wrong.
- **Parent and child plan modules are separate credit buckets.** Skipping a node because it has children silently drops its required credits.
- **Reusing a CAS token requires restoring MFA state too**, or `login()` raises an MFA error.
- **The campus self-service account object is server-rendered inline JS**, not a JSON API: `GET /Self/setting/personList` embeds `(function (user) { window.user = user || {}; })({...})`. **That page also inlines the account password in plaintext as `userPassword`** — `mobile_network_page` deliberately neither parses nor returns it. `GET /Self/dashboard/getLoginHistory` returns a **positional array** with no field names, so only confirmed positions are mapped and the untouched row is kept in `raw`. The self-service login posts **form-encoded** data, which is why `HttpClient.post` grew a `form=` argument.
- **The exam schedule is another server-rendered inline-JS page**, not an XHR/JSON API. `GET /student/for-std/exam-arrange/info/{studentId}?semesterId={id}` returns HTML with `var studentExamInfoVms = [...]`; the semester dropdown comes from `GET /student/for-std/exam-arrange`. A semester with no exams yet returns an **empty array** — that is normal, not an error.

## Building The APK (Windows)

The toolchain is pinned outside the repository; `flutter-app/android/local.properties` and `gradle.properties` point at it. Set these first:

```powershell
$env:JAVA_HOME         = "E:\dev-tools\jdk-17.0.20.1+1"
$env:GRADLE_USER_HOME  = "E:\dev-tools\gradle-home"
$env:ANDROID_SDK_ROOT  = "E:\dev-tools\android-sdk"
$env:PUB_CACHE         = "D:\code\.flutter-pub-cache"
$env:PATH = "E:\dev-tools\jdk-17.0.20.1+1\bin;D:\code\.flutter-sdk-good\flutter\bin;" + $env:PATH
cd flutter-app
flutter build apk --release --target-platform android-arm64
```

- ~40s with a warm Gradle cache. If a build hangs with no file writes, check `android/local.properties` — a wrong `sdk.dir` makes AGP try to download the NDK.
- Chaquopy needs **Python 3.12**. The default `python` on this machine is 3.13, so set `CHAQUOPY_BUILD_PYTHON` to the 3.12 interpreter (`C:\Users\<you>\AppData\Local\Programs\Python\Python312\python.exe`).
- **Chaquopy's pip step can hang for tens of minutes** fetching Android wheels (`cryptography`, `cffi`, `chaquopy-libffi`) from `pypi.org` / `chaquo.com`. Download them once and point the build at a local directory to make the step fully offline (it then takes seconds):

  ```powershell
  py -3.12 -m pip download --only-binary :all: --no-deps --dest D:\code\chaquopy-wheels `
    --platform android_24_arm64_v8a --python-version 3.12 --implementation cp `
    --extra-index-url https://chaquo.com/pypi-13.1 cryptography==42.0.8 cffi==1.17.1
  # chaquopy-libffi is only on the Chaquo index; fetch its arm64 wheel there directly.
  $env:CHAQUOPY_WHEEL_DIR = "D:\code\chaquopy-wheels"
  ```

  `build.gradle.kts` adds `--no-index --find-links <dir>` when `CHAQUOPY_WHEEL_DIR` is set, so no network is used at all. Note the platform tag is `android_24_arm64_v8a` (API 24), not the `compileSdk` value.

- **Never write `android/keystore.properties` with a UTF-8 BOM.** Java's `Properties` reads the BOM as part of the first key, so `storeFile` silently becomes `\uFEFFstoreFile`, the lookup fails, and Gradle quietly falls back to the auto-generated debug key — producing an APK that cannot upgrade the installed app. PowerShell's `Set-Content -Encoding UTF8` adds a BOM; write it with `[System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))` instead. Verify with `apksigner verify --print-certs` that the digest matches the expected keystore.

## In-App Update

- `UpdateChecker.java` reads `https://api.github.com/repos/zzu-sensei/zzu-life-android/releases/latest`, compares `tag_name` against the installed `versionName`, then downloads the `arm64` APK asset and hands it to the system installer through a `FileProvider` (`${applicationId}.fileprovider`, paths defined in `res/xml/file_paths.xml`).
- **Installation always requires the user to confirm in the system UI.** No app can install silently; do not try to work around this. Android 8+ additionally needs per-source "install unknown apps" permission — the code detects this and sends the user to the right settings screen before failing with an explanatory message.
- Download URLs are restricted to `github.com` / `githubusercontent.com` hosts (`isTrusted`). Keep that check: it prevents a tampered release payload from pointing the download somewhere else.
- **Releases are published per tag, not per push.** Pushing to `main` does not update the Release the app checks; push a `v*` tag (see Versioning below).
- **GitHub is often unreachable from mainland China.** `MonitorSettings.updateProxyPrefix` holds a user-editable "acceleration prefix", and `applyPrefix()` concatenates it in front of the full original URL — many mirrors work as `prefix + original_url` (e.g. `https://ghfast.top/`). Empty means direct. A bare host (`ghfast.top`) is normalised to `https://`. Both the API call and the APK download go through it. Do not replace this with local-port proxy probing; end users on a phone rarely run a local proxy.

## Versioning And Release

- Version lives in `flutter-app/pubspec.yaml` as `versionName+versionCode`.
- **`versionCode` must never decrease.** It is currently `23`. A version code lower than the installed one makes `adb install -r` fail with `INSTALL_FAILED_VERSION_DOWNGRADE`, and the only fix is uninstalling (which wipes app data).
- `versionName` restarted at `1.0.0`. The earlier `3.x` series continued the numbering of a superseded native app and meant nothing for this project.

### When To Bump (read before touching the version)

The version tracks **releases, not commits**. Bumping on every commit produces meaningless version numbers and useless Releases.

- **Do not bump while iterating.** A feature split across five commits, or a day of debugging, needs one version change at most — at the end, when it is ready to ship.
- **Patch (`1.2.0` → `1.2.1`)** for fixes, wording, and internal changes users would not notice.
- **Minor (`1.2.0` → `1.3.0`)** for new user-visible features.
- **Major (`1.3.0` → `2.0.0`)** for breaking changes — but note the app's real compatibility gate is `versionCode`, not `versionName`.
- `versionCode` must increase whenever `versionName` does, and may also increase on its own for builds that are not user-facing.

### Release Checklist

Two ways to ship. Both end in the same place: a `v*` tag whose APK is attached to a GitHub Release.

**A. One click (no local terminal) — recommended.** Actions → *Build APK* → *Run workflow*, on `main`:

- pick `bump` (`patch` / `minor` / `major`), or fill `version` with an explicit `x.y.z`;
- the workflow bumps `flutter-app/pubspec.yaml` (versionCode +1), commits it, pushes `main`, creates and pushes the tag, then builds and publishes — all in the same run;
- leave both empty and it only builds an artifact, no Release.

The bump and the build must stay in the same run: **a tag pushed with `GITHUB_TOKEN` does not trigger another workflow**, so a separate "tag it, then let the tag build" workflow would silently do nothing.

**B. By hand**

1. Decide the bump from the rules above; set `version: <name>+<code>` in `flutter-app/pubspec.yaml`.
2. `flutter analyze` clean, `python scripts/run_tests.py` green.
3. `git tag -a v<name> -m "<release notes>"` and `git push origin v<name>`. **The tag is what publishes** — a push to `main` alone does not update the Release the in-app updater reads.

**Either way, before announcing the release:**

4. Confirm the attached APK is signed with the project keystore, not a throwaway one:

   ```powershell
   apksigner verify --print-certs <downloaded.apk>
   # must print 4858d66c6a5c5e426a36ed861aba68afb417668a896f3290a5962c36fc0752bc
   ```

   **A CI build with no keystore secret signs with a freshly generated debug key, so every run differs** — such an APK cannot upgrade the installed app, and the in-app updater silently fails for everyone. Check this digest before announcing a release.

5. Confirm the APK's `versionName` equals the tag. If they disagree the in-app updater loops forever: it keeps offering an update that installs a build reporting the old version.

### Distribution

- `release/` and `*.apk` are gitignored: **APKs are distributed as GitHub Release assets, not committed.**
- Signing: `flutter-app/android/keystore.properties` (gitignored, template `keystore.properties.example`). **Keep the keystore** — changing it breaks in-place upgrades for everyone.
- CI reads the keystore from repository secrets. Store the keystore as base64 in `ANDROID_KEYSTORE_BASE64` (plus `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`). Generate with:

  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("<path>.keystore"))
  ```

  Secrets are read at build time only: **a Release built before the secrets were added keeps its throwaway signature forever.** Re-tag to rebuild.

### Update Checks

The in-app updater has two paths, both writing the same `update_state` blob in `MonitorSettings`:

- **Automatic (silent)**: `UpdateChecker.autoCheck()` runs on app start and from the background monitoring alarm, throttled to **48 hours** via `next_check_at` (a failed check retries in 6 hours instead of 48). No dialog, no launch popup.
- **Manual**: the 检查 button in the 更多 sheet (top-right, next to 退出登录) calls `checkNow()`, which ignores the throttle.

When the **automatic** check finds a new version it posts **one local notification** on the `zzu_life_updates` channel (separate from the 成绩与电量提醒 channel, so users can mute updates alone). It is deduped by `notified_version` in `update_state`, so each version notifies **at most once**. If notification permission is missing the notification is skipped and `notified_version` is deliberately left unset — the app asks for POST_NOTIFICATIONS only when an update actually exists, and `notifyPendingUpdate()` fires the missed notification once permission is granted. Manual checks never notify (the user is already looking at the app).

Keep it this way: shipping often must not nag, and frequent releases must not become user-visible noise.

## Workspace Hygiene

- Do not commit captured pages, session caches, or anything with a real student's name, ID, grades, or credentials. Debug dumps go outside the repository and must be deleted after use.
- `git status` before broad edits; the tree may hold unrelated user changes. Do not revert changes you did not make.
