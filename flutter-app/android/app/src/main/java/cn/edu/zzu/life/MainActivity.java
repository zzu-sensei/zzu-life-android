package cn.edu.zzu.life;

import android.Manifest;
import android.app.Activity;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.print.PrintManager;
import android.provider.Settings;
import android.util.Base64;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.annotation.NonNull;

import org.json.JSONObject;

import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "cn.edu.zzu.life/api";
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private String pendingAccount = "";
    private static final int SAVE_FILE_REQUEST = 8104;
    /** 申请通知权限，用于「发现新版本」的提醒。 */
    private static final int REQUEST_UPDATE_NOTIFY = 8105;
    private MethodChannel.Result pendingSaveResult;
    private String pendingSaveContent;
    private WebView printingWebView;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler(this::handleCall);
        // 应用每次启动都重排巡检闹钟：只靠开机广播会导致应用更新后闹钟链断掉，
        // 巡检从此不再触发。
        executor.execute(() -> {
            try {
                MonitorScheduler.reschedule(getApplicationContext());
            } catch (Exception ignored) {
                // 重排失败不影响应用启动。
            }
        });
    }

    private void handleCall(MethodCall call, MethodChannel.Result result) {
        if ("getSession".equals(call.method)) {
            String[] stored = SessionStore.load(this);
            JSONObject payload = new JSONObject();
            try {
                payload.put("ok", true);
                payload.put("logged_in", stored != null);
                if (stored != null) payload.put("account", stored[0]);
                result.success(payload.toString());
            } catch (Exception error) {
                result.error("SESSION", error.getMessage(), null);
            }
            return;
        }
        if ("logout".equals(call.method)) {
            SessionStore.clear(this);
            try {
                WidgetSupport.clearCache(getApplicationContext());
                WidgetSupport.refreshAllFromCache(getApplicationContext());
                AiConfigStore.clearHistory(getApplicationContext());
            } catch (Exception ignored) {
                // 小组件或对话清理失败不影响退出登录。
            }
            result.success("{\"ok\":true}");
            return;
        }
        if ("saveFile".equals(call.method)) {
            startSaveFile(call, result);
            return;
        }
        if ("printDocument".equals(call.method)) {
            startPrint(call, result);
            return;
        }
        if ("saveMonitorSettings".equals(call.method) && Build.VERSION.SDK_INT >= 33) {
            Boolean energy = call.argument("energy_enabled");
            Boolean grades = call.argument("grade_enabled");
            if (Boolean.TRUE.equals(energy) || Boolean.TRUE.equals(grades)) {
                requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS}, 8103);
            }
        }
        if ("checkUpdate".equals(call.method)) {
            executor.execute(() -> {
                try {
                    result.success(UpdateChecker.checkNow(this).toString());
                } catch (Exception error) {
                    result.error("UPDATE_CHECK", describe(error), null);
                }
            });
            return;
        }
        if ("autoCheckUpdate".equals(call.method)) {
            // 静默的自动检查（48 小时节流）：只写状态，界面自己读，不弹任何东西。
            executor.execute(() -> {
                try {
                    result.success(UpdateChecker.autoCheck(this).toString());
                } catch (Exception error) {
                    result.error("UPDATE_AUTO_CHECK", describe(error), null);
                }
            });
            return;
        }
        if ("requestUpdateNotifyPermission".equals(call.method)) {
            // 只有检测到新版本时前端才会调这里，所以不会无缘无故弹权限框。
            requestUpdateNotifyPermission();
            result.success("{\"ok\":true}");
            return;
        }
        if ("saveUpdateProxyPrefix".equals(call.method)) {
            MonitorSettings.saveUpdateProxyPrefix(this, call.argument("prefix"));
            result.success("{\"ok\":true}");
            return;
        }
        if ("getUpdateProxyPrefix".equals(call.method)) {
            JSONObject payload = new JSONObject();
            try {
                payload.put("ok", true);
                payload.put("prefix", MonitorSettings.updateProxyPrefix(this));
                result.success(payload.toString());
            } catch (Exception error) {
                result.error("UPDATE_PREFIX", describe(error), null);
            }
            return;
        }
        if ("getThemeMode".equals(call.method)) {
            JSONObject payload = new JSONObject();
            try {
                payload.put("ok", true);
                payload.put("mode", MonitorSettings.themeMode(this));
                result.success(payload.toString());
            } catch (Exception error) {
                result.error("THEME_MODE", describe(error), null);
            }
            return;
        }
        if ("saveThemeMode".equals(call.method)) {
            MonitorSettings.saveThemeMode(this, call.argument("mode"));
            try {
                WidgetSupport.refreshAllFromCache(getApplicationContext());
            } catch (Exception ignored) {
                // 小组件重绘失败不影响主题切换。
            }
            result.success("{\"ok\":true}");
            return;
        }
        if ("getCachedSchedule".equals(call.method)) {
            executor.execute(() -> {
                try {
                    JSONObject data = WidgetSupport.loadSemesterSchedule(getApplicationContext());
                    JSONObject payload = new JSONObject();
                    payload.put("ok", true);
                    payload.put("cached", data != null);
                    if (data != null) {
                        payload.put("data", data);
                    }
                    String text = payload.toString();
                    runOnUiThread(() -> result.success(text));
                } catch (Exception error) {
                    runOnUiThread(() -> result.error("CACHE_READ", describe(error), null));
                }
            });
            return;
        }
        if ("clearCachedSchedule".equals(call.method)) {
            WidgetSupport.clearSemesterSchedule(getApplicationContext());
            try {
                ScheduleWidgetProvider.renderCached(getApplicationContext());
                WeekScheduleWidgetProvider.renderCached(getApplicationContext());
            } catch (Exception ignored) {
                // 清理后的小组件重绘失败不影响缓存清除。
            }
            result.success("{\"ok\":true}");
            return;
        }
        if ("pinWidget".equals(call.method)) {
            handlePinWidget(call.argument("type"), result);
            return;
        }
        if ("openAppSettings".equals(call.method)) {
            Intent intent = new Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", getPackageName(), null)
            );
            startActivity(intent);
            result.success("{\"ok\":true}");
            return;
        }
        if ("getAiConfig".equals(call.method)) {
            try {
                result.success(AiConfigStore.loadConfig(getApplicationContext()).toString());
            } catch (Exception error) {
                result.error("AI_CONFIG", describe(error), null);
            }
            return;
        }
        if ("saveAiConfig".equals(call.method)) {
            try {
                @SuppressWarnings("unchecked")
                Map<String, Object> values = (Map<String, Object>) call.arguments;
                AiConfigStore.saveConfig(getApplicationContext(), values);
                result.success(AiConfigStore.loadConfig(getApplicationContext()).toString());
            } catch (Exception error) {
                result.error("AI_CONFIG_SAVE", describe(error), null);
            }
            return;
        }
        if ("getAiHistory".equals(call.method)) {
            executor.execute(() -> {
                try {
                    String payload = AiConfigStore.loadHistory(getApplicationContext()).toString();
                    runOnUiThread(() -> result.success(payload));
                } catch (Exception error) {
                    runOnUiThread(() -> result.error("AI_HISTORY", describe(error), null));
                }
            });
            return;
        }
        if ("saveAiHistory".equals(call.method)) {
            String messagesJson = call.argument("messages");
            executor.execute(() -> {
                try {
                    AiConfigStore.saveHistory(getApplicationContext(), messagesJson);
                    runOnUiThread(() -> result.success("{\"ok\":true}"));
                } catch (Exception error) {
                    runOnUiThread(() -> result.error("AI_HISTORY_SAVE", describe(error), null));
                }
            });
            return;
        }
        if ("clearAiHistory".equals(call.method)) {
            AiConfigStore.clearHistory(getApplicationContext());
            result.success("{\"ok\":true}");
            return;
        }
        if ("installUpdate".equals(call.method)) {
            String url = call.argument("url");
            String version = call.argument("version");
            executor.execute(() -> {
                try {
                    result.success(
                            UpdateChecker.downloadAndInstall(this, url, version).toString());
                } catch (Exception error) {
                    result.error("UPDATE_INSTALL", describe(error), null);
                }
            });
            return;
        }
        executor.execute(() -> executePython(call, result));
    }

    private void handlePinWidget(String type, MethodChannel.Result result) {
        Class<?> providerClass;
        if ("week".equals(type)) {
            providerClass = WeekScheduleWidgetProvider.class;
        } else if ("energy".equals(type)) {
            providerClass = EnergyWidgetProvider.class;
        } else {
            providerClass = ScheduleWidgetProvider.class;
        }
        try {
            AppWidgetManager manager = AppWidgetManager.getInstance(this);
            boolean supported = manager != null && manager.isRequestPinAppWidgetSupported();
            boolean requested = false;
            if (supported) {
                PendingIntent callback = PendingIntent.getBroadcast(
                    this,
                    providerClass.hashCode() & 0x7FFF,
                    new Intent(this, providerClass).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE),
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
                );
                requested = manager.requestPinAppWidget(
                    new ComponentName(this, providerClass),
                    null,
                    callback
                );
            }
            JSONObject payload = new JSONObject();
            payload.put("ok", true);
            payload.put("supported", supported);
            payload.put("requested", requested);
            result.success(payload.toString());
        } catch (Exception error) {
            result.error("PIN_WIDGET", describe(error), null);
        }
    }

    /** 把异常整理成能直接展示给用户的一句话。 */
    private static String describe(Exception error) {
        String message = error.getMessage();
        if (message == null || message.isEmpty()) {
            return error.getClass().getSimpleName();
        }
        return message;
    }

    @SuppressWarnings("unchecked")
    private void executePython(MethodCall call, MethodChannel.Result result) {
        try {
            Map<String, Object> args = (Map<String, Object>) call.arguments;
            JSONObject payload;
            switch (call.method) {
                case "beginLogin":
                    pendingAccount = string(args, "account");
                    payload = PythonGateway.call(
                        "begin_login", pendingAccount, string(args, "password"), "ZZU Life Flutter"
                    );
                    payload = saveLoginIfComplete(payload, pendingAccount);
                    break;
                case "completeMfa":
                    payload = PythonGateway.call("complete_mfa", string(args, "code"));
                    payload = saveLoginIfComplete(payload, pendingAccount);
                    break;
                case "getGrades":
                    payload = callSession("get_grades");
                    break;
                case "getTranscriptDocument":
                    payload = callSession("get_transcript_document");
                    break;
                case "getGradeRankDocument":
                    payload = callSession("get_grade_rank_document");
                    break;
                case "getProgramPlan":
                    payload = callSession("get_program_plan");
                    break;
                case "getExams":
                    payload = callSession("get_exams", string(args, "semester_id"));
                    break;
                case "getSchedule":
                    payload = callSession(
                        "get_schedule", number(args, "week"), number(args, "semester_id")
                    );
                    if (payload.optBoolean("ok")
                            && number(args, "week") == 0
                            && number(args, "semester_id") == 0) {
                        try {
                            WidgetSupport.saveScheduleFromApp(getApplicationContext(), payload);
                        } catch (Exception ignored) {
                            // 小组件同步失败不影响前台课表展示。
                        }
                    }
                    break;
                case "cacheSemesterSchedule":
                    payload = callSession("get_semester_schedule");
                    if (payload.optBoolean("ok")) {
                        WidgetSupport.saveSemesterSchedule(getApplicationContext(), payload);
                    }
                    break;
                case "getEnergy":
                    payload = callSession("get_energy");
                    recordEnergySamples(payload);
                    if (payload.optBoolean("ok")) {
                        try {
                            WidgetSupport.saveCache(
                                getApplicationContext(), WidgetSupport.KEY_ENERGY, payload
                            );
                            EnergyWidgetProvider.renderCached(getApplicationContext());
                        } catch (Exception ignored) {
                            // 小组件同步失败不影响前台电量展示。
                        }
                    }
                    break;
                case "getCardBalance":
                    payload = callSession("get_card_balance");
                    break;
                case "getFreeRoomMeta":
                    payload = callSession("get_free_room_meta", number(args, "campus_id"));
                    break;
                case "getFreeRooms":
                    payload = callSession(
                        "get_free_rooms",
                        number(args, "campus_id"),
                        string(args, "building_id"),
                        string(args, "date"),
                        string(args, "units"),
                        number(args, "room_type"),
                        number(args, "min_seats")
                    );
                    break;
                case "rechargeEnergy":
                    payload = callSession(
                        "recharge_energy",
                        string(args, "meter_id"),
                        string(args, "meter_type"),
                        number(args, "amount"),
                        string(args, "payment_password")
                    );
                    break;
                case "getMonitorSettings":
                    payload = MonitorSettings.toJson(this);
                    break;
                case "getEnergySamples":
                    payload = new JSONObject();
                    payload.put("ok", true);
                    payload.put("samples", MonitorSettings.readSamples(this));
                    break;
                case "clearEnergySamples":
                    MonitorSettings.clearEnergySamples(this);
                    payload = new JSONObject();
                    payload.put("ok", true);
                    break;
                case "saveMonitorSettings":
                    MonitorSettings.update(this, args);
                    MonitorScheduler.reschedule(this);
                    payload = MonitorSettings.toJson(this);
                    break;
                case "checkGradesNow":
                    payload = MonitorScheduler.check(this, true, false, false);
                    break;
                case "exportSchedule":
                    payload = callSession("export_schedule_ics");
                    break;
                case "getNetwork":
                    // 校园网用网络账号，不走统一认证，所以这里直接调 Python，不带会话。
                    payload = PythonGateway.call(
                        "get_network",
                        string(args, "account"),
                        string(args, "password"),
                        string(args, "base_url"),
                        string(args, "history")
                    );
                    break;
                default:
                    throw new IllegalArgumentException("未知调用：" + call.method);
            }
            JSONObject output = payload;
            runOnUiThread(() -> result.success(output.toString()));
        } catch (Exception error) {
            runOnUiThread(() -> result.error(
                "NATIVE_API", error.getMessage() == null ? "本地调用失败" : error.getMessage(), null
            ));
        }
    }

    private JSONObject saveLoginIfComplete(JSONObject payload, String account) throws Exception {
        if (payload.optBoolean("ok") && !payload.optBoolean("mfa_required")) {
            String userToken = payload.optString("user_token");
            String refreshToken = payload.optString("refresh_token");
            if (!userToken.isEmpty() && !refreshToken.isEmpty()) {
                SessionStore.save(this, account, userToken, refreshToken);
                payload.remove("user_token");
                payload.remove("refresh_token");
                payload.put("account", account);
            }
        }
        return payload;
    }

    /**
     * 申请通知权限。
     *
     * 只在应用真的检测到新版本时才会被调到（见 requestUpdateNotifyPermission 通道），
     * 因此不会在用户没更新可看的时候弹权限框。已经授权时直接把还没发出去的提醒补上。
     */
    private void requestUpdateNotifyPermission() {
        if (Build.VERSION.SDK_INT < 33
                || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) {
            UpdateChecker.notifyPendingUpdate(this);
            return;
        }
        requestPermissions(
                new String[] {Manifest.permission.POST_NOTIFICATIONS},
                REQUEST_UPDATE_NOTIFY);
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_UPDATE_NOTIFY) {
            // 授权了就把这次「发现新版本」补成一条通知；拒绝了也不打扰。
            UpdateChecker.notifyPendingUpdate(this);
        }
    }

    private JSONObject callSession(String method, Object... args) throws Exception {
        String[] stored = SessionStore.load(this);
        if (stored == null) throw new IllegalStateException("登录已失效，请重新登录");
        return PythonGateway.callWithSession(new PythonGateway.ContextSession(stored), method, args);
    }

    /**
     * 把刚查到的电量记一次采样。
     *
     * 前台查询与后台巡检都走这里，保证「只要查过就有采样」，用户不必为了估算
     * 耗电速度而额外等待后台巡检。
     */
    private void recordEnergySamples(JSONObject payload) {
        if (payload == null || !payload.optBoolean("ok")) return;
        try {
            MonitorSettings.recordEnergySamples(
                this,
                payload.optJSONArray("meter_list"),
                System.currentTimeMillis()
            );
        } catch (Exception ignored) {
            // 采样失败不影响查询结果。
        }
    }

    @SuppressWarnings("unchecked")
    private void startSaveFile(MethodCall call, MethodChannel.Result result) {
        if (pendingSaveResult != null) {
            result.error("SAVE_BUSY", "已有文件正在保存", null);
            return;
        }
        Map<String, Object> args = (Map<String, Object>) call.arguments;
        pendingSaveContent = string(args, "content");
        pendingSaveResult = result;
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("text/calendar")
            .putExtra(Intent.EXTRA_TITLE, string(args, "filename"));
        startActivityForResult(intent, SAVE_FILE_REQUEST);
    }

    @SuppressWarnings("unchecked")
    private void startPrint(MethodCall call, MethodChannel.Result result) {
        try {
            Map<String, Object> args = (Map<String, Object>) call.arguments;
            String name = string(args, "name");
            String mimeType = string(args, "mime_type").toLowerCase();
            byte[] content = Base64.decode(string(args, "content_base64"), Base64.DEFAULT);
            PrintManager manager = (PrintManager) getSystemService(PRINT_SERVICE);
            if (mimeType.contains("pdf")) {
                manager.print(name, new RawPdfPrintAdapter(name, content), null);
                result.success("{\"ok\":true,\"message\":\"已打开打印服务\"}");
                return;
            }
            if (!mimeType.contains("html")) {
                throw new IllegalArgumentException("暂不支持打印此文件格式");
            }
            WebView webView = new WebView(this);
            printingWebView = webView;
            webView.getSettings().setDefaultTextEncodingName("utf-8");
            webView.setWebViewClient(new WebViewClient() {
                private boolean started;

                @Override
                public void onPageFinished(WebView view, String url) {
                    if (started) return;
                    started = true;
                    manager.print(name, view.createPrintDocumentAdapter(name), null);
                    result.success("{\"ok\":true,\"message\":\"已打开打印服务\"}");
                }
            });
            webView.loadData(
                Base64.encodeToString(content, Base64.NO_WRAP),
                "text/html",
                "base64"
            );
        } catch (Exception error) {
            result.error(
                "PRINT",
                error.getMessage() == null ? "无法打开打印服务" : error.getMessage(),
                null
            );
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != SAVE_FILE_REQUEST || pendingSaveResult == null) return;
        MethodChannel.Result callback = pendingSaveResult;
        pendingSaveResult = null;
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            pendingSaveContent = null;
            callback.success("{\"ok\":true,\"cancelled\":true}");
            return;
        }
        String content = pendingSaveContent == null ? "" : pendingSaveContent;
        pendingSaveContent = null;
        executor.execute(() -> {
            try (OutputStream stream = getContentResolver().openOutputStream(data.getData())) {
                if (stream == null) throw new IllegalStateException("无法创建课表文件");
                stream.write(content.getBytes(StandardCharsets.UTF_8));
                stream.flush();
                runOnUiThread(() -> callback.success(
                    "{\"ok\":true,\"message\":\"完整课表已保存\"}"
                ));
            } catch (Exception error) {
                runOnUiThread(() -> callback.error(
                    "SAVE_FILE",
                    error.getMessage() == null ? "保存失败" : error.getMessage(),
                    null
                ));
            }
        });
    }

    private static String string(Map<String, Object> values, String key) {
        Object value = values == null ? null : values.get(key);
        return value == null ? "" : value.toString();
    }

    private static int number(Map<String, Object> values, String key) {
        Object value = values == null ? null : values.get(key);
        return value instanceof Number ? ((Number) value).intValue() : 0;
    }

    @Override
    protected void onDestroy() {
        executor.shutdownNow();
        super.onDestroy();
    }
}
