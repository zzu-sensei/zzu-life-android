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
import android.graphics.RectF;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.View;
import android.widget.RemoteViews;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executors;

public class ScheduleWidgetProvider extends AppWidgetProvider {
    private static final String REFRESH = "cn.edu.zzu.life.REFRESH_SCHEDULE";
    private static final int[] COURSE_COLORS = {
        0xFF4F86D9, 0xFF4AA89B, 0xFFE17872, 0xFFD5A344, 0xFF7188C5,
        0xFFA477BD, 0xFF3D9F78, 0xFFD16F9A, 0xFFCF7845, 0xFF598FB0,
        0xFF879E4C, 0xFFB66A65, 0xFF6A76C2, 0xFFB98B43, 0xFF497FA2,
        0xFF8F6FAD, 0xFF3C987F, 0xFFC26285, 0xFF7F8A45, 0xFFB76055
    };

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
            loading.setViewVisibility(R.id.widget_schedule_grid, View.GONE);
            loading.setViewVisibility(R.id.widget_schedule_status, View.VISIBLE);
            loading.setTextViewText(R.id.widget_schedule_status, "正在生成今日课表…");
            manager.updateAppWidget(id, loading);
        }
        Executors.newSingleThreadExecutor().execute(() -> {
            JSONObject result = null;
            String error = null;
            try {
                String[] stored = SessionStore.load(context);
                if (stored == null) throw new IllegalStateException("请先打开应用登录");
                result = PythonGateway.callWithSession(
                    new PythonGateway.ContextSession(stored), "get_today_schedule"
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
                    views.setViewVisibility(R.id.widget_schedule_grid, View.GONE);
                    views.setViewVisibility(R.id.widget_schedule_status, View.VISIBLE);
                    views.setTextViewText(R.id.widget_schedule_status, "刷新失败\n" + error);
                    views.setTextViewText(R.id.widget_schedule_meta, "打开应用重新登录");
                } else {
                    Bundle options = manager.getAppWidgetOptions(id);
                    int widthDp = Math.max(
                        250,
                        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
                    );
                    int heightDp = Math.max(
                        155,
                        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 155)
                    );
                    int bitmapWidth = Math.min(1400, Math.max(500, widthDp * 2));
                    int bitmapHeight = Math.min(1500, Math.max(240, (heightDp - 68) * 2));
                    views.setImageViewBitmap(
                        R.id.widget_schedule_grid,
                        renderToday(result.optJSONArray("lessons"), bitmapWidth, bitmapHeight)
                    );
                    views.setViewVisibility(R.id.widget_schedule_grid, View.VISIBLE);
                    views.setViewVisibility(R.id.widget_schedule_status, View.GONE);
                    views.setTextViewText(
                        R.id.widget_schedule_meta,
                        "第 " + result.optInt("week") + " 周 · 含实验 · 点击打开应用"
                    );
                }
                manager.updateAppWidget(id, views);
            }
            if (pending != null) pending.finish();
        });
    }

    private static Bitmap renderToday(JSONArray lessons, int width, int height) {
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(Color.TRANSPARENT);
        float unitWidth = Math.max(28f, width * 0.055f);
        float unitHeight = height / 10f;

        Paint grid = new Paint(Paint.ANTI_ALIAS_FLAG);
        grid.setColor(0x385FC5B3);
        grid.setStrokeWidth(Math.max(1f, width / 700f));
        for (int unit = 0; unit <= 10; unit++) {
            float y = unit * unitHeight;
            canvas.drawLine(0, y, width, y, grid);
        }
        canvas.drawLine(unitWidth, 0, unitWidth, height, grid);

        Paint unitPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        unitPaint.setColor(0xFFB8D8CE);
        unitPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        unitPaint.setTextSize(Math.max(12f, Math.min(20f, unitWidth * 0.46f)));
        unitPaint.setTextAlign(Paint.Align.CENTER);
        for (int unit = 1; unit <= 10; unit++) {
            float y = (unit - 0.5f) * unitHeight;
            drawTextCentered(canvas, String.valueOf(unit), unitWidth / 2f, y, unitPaint);
        }

        Map<String, Integer> colors = colorsForLessons(lessons);
        if (lessons == null || lessons.length() == 0) {
            Paint empty = new Paint(Paint.ANTI_ALIAS_FLAG);
            empty.setColor(0xFFF2FFF9);
            empty.setTextSize(Math.max(20f, width * 0.04f));
            empty.setTextAlign(Paint.Align.CENTER);
            drawTextCentered(canvas, "今天没有课程", width / 2f, height / 2f, empty);
            return bitmap;
        }

        for (int index = 0; index < lessons.length(); index++) {
            JSONObject lesson = lessons.optJSONObject(index);
            if (lesson == null) continue;
            int start = clamp(lesson.optInt("start_unit", 1), 1, 10);
            int end = clamp(lesson.optInt("end_unit", start), start, 10);
            String course = lesson.optString("course", "未知课程");
            String place = lesson.optString("place", "地点未定");
            String time = lesson.optString("start_time") + "–" + lesson.optString("end_time");
            float gap = Math.max(2f, width / 420f);
            RectF block = new RectF(
                unitWidth + gap,
                (start - 1) * unitHeight + gap,
                width - gap,
                end * unitHeight - gap
            );
            Paint blockPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            blockPaint.setColor(colors.get(course));
            canvas.drawRoundRect(block, gap * 2.5f, gap * 2.5f, blockPaint);

            float padding = Math.max(4f, width / 220f);
            Paint coursePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            coursePaint.setColor(Color.WHITE);
            coursePaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
            coursePaint.setTextSize(Math.max(14f, Math.min(24f, block.height() * 0.28f)));
            canvas.drawText(
                course,
                block.left + padding,
                Math.min(block.bottom - padding, block.top + padding + coursePaint.getTextSize()),
                coursePaint
            );

            Paint detailPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            detailPaint.setColor(0xF0FFFFFF);
            detailPaint.setTextSize(Math.max(11f, coursePaint.getTextSize() * 0.72f));
            String detail = time + " · " + place + (lesson.optBoolean("is_experiment") ? " · 实验" : "");
            float detailY = block.top + padding + coursePaint.getTextSize() + detailPaint.getTextSize() * 1.15f;
            if (detailY < block.bottom - padding) {
                canvas.drawText(
                    ellipsize(detail, detailPaint, block.width() - padding * 2),
                    block.left + padding,
                    detailY,
                    detailPaint
                );
            }
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

    private static String ellipsize(String text, Paint paint, float width) {
        if (paint.measureText(text) <= width) return text;
        String value = text;
        while (!value.isEmpty() && paint.measureText(value + "…") > width) {
            value = value.substring(0, value.length() - 1);
        }
        return value + "…";
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
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_schedule);
        Intent refresh = new Intent(context, ScheduleWidgetProvider.class).setAction(REFRESH);
        views.setOnClickPendingIntent(
            R.id.widget_schedule_refresh,
            PendingIntent.getBroadcast(
                context,
                id,
                refresh,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            )
        );
        Intent open = new Intent(context, MainActivity.class);
        views.setOnClickPendingIntent(
            R.id.widget_schedule_root,
            PendingIntent.getActivity(
                context,
                id + 10000,
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
