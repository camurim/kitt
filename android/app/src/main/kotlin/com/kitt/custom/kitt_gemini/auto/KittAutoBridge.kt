package com.kitt.custom.kitt_gemini.auto

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Snapshot do estado atual do K.I.T.T. sincronizado entre Flutter e Android Auto.
 */
data class AutoKittState(
    val statusSubtitle: String = "ONLINE - AGUARDANDO COMANDO",
    val isListening: Boolean = false,
    val driveMode: String = "normal",
    val activeGadget: String? = null,
    val isConnected: Boolean = false,
)

/**
 * Ponte singleton entre o MethodChannel do Flutter (`com.kitt.project/android_auto`)
 * e a interface nativa do Android Auto (`KittMainScreen`).
 */
object KittAutoBridge {
    const val CHANNEL_NAME = "com.kitt.project/android_auto"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArraySet<() -> Unit>()

    @Volatile
    private var channel: MethodChannel? = null

    @Volatile
    var state: AutoKittState = AutoKittState()
        private set

    fun attach(messenger: BinaryMessenger) {
        val methodChannel = MethodChannel(messenger, CHANNEL_NAME)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateState" -> {
                    val subtitle = call.argument<String>("statusSubtitle")
                        ?.takeIf { it.isNotBlank() }
                        ?: state.statusSubtitle
                    val isListening = call.argument<Boolean>("isListening") ?: false
                    val driveMode = call.argument<String>("driveMode") ?: "normal"
                    val activeGadget = call.argument<String>("activeGadget")
                    val isConnected = call.argument<Boolean>("isConnected") ?: false

                    state = AutoKittState(
                        statusSubtitle = subtitle,
                        isListening = isListening,
                        driveMode = driveMode,
                        activeGadget = activeGadget,
                        isConnected = isConnected,
                    )
                    notifyListeners()
                    result.success(true)
                }

                "getCurrentState" -> {
                    result.success(
                        mapOf(
                            "statusSubtitle" to state.statusSubtitle,
                            "isListening" to state.isListening,
                            "driveMode" to state.driveMode,
                            "activeGadget" to state.activeGadget,
                            "isConnected" to state.isConnected,
                        )
                    )
                }

                else -> result.notImplemented()
            }
        }
        channel = methodChannel
        notifyListeners()
    }

    fun isFlutterAttached(): Boolean = channel != null

    /**
     * Envia um comando acionado pelo motorista no Android Auto para o Dart.
     * Retorna `true` se o Flutter estiver ativo e pronto para receber o comando.
     */
    fun dispatchCommand(command: String): Boolean {
        val activeChannel = channel ?: return false
        mainHandler.post {
            activeChannel.invokeMethod(
                "onAutoCommand",
                mapOf("command" to command),
            )
        }
        return true
    }

    fun addStateListener(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun removeStateListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    private fun notifyListeners() {
        mainHandler.post {
            for (listener in listeners) {
                listener()
            }
        }
    }
}
