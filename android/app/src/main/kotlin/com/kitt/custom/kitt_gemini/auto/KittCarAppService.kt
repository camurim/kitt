package com.kitt.custom.kitt_gemini.auto

import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Serviço nativo do Android Auto para o painel pessoal do K.I.T.T.
 *
 * Inicializa/reutiliza o [FlutterEngine] compartilhado via [KittEngineManager]
 * e mantém o [KittAutoForegroundService] ativo durante a sessão veicular para
 * que o Gemini Live e o AndroidAutoBridgeService não sejam suspensos com a tela
 * do smartphone apagada.
 */
class KittCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session {
        KittEngineManager.ensureEngine(applicationContext)
        KittAutoForegroundService.start(applicationContext)
        return KittCarSession()
    }
}

class KittCarSession : Session() {
    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                KittEngineManager.ensureEngine(carContext.applicationContext)
                KittEngineManager.keepResumedForCar()
                KittAutoForegroundService.start(carContext.applicationContext)
            }

            override fun onDestroy(owner: LifecycleOwner) {
                KittAutoForegroundService.stop(carContext.applicationContext)
            }
        })
    }

    override fun onCreateScreen(intent: Intent): Screen {
        KittEngineManager.ensureEngine(carContext.applicationContext)
        return KittMainScreen(carContext)
    }
}
