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
import android.graphics.RectF;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.View;
import android.widget.RemoteViews;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

public class ScheduleWidgetProvider extends AppWidgetProvider {
    private static final String REFRESH = "cn.edu.zzu.life.REFRESH_SCHEDULE";

    private static final int STATE_UPCOMING = 0;
    private static final int STATE_NEXT = 1;
    private static final int STATE_ONGOING = 2;
    private static final int STATE_PAST = 3;

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
            int[] ids = manager.getAppWidgetIds(new ComponentName(context, ScheduleWidgetProvider.class));
            if (ids != null && ids.length > 0) {
                startUpdate(context, manager, ids, goAsync());
            }
        }
    }

    private static WidgetSupport.CachedData loadEffectiveCache(Context context) {
        WidgetSupport.CachedData sem = WidgetSupport.buildTodayFromSemesterCache(context);
        WidgetSupport.CachedData direct = WidgetSupport.loadCache(context, WidgetSupport.KEY_TODAY);
        boolean directValid = direct != null && WidgetSupport.todayIso().equals(direct.date);
        if (sem != null && directValid) {
            return direct.updatedAt > sem.updatedAt ? direct : sem;
        }
        if (sem != null) return sem;
        return directValid ? direct : null;
    }

    /** 仅从离线缓存重绘今日课表小组件，不发起网络请求（用于主题切换/前台同步/退出登录）。 */
    static void renderCached(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, ScheduleWidgetProvider.class));
        if (ids == null || ids.length == 0) return;

        String[] stored = SessionStore.load(context);
        if (stored == null) {
            renderStatusForIds(context, manager, ids, "请先打开应用登录", "登录后可在桌面查看今日课程", null);
            return;
        }
        WidgetSupport.CachedData cached = loadEffectiveCache(context);
        if (cached == null) {
            renderStatusForIds(
                context,
                manager,
                ids,
                "点击右上角刷新同步今日课表",
                WidgetSupport.todayShortDate() + " · 周" + WidgetSupport.DAYS[WidgetSupport.todayWeekday()],
                null
            );
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
            renderStatusForIds(context, manager, ids, "正在生成今日课表…", "正在同步课程安排", null);
        }

        WidgetSupport.runAsync(() -> {
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
                WidgetSupport.saveCache(context, WidgetSupport.KEY_TODAY, result);
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
                        "点按刷新或打开应用重新登录",
                        null
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
        int weekday = WidgetSupport.clamp(WidgetSupport.todayWeekday(), 1, 7);
        String badge = week > 0
            ? ("第 " + week + " 周 · 周" + WidgetSupport.DAYS[weekday])
            : (WidgetSupport.todayShortDate() + " · 周" + WidgetSupport.DAYS[weekday]);
        boolean fromSemester = result.optBoolean("from_semester_cache", false);
        String meta = footerOverride != null
            ? footerOverride
            : ((count == 0 ? "今日无课" : ("今日 " + count + " 节课"))
                + (fromSemester ? " · 离线缓存 " : " · 更新于 ")
                + WidgetSupport.formatTime(cached.updatedAt));

        for (int id : ids) {
            RemoteViews views = baseViews(context, id, palette, badge);
            Bundle options = manager.getAppWidgetOptions(id);
            int[] size = WidgetSupport.bitmapSize(context, options, 250, 155, 76, 960, 1080);
            views.setImageViewBitmap(
                R.id.widget_schedule_grid,
                renderTodayAgenda(lessons, size[0], size[1], palette)
            );
            views.setViewVisibility(R.id.widget_schedule_grid, View.VISIBLE);
            views.setViewVisibility(R.id.widget_schedule_status, View.GONE);
            views.setTextViewText(R.id.widget_schedule_meta, meta);
            manager.updateAppWidget(id, views);
        }
    }

    private static void renderStatusForIds(
        Context context,
        AppWidgetManager manager,
        int[] ids,
        String statusText,
        String metaText,
        String badgeOverride
    ) {
        WidgetSupport.Palette palette = WidgetSupport.palette(context);
        int weekday = WidgetSupport.clamp(WidgetSupport.todayWeekday(), 1, 7);
        String badge = badgeOverride != null
            ? badgeOverride
            : (WidgetSupport.todayShortDate() + " · 周" + WidgetSupport.DAYS[weekday]);

        for (int id : ids) {
            RemoteViews views = baseViews(context, id, palette, badge);
            views.setViewVisibility(R.id.widget_schedule_grid, View.GONE);
            views.setViewVisibility(R.id.widget_schedule_status, View.VISIBLE);
            views.setTextViewText(R.id.widget_schedule_status, statusText);
            views.setTextViewText(R.id.widget_schedule_meta, metaText);
            manager.updateAppWidget(id, views);
        }
    }

    private static Bitmap renderTodayAgenda(
        JSONArray lessonsArray,
        int width,
        int height,
        WidgetSupport.Palette palette
    ) {
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(Color.TRANSPARENT);

        List<JSONObject> lessons = new ArrayList<>();
        if (lessonsArray != null) {
            for (int i = 0; i < lessonsArray.length(); i++) {
                JSONObject obj = lessonsArray.optJSONObject(i);
                if (obj != null) lessons.add(obj);
            }
        }
        Collections.sort(lessons, new Comparator<JSONObject>() {
            @Override
            public int compare(JSONObject a, JSONObject b) {
                int cmp = Integer.compare(a.optInt("start_unit", 0), b.optInt("start_unit", 0));
                if (cmp != 0) return cmp;
                return a.optString("start_time", "").compareTo(b.optString("start_time", ""));
            }
        });

        if (lessons.isEmpty()) {
            drawEmptyCard(canvas, width, height, palette);
            return bitmap;
        }

        Map<String, WidgetSupport.CourseStyle> styles = WidgetSupport.assignCourseStyles(lessonsArray, palette.dark);
        int[] states = classifyStates(lessons);

        float gap = Math.max(8f, Math.min(14f, width * 0.015f));
        float minCardH = Math.max(64f, Math.min(82f, width * 0.115f));
        float maxCardH = Math.max(106f, Math.min(134f, width * 0.185f));
        int total = lessons.size();

        int visibleCount = total;
        float footerPillH = 0f;
        float needed = total * minCardH + Math.max(0, total - 1) * gap;
        if (needed > height && total > 1) {
            footerPillH = Math.max(26f, Math.min(34f, width * 0.05f));
            float avail = Math.max(minCardH, height - footerPillH - gap);
            visibleCount = Math.max(1, (int) Math.floor((avail + gap) / (minCardH + gap)));
            if (visibleCount >= total) {
                visibleCount = total - 1;
            }
        }

        float cardsAreaH = footerPillH > 0f ? (height - footerPillH - gap) : height;
        float cardH = (cardsAreaH - Math.max(0, visibleCount - 1) * gap) / visibleCount;
        cardH = Math.min(maxCardH, Math.max(54f, cardH));

        float radius = Math.max(14f, Math.min(20f, cardH * 0.22f));
        float strokeW = Math.max(1.2f, width / 560f);

        Paint fillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Paint borderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        borderPaint.setStyle(Paint.Style.STROKE);
        Paint accentPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Paint dividerPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Paint badgeFillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

        Paint timeStartPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        timeStartPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        timeStartPaint.setTextAlign(Paint.Align.CENTER);

        Paint timeEndPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        timeEndPaint.setTextAlign(Paint.Align.CENTER);

        Paint titlePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        titlePaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));

        Paint subPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

        Paint badgeTextPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        badgeTextPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        badgeTextPaint.setTextAlign(Paint.Align.CENTER);

        float top = 0f;
        for (int i = 0; i < visibleCount; i++) {
            JSONObject lesson = lessons.get(i);
            int state = states[i];
            boolean isPast = state == STATE_PAST;
            boolean isOngoing = state == STATE_ONGOING;
            boolean isNext = state == STATE_NEXT;

            String course = lesson.optString("course", "未知课程");
            WidgetSupport.CourseStyle style = styles.get(course);
            if (style == null) {
                style = new WidgetSupport.CourseStyle(
                    palette.cardFill, palette.cardBorder, palette.primary, palette.ink, palette.inkSecondary
                );
            }

            RectF card = new RectF(strokeW, top + strokeW, width - strokeW, top + cardH - strokeW);
            fillPaint.setColor(isPast ? palette.cardFill : style.background);
            canvas.drawRoundRect(card, radius, radius, fillPaint);

            borderPaint.setColor(isOngoing ? style.accent : (isPast ? palette.cardBorder : style.border));
            borderPaint.setStrokeWidth(isOngoing ? strokeW * 1.8f : strokeW);
            canvas.drawRoundRect(card, radius, radius, borderPaint);

            // 左侧圆角竖条强调线
            float barW = Math.max(5f, width * 0.0085f);
            float padH = Math.max(12f, width * 0.022f);
            float barInsetV = Math.max(9f, cardH * 0.16f);
            RectF bar = new RectF(
                card.left + padH * 0.72f,
                card.top + barInsetV,
                card.left + padH * 0.72f + barW,
                card.bottom - barInsetV
            );
            accentPaint.setColor(isPast ? WidgetSupport.withAlpha(style.accent, 0.42f) : style.accent);
            canvas.drawRoundRect(bar, barW / 2f, barW / 2f, accentPaint);

            // 时间列
            float timeColLeft = bar.right + padH * 0.65f;
            float timeColW = Math.max(66f, Math.min(110f, width * 0.165f));
            float timeCenterX = timeColLeft + timeColW / 2f;
            float centerY = card.centerY();

            String startTime = lesson.optString("start_time", "").trim();
            String endTime = lesson.optString("end_time", "").trim();
            int startUnit = lesson.optInt("start_unit", 1);
            int endUnit = lesson.optInt("end_unit", startUnit);
            String topTimeLabel = !startTime.isEmpty() ? startTime : ("第" + startUnit + "节");
            String bottomTimeLabel = !endTime.isEmpty() ? endTime : ("第" + endUnit + "节");

            float timeSize = Math.max(14f, Math.min(22f, cardH * 0.24f));
            timeStartPaint.setTextSize(timeSize);
            timeStartPaint.setColor(isPast ? palette.inkSecondary : style.title);
            timeEndPaint.setTextSize(timeSize * 0.80f);
            timeEndPaint.setColor(isPast ? palette.inkMuted : style.subtitle);

            WidgetSupport.drawTextCentered(canvas, topTimeLabel, timeCenterX, centerY - timeSize * 0.56f, timeStartPaint);
            WidgetSupport.drawTextCentered(canvas, bottomTimeLabel, timeCenterX, centerY + timeSize * 0.54f, timeEndPaint);

            // 时间列与详情列分割线
            float divX = timeColLeft + timeColW + padH * 0.5f;
            float divInsetV = Math.max(12f, cardH * 0.20f);
            dividerPaint.setColor(isPast ? palette.divider : style.border);
            dividerPaint.setStrokeWidth(Math.max(1f, strokeW * 0.9f));
            canvas.drawLine(divX, card.top + divInsetV, divX, card.bottom - divInsetV, dividerPaint);

            // 状态徽章（先测宽，确保课程标题绝不重叠）
            String badgeLabel = null;
            int badgeBg = 0;
            int badgeFg = 0;
            if (isOngoing) {
                badgeLabel = "进行中";
                badgeBg = style.accent;
                badgeFg = Color.WHITE;
            } else if (isNext) {
                badgeLabel = "下一节";
                badgeBg = palette.primarySoft;
                badgeFg = palette.primary;
            } else if (isPast) {
                badgeLabel = "已下课";
                badgeBg = palette.divider;
                badgeFg = palette.inkMuted;
            }

            float detailLeft = divX + padH * 0.85f;
            float detailRight = card.right - padH;
            float titleSize = Math.max(16f, Math.min(25f, cardH * 0.27f));
            float subSize = Math.max(12f, Math.min(18f, titleSize * 0.74f));
            titlePaint.setTextSize(titleSize);
            titlePaint.setColor(isPast ? palette.inkSecondary : style.title);
            subPaint.setTextSize(subSize);
            subPaint.setColor(isPast ? palette.inkMuted : style.subtitle);

            float titleRightLimit = detailRight;
            if (badgeLabel != null) {
                float bTextSize = Math.max(11f, Math.min(16f, titleSize * 0.66f));
                badgeTextPaint.setTextSize(bTextSize);
                float bPadH = bTextSize * 0.72f;
                float bPadV = bTextSize * 0.36f;
                float bW = badgeTextPaint.measureText(badgeLabel) + bPadH * 2f;
                float bH = bTextSize + bPadV * 2f;
                float titleCenterY = centerY - titleSize * 0.50f;
                RectF badgeRect = new RectF(
                    detailRight - bW,
                    titleCenterY - bH / 2f,
                    detailRight,
                    titleCenterY + bH / 2f
                );
                badgeFillPaint.setColor(badgeBg);
                canvas.drawRoundRect(badgeRect, bH / 2f, bH / 2f, badgeFillPaint);
                badgeTextPaint.setColor(badgeFg);
                WidgetSupport.drawTextCentered(canvas, badgeLabel, badgeRect.centerX(), badgeRect.centerY(), badgeTextPaint);
                titleRightLimit = badgeRect.left - padH * 0.55f;
            }

            String clippedCourse = WidgetSupport.ellipsize(
                course,
                titlePaint,
                Math.max(40f, titleRightLimit - detailLeft)
            );
            WidgetSupport.drawTextCentered(canvas, clippedCourse, detailLeft, centerY - titleSize * 0.50f, titlePaint);

            String place = lesson.optString("place", "").trim();
            if (place.isEmpty()) place = "地点未定";
            String unitText = startUnit == endUnit
                ? ("第" + startUnit + "节")
                : ("第" + startUnit + "–" + endUnit + "节");
            String detailText = unitText + " · " + place + (lesson.optBoolean("is_experiment") ? " · 实验" : "");
            String clippedDetail = WidgetSupport.ellipsize(
                detailText,
                subPaint,
                Math.max(40f, detailRight - detailLeft)
            );
            WidgetSupport.drawTextCentered(canvas, clippedDetail, detailLeft, centerY + subSize * 0.78f, subPaint);

            top += cardH + gap;
        }

        if (footerPillH > 0f && total > visibleCount) {
            int remaining = total - visibleCount;
            RectF pill = new RectF(0, height - footerPillH, width, height);
            fillPaint.setColor(palette.cardFill);
            canvas.drawRoundRect(pill, footerPillH / 2f, footerPillH / 2f, fillPaint);

            Paint morePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            morePaint.setColor(palette.inkSecondary);
            morePaint.setTextSize(Math.max(12f, Math.min(17f, footerPillH * 0.52f)));
            morePaint.setTextAlign(Paint.Align.CENTER);
            WidgetSupport.drawTextCentered(
                canvas,
                "还有 " + remaining + " 节课 · 点击查看全部",
                pill.centerX(),
                pill.centerY(),
                morePaint
            );
        }

        return bitmap;
    }

    private static void drawEmptyCard(
        Canvas canvas,
        int width,
        int height,
        WidgetSupport.Palette palette
    ) {
        float strokeW = Math.max(1.2f, width / 560f);
        RectF card = new RectF(strokeW, strokeW, width - strokeW, height - strokeW);
        float radius = Math.max(16f, Math.min(26f, height * 0.14f));

        Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        fill.setColor(palette.cardFill);
        canvas.drawRoundRect(card, radius, radius, fill);

        Paint border = new Paint(Paint.ANTI_ALIAS_FLAG);
        border.setStyle(Paint.Style.STROKE);
        border.setStrokeWidth(strokeW);
        border.setColor(palette.cardBorder);
        canvas.drawRoundRect(card, radius, radius, border);

        Paint title = new Paint(Paint.ANTI_ALIAS_FLAG);
        title.setColor(palette.ink);
        title.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
        title.setTextSize(Math.max(20f, Math.min(30f, height * 0.12f)));
        title.setTextAlign(Paint.Align.CENTER);

        Paint sub = new Paint(Paint.ANTI_ALIAS_FLAG);
        sub.setColor(palette.inkMuted);
        sub.setTextSize(Math.max(13f, Math.min(20f, title.getTextSize() * 0.66f)));
        sub.setTextAlign(Paint.Align.CENTER);

        WidgetSupport.drawTextCentered(canvas, "今日无课", card.centerX(), card.centerY() - title.getTextSize() * 0.55f, title);
        WidgetSupport.drawTextCentered(canvas, "好好休息，或点击查看整周课表", card.centerX(), card.centerY() + sub.getTextSize() * 0.95f, sub);
    }

    private static int[] classifyStates(List<JSONObject> lessons) {
        int[] states = new int[lessons.size()];
        int nowMin = WidgetSupport.nowMinutes();
        boolean nextAssigned = false;
        for (int i = 0; i < lessons.size(); i++) {
            JSONObject lesson = lessons.get(i);
            int s = WidgetSupport.parseClockMinutes(lesson.optString("start_time", ""));
            int e = WidgetSupport.parseClockMinutes(lesson.optString("end_time", ""));
            if (s < 0 || e < 0) {
                states[i] = STATE_UPCOMING;
                continue;
            }
            if (nowMin >= s && nowMin <= e) {
                states[i] = STATE_ONGOING;
            } else if (nowMin > e) {
                states[i] = STATE_PAST;
            } else if (!nextAssigned) {
                states[i] = STATE_NEXT;
                nextAssigned = true;
            } else {
                states[i] = STATE_UPCOMING;
            }
        }
        return states;
    }

    private static RemoteViews baseViews(
        Context context,
        int id,
        WidgetSupport.Palette palette,
        String badgeText
    ) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_schedule);
        views.setInt(R.id.widget_schedule_root, "setBackgroundResource", palette.bgRes);
        views.setTextColor(R.id.widget_schedule_title, palette.ink);
        views.setInt(R.id.widget_schedule_badge, "setBackgroundResource", palette.badgeBlueRes);
        views.setTextColor(R.id.widget_schedule_badge, palette.primary);
        views.setTextViewText(R.id.widget_schedule_badge, badgeText);
        views.setInt(R.id.widget_schedule_refresh, "setBackgroundResource", palette.pillRes);
        views.setTextColor(R.id.widget_schedule_refresh, palette.primary);
        views.setTextColor(R.id.widget_schedule_status, palette.inkSecondary);
        views.setTextColor(R.id.widget_schedule_meta, palette.inkMuted);

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
}
