package cn.edu.zzu.life;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
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

import java.util.Map;

public class WeekScheduleWidgetProvider extends AppWidgetProvider {
    private static final String REFRESH = "cn.edu.zzu.life.REFRESH_WEEK_SCHEDULE";

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        if (ids == null || ids.length == 0) return;
        String[] stored = SessionStore.load(context);
        WidgetSupport.CachedData cached = loadEffectiveCache(context);
        if (stored != null && cached != null) {
            renderCachedForIds(context, manager, ids, cached, null);
            return;
        }
        startUpdate(context, manager, ids, goAsync());
    }

    @Override
    public void onAppWidgetOptionsChanged(
        Context context,
        AppWidgetManager manager,
        int appWidgetId,
        Bundle newOptions
    ) {
        String[] stored = SessionStore.load(context);
        WidgetSupport.CachedData cached = loadEffectiveCache(context);
        if (stored != null && cached != null) {
            renderCachedForIds(context, manager, new int[] {appWidgetId}, cached, null);
        } else {
            startUpdate(context, manager, new int[] {appWidgetId}, goAsync());
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (REFRESH.equals(intent.getAction())) {
            AppWidgetManager manager = AppWidgetManager.getInstance(context);
            int[] ids = manager.getAppWidgetIds(new ComponentName(context, WeekScheduleWidgetProvider.class));
            if (ids != null && ids.length > 0) {
                startUpdate(context, manager, ids, goAsync());
            }
        }
    }

    private static WidgetSupport.CachedData loadEffectiveCache(Context context) {
        WidgetSupport.CachedData sem = WidgetSupport.buildWeekFromSemesterCache(context);
        WidgetSupport.CachedData direct = WidgetSupport.loadCache(context, WidgetSupport.KEY_WEEK);
        if (sem != null && direct != null) {
            boolean directStillCurrentWeek = direct.payload.optInt("week", 0) == sem.payload.optInt("week", -1);
            if (direct.updatedAt > sem.updatedAt && directStillCurrentWeek) {
                return direct;
            }
            return sem;
        }
        return sem != null ? sem : direct;
    }

    /** 仅从离线缓存重绘整周课表小组件，不发起网络请求（用于主题切换/前台同步/退出登录）。 */
    static void renderCached(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, WeekScheduleWidgetProvider.class));
        if (ids == null || ids.length == 0) return;

        String[] stored = SessionStore.load(context);
        if (stored == null) {
            renderStatusForIds(context, manager, ids, "请先打开应用登录", "登录后可在桌面查看整周课程");
            return;
        }
        WidgetSupport.CachedData cached = loadEffectiveCache(context);
        if (cached == null) {
            renderStatusForIds(context, manager, ids, "点击右上角刷新同步整周课表", "含实验 · 本机直连");
            return;
        }
        renderCachedForIds(context, manager, ids, cached, null);
    }

    private static void startUpdate(
        Context context,
        AppWidgetManager manager,
        int[] ids,
        BroadcastReceiver.PendingResult pending
    ) {
        WidgetSupport.CachedData existing = loadEffectiveCache(context);
        if (existing != null) {
            renderCachedForIds(context, manager, ids, existing, "正在刷新…");
        } else {
            renderStatusForIds(context, manager, ids, "正在生成彩色课表…", "正在同步本周课程");
        }

        WidgetSupport.runAsync(() -> {
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
                WidgetSupport.saveCache(context, WidgetSupport.KEY_WEEK, result);
            } catch (Exception caught) {
                error = WidgetSupport.safe(caught.getMessage());
            }

            if (result != null) {
                WidgetSupport.CachedData fresh = new WidgetSupport.CachedData(
                    result, System.currentTimeMillis(), WidgetSupport.todayIso()
                );
                renderCachedForIds(context, manager, ids, fresh, null);
            } else {
                boolean loggedOut = SessionStore.load(context) == null;
                WidgetSupport.CachedData fallback = loggedOut ? null : loadEffectiveCache(context);
                if (fallback != null) {
                    renderCachedForIds(
                        context,
                        manager,
                        ids,
                        fallback,
                        "刷新失败 · 显示 " + WidgetSupport.formatTime(fallback.updatedAt) + " 缓存"
                    );
                } else {
                    renderStatusForIds(
                        context,
                        manager,
                        ids,
                        loggedOut ? "请先打开应用登录" : ("刷新失败\n" + error),
                        "点按刷新或打开应用重新登录"
                    );
                }
            }
            if (pending != null) pending.finish();
        });
    }

    private static void renderCachedForIds(
        Context context,
        AppWidgetManager manager,
        int[] ids,
        WidgetSupport.CachedData cached,
        String footerOverride
    ) {
        WidgetSupport.Palette palette = WidgetSupport.palette(context);
        JSONObject result = cached.payload;
        int week = result.optInt("week", 0);
        JSONArray lessons = result.optJSONArray("lessons");
        int count = lessons == null ? 0 : lessons.length();
        String badge = week > 0 ? ("第 " + week + " 周") : "本周课表";
        boolean fromSemester = result.optBoolean("from_semester_cache", false);
        String meta = footerOverride != null
            ? footerOverride
            : ("本周 " + count + " 节课 · 含实验"
                + (fromSemester ? " · 离线缓存 " : " · 更新于 ")
                + WidgetSupport.formatTime(cached.updatedAt));

        for (int id : ids) {
            RemoteViews views = baseViews(context, id, palette, badge);
            Bundle options = manager.getAppWidgetOptions(id);
            int[] size = WidgetSupport.bitmapSize(context, options, 250, 220, 72, 960, 1280);
            Bitmap timetable = renderWeekTimetable(lessons, size[0], size[1], palette);
            views.setImageViewBitmap(R.id.widget_week_schedule_grid, timetable);
            views.setViewVisibility(R.id.widget_week_schedule_grid, View.VISIBLE);
            views.setViewVisibility(R.id.widget_week_schedule_status, View.GONE);
            views.setTextViewText(R.id.widget_week_schedule_meta, meta);
            manager.updateAppWidget(id, views);
        }
    }

    private static void renderStatusForIds(
        Context context,
        AppWidgetManager manager,
        int[] ids,
        String statusText,
        String metaText
    ) {
        WidgetSupport.Palette palette = WidgetSupport.palette(context);
        for (int id : ids) {
            RemoteViews views = baseViews(context, id, palette, "本周");
            views.setViewVisibility(R.id.widget_week_schedule_grid, View.GONE);
            views.setViewVisibility(R.id.widget_week_schedule_status, View.VISIBLE);
            views.setTextViewText(R.id.widget_week_schedule_status, statusText);
            views.setTextViewText(R.id.widget_week_schedule_meta, metaText);
            manager.updateAppWidget(id, views);
        }
    }

    private static Bitmap renderWeekTimetable(
        JSONArray lessons,
        int width,
        int height,
        WidgetSupport.Palette palette
    ) {
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(Color.TRANSPARENT);

        int highestEnd = 10;
        if (lessons != null) {
            for (int i = 0; i < lessons.length(); i++) {
                JSONObject lesson = lessons.optJSONObject(i);
                if (lesson == null) continue;
                int end = lesson.optInt("end_unit", 10);
                if (end > highestEnd) highestEnd = end;
            }
        }
        int maxUnit = WidgetSupport.clamp(highestEnd, 10, 14);
        int todayWeekday = WidgetSupport.clamp(WidgetSupport.todayWeekday(), 1, 7);

        float headerHeight = Math.max(34f, Math.min(48f, height * 0.072f));
        float unitWidth = Math.max(24f, Math.min(38f, width * 0.048f));
        float dayWidth = (width - unitWidth) / 7f;
        float unitHeight = (height - headerHeight) / maxUnit;

        // 今日列淡蓝底色高亮
        Paint todayColPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        todayColPaint.setColor(palette.todayColBg);
        float todayLeft = unitWidth + (todayWeekday - 1) * dayWidth;
        canvas.drawRect(todayLeft, headerHeight, todayLeft + dayWidth, height, todayColPaint);

        // 细网格线
        Paint grid = new Paint(Paint.ANTI_ALIAS_FLAG);
        grid.setColor(palette.divider);
        grid.setStrokeWidth(Math.max(1f, width / 760f));
        for (int day = 0; day <= 7; day++) {
            float x = unitWidth + day * dayWidth;
            canvas.drawLine(x, headerHeight, x, height, grid);
        }
        for (int unit = 0; unit <= maxUnit; unit++) {
            float y = headerHeight + unit * unitHeight;
            canvas.drawLine(unit == 0 ? 0f : unitWidth, y, width, y, grid);
        }

        // 星期表头（今天加亮 HyperOS 蓝胶囊）
        Paint headerPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        headerPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        float headerTextSize = Math.max(13f, Math.min(22f, dayWidth * 0.30f));
        headerPaint.setTextSize(headerTextSize);
        headerPaint.setTextAlign(Paint.Align.CENTER);

        Paint pillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        pillPaint.setColor(palette.primary);

        for (int day = 1; day <= 7; day++) {
            float cx = unitWidth + (day - 0.5f) * dayWidth;
            float cy = headerHeight * 0.48f;
            String label = "周" + WidgetSupport.DAYS[day];
            if (day == todayWeekday) {
                float pillW = Math.min(dayWidth * 0.84f, headerPaint.measureText(label) + headerTextSize * 1.1f);
                float pillH = Math.min(headerHeight * 0.80f, headerTextSize * 1.65f);
                RectF pill = new RectF(cx - pillW / 2f, cy - pillH / 2f, cx + pillW / 2f, cy + pillH / 2f);
                canvas.drawRoundRect(pill, pillH / 2f, pillH / 2f, pillPaint);
                headerPaint.setColor(Color.WHITE);
            } else {
                headerPaint.setColor(palette.inkSecondary);
            }
            WidgetSupport.drawTextCentered(canvas, label, cx, cy, headerPaint);
        }

        // 左侧节次编号
        Paint unitPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        unitPaint.setColor(palette.inkMuted);
        unitPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        unitPaint.setTextSize(Math.max(11f, Math.min(18f, Math.min(unitWidth * 0.48f, unitHeight * 0.55f))));
        unitPaint.setTextAlign(Paint.Align.CENTER);
        for (int unit = 1; unit <= maxUnit; unit++) {
            float y = headerHeight + (unit - 0.5f) * unitHeight;
            WidgetSupport.drawTextCentered(canvas, String.valueOf(unit), unitWidth / 2f, y, unitPaint);
        }

        if (lessons == null || lessons.length() == 0) {
            Paint emptyPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            emptyPaint.setColor(palette.inkMuted);
            emptyPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
            emptyPaint.setTextSize(Math.max(16f, Math.min(24f, width * 0.036f)));
            emptyPaint.setTextAlign(Paint.Align.CENTER);
            WidgetSupport.drawTextCentered(
                canvas,
                "本周暂无排课",
                unitWidth + (width - unitWidth) / 2f,
                headerHeight + (height - headerHeight) / 2f,
                emptyPaint
            );
            return bitmap;
        }

        Map<String, WidgetSupport.CourseStyle> styles = WidgetSupport.assignCourseStyles(lessons, palette.dark);
        Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Paint borderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        borderPaint.setStyle(Paint.Style.STROKE);
        borderPaint.setStrokeWidth(Math.max(1f, width / 760f));
        Paint accentPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

        Paint coursePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        coursePaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        Paint placePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Paint labPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        labPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        labPaint.setTextAlign(Paint.Align.RIGHT);

        float gap = Math.max(1.8f, width / 460f);
        float radius = Math.max(6f, Math.min(11f, dayWidth * 0.14f));
        float barW = Math.max(3f, Math.min(5f, dayWidth * 0.055f));
        float padding = Math.max(3f, width / 260f);

        for (int index = 0; index < lessons.length(); index++) {
            JSONObject lesson = lessons.optJSONObject(index);
            if (lesson == null) continue;
            int weekday = WidgetSupport.clamp(lesson.optInt("weekday", 1), 1, 7);
            int start = WidgetSupport.clamp(lesson.optInt("start_unit", 1), 1, maxUnit);
            int end = WidgetSupport.clamp(lesson.optInt("end_unit", start), start, maxUnit);
            String course = lesson.optString("course", "未知课程");
            String place = lesson.optString("place", "地点未定");

            WidgetSupport.CourseStyle style = styles.get(course);
            if (style == null) {
                style = new WidgetSupport.CourseStyle(
                    palette.cardFill, palette.cardBorder, palette.primary, palette.ink, palette.inkSecondary
                );
            }

            RectF block = new RectF(
                unitWidth + (weekday - 1) * dayWidth + gap,
                headerHeight + (start - 1) * unitHeight + gap,
                unitWidth + weekday * dayWidth - gap,
                headerHeight + end * unitHeight - gap
            );

            fillPaint.setColor(style.background);
            canvas.drawRoundRect(block, radius, radius, fillPaint);

            borderPaint.setColor(style.border);
            canvas.drawRoundRect(block, radius, radius, borderPaint);

            canvas.save();
            Path clip = new Path();
            clip.addRoundRect(block, radius, radius, Path.Direction.CW);
            canvas.clipPath(clip);

            // 左侧强调竖条
            accentPaint.setColor(style.accent);
            canvas.drawRect(block.left, block.top, block.left + barW, block.bottom, accentPaint);

            float textLeft = block.left + barW + padding;
            float textMaxW = Math.max(12f, block.right - padding - textLeft);

            float courseSize = Math.max(10f, Math.min(17f, dayWidth * 0.23f));
            coursePaint.setTextSize(courseSize);
            coursePaint.setColor(style.title);

            float placeSize = Math.max(8.5f, Math.min(13.5f, dayWidth * 0.18f));
            placePaint.setTextSize(placeSize);
            placePaint.setColor(style.subtitle);

            boolean showLab = lesson.optBoolean("is_experiment") && block.height() > placeSize * 3.4f;
            float contentBottom = block.bottom - padding - (showLab ? (placeSize * 1.15f) : 0f);

            int courseLines = end > start ? 3 : 2;
            float y = block.top + padding + courseSize;
            y = WidgetSupport.drawWrappedText(
                canvas,
                course,
                textLeft,
                y,
                textMaxW,
                courseLines,
                coursePaint,
                contentBottom
            );

            WidgetSupport.drawWrappedText(
                canvas,
                place,
                textLeft,
                y + padding * 0.45f,
                textMaxW,
                end > start ? 2 : 1,
                placePaint,
                contentBottom
            );

            if (showLab) {
                labPaint.setColor(style.accent);
                labPaint.setTextSize(placeSize);
                canvas.drawText("实验", block.right - padding, block.bottom - padding, labPaint);
            }
            canvas.restore();
        }
        return bitmap;
    }

    private static RemoteViews baseViews(
        Context context,
        int id,
        WidgetSupport.Palette palette,
        String badgeText
    ) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_week_schedule);
        views.setInt(R.id.widget_week_schedule_root, "setBackgroundResource", palette.bgRes);
        views.setTextColor(R.id.widget_week_schedule_title, palette.ink);
        views.setInt(R.id.widget_week_schedule_badge, "setBackgroundResource", palette.badgeBlueRes);
        views.setTextColor(R.id.widget_week_schedule_badge, palette.primary);
        views.setTextViewText(R.id.widget_week_schedule_badge, badgeText);
        views.setInt(R.id.widget_week_schedule_refresh, "setBackgroundResource", palette.pillRes);
        views.setTextColor(R.id.widget_week_schedule_refresh, palette.primary);
        views.setTextColor(R.id.widget_week_schedule_status, palette.inkSecondary);
        views.setTextColor(R.id.widget_week_schedule_meta, palette.inkMuted);

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
}
