package net.carlosamorim.kitturbo.auto

import android.content.Context
import android.os.Handler
import android.os.Looper
import net.carlosamorim.kitturbo.notifications.KittNotificationBridge
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Gerencia uma instância única e compartilhada do [FlutterEngine] entre
 * a [MainActivity] (UI mobile) e o [KittCarAppService] (Android Auto).
 *
 * Permite que o serviço da Gemini Live API e o `AndroidAutoBridgeService`
 * rodem em modo headless mesmo com a tela do smartphone apagada no bolso/console.
 */
object KittEngineManager {
    const val ENGINE_ID = "kitt_shared_engine"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Synchronized
    fun ensureEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        val existing = cache.get(ENGINE_ID)
        if (existing != null) {
            KittAutoBridge.attach(existing.dartExecutor.binaryMessenger)
            KittNotificationBridge.attach(context.applicationContext, existing.dartExecutor.binaryMessenger)
            return existing
        }

        val appContext = context.applicationContext
        val engine = FlutterEngine(appContext)
        KittAutoBridge.attach(engine.dartExecutor.binaryMessenger)
        KittNotificationBridge.attach(appContext, engine.dartExecutor.binaryMessenger)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        engine.lifecycleChannel.appIsResumed()
        cache.put(ENGINE_ID, engine)
        return engine
    }

    /**
     * Garante que o motor Flutter permaneça no estado `resumed` enquanto o
     * Android Auto estiver conectado, evitando suspensão de timers/WebSockets.
     */
    fun keepResumedForCar() {
        mainHandler.post {
            FlutterEngineCache.getInstance()
                .get(ENGINE_ID)
                ?.lifecycleChannel
                ?.appIsResumed()
        }
    }

    /**
     * Destrói o FlutterEngine compartilhado durante o encerramento permanente do app.
     */
    @Synchronized
    fun destroyEngine() {
        val cache = FlutterEngineCache.getInstance()
        val engine = cache.get(ENGINE_ID)
        cache.remove(ENGINE_ID)
        if (engine != null) {
            mainHandler.post {
                try {
                    engine.destroy()
                } catch (_: Exception) {
                }
            }
        }
    }
}
