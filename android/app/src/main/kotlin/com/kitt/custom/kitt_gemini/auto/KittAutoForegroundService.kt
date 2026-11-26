package com.kitt.custom.kitt_gemini.auto

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.kitt.custom.kitt_gemini.R

/**
 * Foreground Service leve mantido ativo enquanto o celular está conectado ao
 * Android Auto, impedindo que o Android suspenda o WebSocket da Gemini Live API
 * ou bloqueie o microfone quando a tela do smartphone está apagada.
 */
class KittAutoForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        KittEngineManager.ensureEngine(applicationContext)
        KittEngineManager.keepResumedForCar()

        val notification = buildNotification()
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
            // Fallback seguro caso o SO restrinja o tipo microphone sem permissão prévia.
            try {
                startForeground(NOTIFICATION_ID, notification)
            } catch (_: Exception) {
                stopSelf()
            }
        }

        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "K.I.T.T. Android Auto",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Mantém a sessão Gemini Live e os comandos do K.I.T.T. ativos no Android Auto."
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("K.I.T.T. Systems Activated")
            .setContentText("Conectado ao Android Auto • Gemini Live ativo")
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "kitt_auto_session"
        private const val NOTIFICATION_ID = 1982
        private const val ACTION_START = "com.kitt.custom.kitt_gemini.auto.START"
        private const val ACTION_STOP = "com.kitt.custom.kitt_gemini.auto.STOP"

        fun start(context: Context) {
            val intent = Intent(context, KittAutoForegroundService::class.java).apply {
                action = ACTION_START
            }
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (_: Exception) {
                // Em dispositivos com restrições de background, o engine ainda roda no processo do CarAppService.
            }
        }

        fun stop(context: Context) {
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
