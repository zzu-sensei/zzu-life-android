package cn.edu.zzu.life;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.print.PrintManager;
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
        executor.execute(() -> executePython(call, result));
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
                case "getSchedule":
                    payload = callSession(
                        "get_schedule", number(args, "week"), number(args, "semester_id")
                    );
                    break;
                case "getEnergy":
                    payload = callSession("get_energy");
                    recordEnergySamples(payload);
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
