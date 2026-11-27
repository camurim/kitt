package net.carlosamorim.kitturbo.auto

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import net.carlosamorim.kitturbo.MainActivity
import net.carlosamorim.kitturbo.R

/**
 * Foreground Service mantido ativo quando o K.i.t.Turbo está em segundo plano
 * (após pressionar Voltar/Home) ou conectado ao Android Auto.
 *
 * Exibe uma notificação persistente avisando que o K.I.T.T. segue ativo, com:
 * - Toque na notificação -> reabre a MainActivity
 * - Botão "ENCERRAR" -> destrói o engine e finaliza o aplicativo permanentemente
 */
class KittAutoForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHUTDOWN -> {
                isShuttingDown = true
                currentMode = null
                MainActivity.finishIfActive()
                KittEngineManager.destroyEngine()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                Handler(Looper.getMainLooper()).postDelayed({
                    Process.killProcess(Process.myPid())
                }, 180L)
                return START_NOT_STICKY
            }

            ACTION_STOP -> {
                currentMode = null
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }

        val mode = intent?.getStringExtra(EXTRA_MODE) ?: MODE_ANDROID_AUTO
        // Se o Android Auto já estiver ativo, preserva o modo android_auto
        if (currentMode != MODE_ANDROID_AUTO || mode == MODE_ANDROID_AUTO) {
            currentMode = mode
        }

        KittEngineManager.ensureEngine(applicationContext)
        KittEngineManager.keepResumedForCar()

        val notification = buildNotification(currentMode ?: MODE_BACKGROUND)
        val hasMicPerm = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && hasMicPerm) {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
            try {
                startForeground(NOTIFICATION_ID, notification)
            } catch (_: Exception) {
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "K.i.t.Turbo • Segundo Plano",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description =
                    "Informa quando o K.i.t.Turbo está ativo em segundo plano ou no Android Auto, com opção de encerramento permanente."
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(mode: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            100,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val shutdownIntent = Intent(this, KittAutoForegroundService::class.java).apply {
            action = ACTION_SHUTDOWN
        }
        val shutdownPendingIntent = PendingIntent.getService(
            this,
            101,
            shutdownIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = if (mode == MODE_ANDROID_AUTO) {
            "K.i.t.Turbo • Android Auto"
        } else {
            "K.i.t.Turbo em segundo plano"
        }
        val text = if (mode == MODE_ANDROID_AUTO) {
            "Conectado ao Android Auto • Toque para abrir ou encerrar"
        } else {
            "O K.I.T.T. continua ativo. Toque para voltar ou encerre abaixo."
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "ENCERRAR",
                shutdownPendingIntent,
            )
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "kitt_auto_session"
        private const val NOTIFICATION_ID = 1982
        private const val ACTION_START = "net.carlosamorim.kitturbo.auto.START"
        private const val ACTION_STOP = "net.carlosamorim.kitturbo.auto.STOP"
        private const val ACTION_SHUTDOWN = "net.carlosamorim.kitturbo.auto.SHUTDOWN"
        private const val EXTRA_MODE = "mode"
        const val MODE_ANDROID_AUTO = "android_auto"
        const val MODE_BACKGROUND = "background"

        @Volatile
        var isShuttingDown: Boolean = false
            private set

        @Volatile
        private var currentMode: String? = null

        fun isBackgroundOnly(): Boolean = currentMode == MODE_BACKGROUND

        fun start(context: Context, mode: String = MODE_ANDROID_AUTO) {
            if (isShuttingDown) return
            val intent = Intent(context, KittAutoForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_MODE, mode)
            }
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (_: Exception) {
            }
        }

        fun stop(context: Context) {
            currentMode = null
            val intent = Intent(context, KittAutoForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.stopService(intent)
            } catch (_: Exception) {
            }
        }
    }
}
