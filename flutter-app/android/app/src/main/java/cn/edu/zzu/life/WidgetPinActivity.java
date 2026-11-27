package cn.edu.zzu.life;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.widget.Toast;

/**
 * 桌面长按应用图标后的「添加小部件」快捷入口。
 *
 * 轻量原生透明弹窗，无需启动 Flutter 引擎即可直接唤起系统小部件固定弹窗，
 * 并兼容 HyperOS / MIUI 桌面快捷方式权限引导。
 */
public class WidgetPinActivity extends Activity {
    private static final String[] OPTIONS = {
        "今日课表 · 当天课程日程卡片",
        "整周课表 · 整周彩色课程表",
        "寝室电量 · 空调与照明余量",
    };

    private static final Class<?>[] PROVIDERS = {
        ScheduleWidgetProvider.class,
        WeekScheduleWidgetProvider.class,
        EnergyWidgetProvider.class,
    };

    private boolean pendingPin = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        int dialogTheme = WidgetSupport.isDark(this)
            ? android.R.style.Theme_DeviceDefault_Dialog_Alert
            : android.R.style.Theme_DeviceDefault_Light_Dialog_Alert;

        new AlertDialog.Builder(this, dialogTheme)
            .setTitle("添加桌面小部件")
            .setItems(OPTIONS, (dialog, which) -> pinWidget(PROVIDERS[which]))
            .setNeutralButton("开启桌面权限", (dialog, which) -> openPermissionSettings())
            .setNegativeButton("取消", (dialog, which) -> finish())
            .setOnCancelListener(dialog -> finish())
            .setOnDismissListener(dialog -> {
                if (!pendingPin && !isFinishing()) {
                    finish();
                }
            })
            .show();
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (pendingPin && !isFinishing()) {
            finish();
        }
    }

    private void openPermissionSettings() {
        pendingPin = false;
        Toast.makeText(
            this,
            "请在「权限管理」中开启「桌面快捷方式」后重试",
            Toast.LENGTH_LONG
        ).show();
        Intent intent = new Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", getPackageName(), null)
        );
        startActivity(intent);
        finish();
    }

    private void pinWidget(Class<?> providerClass) {
        pendingPin = true;
        AppWidgetManager manager = AppWidgetManager.getInstance(this);
        boolean supported = manager != null && manager.isRequestPinAppWidgetSupported();
        if (supported) {
            PendingIntent callback = PendingIntent.getBroadcast(
                this,
                providerClass.hashCode() & 0x7FFF,
                new Intent(this, providerClass).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            boolean requested = manager.requestPinAppWidget(
                new ComponentName(this, providerClass),
                null,
                callback
            );
            if (requested) {
                Toast.makeText(
                    this,
                    "已请求添加到桌面；若无弹窗请先点击「开启桌面权限」开启「桌面快捷方式」，或在桌面双指捏合 → Android 小部件添加",
                    Toast.LENGTH_LONG
                ).show();
            } else {
                Toast.makeText(
                    this,
                    "未能唤起系统添加弹窗，请在桌面双指捏合 → Android 小部件 → 郑大生活助手",
                    Toast.LENGTH_LONG
                ).show();
            }
        } else {
            Toast.makeText(
                this,
                "当前桌面不支持一键添加，请在桌面双指捏合 → Android 小部件 → 郑大生活助手",
                Toast.LENGTH_LONG
            ).show();
        }
        getWindow().getDecorView().postDelayed(() -> {
            if (!isFinishing()) {
                finish();
            }
        }, 1200);
    }
}
