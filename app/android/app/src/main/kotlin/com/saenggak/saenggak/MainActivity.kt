package com.saenggak.saenggak

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createAlertChannel()
    }

    /**
     * The channel push alerts arrive in (named in the manifest), so the
     * phone's settings list them as "알림" rather than "Miscellaneous".
     * The fallback channel Firebase made in earlier builds is removed.
     */
    private fun createAlertChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            getString(R.string.alert_channel_id),
            getString(R.string.alert_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = getString(R.string.alert_channel_description) }
        manager.createNotificationChannel(channel)
        manager.deleteNotificationChannel("fcm_fallback_notification_channel")
    }
}
