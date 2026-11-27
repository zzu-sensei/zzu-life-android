package cn.edu.zzu.life;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.RemoteViews;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.Locale;

public class EnergyWidgetProvider extends AppWidgetProvider {
    private static final String REFRESH = "cn.edu.zzu.life.REFRESH_ENERGY";

    private static final int[] ROW_IDS = {
        R.id.widget_energy_row_0,
        R.id.widget_energy_row_1,
        R.id.widget_energy_row_2,
    };
    private static final int[] LABEL_IDS = {
        R.id.widget_energy_label_0,
        R.id.widget_energy_label_1,
        R.id.widget_energy_label_2,
    };
    private static final int[] BADGE_IDS = {
        R.id.widget_energy_badge_0,
        R.id.widget_energy_badge_1,
        R.id.widget_energy_badge_2,
    };
    private static final int[] VAL_IDS = {
        R.id.widget_energy_val_0,
        R.id.widget_energy_val_1,
        R.id.widget_energy_val_2,
    };
    private static final int[] UNIT_IDS = {
        R.id.widget_energy_unit_0,
        R.id.widget_energy_unit_1,
        R.id.widget_energy_unit_2,
    };

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        if (ids == null || ids.length == 0) return;
        startUpdate(context, manager, ids, goAsync());
    }

    @Override
    public void onAppWidgetOptionsChanged(
        Context context,
        AppWidgetManager manager,
        int appWidgetId,
        Bundle newOptions
    ) {
        WidgetSupport.CachedData cached = WidgetSupport.loadCache(context, WidgetSupport.KEY_ENERGY);
        if (cached != null) {
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
            int[] ids = manager.getAppWidgetIds(new ComponentName(context, EnergyWidgetProvider.class));
            if (ids != null && ids.length > 0) {
                startUpdate(context, manager, ids, goAsync());
            }
        }
    }

    /** 仅从离线缓存重绘已放置的电量小组件，不发起网络请求（用于主题切换/前台同步/退出登录）。 */
    static void renderCached(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, EnergyWidgetProvider.class));
        if (ids == null || ids.length == 0) return;

        String[] stored = SessionStore.load(context);
        if (stored == null) {
            renderStatusForIds(context, manager, ids, "请先打开应用登录", "登录后可直接在桌面查看寝室电量");
            return;
        }
        WidgetSupport.CachedData cached = WidgetSupport.loadCache(context, WidgetSupport.KEY_ENERGY);
        if (cached == null) {
            renderStatusForIds(context, manager, ids, "点击右上角刷新获取电量", "照明与空调独立匹配");
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
        WidgetSupport.CachedData existing = WidgetSupport.loadCache(context, WidgetSupport.KEY_ENERGY);
        if (existing != null) {
            // 有缓存时保持现有卡片可见，仅把页脚改为刷新中，避免整个组件闪白。
            renderCachedForIds(context, manager, ids, existing, "正在刷新…");
        } else {
            renderStatusForIds(context, manager, ids, "正在匹配电表…", "照明与空调独立匹配");
        }

        WidgetSupport.runAsync(() -> {
            JSONObject result = null;
            String error = null;
            try {
                String[] stored = SessionStore.load(context);
                if (stored == null) throw new IllegalStateException("请先打开应用登录");
                result = PythonGateway.callWithSession(
                    new PythonGateway.ContextSession(stored), "get_energy"
                );
                if (!result.optBoolean("ok")) {
                    throw new IllegalStateException(result.optString("error", "电量查询失败"));
                }
                WidgetSupport.saveCache(context, WidgetSupport.KEY_ENERGY, result);
                try {
                    MonitorSettings.recordEnergySamples(
                        context,
                        result.optJSONArray("meter_list"),
                        System.currentTimeMillis()
                    );
                } catch (Exception ignored) {
                    // 采样失败不影响小组件显示。
                }
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
                WidgetSupport.CachedData fallback = loggedOut
                    ? null
                    : WidgetSupport.loadCache(context, WidgetSupport.KEY_ENERGY);
                if (fallback != null) {
                    renderCachedForIds(
                        context,
                        manager,
                        ids,
                        fallback,
                        "刷新失败 · 显示 " + WidgetSupport.formatTime(fallback.updatedAt) + " 数据"
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
            if (pending != null) {
                pending.finish();
            }
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
        JSONObject data = cached.payload;
        JSONArray meters = data.optJSONArray("meter_list");
        String room = data.optString("room", "").trim();
        double threshold = MonitorSettings.energyThreshold(context);
        boolean alertEnabled = MonitorSettings.energyEnabled(context);

        for (int id : ids) {
            RemoteViews views = baseViews(context, id, palette);
            if (!room.isEmpty()) {
                views.setViewVisibility(R.id.widget_energy_room, View.VISIBLE);
                views.setTextViewText(R.id.widget_energy_room, room);
            } else {
                views.setViewVisibility(R.id.widget_energy_room, View.GONE);
            }

            int shown = 0;
            boolean anyLow = false;
            if (meters != null) {
                for (int i = 0; i < meters.length() && shown < ROW_IDS.length; i++) {
                    JSONObject meter = meters.optJSONObject(i);
                    if (meter == null || meter.has("error")) continue;
                    String label = meter.optString("label", "寝室电表");
                    double remaining = meter.optDouble("remaining", Double.NaN);
                    boolean low = alertEnabled && !Double.isNaN(remaining) && remaining <= threshold;
                    if (low) anyLow = true;

                    views.setViewVisibility(ROW_IDS[shown], View.VISIBLE);
                    views.setInt(
                        ROW_IDS[shown],
                        "setBackgroundResource",
                        low ? palette.tileWarnRes : palette.tileRes
                    );
                    views.setTextViewText(LABEL_IDS[shown], label);
                    views.setTextColor(LABEL_IDS[shown], palette.ink);
                    views.setTextViewText(
                        VAL_IDS[shown],
                        Double.isNaN(remaining) ? "--" : String.format(Locale.CHINA, "%.2f", remaining)
                    );
                    views.setTextColor(VAL_IDS[shown], low ? palette.danger : palette.ink);
                    views.setTextColor(UNIT_IDS[shown], palette.inkMuted);

                    if (low) {
                        views.setViewVisibility(BADGE_IDS[shown], View.VISIBLE);
                        views.setInt(BADGE_IDS[shown], "setBackgroundResource", palette.badgeWarnRes);
                        views.setTextColor(BADGE_IDS[shown], palette.danger);
                    } else {
                        views.setViewVisibility(BADGE_IDS[shown], View.GONE);
                    }
                    shown++;
                }
            }
            for (int i = shown; i < ROW_IDS.length; i++) {
                views.setViewVisibility(ROW_IDS[i], View.GONE);
            }

            if (shown == 0) {
                views.setViewVisibility(R.id.widget_energy_cards, View.GONE);
                views.setViewVisibility(R.id.widget_energy_status, View.VISIBLE);
                views.setTextViewText(R.id.widget_energy_status, "没有查询到可用电表");
            } else {
                views.setViewVisibility(R.id.widget_energy_cards, View.VISIBLE);
                views.setViewVisibility(R.id.widget_energy_status, View.GONE);
            }

            String meta;
            if (footerOverride != null) {
                meta = footerOverride;
            } else {
                String warnText = alertEnabled
                    ? ("预警 " + WidgetSupport.formatThreshold(threshold) + " 度")
                    : "本机直连";
                if (anyLow) {
                    meta = "电量偏低 · " + warnText + " · 更新于 " + WidgetSupport.formatTime(cached.updatedAt);
                } else {
                    meta = warnText + " · 更新于 " + WidgetSupport.formatTime(cached.updatedAt);
                }
            }
            views.setTextViewText(R.id.widget_energy_meta, meta);
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
            RemoteViews views = baseViews(context, id, palette);
            views.setViewVisibility(R.id.widget_energy_room, View.GONE);
            views.setViewVisibility(R.id.widget_energy_cards, View.GONE);
            views.setViewVisibility(R.id.widget_energy_status, View.VISIBLE);
            views.setTextViewText(R.id.widget_energy_status, statusText);
            views.setTextViewText(R.id.widget_energy_meta, metaText);
            manager.updateAppWidget(id, views);
        }
    }

    private static RemoteViews baseViews(Context context, int id, WidgetSupport.Palette palette) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_energy);
        views.setInt(R.id.widget_energy_root, "setBackgroundResource", palette.bgRes);
        views.setTextColor(R.id.widget_energy_title, palette.ink);
        views.setInt(R.id.widget_energy_room, "setBackgroundResource", palette.badgeBlueRes);
        views.setTextColor(R.id.widget_energy_room, palette.primary);
        views.setInt(R.id.widget_energy_refresh, "setBackgroundResource", palette.pillRes);
        views.setTextColor(R.id.widget_energy_refresh, palette.primary);
        views.setTextColor(R.id.widget_energy_status, palette.inkSecondary);
        views.setTextColor(R.id.widget_energy_meta, palette.inkMuted);

        Intent refresh = new Intent(context, EnergyWidgetProvider.class).setAction(REFRESH);
        views.setOnClickPendingIntent(
            R.id.widget_energy_refresh,
            PendingIntent.getBroadcast(
                context,
                id,
                refresh,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            )
        );
        Intent open = new Intent(context, MainActivity.class);
        views.setOnClickPendingIntent(
            R.id.widget_energy_root,
            PendingIntent.getActivity(
                context,
                id + 20000,
                open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            )
        );
        return views;
    }
}
