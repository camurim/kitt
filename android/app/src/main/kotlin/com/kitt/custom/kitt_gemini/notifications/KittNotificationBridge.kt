package com.kitt.custom.kitt_gemini.notifications

import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * Ponte singleton entre o [KittNotificationListenerService] nativo e o Flutter
 * via MethodChannel (`com.kitt.project/notifications`).
 */
object KittNotificationBridge {
    const val CHANNEL_NAME = "com.kitt.project/notifications"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val allowedPackages: MutableSet<String> = ConcurrentHashMap.newKeySet()

    @Volatile
    private var hasSyncedAllowedPackages: Boolean = false

    @Volatile
    private var channel: MethodChannel? = null

    fun isPackageAllowedForCache(packageName: String): Boolean {
        // Se o Flutter já sincronizou a lista de apps autorizados, respeita o filtro exato.
        // Caso contrário (ex.: boot antes do sync), permite cachear para não perder a mensagem.
        if (!hasSyncedAllowedPackages) return true
        return allowedPackages.contains(packageName)
    }

    fun attach(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        val methodChannel = MethodChannel(messenger, CHANNEL_NAME)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationAccessGranted" -> {
                    val enabled = NotificationManagerCompat
                        .getEnabledListenerPackages(appContext)
                        .contains(appContext.packageName)
                    result.success(enabled)
                }

                "openNotificationAccessSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        appContext.startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }

                "syncAllowedPackages" -> {
                    val pkgs = call.argument<List<String>>("packages") ?: emptyList()
                    allowedPackages.clear()
                    allowedPackages.addAll(pkgs)
                    hasSyncedAllowedPackages = true
                    result.success(true)
                }

                "getLastNotificationInfo" -> {
                    val cached = LastNotificationCache.latest
                    if (cached == null) {
                        result.success(null)
                    } else {
                        result.success(
                            mapOf(
                                "notificationKey" to cached.notificationKey,
                                "packageName" to cached.packageName,
                                "appName" to cached.appName,
                                "senderTitle" to cached.senderTitle,
                                "messageText" to cached.messageText,
                                "timestamp" to cached.timestamp,
                                "canReply" to cached.supportsDirectReply,
                            )
                        )
                    }
                }

                "replyToLastNotification" -> {
                    val messageText = when (val raw = call.arguments) {
                        is String -> raw
                        is Map<*, *> -> raw["messageText"] as? String
                        else -> call.argument<String>("messageText")
                    }?.trim().orEmpty()

                    result.success(sendDirectReply(appContext, messageText))
                }

                else -> result.notImplemented()
            }
        }
        channel = methodChannel
    }

    private fun sendDirectReply(context: Context, messageText: String): Map<String, Any?> {
        if (messageText.isEmpty()) {
            return mapOf(
                "success" to false,
                "error" to "empty_message",
                "message" to "O texto da resposta não pode estar vazio.",
            )
        }

        val cached = LastNotificationCache.latest
            ?: return mapOf(
                "success" to false,
                "error" to "no_recent_notification",
                "message" to "Nenhuma transmissão recente disponível para responder.",
            )

        val actionIntent = cached.actionIntent
        val remoteInput = cached.remoteInput
        if (actionIntent == null || remoteInput == null) {
            return mapOf(
                "success" to false,
                "error" to "reply_not_supported",
                "appName" to cached.appName,
                "sender" to cached.senderTitle,
                "message" to "${cached.appName} não suporta resposta rápida direta nesta notificação.",
            )
        }

        return try {
            val replyIntent = Intent()
            val resultsBundle = Bundle().apply {
                putCharSequence(remoteInput.resultKey, messageText)
            }
            RemoteInput.addResultsToIntent(arrayOf(remoteInput), replyIntent, resultsBundle)
            actionIntent.send(context, 0, replyIntent)
            mapOf(
                "success" to true,
                "notificationKey" to cached.notificationKey,
                "packageName" to cached.packageName,
                "appName" to cached.appName,
                "sender" to cached.senderTitle,
                "sentMessage" to messageText,
                "message" to "Resposta enviada para ${cached.senderTitle} via ${cached.appName}.",
            )
        } catch (e: PendingIntent.CanceledException) {
            mapOf(
                "success" to false,
                "error" to "pending_intent_canceled",
                "message" to "A ação de resposta expirou ou foi cancelada pelo sistema.",
            )
        } catch (e: Exception) {
            mapOf(
                "success" to false,
                "error" to "reply_failed",
                "message" to "Falha ao enviar resposta rápida: ${e.message}",
            )
        }
    }

    fun dispatchNotification(
        notificationKey: String,
        packageName: String,
        appName: String,
        title: String,
        text: String,
        timestamp: Long,
        canReply: Boolean,
    ) {
        val activeChannel = channel ?: return
        mainHandler.post {
            activeChannel.invokeMethod(
                "onNotificationPosted",
                mapOf(
                    "notificationKey" to notificationKey,
                    "packageName" to packageName,
                    "appName" to appName,
                    "title" to title,
                    "text" to text,
                    "timestamp" to timestamp,
                    "canReply" to canReply,
                ),
            )
        }
    }
}
