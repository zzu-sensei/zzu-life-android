package cn.edu.zzu.life;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.net.Uri;
import android.os.Build;
import android.util.Log;

import androidx.core.content.FileProvider;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/**
 * 应用内检查更新。
 *
 * 版本来源是 GitHub Release：远端标签形如 {@code v1.1.0}，与本机
 * {@code versionName} 比较。下载完成后交给系统安装器，**安装仍需用户在系统界面
 * 确认**——应用无法静默安装，这既是 Android 的限制也是应有的行为。
 *
 * 只信任 {@code github.com} / {@code githubusercontent.com} 的下载地址，避免
 * Release 数据被篡改时把包引到别处。
 */
final class UpdateChecker {

    private static final String TAG = "UpdateChecker";
    private static final String RELEASES_API =
            "https://api.github.com/repos/zzu-sensei/zzu-life-android/releases/latest";
    private static final String USER_AGENT = "ZZU-Life-Android";
    private static final int TIMEOUT_MS = 20_000;
    private static final int CONNECT_TIMEOUT_MS = 15_000;

    private UpdateChecker() {
    }

    /**
     * 把「加速前缀」拼到原始地址前面。
     *
     * 国内直连 GitHub 常常超时，很多镜像服务支持「前缀 + 原始地址」的用法，
     * 例如前缀 {@code https://ghfast.top/} 会把
     * {@code https://github.com/a/b.apk} 变成
     * {@code https://ghfast.top/https://github.com/a/b.apk}。
     *
     * 前缀由用户在设置里填写（见 {@link MonitorSettings#updateProxyPrefix}），
     * 留空则直连。接受 {@code ghfast.top} 这种不带协议的写法，自动补 https。
     */
    static String applyPrefix(String prefix, String url) {
        String trimmed = prefix == null ? "" : prefix.trim();
        if (trimmed.isEmpty() || url == null || url.isEmpty()) {
            return url;
        }
        if (!trimmed.contains("://")) {
            trimmed = "https://" + trimmed;
        }
        if (!trimmed.endsWith("/")) {
            trimmed = trimmed + "/";
        }
        return trimmed + url;
    }

    private static HttpURLConnection open(String url, String accept) throws Exception {
        HttpURLConnection connection =
                (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
        connection.setReadTimeout(TIMEOUT_MS);
        connection.setInstanceFollowRedirects(true);
        connection.setRequestProperty("User-Agent", USER_AGENT);
        if (accept != null && !accept.isEmpty()) {
            connection.setRequestProperty("Accept", accept);
        }
        return connection;
    }

    /** 本机版本名，例如 {@code 1.1.0}。 */
    static String currentVersion(Context context) {
        try {
            PackageInfo info = context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), 0);
            return info.versionName == null ? "" : info.versionName;
        } catch (Exception error) {
            Log.w(TAG, "读取本机版本失败", error);
            return "";
        }
    }

    /**
     * 查询最新 Release 并与本机版本比较。
     *
     * 返回的 JSON 字段：{@code current}、{@code latest}、{@code has_update}、
     * {@code notes}、{@code url}、{@code size}、{@code published_at}、
     * {@code prefix}。
     */
    static JSONObject check(Context context) throws Exception {
        String current = currentVersion(context);
        String prefix = MonitorSettings.updateProxyPrefix(context);
        String requestUrl = applyPrefix(prefix, RELEASES_API);

        String body;
        HttpURLConnection connection = open(requestUrl, "application/vnd.github+json");
        try {
            int status = connection.getResponseCode();
            if (status == 404) {
                throw new IllegalStateException("仓库还没有发布过版本");
            }
            if (status != 200) {
                throw new IllegalStateException(
                        "HTTP " + status
                                + (prefix.isEmpty()
                                        ? "。若因网络无法访问 GitHub，可在下方填写加速前缀后重试"
                                        : "。当前加速前缀：" + prefix));
            }
            body = readAll(connection.getInputStream());
        } finally {
            connection.disconnect();
        }

        JSONObject release = new JSONObject(body);
        String tag = release.optString("tag_name", "").trim();
        String latest = stripPrefix(tag);

        JSONObject asset = pickApk(release.optJSONArray("assets"));
        String url = asset == null ? "" : asset.optString("browser_download_url", "");
        long size = asset == null ? 0 : asset.optLong("size", 0);

        JSONObject out = new JSONObject();
        out.put("ok", true);
        out.put("current", current);
        out.put("latest", latest);
        out.put("has_update", isNewer(latest, current));
        out.put("notes", release.optString("body", ""));
        out.put("url", url);
        out.put("size", size);
        out.put("published_at", release.optString("published_at", ""));
        out.put("prefix", prefix);
        return out;
    }

    /**
     * 下载 APK 并唤起系统安装器。
     *
     * 文件落在应用私有目录 {@code files/updates/}，通过 FileProvider 以
     * {@code content://} 暴露。Android 8 起还需要用户为该来源授予「安装未知应用」
     * 权限，因此这里会先检查并跳转到对应设置页。
     */
    static JSONObject downloadAndInstall(Activity activity, String url, String version)
            throws Exception {
        if (!isTrusted(url)) {
            throw new IllegalArgumentException("下载地址不在受信任的域名下，已拒绝");
        }
        String current = currentVersion(activity);
        if (!isNewer(version, current)) {
            throw new IllegalStateException("该版本不高于当前版本（" + version + "）");
        }

        File dir = new File(activity.getFilesDir(), "updates");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IllegalStateException("无法创建下载目录");
        }
        // 覆盖同一个文件名，避免历史包堆积占空间。
        final File apk = new File(dir, "zzu-life-update.apk");

        String prefix = MonitorSettings.updateProxyPrefix(activity);
        String requestUrl = applyPrefix(prefix, url);
        Log.i(TAG, "开始下载安装包：" + requestUrl);

        HttpURLConnection connection = open(requestUrl, "application/octet-stream");
        try {
            int status = connection.getResponseCode();
            if (status != 200) {
                throw new IllegalStateException("下载失败（HTTP " + status + "）");
            }
            try (InputStream in = connection.getInputStream();
                 FileOutputStream out = new FileOutputStream(apk)) {
                byte[] buffer = new byte[64 * 1024];
                int read;
                while ((read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                }
            }
        } finally {
            connection.disconnect();
        }

        if (apk.length() <= 0) {
            throw new IllegalStateException("下载到的文件为空");
        }

        // Android 8 起，安装未知来源应用需要用户按来源授权。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && !activity.getPackageManager().canRequestPackageInstalls()) {
            Intent settings = new Intent(
                    android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + activity.getPackageName()));
            activity.startActivity(settings);
            throw new IllegalStateException(
                    "请先允许「安装未知应用」，授权后再次点击更新");
        }

        Uri uri = FileProvider.getUriForFile(
                activity, activity.getPackageName() + ".fileprovider", apk);
        Intent install = new Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        activity.startActivity(install);

        JSONObject out = new JSONObject();
        out.put("ok", true);
        out.put("path", apk.getAbsolutePath());
        out.put("size", apk.length());
        return out;
    }

    // ------------------------------------------------------------------ 工具

    private static String readAll(InputStream in) throws Exception {
        StringBuilder builder = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(in, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line).append('\n');
            }
        }
        return builder.toString();
    }

    /** 从 assets 里挑出 arm64 的 APK；没有 arch 标记时退回第一个 APK。 */
    private static JSONObject pickApk(JSONArray assets) {
        if (assets == null) return null;
        JSONObject fallback = null;
        for (int i = 0; i < assets.length(); i++) {
            JSONObject asset = assets.optJSONObject(i);
            if (asset == null) continue;
            String name = asset.optString("name", "");
            if (!name.endsWith(".apk")) continue;
            if (name.contains("arm64")) return asset;
            if (fallback == null) fallback = asset;
        }
        return fallback;
    }

    private static boolean isTrusted(String url) {
        if (url == null) return false;
        String lower = url.toLowerCase();
        return lower.startsWith("https://github.com/")
                || lower.startsWith("https://objects.githubusercontent.com/")
                || lower.startsWith("https://github-releases.githubusercontent.com/");
    }

    private static String stripPrefix(String tag) {
        String value = tag == null ? "" : tag.trim();
        while (value.startsWith("v") || value.startsWith("V")) {
            value = value.substring(1);
        }
        return value;
    }

    /**
     * 比较点分版本号，远端更高时返回 true。
     *
     * 版本段不足的按 0 补齐，因此 {@code 1.1} 与 {@code 1.1.0} 视为相同；带
     * 后缀的预发布段（如 {@code 1.1.0-beta}）只比较数字部分。
     */
    static boolean isNewer(String remote, String local) {
        int[] a = parse(remote);
        int[] b = parse(local);
        int length = Math.max(a.length, b.length);
        for (int i = 0; i < length; i++) {
            int left = i < a.length ? a[i] : 0;
            int right = i < b.length ? b[i] : 0;
            if (left != right) return left > right;
        }
        return false;
    }

    private static int[] parse(String version) {
        if (version == null || version.isEmpty()) return new int[0];
        String[] parts = version.split("\\.");
        int[] out = new int[parts.length];
        for (int i = 0; i < parts.length; i++) {
            StringBuilder digits = new StringBuilder();
            for (char c : parts[i].toCharArray()) {
                if (Character.isDigit(c)) {
                    digits.append(c);
                } else {
                    break;
                }
            }
            try {
                out[i] = digits.length() == 0 ? 0 : Integer.parseInt(digits.toString());
            } catch (NumberFormatException error) {
                out[i] = 0;
            }
        }
        return out;
    }
}
