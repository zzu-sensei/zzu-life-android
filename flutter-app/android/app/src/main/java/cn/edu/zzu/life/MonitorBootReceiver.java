package cn.edu.zzu.life;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class MonitorBootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        MonitorScheduler.reschedule(context.getApplicationContext());
    }
}
