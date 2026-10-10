package cn.edu.zzu.life;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.Map;

final class MonitorSettings {
    private static final String PREFS = "monitor_settings";
    private static final String ENERGY_ENABLED = "energy_enabled";
    private static final String ENERGY_THRESHOLD = "energy_threshold";
    private static final String GRADE_ENABLED = "grade_enabled";
    private static final String GRADE_INTERVAL = "grade_interval_hours";
    private static final String GRADE_INTERVAL_MINUTES = "grade_interval_minutes";
    private static final String GRADE_SNAPSHOT = "grade_snapshot";
    private static final String LAST_GRADE_CHECK = "last_grade_check";
    private static final String LAST_GRADE_MESSAGE = "last_grade_message";
    private static final String ENERGY_ALERTED = "energy_alerted";

    /** 电量低到一定程度时额外发一封邮件。 */
    private static final String ENERGY_EMAIL_ENABLED = "energy_email_enabled";
    private static final String ENERGY_EMAIL_THRESHOLD = "energy_email_threshold";
    /** 服务端发信接口地址，例如 https://example.vercel.app/api/energy-alert 。 */
    private static final String ENERGY_EMAIL_ENDPOINT = "energy_email_endpoint";
    /** 保护该接口的共享密钥，需要与服务端 ZZU_ALERT_SECRET 一致。 */
    private static final String ENERGY_EMAIL_SECRET = "energy_email_secret";
    private static final String LAST_EMAIL_STATUS = "last_email_status";
    private static final String ENERGY_EMAIL_ALERTED = "energy_email_alerted";

    /** 电量采样历史，用于估算耗电速度。 */
    private static final String ENERGY_SAMPLES = "energy_samples";

    /** 培养方案各类别的学分要求（JSON 数组）。 */
    private static final String PLAN_REQUIREMENTS = "plan_requirements";

    /** 采样保留天数。 */
    private static final int SAMPLE_RETENTION_DAYS = 30;
    /** 采样条数上限，避免 SharedPreferences 无限膨胀。 */
    private static final int SAMPLE_LIMIT = 4000;

    /** 本地通知与邮件共用的默认阈值：2 度。 */
    private static final double DEFAULT_THRESHOLD = 2.0;

    private MonitorSettings() {}

    static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean energyEnabled(Context context) {
        return prefs(context).getBoolean(ENERGY_ENABLED, false);
    }

    static double energyThreshold(Context context) {
        return Double.longBitsToDouble(
            prefs(context).getLong(
                ENERGY_THRESHOLD, Double.doubleToRawLongBits(DEFAULT_THRESHOLD)
            )
        );
    }

    static boolean energyEmailEnabled(Context context) {
        return prefs(context).getBoolean(ENERGY_EMAIL_ENABLED, false);
    }

    static double energyEmailThreshold(Context context) {
        return Double.longBitsToDouble(
            prefs(context).getLong(
                ENERGY_EMAIL_THRESHOLD, Double.doubleToRawLongBits(DEFAULT_THRESHOLD)
            )
        );
    }

    static String energyEmailEndpoint(Context context) {
        return prefs(context).getString(ENERGY_EMAIL_ENDPOINT, "").trim();
    }

    static String energyEmailSecret(Context context) {
        return prefs(context).getString(ENERGY_EMAIL_SECRET, "").trim();
    }

    static boolean energyEmailAlerted(Context context) {
        return prefs(context).getBoolean(ENERGY_EMAIL_ALERTED, false);
    }

    static void setEnergyEmailAlerted(Context context, boolean alerted) {
        prefs(context).edit().putBoolean(ENERGY_EMAIL_ALERTED, alerted).apply();
    }

    static void setLastEmailStatus(Context context, String status) {
        prefs(context).edit().putString(LAST_EMAIL_STATUS, status).apply();
    }

    /**
     * 记录一次电量采样。
     *
     * 采样用于估算耗电速度：只追加、按时间裁剪，不做去重，因为「什么时刻读到
     * 多少度」本身就是拟合需要的原始数据。
     *
     * @param meters 电表列表，每项取 label / meter_id / remaining 三个字段。
     * @return 本次写入的采样条数。
     */
    static synchronized int recordEnergySamples(Context context, JSONArray meters, long now) {
        if (meters == null || meters.length() == 0) return 0;

        JSONArray samples = readSamples(context);
        int written = 0;
        for (int i = 0; i < meters.length(); i++) {
            JSONObject meter = meters.optJSONObject(i);
            if (meter == null || meter.has("error")) continue;
            if (!meter.has("remaining") || meter.isNull("remaining")) continue;
            try {
                JSONObject sample = new JSONObject();
                sample.put("t", now);
                sample.put("id", meter.optString("meter_id", ""));
                sample.put("label", meter.optString("label", "寝室电表"));
                sample.put("q", meter.optDouble("remaining", 0));
                samples.put(sample);
                written++;
            } catch (Exception ignored) {
                // 单条失败不影响其它电表。
            }
        }
        if (written == 0) return 0;

        JSONArray pruned = pruneSamples(samples, now);
        prefs(context).edit().putString(ENERGY_SAMPLES, pruned.toString()).apply();
        return written;
    }

    /** 读取原始采样数组。 */
    static JSONArray readSamples(Context context) {
        String raw = prefs(context).getString(ENERGY_SAMPLES, "");
        if (raw == null || raw.isEmpty()) return new JSONArray();
        try {
            JSONArray parsed = new JSONArray(raw);
            return parsed;
        } catch (Exception ignored) {
            // 数据损坏时重建，不阻塞读取。
            return new JSONArray();
        }
    }

    /** 去掉过期和超出上限的采样，保留最近的。 */
    private static JSONArray pruneSamples(JSONArray samples, long now) {
        long cutoff = now - SAMPLE_RETENTION_DAYS * 86400_000L;
        JSONArray kept = new JSONArray();
        for (int i = 0; i < samples.length(); i++) {
            JSONObject sample = samples.optJSONObject(i);
            if (sample == null || sample.optLong("t", 0L) < cutoff) continue;
            kept.put(sample);
        }
        if (kept.length() <= SAMPLE_LIMIT) return kept;

        // 超出上限时只保留最新的 SAMPLE_LIMIT 条。
        JSONArray trimmed = new JSONArray();
        int start = kept.length() - SAMPLE_LIMIT;
        for (int i = start; i < kept.length(); i++) {
            JSONObject sample = kept.optJSONObject(i);
            if (sample != null) trimmed.put(sample);
        }
        return trimmed;
    }

    static void clearEnergySamples(Context context) {
        prefs(context).edit().remove(ENERGY_SAMPLES).apply();
    }



    static boolean gradeEnabled(Context context) {
        return prefs(context).getBoolean(GRADE_ENABLED, false);
    }

    static int gradeIntervalMinutes(Context context) {
        SharedPreferences values = prefs(context);
        if (values.contains(GRADE_INTERVAL_MINUTES)) {
            return values.getInt(GRADE_INTERVAL_MINUTES, 720);
        }
        return values.getInt(GRADE_INTERVAL, 12) * 60;
    }

    static String gradeSnapshot(Context context) {
        return prefs(context).getString(GRADE_SNAPSHOT, "");
    }

    static void saveGradeSnapshot(Context context, String snapshot) {
        prefs(context).edit().putString(GRADE_SNAPSHOT, snapshot).apply();
    }

    static boolean energyAlerted(Context context) {
        return prefs(context).getBoolean(ENERGY_ALERTED, false);
    }

    static void setEnergyAlerted(Context context, boolean alerted) {
        prefs(context).edit().putBoolean(ENERGY_ALERTED, alerted).apply();
    }

    static void setGradeStatus(Context context, String time, String message) {
        prefs(context).edit()
            .putString(LAST_GRADE_CHECK, time)
            .putString(LAST_GRADE_MESSAGE, message)
            .apply();
    }

    static void update(Context context, Map<String, Object> values) {
        SharedPreferences.Editor editor = prefs(context).edit();
        if (values.containsKey(ENERGY_ENABLED)) {
            editor.putBoolean(ENERGY_ENABLED, bool(values.get(ENERGY_ENABLED)));
        }
        if (values.containsKey(ENERGY_THRESHOLD)) {
            editor.putLong(
                ENERGY_THRESHOLD,
                Double.doubleToRawLongBits(
                    number(values.get(ENERGY_THRESHOLD), DEFAULT_THRESHOLD)
                )
            );
            editor.putBoolean(ENERGY_ALERTED, false);
        }
        if (values.containsKey(ENERGY_EMAIL_ENABLED)) {
            editor.putBoolean(
                ENERGY_EMAIL_ENABLED, bool(values.get(ENERGY_EMAIL_ENABLED))
            );
        }
        if (values.containsKey(ENERGY_EMAIL_THRESHOLD)) {
            editor.putLong(
                ENERGY_EMAIL_THRESHOLD,
                Double.doubleToRawLongBits(
                    number(values.get(ENERGY_EMAIL_THRESHOLD), DEFAULT_THRESHOLD)
                )
            );
            // 阈值变了就重新武装，否则改了阈值也不会再提醒。
            editor.putBoolean(ENERGY_EMAIL_ALERTED, false);
        }
        if (values.containsKey(ENERGY_EMAIL_ENDPOINT)) {
            editor.putString(
                ENERGY_EMAIL_ENDPOINT, string(values.get(ENERGY_EMAIL_ENDPOINT))
            );
            editor.putBoolean(ENERGY_EMAIL_ALERTED, false);
        }
        if (values.containsKey(ENERGY_EMAIL_SECRET)) {
            editor.putString(
                ENERGY_EMAIL_SECRET, string(values.get(ENERGY_EMAIL_SECRET))
            );
            editor.putBoolean(ENERGY_EMAIL_ALERTED, false);
        }
        if (values.containsKey(GRADE_ENABLED)) {
            editor.putBoolean(GRADE_ENABLED, bool(values.get(GRADE_ENABLED)));
        }
        if (values.containsKey(GRADE_INTERVAL)) {
            int hours = (int) number(values.get(GRADE_INTERVAL), 12);
            editor.putInt(GRADE_INTERVAL, Math.max(1, Math.min(168, hours)));
        }
        if (values.containsKey(GRADE_INTERVAL_MINUTES)) {
            int minutes = (int) number(values.get(GRADE_INTERVAL_MINUTES), 720);
            editor.putInt(GRADE_INTERVAL_MINUTES, Math.max(15, Math.min(10080, minutes)));
        }
        editor.apply();
    }

    static JSONObject toJson(Context context) throws Exception {
        SharedPreferences values = prefs(context);
        JSONObject result = new JSONObject();
        result.put("ok", true);
        result.put(ENERGY_ENABLED, energyEnabled(context));
        result.put(ENERGY_THRESHOLD, energyThreshold(context));
        result.put(ENERGY_EMAIL_ENABLED, energyEmailEnabled(context));
        result.put(ENERGY_EMAIL_THRESHOLD, energyEmailThreshold(context));
        result.put(ENERGY_EMAIL_ENDPOINT, energyEmailEndpoint(context));
        // 密钥只回传是否已配置，不回传明文。
        result.put("energy_email_secret_set", !energyEmailSecret(context).isEmpty());
        result.put("last_email_status", values.getString(LAST_EMAIL_STATUS, "尚未发信"));
        result.put("energy_sample_count", readSamples(context).length());
        result.put(GRADE_ENABLED, gradeEnabled(context));
        result.put(GRADE_INTERVAL, Math.max(1, gradeIntervalMinutes(context) / 60));
        result.put(GRADE_INTERVAL_MINUTES, gradeIntervalMinutes(context));
        result.put("last_grade_check", values.getString(LAST_GRADE_CHECK, ""));
        result.put("last_grade_message", values.getString(LAST_GRADE_MESSAGE, "尚未检查"));
        return result;
    }

    private static boolean bool(Object value) {
        return value instanceof Boolean ? (Boolean) value : Boolean.parseBoolean(String.valueOf(value));
    }

    private static String string(Object value) {
        return value == null ? "" : String.valueOf(value).trim();
    }

    private static double number(Object value, double fallback) {
        if (value instanceof Number) return ((Number) value).doubleValue();
        try {
            return Double.parseDouble(String.valueOf(value));
        } catch (Exception ignored) {
            return fallback;
        }
    }
}
