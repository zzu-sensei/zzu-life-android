package cn.edu.zzu.life;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

final class MonitorScheduler {
    private static final String CHANNEL_ID = "zzu_life_monitoring";
    private static final int ALARM_REQUEST = 8102;
    private static final long MIN_INTERVAL = 15L * 60L * 1000L;

    private MonitorScheduler() {}

    /**
     * 重新安排下一次巡检。
     *
     * 这里用「单次精确闹钟 + 每次触发后再排下一次」而不是
     * {@code setInexactRepeating}：后者在 Doze 下会被推迟很久，而且每次间隔是
     * 固定的，无法随设置变化。精确闹钟能唤醒休眠中的设备，更接近用户预期的
     * 「低电量就提醒」。
     */
    static void reschedule(Context context) {
        AlarmManager alarm = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        PendingIntent intent = alarmIntent(context);
        alarm.cancel(intent);
        if (!MonitorSettings.energyEnabled(context) && !MonitorSettings.gradeEnabled(context)) {
            return;
        }
        scheduleNext(alarm, intent, intervalMillis(context));
    }

    /** 巡检间隔：取成绩与电量里更短的那个，电量固定不超过 6 小时。 */
    private static long intervalMillis(Context context) {
        long minutes = MonitorSettings.gradeEnabled(context)
            ? MonitorSettings.gradeIntervalMinutes(context)
            : 24 * 60L;
        if (MonitorSettings.energyEnabled(context)) minutes = Math.min(minutes, 6 * 60L);
        return Math.max(MIN_INTERVAL, minutes * 60L * 1000L);
    }

    private static void scheduleNext(
        AlarmManager alarm, PendingIntent intent, long interval
    ) {
        // 首次检查放在 5 分钟内，之后按设定间隔。
        long triggerAt = System.currentTimeMillis() + Math.min(interval, 5 * 60L * 1000L);
        boolean exact = canScheduleExactAlarms(alarm);
        try {
            if (exact) {
                alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, intent);
            } else {
                // 没有精确闹钟权限时退回允许空闲窗口的非精确闹钟，仍然明显优于
                // 完全不设置的重复闹钟。
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, intent);
            }
        } catch (SecurityException ignored) {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, intent);
        }
    }

    private static boolean canScheduleExactAlarms(AlarmManager alarm) {
        return Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms();
    }

    /** 一次巡检结束后安排下一次，保证链式调度不断掉。 */
    static void scheduleAfterRun(Context context) {
        AlarmManager alarm = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (!MonitorSettings.energyEnabled(context) && !MonitorSettings.gradeEnabled(context)) {
            return;
        }
        scheduleNext(alarm, alarmIntent(context), intervalMillis(context));
    }

    static JSONObject check(Context context, boolean grades, boolean energy, boolean notify) {
        JSONObject result = new JSONObject();
        try {
            result.put("ok", true);
            String[] stored = SessionStore.load(context);
            if (stored == null) {
                result.put("message", "登录已失效，请打开应用重新登录");
                return result;
            }
            PythonGateway.ContextSession session = new PythonGateway.ContextSession(stored);
            if (grades) checkGrades(context, session, notify, result);
            if (energy) checkEnergy(context, session, notify, result);
            if (!result.has("message")) result.put("message", "检查完成");
        } catch (Exception error) {
            try {
                result.put("ok", true);
                result.put("message", error.getMessage() == null ? "检查失败" : error.getMessage());
            } catch (Exception ignored) {}
        } finally {
            // 单次闹钟不会自动重复，必须在这里接上下一环，否则巡检只跑一次。
            scheduleAfterRun(context);
        }
        return result;
    }

    private static void checkGrades(
        Context context,
        PythonGateway.ContextSession session,
        boolean notify,
        JSONObject output
    ) throws Exception {
        JSONObject payload = PythonGateway.callWithSession(session, "get_grades");
        if (!payload.optBoolean("ok")) throw new IllegalStateException(payload.optString("error", "成绩查询失败"));
        JSONArray grades = payload.optJSONArray("grades");
        if (grades == null) grades = new JSONArray();
        JSONObject current = new JSONObject();
        for (int i = 0; i < grades.length(); i++) {
            JSONObject item = grades.optJSONObject(i);
            if (item == null) continue;
            String key = item.optString("semester") + "\u0001" + item.optString("course");
            String value = item.optString("score") + "\u0001" + item.optString("gp");
            current.put(key, value);
        }

        String previousRaw = MonitorSettings.gradeSnapshot(context);
        int changed = 0;
        if (!previousRaw.isEmpty()) {
            JSONObject previous = new JSONObject(previousRaw);
            JSONArray keys = current.names();
            if (keys != null) {
                for (int i = 0; i < keys.length(); i++) {
                    String key = keys.getString(i);
                    if (!previous.has(key) || !current.optString(key).equals(previous.optString(key))) changed++;
                }
            }
        }
        MonitorSettings.saveGradeSnapshot(context, current.toString());
        String now = new SimpleDateFormat("MM-dd HH:mm", Locale.CHINA).format(new Date());
        String message;
        if (previousRaw.isEmpty()) {
            message = "已建立监测基准，共 " + current.length() + " 门课程";
        } else if (changed > 0) {
            message = "发现 " + changed + " 门课程成绩更新";
            if (notify) notify(context, 2101, "成绩有更新", message);
        } else {
            message = "暂未发现新成绩";
        }
        MonitorSettings.setGradeStatus(context, now, message);
        output.put("new_grades", changed);
        output.put("message", message);
    }

    private static void checkEnergy(
        Context context,
        PythonGateway.ContextSession session,
        boolean notify,
        JSONObject output
    ) throws Exception {
        JSONObject payload = PythonGateway.callWithSession(session, "get_energy");
        if (!payload.optBoolean("ok")) throw new IllegalStateException(payload.optString("error", "电量查询失败"));
        JSONArray meters = payload.optJSONArray("meter_list");
        if (meters == null) return;
        String room = payload.optString("room", "");
        double threshold = MonitorSettings.energyThreshold(context);
        String lowLabel = "";
        double lowest = Double.MAX_VALUE;
        for (int i = 0; i < meters.length(); i++) {
            JSONObject meter = meters.optJSONObject(i);
            if (meter == null || meter.has("error")) continue;
            double remaining = meter.optDouble("remaining", Double.NaN);
            if (!Double.isNaN(remaining) && remaining <= threshold && remaining < lowest) {
                lowest = remaining;
                lowLabel = meter.optString("label", "寝室电表");
            }
        }
        boolean low = !lowLabel.isEmpty();
        if (low && !MonitorSettings.energyAlerted(context)) {
            if (notify) {
                notify(
                    context,
                    2102,
                    "寝室电量偏低",
                    lowLabel + "剩余 " + String.format(Locale.CHINA, "%.2f", lowest) + " 度"
                );
            }
            MonitorSettings.setEnergyAlerted(context, true);
        } else if (!low) {
            MonitorSettings.setEnergyAlerted(context, false);
        }
        output.put("energy_low", low);

        // 记录采样，供客户端估算耗电速度。
        try {
            MonitorSettings.recordEnergySamples(
                context, meters, System.currentTimeMillis()
            );
        } catch (Exception ignored) {
            // 采样失败不影响提醒逻辑。
        }

        sendEnergyEmailIfNeeded(context, meters, room, output);
    }

    /**
     * 电量低于邮件阈值时调用服务端发信接口。
     *
     * 发信需要邮箱服务商的 API Key，而把 Key 放进手机既不安全也难轮换，因此
     * 手机只把读数上报给服务端，由服务端完成发信。是否已经提醒过由本地标记
     * 去重，服务端另有自己的去重状态。
     *
     * @throws Exception 写入结果 JSON 失败（org.json 的 put 会抛受检异常）。
     */
    private static void sendEnergyEmailIfNeeded(
        Context context,
        JSONArray meters,
        String room,
        JSONObject output
    ) throws Exception {
        if (!MonitorSettings.energyEmailEnabled(context)) return;

        double threshold = MonitorSettings.energyEmailThreshold(context);
        String lowLabel = "";
        double lowest = Double.MAX_VALUE;
        for (int i = 0; i < meters.length(); i++) {
            JSONObject meter = meters.optJSONObject(i);
            if (meter == null || meter.has("error")) continue;
            double remaining = meter.optDouble("remaining", Double.NaN);
            if (!Double.isNaN(remaining) && remaining <= threshold && remaining < lowest) {
                lowest = remaining;
                lowLabel = meter.optString("label", "寝室电表");
            }
        }

        boolean low = !lowLabel.isEmpty();
        if (!low) {
            // 电量回升后重新武装，下次再低还会发信。
            MonitorSettings.setEnergyEmailAlerted(context, false);
            output.put("email_sent", false);
            return;
        }
        if (MonitorSettings.energyEmailAlerted(context)) {
            output.put("email_sent", false);
            output.put("email_skipped", "已提醒过且尚未恢复供电");
            return;
        }

        String endpoint = MonitorSettings.energyEmailEndpoint(context);
        String secret = MonitorSettings.energyEmailSecret(context);
        if (endpoint.isEmpty() || secret.isEmpty()) {
            MonitorSettings.setLastEmailStatus(context, "未配置发信接口或密钥");
            output.put("email_sent", false);
            output.put("email_error", "未配置发信接口或密钥");
            return;
        }

        try {
            String response = postEnergyAlert(endpoint, secret, meters, room, threshold);
            MonitorSettings.setEnergyEmailAlerted(context, true);
            MonitorSettings.setLastEmailStatus(
                context, new SimpleDateFormat("MM-dd HH:mm", Locale.CHINA).format(new Date()) + " 已请求发信"
            );
            output.put("email_sent", true);
            output.put("email_response", response);
        } catch (Exception error) {
            String message = error.getMessage() == null ? "发信请求失败" : error.getMessage();
            // 失败时不写入已提醒标记，下次巡检会重试。
            MonitorSettings.setLastEmailStatus(context, "发信失败：" + message);
            output.put("email_sent", false);
            output.put("email_error", message);
        }
    }

    /** 用 HttpURLConnection 上报读数；不引入额外依赖，也不需要读取响应体。 */
    private static String postEnergyAlert(
        String endpoint,
        String secret,
        JSONArray meters,
        String room,
        double threshold
    ) throws Exception {
        JSONObject body = new JSONObject();
        JSONArray payloadMeters = new JSONArray();
        for (int i = 0; i < meters.length(); i++) {
            JSONObject meter = meters.optJSONObject(i);
            if (meter == null) continue;
            JSONObject item = new JSONObject();
            item.put("label", meter.optString("label", "寝室电表"));
            item.put("meter_id", meter.optString("meter_id", ""));
            if (meter.has("error") && !meter.isNull("error")) {
                item.put("error", meter.optString("error"));
            } else {
                item.put("remaining", meter.optDouble("remaining", 0));
            }
            payloadMeters.put(item);
        }
        body.put("meters", payloadMeters);
        body.put("room", room);
        body.put("threshold", threshold);

        HttpURLConnection connection = (HttpURLConnection) new URL(endpoint).openConnection();
        try {
            connection.setRequestMethod("POST");
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(15000);
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            connection.setRequestProperty("X-ZZU-Alert-Secret", secret);
            byte[] payload = body.toString().getBytes(StandardCharsets.UTF_8);
            connection.setFixedLengthStreamingMode(payload.length);
            try (OutputStream stream = connection.getOutputStream()) {
                stream.write(payload);
            }
            int code = connection.getResponseCode();
            if (code < 200 || code >= 300) {
                throw new IllegalStateException("服务端返回 " + code);
            }
            return "HTTP " + code;
        } finally {
            connection.disconnect();
        }
    }

    private static void notify(Context context, int id, String title, String text) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
            return;
        }
        NotificationManager manager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        NotificationChannel channel = new NotificationChannel(
            CHANNEL_ID,
            "成绩与电量提醒",
            NotificationManager.IMPORTANCE_DEFAULT
        );
        manager.createNotificationChannel(channel);
        Intent open = new Intent(context, MainActivity.class);
        PendingIntent content = PendingIntent.getActivity(
            context,
            id,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        Notification notification = new Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher_v6)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(content)
            .setAutoCancel(true)
            .build();
        manager.notify(id, notification);
    }

    private static PendingIntent alarmIntent(Context context) {
        return PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST,
            new Intent(context, MonitorReceiver.class),
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }
}
