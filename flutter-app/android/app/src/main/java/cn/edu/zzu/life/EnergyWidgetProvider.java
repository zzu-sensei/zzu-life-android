package cn.edu.zzu.life;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.widget.RemoteViews;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.concurrent.Executors;

public class EnergyWidgetProvider extends AppWidgetProvider {
    private static final String REFRESH = "cn.edu.zzu.life.REFRESH_ENERGY";

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        startUpdate(context, manager, ids, goAsync());
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
            loading.setTextViewText(R.id.widget_energy_value, "正在匹配电表…");
            manager.updateAppWidget(id, loading);
        }
        Executors.newSingleThreadExecutor().execute(() -> {
            String value;
            String meta;
            boolean warning = false;
            try {
                String[] stored = SessionStore.load(context);
                if (stored == null) throw new IllegalStateException("请先打开应用登录");
                JSONObject result = PythonGateway.callWithSession(
                    new PythonGateway.ContextSession(stored), "get_energy"
                );
                if (!result.optBoolean("ok")) throw new IllegalStateException(result.optString("error"));
                JSONArray meters = result.optJSONArray("meter_list");
                StringBuilder text = new StringBuilder();
                double threshold = MonitorSettings.energyThreshold(context);
                boolean alertEnabled = MonitorSettings.energyEnabled(context);
                for (int index = 0; meters != null && index < Math.min(3, meters.length()); index++) {
                    JSONObject meter = meters.optJSONObject(index);
                    if (meter == null || meter.has("error")) continue;
                    double remaining = meter.optDouble("remaining", Double.NaN);
                    if (text.length() > 0) text.append("\n");
                    text.append(meter.optString("label", "寝室电表"))
                        .append("：")
                        .append(Double.isNaN(remaining) ? "--" : String.format("%.2f", remaining))
                        .append(" 度");
                    if (alertEnabled && !Double.isNaN(remaining) && remaining <= threshold) {
                        warning = true;
                    }
                }
                value = text.length() == 0 ? "没有查询到可用电表" : text.toString();
                meta = "寝室 " + result.optString("room") +
                    (alertEnabled ? " · 预警 " + String.format("%.0f", threshold) + " 度" : " · 本机直连");
                if (warning) value = "⚠ 电量不足\n" + value;
            } catch (Exception error) {
                value = "刷新失败\n" + safe(error.getMessage());
                meta = "点按刷新或打开应用重新登录";
            } finally {
                // Updated below so every placed instance receives the same snapshot.
            }
            for (int id : ids) {
                RemoteViews views = baseViews(context, id);
                views.setTextViewText(R.id.widget_energy_value, value);
                views.setTextViewText(R.id.widget_energy_meta, meta);
                views.setTextColor(
                    R.id.widget_energy_value,
                    warning ? Color.rgb(255, 158, 148) : Color.rgb(245, 251, 248)
                );
                manager.updateAppWidget(id, views);
            }
            if (pending != null) {
                pending.finish();
            }
        });
    }

    private static RemoteViews baseViews(Context context, int id) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_energy);
        Intent refresh = new Intent(context, EnergyWidgetProvider.class).setAction(REFRESH);
        views.setOnClickPendingIntent(R.id.widget_energy_refresh, PendingIntent.getBroadcast(
            context, id, refresh, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        ));
        Intent open = new Intent(context, MainActivity.class);
        views.setOnClickPendingIntent(R.id.widget_energy_root, PendingIntent.getActivity(
            context, id + 20000, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        ));
        return views;
    }

    private static String safe(String value) {
        return value == null || value.isEmpty() ? "未知错误" : value;
    }
}
