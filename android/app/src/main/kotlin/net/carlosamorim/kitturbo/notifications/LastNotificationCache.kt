package net.carlosamorim.kitturbo.notifications

import android.app.PendingIntent
import android.app.RemoteInput

/**
 * Dados em memória da última transmissão válida interceptada pelo
 * [KittNotificationListenerService], incluindo os objetos necessários para
 * resposta rápida direta via [RemoteInput] e [PendingIntent].
 */
data class CachedNotificationReply(
    val notificationKey: String,
    val packageName: String,
    val appName: String,
    val senderTitle: String,
    val messageText: String,
    val timestamp: Long,
    val actionIntent: PendingIntent?,
    val remoteInput: RemoteInput?,
) {
    val supportsDirectReply: Boolean
        get() = actionIntent != null && remoteInput != null
}

/**
 * Cache em memória da última notificação autorizada recebida no dispositivo.
 */
object LastNotificationCache {
    @Volatile
    var latest: CachedNotificationReply? = null
        private set

    fun update(entry: CachedNotificationReply) {
        latest = entry
    }

    fun clear() {
        latest = null
    }
}
