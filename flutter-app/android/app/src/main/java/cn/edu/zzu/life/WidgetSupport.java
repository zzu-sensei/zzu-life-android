package cn.edu.zzu.life;

import android.appwidget.AppWidgetManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.util.DisplayMetrics;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.text.DecimalFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 桌面小组件共用的主题色板、离线缓存、异步执行器与绘制工具。
 *
 * 所有数值、圆角与课程调色板均与 Flutter 端 M3 × Miuix 设计系统保持一致。
 */
final class WidgetSupport {
    private static final String CACHE_PREFS = "widget_cache";
    private static final String SEMESTER_CACHE_FILE = "semester_schedule_cache.json";
    static final String KEY_ENERGY = "energy";
    static final String KEY_TODAY = "today";
    static final String KEY_WEEK = "week";

    static final String[] DAYS = {"", "一", "二", "三", "四", "五", "六", "日"};

    /** 与 flutter-app/lib/core/course_palette.dart 完全一致的 20 组种子色。 */
    private static final int[] COURSE_SEEDS = {
        0xFF3482FF, // HyperOS Blue
        0xFF14A38B, // Teal
        0xFFE5646B, // Coral
        0xFFD98A1C, // Amber
        0xFF5D6FE8, // Indigo
        0xFF935EE2, // Violet
        0xFF1AA35E, // Emerald
        0xFFD95B96, // Rose
        0xFFE06D3B, // Terracotta
        0xFF0E94C4, // Cyan
        0xFF6B9C32, // Olive
        0xFFAF5A82, // Plum
        0xFF4267D6, // Cobalt
        0xFFB88322, // Ochre
        0xFF288FA8, // Cerulean
        0xFF7B61C9, // Iris
        0xFF279976, // Jade
        0xFFCC4F73, // Berry
        0xFF608C4B, // Moss
        0xFFBD584D, // Rust
    };

    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    private WidgetSupport() {}

    static void runAsync(Runnable task) {
        EXECUTOR.execute(task);
    }

    static boolean isDark(Context context) {
        String mode = MonitorSettings.themeMode(context);
        if ("dark".equals(mode)) return true;
        if ("light".equals(mode)) return false;
        int night = context.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
        return night == Configuration.UI_MODE_NIGHT_YES;
    }

    static Palette palette(Context context) {
        return new Palette(isDark(context));
    }

    static final class Palette {
        final boolean dark;
        final int bgRes;
        final int pillRes;
        final int badgeBlueRes;
        final int badgeWarnRes;
        final int tileRes;
        final int tileWarnRes;

        final int ink;
        final int inkSecondary;
        final int inkMuted;
        final int primary;
        final int primarySoft;
        final int success;
        final int warning;
        final int danger;
        final int divider;
        final int cardFill;
        final int cardBorder;
        final int todayColBg;

        Palette(boolean dark) {
            this.dark = dark;
            if (dark) {
                this.bgRes = R.drawable.widget_bg_dark;
                this.pillRes = R.drawable.widget_pill_dark;
                this.badgeBlueRes = R.drawable.widget_badge_blue_dark;
                this.badgeWarnRes = R.drawable.widget_badge_warn_dark;
                this.tileRes = R.drawable.widget_tile_dark;
                this.tileWarnRes = R.drawable.widget_tile_warn_dark;

                this.ink = 0xFFF3F5F8;
                this.inkSecondary = 0xFFA5AEBC;
                this.inkMuted = 0xFF6E7785;
                this.primary = 0xFF4D96FF;
                this.primarySoft = 0xFF1D2E4D;
                this.success = 0xFF36C275;
                this.warning = 0xFFF5B041;
                this.danger = 0xFFFF6B6B;
                this.divider = 0xFF282D36;
                this.cardFill = 0xFF1F232B;
                this.cardBorder = 0xFF2B303A;
                this.todayColBg = 0x1A4D96FF;
            } else {
                this.bgRes = R.drawable.widget_bg_light;
                this.pillRes = R.drawable.widget_pill_light;
                this.badgeBlueRes = R.drawable.widget_badge_blue_light;
                this.badgeWarnRes = R.drawable.widget_badge_warn_light;
                this.tileRes = R.drawable.widget_tile_light;
                this.tileWarnRes = R.drawable.widget_tile_warn_light;

                this.ink = 0xFF14181F;
                this.inkSecondary = 0xFF555E6B;
                this.inkMuted = 0xFF8A94A3;
                this.primary = 0xFF3482FF;
                this.primarySoft = 0xFFEBF3FF;
                this.success = 0xFF1AA35E;
                this.warning = 0xFFD98A1C;
                this.danger = 0xFFE5484D;
                this.divider = 0xFFE8ECF2;
                this.cardFill = 0xFFF5F7FA;
                this.cardBorder = 0xFFE6EAF0;
                this.todayColBg = 0x103482FF;
            }
        }
    }

    static final class CourseStyle {
        final int background;
        final int border;
        final int accent;
        final int title;
        final int subtitle;

        CourseStyle(int background, int border, int accent, int title, int subtitle) {
            this.background = background;
            this.border = border;
            this.accent = accent;
            this.title = title;
            this.subtitle = subtitle;
        }
    }

    static int courseHash(String course) {
        int value = 0x811C9DC5;
        for (int index = 0; index < course.length(); index++) {
            value = ((value ^ course.charAt(index)) * 0x01000193) & 0x7FFFFFFF;
        }
        return value;
    }

    static Map<String, CourseStyle> assignCourseStyles(JSONArray lessons, boolean dark) {
        Map<String, CourseStyle> styles = new HashMap<>();
        if (lessons == null || lessons.length() == 0) return styles;
        Set<String> uniqueSet = new HashSet<>();
        for (int index = 0; index < lessons.length(); index++) {
            JSONObject lesson = lessons.optJSONObject(index);
            if (lesson == null) continue;
            uniqueSet.add(lesson.optString("course", "未知课程"));
        }
        List<String> unique = new ArrayList<>(uniqueSet);
        Collections.sort(unique);

        Set<Integer> used = new HashSet<>();
        for (String name : unique) {
            int colorIndex = courseHash(name) % COURSE_SEEDS.length;
            while (used.contains(colorIndex) && used.size() < COURSE_SEEDS.length) {
                colorIndex = (colorIndex + 1) % COURSE_SEEDS.length;
            }
            used.add(colorIndex);
            styles.put(name, courseStyleForSeed(COURSE_SEEDS[colorIndex], dark));
        }
        return styles;
    }

    private static CourseStyle courseStyleForSeed(int seed, boolean dark) {
        if (dark) {
            int accent = withLightness(seed, 0.68f);
            int background = alphaBlend(withAlpha(seed, 0.24f), 0xFF16181D);
            int border = withAlpha(accent, 0.36f);
            return new CourseStyle(background, border, accent, 0xFFF3F6FA, 0xFFB9C4D4);
        }
        int titleColor = withLightness(seed, 0.24f);
        int subtitleColor = withLightness(seed, 0.36f);
        int background = alphaBlend(withAlpha(seed, 0.14f), 0xFFFFFFFF);
        int border = withAlpha(seed, 0.28f);
        return new CourseStyle(background, border, seed, titleColor, subtitleColor);
    }

    static int withAlpha(int color, float alphaRatio) {
        int a = clamp(Math.round(clampF(alphaRatio, 0f, 1f) * 255f), 0, 255);
        return (a << 24) | (color & 0x00FFFFFF);
    }

    private static int alphaBlend(int fgWithAlpha, int bgOpaque) {
        int alpha = Color.alpha(fgWithAlpha);
        int invAlpha = 255 - alpha;
        int r = (Color.red(fgWithAlpha) * alpha + Color.red(bgOpaque) * invAlpha) / 255;
        int g = (Color.green(fgWithAlpha) * alpha + Color.green(bgOpaque) * invAlpha) / 255;
        int b = (Color.blue(fgWithAlpha) * alpha + Color.blue(bgOpaque) * invAlpha) / 255;
        return Color.rgb(r, g, b);
    }

    private static int withLightness(int color, float targetL) {
        float r = Color.red(color) / 255f;
        float g = Color.green(color) / 255f;
        float b = Color.blue(color) / 255f;
        float max = Math.max(r, Math.max(g, b));
        float min = Math.min(r, Math.min(g, b));
        float d = max - min;
        float h = 0f;
        float l = (max + min) / 2f;
        float s = 0f;
        if (d > 1e-6f) {
            s = l > 0.5f ? d / (2f - max - min) : d / (max + min);
            if (max == r) {
                h = (g - b) / d + (g < b ? 6f : 0f);
            } else if (max == g) {
                h = (b - r) / d + 2f;
            } else {
                h = (r - g) / d + 4f;
            }
            h /= 6f;
        }
        return hslToRgb(h, s, clampF(targetL, 0f, 1f));
    }

    private static int hslToRgb(float h, float s, float l) {
        if (s <= 1e-6f) {
            int v = clamp(Math.round(l * 255f), 0, 255);
            return Color.rgb(v, v, v);
        }
        float q = l < 0.5f ? l * (1f + s) : l + s - l * s;
        float p = 2f * l - q;
        int r = clamp(Math.round(hueToRgb(p, q, h + 1f / 3f) * 255f), 0, 255);
        int g = clamp(Math.round(hueToRgb(p, q, h) * 255f), 0, 255);
        int b = clamp(Math.round(hueToRgb(p, q, h - 1f / 3f) * 255f), 0, 255);
        return Color.rgb(r, g, b);
    }

    private static float hueToRgb(float p, float q, float t) {
        float x = t;
        if (x < 0f) x += 1f;
        if (x > 1f) x -= 1f;
        if (x < 1f / 6f) return p + (q - p) * 6f * x;
        if (x < 0.5f) return q;
        if (x < 2f / 3f) return p + (q - p) * (2f / 3f - x) * 6f;
        return p;
    }

    // ---------- Cache Management ----------

    static final class CachedData {
        final JSONObject payload;
        final long updatedAt;
        final String date;

        CachedData(JSONObject payload, long updatedAt, String date) {
            this.payload = payload;
            this.updatedAt = updatedAt;
            this.date = date;
        }
    }

    private static SharedPreferences cachePrefs(Context context) {
        return context.getSharedPreferences(CACHE_PREFS, Context.MODE_PRIVATE);
    }

    static void saveCache(Context context, String key, JSONObject payload) {
        if (payload == null) return;
        cachePrefs(context).edit()
            .putString(key + "_json", payload.toString())
            .putLong(key + "_time", System.currentTimeMillis())
            .putString(key + "_date", todayIso())
            .apply();
    }

    static CachedData loadCache(Context context, String key) {
        SharedPreferences prefs = cachePrefs(context);
        String raw = prefs.getString(key + "_json", "");
        if (raw == null || raw.isEmpty()) return null;
        try {
            JSONObject obj = new JSONObject(raw);
            long time = prefs.getLong(key + "_time", 0L);
            String date = prefs.getString(key + "_date", "");
            return new CachedData(obj, time, date == null ? "" : date);
        } catch (Exception ignored) {
            return null;
        }
    }

    static void clearCache(Context context) {
        cachePrefs(context).edit().clear().apply();
        clearSemesterSchedule(context);
    }

    static synchronized void saveSemesterSchedule(Context context, JSONObject payload) {
        if (payload == null || !payload.optBoolean("ok")) return;
        try {
            payload.put("cached_at", System.currentTimeMillis());
            File file = new File(context.getFilesDir(), SEMESTER_CACHE_FILE);
            try (FileOutputStream out = new FileOutputStream(file)) {
                out.write(payload.toString().getBytes(StandardCharsets.UTF_8));
                out.flush();
            }
            ScheduleWidgetProvider.renderCached(context);
            WeekScheduleWidgetProvider.renderCached(context);
        } catch (Exception ignored) {
            // 持久化整学期课表失败不影响本次前台返回。
        }
    }

    static synchronized JSONObject loadSemesterSchedule(Context context) {
        File file = new File(context.getFilesDir(), SEMESTER_CACHE_FILE);
        if (!file.exists()) return null;
        try (FileInputStream in = new FileInputStream(file)) {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            byte[] chunk = new byte[8192];
            int n;
            while ((n = in.read(chunk)) != -1) {
                buffer.write(chunk, 0, n);
            }
            String raw = new String(buffer.toByteArray(), StandardCharsets.UTF_8);
            if (raw.isEmpty()) return null;
            return new JSONObject(raw);
        } catch (Exception ignored) {
            return null;
        }
    }

    static synchronized void clearSemesterSchedule(Context context) {
        File file = new File(context.getFilesDir(), SEMESTER_CACHE_FILE);
        if (file.exists()) {
            //noinspection ResultOfMethodCallIgnored
            file.delete();
        }
    }

    static int resolveWeekFromSemester(JSONObject semester) {
        if (semester == null) return 1;
        String startDate = semester.optString("start_date", "").trim();
        if (startDate.length() >= 10) {
            try {
                int y = Integer.parseInt(startDate.substring(0, 4));
                int m = Integer.parseInt(startDate.substring(5, 7));
                int d = Integer.parseInt(startDate.substring(8, 10));
                Calendar startCal = Calendar.getInstance();
                startCal.set(y, m - 1, d, 0, 0, 0);
                startCal.set(Calendar.MILLISECOND, 0);

                Calendar todayCal = Calendar.getInstance();
                todayCal.set(Calendar.HOUR_OF_DAY, 0);
                todayCal.set(Calendar.MINUTE, 0);
                todayCal.set(Calendar.SECOND, 0);
                todayCal.set(Calendar.MILLISECOND, 0);

                long diffDays = Math.round(
                    (todayCal.getTimeInMillis() - startCal.getTimeInMillis()) / 86400000.0
                );
                int week = (int) Math.floor(diffDays / 7.0) + 1;
                return Math.max(1, week);
            } catch (Exception ignored) {
                // 开学日期不可用时回退到服务端当时返回的周次。
            }
        }
        return Math.max(1, semester.optInt("current_week", 1));
    }

    static CachedData buildWeekFromSemesterCache(Context context) {
        JSONObject sem = loadSemesterSchedule(context);
        if (sem == null) return null;
        int week = resolveWeekFromSemester(sem);
        JSONObject weeks = sem.optJSONObject("weeks");
        JSONArray weekLessons = weeks == null ? null : weeks.optJSONArray(String.valueOf(week));
        if (weekLessons == null) weekLessons = new JSONArray();
        try {
            JSONObject payload = new JSONObject();
            payload.put("ok", true);
            payload.put("week", week);
            payload.put("lessons", weekLessons);
            payload.put("from_semester_cache", true);
            return new CachedData(payload, sem.optLong("cached_at", 0L), todayIso());
        } catch (Exception ignored) {
            return null;
        }
    }

    static CachedData buildTodayFromSemesterCache(Context context) {
        CachedData weekCached = buildWeekFromSemesterCache(context);
        if (weekCached == null) return null;
        try {
            JSONArray all = weekCached.payload.optJSONArray("lessons");
            JSONArray todayLessons = new JSONArray();
            int weekday = todayWeekday();
            if (all != null) {
                for (int i = 0; i < all.length(); i++) {
                    JSONObject lesson = all.optJSONObject(i);
                    if (lesson != null && lesson.optInt("weekday", 0) == weekday) {
                        todayLessons.put(lesson);
                    }
                }
            }
            JSONObject payload = new JSONObject();
            payload.put("ok", true);
            payload.put("week", weekCached.payload.optInt("week", 0));
            payload.put("lessons", todayLessons);
            payload.put("from_semester_cache", true);
            return new CachedData(payload, weekCached.updatedAt, todayIso());
        } catch (Exception ignored) {
            return null;
        }
    }

    static void saveScheduleFromApp(Context context, JSONObject weekPayload) {
        if (weekPayload == null || !weekPayload.optBoolean("ok")) return;
        saveCache(context, KEY_WEEK, weekPayload);
        try {
            JSONArray all = weekPayload.optJSONArray("lessons");
            JSONArray todayLessons = new JSONArray();
            int weekday = todayWeekday();
            if (all != null) {
                for (int i = 0; i < all.length(); i++) {
                    JSONObject lesson = all.optJSONObject(i);
                    if (lesson != null && lesson.optInt("weekday", 0) == weekday) {
                        todayLessons.put(lesson);
                    }
                }
            }
            JSONObject todayPayload = new JSONObject();
            todayPayload.put("ok", true);
            todayPayload.put("week", weekPayload.optInt("week", 0));
            todayPayload.put("lessons", todayLessons);
            saveCache(context, KEY_TODAY, todayPayload);
        } catch (Exception ignored) {
            // 派生今日课表失败不影响整周课表保存。
        }
        ScheduleWidgetProvider.renderCached(context);
        WeekScheduleWidgetProvider.renderCached(context);
    }

    static void refreshAllFromCache(Context context) {
        EnergyWidgetProvider.renderCached(context);
        ScheduleWidgetProvider.renderCached(context);
        WeekScheduleWidgetProvider.renderCached(context);
    }

    // ---------- Date / Time / Text / Bitmap Helpers ----------

    static String todayIso() {
        return new SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).format(new Date());
    }

    static String todayShortDate() {
        return new SimpleDateFormat("M月d日", Locale.CHINA).format(new Date());
    }

    /** 1 = 周一 ... 7 = 周日 */
    static int todayWeekday() {
        int dow = Calendar.getInstance().get(Calendar.DAY_OF_WEEK);
        return dow == Calendar.SUNDAY ? 7 : (dow - Calendar.MONDAY + 1);
    }

    static String formatTime(long millis) {
        if (millis <= 0L) return "--:--";
        return new SimpleDateFormat("HH:mm", Locale.CHINA).format(new Date(millis));
    }

    static int nowMinutes() {
        Calendar cal = Calendar.getInstance();
        return cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE);
    }

    static int parseClockMinutes(String hhmm) {
        if (hhmm == null) return -1;
        String trimmed = hhmm.trim();
        int colon = trimmed.indexOf(':');
        if (colon <= 0 || colon >= trimmed.length() - 1) return -1;
        try {
            int h = Integer.parseInt(trimmed.substring(0, colon));
            int m = Integer.parseInt(trimmed.substring(colon + 1));
            if (h < 0 || h > 23 || m < 0 || m > 59) return -1;
            return h * 60 + m;
        } catch (NumberFormatException ignored) {
            return -1;
        }
    }

    static String formatThreshold(double value) {
        DecimalFormat fmt = new DecimalFormat("0.##");
        return fmt.format(value);
    }

    static String safe(String value) {
        return value == null || value.isEmpty() ? "未知错误" : value;
    }

    static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static float clampF(float value, float min, float max) {
        return Math.max(min, Math.min(max, value));
    }

    static int[] bitmapSize(
        Context context,
        Bundle options,
        int defaultW,
        int defaultH,
        int headerReserveDp,
        int maxW,
        int maxH
    ) {
        int minW = options == null ? defaultW : Math.max(defaultW, options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, defaultW));
        int minH = options == null ? defaultH : Math.max(defaultH, options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, defaultH));
        int innerW = Math.max(120, minW - 28);
        int innerH = Math.max(100, minH - headerReserveDp);
        DisplayMetrics metrics = context.getResources().getDisplayMetrics();
        float scale = Math.min(2.5f, Math.max(2.0f, metrics.density));
        int bw = clamp(Math.round(innerW * scale), 440, maxW);
        int bh = clamp(Math.round(innerH * scale), 220, maxH);
        return new int[] {bw, bh};
    }

    static void drawTextCentered(Canvas canvas, String text, float x, float y, Paint paint) {
        Paint.FontMetrics metrics = paint.getFontMetrics();
        canvas.drawText(text, x, y - (metrics.ascent + metrics.descent) / 2f, paint);
    }

    static String ellipsize(String text, Paint paint, float maxWidth) {
        if (text == null || maxWidth <= 0f) return "";
        if (paint.measureText(text) <= maxWidth) return text;
        String value = text;
        while (!value.isEmpty() && paint.measureText(value + "…") > maxWidth) {
            value = value.substring(0, value.length() - 1);
        }
        return value.isEmpty() ? "…" : (value + "…");
    }

    static float drawWrappedText(
        Canvas canvas,
        String text,
        float x,
        float firstBaseline,
        float maxWidth,
        int maxLines,
        Paint paint,
        float bottom
    ) {
        List<String> lines = wrap(text, paint, maxWidth, maxLines);
        float lineHeight = paint.getTextSize() * 1.14f;
        float y = firstBaseline;
        for (String line : lines) {
            if (y > bottom) break;
            canvas.drawText(line, x, y, paint);
            y += lineHeight;
        }
        return y;
    }

    static List<String> wrap(String text, Paint paint, float maxWidth, int maxLines) {
        List<String> lines = new ArrayList<>();
        if (text == null || text.isEmpty() || maxWidth <= 0f || maxLines <= 0) return lines;
        StringBuilder current = new StringBuilder();
        int consumed = 0;
        for (int index = 0; index < text.length(); index++) {
            char character = text.charAt(index);
            String candidate = current.toString() + character;
            if (current.length() > 0 && paint.measureText(candidate) > maxWidth) {
                lines.add(current.toString());
                current.setLength(0);
                if (lines.size() == maxLines) break;
            }
            current.append(character);
            consumed = index + 1;
        }
        if (lines.size() < maxLines && current.length() > 0) lines.add(current.toString());
        if (consumed < text.length() && !lines.isEmpty()) {
            int last = lines.size() - 1;
            String value = lines.get(last);
            while (!value.isEmpty() && paint.measureText(value + "…") > maxWidth) {
                value = value.substring(0, value.length() - 1);
            }
            lines.set(last, value.isEmpty() ? "…" : (value + "…"));
        }
        return lines;
    }
}
