package cn.edu.zzu.life;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class MonitorReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        PendingResult pending = goAsync();
        new Thread(() -> {
            try {
                MonitorScheduler.check(
                    context.getApplicationContext(),
                    MonitorSettings.gradeEnabled(context),
                    MonitorSettings.energyEnabled(context),
                    true
                );
            } finally {
                pending.finish();
            }
        }, "zzu-monitor").start();
    }
}
