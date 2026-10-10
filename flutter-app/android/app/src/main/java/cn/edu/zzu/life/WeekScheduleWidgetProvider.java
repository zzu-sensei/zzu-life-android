package cn.edu.zzu.life;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.View;
import android.widget.RemoteViews;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executors;

public class WeekScheduleWidgetProvider extends AppWidgetProvider {
    private static final String REFRESH = "cn.edu.zzu.life.REFRESH_WEEK_SCHEDULE";
    private static final int[] COURSE_COLORS = {
        0xFF4F86D9, 0xFF4AA89B, 0xFFE17872, 0xFFD5A344, 0xFF7188C5,
        0xFFA477BD, 0xFF3D9F78, 0xFFD16F9A, 0xFFCF7845, 0xFF598FB0,
        0xFF879E4C, 0xFFB66A65, 0xFF6A76C2, 0xFFB98B43, 0xFF497FA2,
        0xFF8F6FAD, 0xFF3C987F, 0xFFC26285, 0xFF7F8A45, 0xFFB76055
    };
    private static final String[] DAYS = {"", "一", "二", "三", "四", "五", "六", "日"};

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        startUpdate(context, manager, ids, goAsync());
    }

    @Override
    public void onAppWidgetOptionsChanged(
        Context context,
        AppWidgetManager manager,
        int appWidgetId,
        Bundle newOptions
    ) {
        startUpdate(context, manager, new int[] {appWidgetId}, goAsync());
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (REFRESH.equals(intent.getAction())) {
            AppWidgetManager manager = AppWidgetManager.getInstance(context);
            int[] ids = manager.getAppWidgetIds(intent.getComponent());
            startUpdate(context, manager, ids, goAsync());
        }
    }

    private static void startUpdate(
        Context context,
        AppWidgetManager manager,
        int[] ids,
        BroadcastReceiver.PendingResult pending
    ) {
        for (int id : ids) {
            RemoteViews loading = baseViews(context, id);
            loading.setViewVisibility(R.id.widget_week_schedule_grid, View.GONE);
            loading.setViewVisibility(R.id.widget_week_schedule_status, View.VISIBLE);
            loading.setTextViewText(R.id.widget_week_schedule_status, "正在生成彩色课表…");
            manager.updateAppWidget(id, loading);
        }
        Executors.newSingleThreadExecutor().execute(() -> {
            JSONObject result = null;
            String error = null;
            try {
                String[] stored = SessionStore.load(context);
                if (stored == null) throw new IllegalStateException("请先打开应用登录");
                result = PythonGateway.callWithSession(
                    new PythonGateway.ContextSession(stored), "get_schedule", 0, 0
                );
                if (!result.optBoolean("ok")) {
                    throw new IllegalStateException(result.optString("error", "课表查询失败"));
                }
            } catch (Exception caught) {
                error = safe(caught.getMessage());
            }

            for (int id : ids) {
                RemoteViews views = baseViews(context, id);
                if (result == null) {
                    views.setViewVisibility(R.id.widget_week_schedule_grid, View.GONE);
                    views.setViewVisibility(R.id.widget_week_schedule_status, View.VISIBLE);
                    views.setTextViewText(R.id.widget_week_schedule_status, "刷新失败\n" + error);
                    views.setTextViewText(
                        R.id.widget_week_schedule_meta,
                        "点按刷新或打开应用重新登录"
                    );
                } else {
                    Bundle options = manager.getAppWidgetOptions(id);
                    int widthDp = Math.max(
                        250,
                        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
                    );
                    int heightDp = Math.max(
                        220,
                        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 220)
                    );
                    int bitmapWidth = Math.min(1400, Math.max(500, widthDp * 2));
                    int bitmapHeight = Math.min(1800, Math.max(360, (heightDp - 68) * 2));
                    Bitmap timetable = renderTimetable(
                        result.optJSONArray("lessons"),
                        bitmapWidth,
                        bitmapHeight
                    );
                    views.setImageViewBitmap(R.id.widget_week_schedule_grid, timetable);
                    views.setViewVisibility(R.id.widget_week_schedule_grid, View.VISIBLE);
                    views.setViewVisibility(R.id.widget_week_schedule_status, View.GONE);
                    views.setTextViewText(
                        R.id.widget_week_schedule_meta,
                        "第 " + result.optInt("week") + " 周 · 含实验 · 点击课程表打开应用"
                    );
                }
                manager.updateAppWidget(id, views);
            }
            if (pending != null) pending.finish();
        });
    }

    private static Bitmap renderTimetable(JSONArray lessons, int width, int height) {
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(Color.TRANSPARENT);

        float headerHeight = Math.max(38f, height * 0.075f);
        float unitWidth = Math.max(26f, width * 0.048f);
        float dayWidth = (width - unitWidth) / 7f;
        float unitHeight = (height - headerHeight) / 10f;

        Paint grid = new Paint(Paint.ANTI_ALIAS_FLAG);
        grid.setColor(0x385FC5B3);
        grid.setStrokeWidth(Math.max(1f, width / 700f));
        for (int day = 0; day <= 7; day++) {
            float x = unitWidth + day * dayWidth;
            canvas.drawLine(x, 0, x, height, grid);
        }
        for (int unit = 0; unit <= 10; unit++) {
            float y = headerHeight + unit * unitHeight;
            canvas.drawLine(0, y, width, y, grid);
        }

        Paint header = new Paint(Paint.ANTI_ALIAS_FLAG);
        header.setColor(0xFFF2FFF9);
        header.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        header.setTextSize(Math.max(15f, Math.min(24f, dayWidth * 0.34f)));
        header.setTextAlign(Paint.Align.CENTER);
        for (int day = 1; day <= 7; day++) {
            float x = unitWidth + (day - 0.5f) * dayWidth;
            drawTextCentered(canvas, "周" + DAYS[day], x, headerHeight / 2f, header);
        }

        Paint unitPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        unitPaint.setColor(0xFFB8D8CE);
        unitPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        unitPaint.setTextSize(Math.max(12f, Math.min(20f, unitWidth * 0.48f)));
        unitPaint.setTextAlign(Paint.Align.CENTER);
        for (int unit = 1; unit <= 10; unit++) {
            float y = headerHeight + (unit - 0.5f) * unitHeight;
            drawTextCentered(canvas, String.valueOf(unit), unitWidth / 2f, y, unitPaint);
        }

        Map<String, Integer> colors = colorsForLessons(lessons);
        if (lessons == null) return bitmap;
        for (int index = 0; index < lessons.length(); index++) {
            JSONObject lesson = lessons.optJSONObject(index);
            if (lesson == null) continue;
            int weekday = clamp(lesson.optInt("weekday", 1), 1, 7);
            int start = clamp(lesson.optInt("start_unit", 1), 1, 10);
            int end = clamp(lesson.optInt("end_unit", start), start, 10);
            String course = lesson.optString("course", "未知课程");
            String place = lesson.optString("place", "地点未定");
            float gap = Math.max(2f, width / 420f);
            RectF block = new RectF(
                unitWidth + (weekday - 1) * dayWidth + gap,
                headerHeight + (start - 1) * unitHeight + gap,
                unitWidth + weekday * dayWidth - gap,
                headerHeight + end * unitHeight - gap
            );

            Paint blockPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            blockPaint.setColor(colors.get(course));
            canvas.drawRoundRect(block, gap * 2.4f, gap * 2.4f, blockPaint);

            canvas.save();
            Path clip = new Path();
            clip.addRoundRect(block, gap * 2.4f, gap * 2.4f, Path.Direction.CW);
            canvas.clipPath(clip);
            float padding = Math.max(3f, width / 250f);
            Paint coursePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            coursePaint.setColor(Color.WHITE);
            coursePaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
            coursePaint.setTextSize(Math.max(11f, Math.min(18f, dayWidth * 0.25f)));
            float y = block.top + padding + coursePaint.getTextSize();
            int courseLines = end > start ? 3 : 2;
            y = drawWrappedText(
                canvas,
                course,
                block.left + padding,
                y,
                block.width() - padding * 2,
                courseLines,
                coursePaint,
                block.bottom - padding
            );

            Paint placePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            placePaint.setColor(0xF0FFFFFF);
            placePaint.setTextSize(Math.max(9f, Math.min(15f, dayWidth * 0.20f)));
            drawWrappedText(
                canvas,
                place,
                block.left + padding,
                y + padding,
                block.width() - padding * 2,
                end > start ? 3 : 1,
                placePaint,
                block.bottom - padding
            );

            if (lesson.optBoolean("is_experiment") && block.height() > placePaint.getTextSize() * 3) {
                Paint labPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
                labPaint.setColor(Color.WHITE);
                labPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
                labPaint.setTextSize(placePaint.getTextSize());
                labPaint.setTextAlign(Paint.Align.RIGHT);
                canvas.drawText("实验", block.right - padding, block.bottom - padding, labPaint);
            }
            canvas.restore();
        }
        return bitmap;
    }

    private static Map<String, Integer> colorsForLessons(JSONArray lessons) {
        Map<String, Integer> result = new HashMap<>();
        Set<Integer> used = new HashSet<>();
        if (lessons == null) return result;
        for (int index = 0; index < lessons.length(); index++) {
            JSONObject lesson = lessons.optJSONObject(index);
            if (lesson == null) continue;
            String course = lesson.optString("course", "未知课程");
            if (result.containsKey(course)) continue;
            int colorIndex = courseIndex(course);
            while (used.contains(colorIndex) && used.size() < COURSE_COLORS.length) {
                colorIndex = (colorIndex + 1) % COURSE_COLORS.length;
            }
            used.add(colorIndex);
            result.put(course, COURSE_COLORS[colorIndex]);
        }
        return result;
    }

    private static float drawWrappedText(
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
        float lineHeight = paint.getTextSize() * 1.12f;
        float y = firstBaseline;
        for (String line : lines) {
            if (y > bottom) break;
            canvas.drawText(line, x, y, paint);
            y += lineHeight;
        }
        return y;
    }

    private static List<String> wrap(String text, Paint paint, float maxWidth, int maxLines) {
        List<String> lines = new ArrayList<>();
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
            lines.set(last, value + "…");
        }
        return lines;
    }

    private static void drawTextCentered(Canvas canvas, String text, float x, float y, Paint paint) {
        Paint.FontMetrics metrics = paint.getFontMetrics();
        canvas.drawText(text, x, y - (metrics.ascent + metrics.descent) / 2f, paint);
    }

    private static int courseIndex(String course) {
        int hash = 0x811C9DC5;
        for (int index = 0; index < course.length(); index++) {
            hash = (hash ^ course.charAt(index)) * 0x01000193;
        }
        return (hash & 0x7FFFFFFF) % COURSE_COLORS.length;
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static RemoteViews baseViews(Context context, int id) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_week_schedule);
        Intent refresh = new Intent(context, WeekScheduleWidgetProvider.class).setAction(REFRESH);
        views.setOnClickPendingIntent(
            R.id.widget_week_schedule_refresh,
            PendingIntent.getBroadcast(
                context,
                id,
                refresh,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            )
        );
        Intent open = new Intent(context, MainActivity.class);
        views.setOnClickPendingIntent(
            R.id.widget_week_schedule_root,
            PendingIntent.getActivity(
                context,
                id + 30000,
                open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            )
        );
        return views;
    }

    private static String safe(String value) {
        return value == null || value.isEmpty() ? "未知错误" : value;
    }
}
