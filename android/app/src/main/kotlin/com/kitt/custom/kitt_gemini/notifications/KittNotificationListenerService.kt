package com.kitt.custom.kitt_gemini.notifications

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Serviço nativo Android que intercepta notificações recebidas no dispositivo,
 * extrai a ação de resposta direta ([RemoteInput] + [PendingIntent]), armazena
 * no [LastNotificationCache] e encaminha ao [KittNotificationBridge].
 */
class KittNotificationListenerService : NotificationListenerService() {
    private var lastSignature: String = ""
    private var lastTimestampMs: Long = 0L

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        if (pkg == applicationContext.packageName) return

        val notification = sbn.notification ?: return
        val flags = notification.flags
        // Ignora notificações persistentes (ex.: players/foreground) e resumos de grupo.
        if ((flags and Notification.FLAG_ONGOING_EVENT) != 0 ||
            (flags and Notification.FLAG_GROUP_SUMMARY) != 0
        ) {
            return
        }

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        val regularText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val text = bigText.ifEmpty { regularText }

        if (title.isEmpty() || text.isEmpty()) return

        // Deduplicação curta (4s) para evitar leituras repetidas quando apps atualizam a mesma notificação.
        val now = System.currentTimeMillis()
        val signature = "$pkg|$title|$text"
        if (signature == lastSignature && (now - lastTimestampMs) < 4000L) {
            return
        }
        lastSignature = signature
        lastTimestampMs = now

        val appName = try {
            val info = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(info)?.toString()?.takeIf { it.isNotBlank() } ?: pkg
        } catch (_: Exception) {
            pkg
        }

        val directReply = extractDirectReplyAction(notification)
        val notificationKey = sbn.key ?: "$pkg:${sbn.id}"

        // Armazena em memória a última transmissão válida de apps autorizados.
        if (KittNotificationBridge.isPackageAllowedForCache(pkg)) {
            LastNotificationCache.update(
                CachedNotificationReply(
                    notificationKey = notificationKey,
                    packageName = pkg,
                    appName = appName,
                    senderTitle = title,
                    messageText = text,
                    timestamp = sbn.postTime,
                    actionIntent = directReply?.first,
                    remoteInput = directReply?.second,
                )
            )
        }

        KittNotificationBridge.dispatchNotification(
            notificationKey = notificationKey,
            packageName = pkg,
            appName = appName,
            title = title,
            text = text,
            timestamp = sbn.postTime,
            canReply = directReply != null,
        )
    }

    /**
     * Procura uma [Notification.Action] com [RemoteInput] anexado (usada para
     * resposta rápida na barra de notificações do WhatsApp, Telegram, SMS, etc.),
     * checando tanto `notification.actions` quanto `WearableExtender.actions`.
     */
    private fun extractDirectReplyAction(
        notification: Notification,
    ): Pair<PendingIntent, RemoteInput>? {
        val standardActions = notification.actions
        if (standardActions != null) {
            findReplyInActions(standardActions)?.let { return it }
        }

        val wearableActions = Notification.WearableExtender(notification).actions
        if (wearableActions.isNotEmpty()) {
            findReplyInActions(wearableActions.toTypedArray())?.let { return it }
        }

        return null
    }

    private fun findReplyInActions(
        actions: Array<Notification.Action>,
    ): Pair<PendingIntent, RemoteInput>? {
        var fallback: Pair<PendingIntent, RemoteInput>? = null
        for (action in actions) {
            val intent = action.actionIntent ?: continue
            val inputs = action.remoteInputs ?: continue
            for (input in inputs) {
                if (input.allowFreeFormInput) {
                    return Pair(intent, input)
                }
                if (fallback == null) {
                    fallback = Pair(intent, input)
                }
            }
        }
        return fallback
    }
}
