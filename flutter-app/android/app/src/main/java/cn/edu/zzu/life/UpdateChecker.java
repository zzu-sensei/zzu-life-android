package cn.edu.zzu.life;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
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

    /**
     * 更新通知单独走一个渠道，用户可以在系统设置里只关掉更新提醒，
     * 不影响成绩与电量的预警。
     */
    private static final String UPDATE_CHANNEL_ID = "zzu_life_updates";
    private static final int UPDATE_NOTIFY_ID = 8110;

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

    /** 自动检查的间隔：48 小时。 */
    private static final long AUTO_CHECK_INTERVAL_MS = 48L * 60L * 60L * 1000L;

    /** 自动检查失败后的重试间隔：6 小时，比正常间隔短，网络恢复后能较快补上。 */
    private static final long AUTO_RETRY_INTERVAL_MS = 6L * 60L * 60L * 1000L;

    /**
     * 用户手动触发的检查：无条件请求，并把结果写进自动检查的状态。
     *
     * 不发通知——用户此刻就在应用里，通知是多余的。
     */
    static JSONObject checkNow(Context context) throws Exception {
        return runCheck(context, false);
    }

    /**
     * 静默的自动检查：距下次允许检查的时间还没到，就直接返回上次结果，不发请求。
     *
     * 由「打开应用」与「后台巡检」两处调用。发现新版本时**发一条通知**（同一版本
     * 只发一次），其余情况全程安静——结果写进 {@code update_state}，由「更多」面板
     * 里那行「检查更新」自己显示。失败也安静：保留上次结果，只把下次允许检查的时间
     * 推后 6 小时，避免反复重试。
     */
    static JSONObject autoCheck(Context context) throws Exception {
        long now = System.currentTimeMillis();
        JSONObject state = storedState(context);
        if (state.optLong("next_check_at", 0L) > now) {
            state.put("cached", true);
            return state;
        }
        try {
            return runCheck(context, true);
        } catch (Exception error) {
            Log.i(TAG, "自动检查更新失败，保留上次结果：" + error.getMessage());
            state.put("cached", true);
            state.put("next_check_at", now + AUTO_RETRY_INTERVAL_MS);
            state.put("error", error.getMessage() == null ? "自动检查失败" : error.getMessage());
            MonitorSettings.saveUpdateState(context, state.toString());
            return state;
        }
    }

    /**
     * 真正发起一次检查并落盘。
     *
     * @param allowNotify 发现新版本时是否允许发通知（手动检查传 {@code false}）。
     */
    private static JSONObject runCheck(Context context, boolean allowNotify) throws Exception {
        long now = System.currentTimeMillis();
        JSONObject fresh = check(context);
        fresh.put("checked_at", now);
        fresh.put("next_check_at", now + AUTO_CHECK_INTERVAL_MS);
        fresh.put("cached", false);

        // 通知去重：同一个版本只提醒一次，等发布方改了版本号（latest 变了）才会再提醒。
        String latest = fresh.optString("latest", "");
        String notified = storedState(context).optString("notified_version", "");
        if (fresh.optBoolean("has_update") && !latest.isEmpty() && !latest.equals(notified)) {
            if (allowNotify && notifyUpdate(context, latest)) {
                notified = latest;
                fresh.put("notified", true);
            } else {
                // 没发出去（手动检查、或通知权限没给）：下次自动检查还有机会。
                fresh.put("notified", false);
            }
        }
        if (!notified.isEmpty()) fresh.put("notified_version", notified);
        MonitorSettings.saveUpdateState(context, fresh.toString());
        return fresh;
    }

    /**
     * 有新版本时发一条本地通知，返回是否真的发出去了。
     *
     * 通知权限没给（Android 13+ 未授权）时直接返回 false，并且**不记录「已提醒」**——
     * 等用户授权后下次检查还会再提醒一次，不会漏掉。
     */
    private static boolean notifyUpdate(Context context, String version) {
        if (Build.VERSION.SDK_INT >= 33
                && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            return false;
        }
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return false;
        manager.createNotificationChannel(new NotificationChannel(
                UPDATE_CHANNEL_ID,
                "应用更新",
                NotificationManager.IMPORTANCE_DEFAULT));
        Intent open = new Intent(context, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent content = PendingIntent.getActivity(
                context,
                UPDATE_NOTIFY_ID,
                open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification notification = new Notification.Builder(context, UPDATE_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher_v6)
                .setContentTitle("发现新版本 " + version)
                .setContentText("点开应用，在「更多 → 检查更新」里下载安装")
                .setContentIntent(content)
                .setAutoCancel(true)
                .build();
        manager.notify(UPDATE_NOTIFY_ID, notification);
        return true;
    }

    /**
     * 用户刚授权通知权限后调用：把「已经发现、但当时没能提醒」的更新补一条通知。
     */
    static void notifyPendingUpdate(Context context) {
        try {
            JSONObject state = storedState(context);
            if (!state.optBoolean("has_update")) return;
            String latest = state.optString("latest", "");
            String notified = state.optString("notified_version", "");
            if (latest.isEmpty() || latest.equals(notified)) return;
            if (notifyUpdate(context, latest)) {
                state.put("notified_version", latest);
                state.put("notified", true);
                MonitorSettings.saveUpdateState(context, state.toString());
            }
        } catch (Exception ignored) {
            // 补通知失败无所谓，下次自动检查还会再试。
        }
    }

    /** 上次自动检查保留下来的结果；从未检查过时返回一个只有 {@code ok} 的空状态。 */
    static JSONObject storedState(Context context) throws Exception {
        String raw = MonitorSettings.updateState(context);
        JSONObject state;
        if (raw == null || raw.isEmpty()) {
            state = new JSONObject();
        } else {
            try {
                state = new JSONObject(raw);
            } catch (Exception ignored) {
                // 数据损坏时重建，不阻塞读取。
                state = new JSONObject();
            }
        }
        state.put("ok", true);
        if (!state.has("current")) state.put("current", currentVersion(context));
        if (!state.has("has_update")) state.put("has_update", false);
        return state;
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
