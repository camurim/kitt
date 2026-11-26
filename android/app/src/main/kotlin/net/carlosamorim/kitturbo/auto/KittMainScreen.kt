package net.carlosamorim.kitturbo.auto

import androidx.annotation.DrawableRes
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.GridItem
import androidx.car.app.model.GridTemplate
import androidx.car.app.model.ItemList
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import net.carlosamorim.kitturbo.R

/**
 * Tela principal do K.I.T.T. no Android Auto baseada em GridTemplate com
 * 6 comandos táticos em ícones vetoriais HUD (vermelho/âmbar) integrados ao Flutter.
 */
class KittMainScreen(carContext: CarContext) : Screen(carContext) {
    private val stateListener: () -> Unit = {
        invalidate()
    }

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                KittAutoBridge.addStateListener(stateListener)
                invalidate()
            }

            override fun onStop(owner: LifecycleOwner) {
                KittAutoBridge.removeStateListener(stateListener)
            }
        })
    }

    override fun onGetTemplate(): Template {
        val currentState = KittAutoBridge.state
        val statusText = if (KittAutoBridge.isFlutterAttached()) {
            currentState.statusSubtitle
        } else {
            "OFFLINE - ABRA O APP KITT"
        }

        val gridList = ItemList.Builder()
            .addItem(
                buildHudItem(
                    title = "VOZ / INTERCOM",
                    subtitle = if (currentState.isListening) "OUVINDO..." else "GEMINI LIVE",
                    iconRes = R.drawable.ic_kitt_auto_voice,
                    command = "toggle_voice",
                )
            )
            .addItem(
                buildHudItem(
                    title = "PURSUIT MODE",
                    subtitle = if (currentState.driveMode == "pursuit") "ENGAGED" else "INATIVO",
                    iconRes = R.drawable.ic_kitt_auto_pursuit,
                    command = "toggle_pursuit",
                )
            )
            .addItem(
                buildHudItem(
                    title = "SURVEILLANCE",
                    subtitle = if (currentState.driveMode == "surveillance") "RADAR ATIVO" else "INATIVO",
                    iconRes = R.drawable.ic_kitt_auto_surveillance,
                    command = "toggle_surveillance",
                )
            )
            .addItem(
                buildHudItem(
                    title = "TURBO BOOST",
                    subtitle = if (currentState.activeGadget == "turbo_boost") "MAX THRUST" else "PROPULSÃO",
                    iconRes = R.drawable.ic_kitt_auto_turbo,
                    command = "trigger_turbo_boost",
                )
            )
            .addItem(
                buildHudItem(
                    title = "OIL SLICK",
                    subtitle = if (currentState.activeGadget == "oil_slick") "DEPLOYED" else "ÓLEO NA PISTA",
                    iconRes = R.drawable.ic_kitt_auto_oil,
                    command = "trigger_oil_slick",
                )
            )
            .addItem(
                buildHudItem(
                    title = "SMOKE SCREEN",
                    subtitle = if (currentState.activeGadget == "smoke_screen") "ACTIVE" else "FUMAÇA",
                    iconRes = R.drawable.ic_kitt_auto_smoke,
                    command = "trigger_smoke_screen",
                )
            )
            .build()

        return GridTemplate.Builder()
            .setTitle("K.i.t.Turbo • $statusText")
            .setHeaderAction(Action.APP_ICON)
            .setSingleList(gridList)
            .build()
    }

    private fun buildHudItem(
        title: String,
        subtitle: String,
        @DrawableRes iconRes: Int,
        command: String,
    ): GridItem {
        val icon = CarIcon.Builder(
            IconCompat.createWithResource(carContext, iconRes)
        ).build()

        return GridItem.Builder()
            .setTitle(title)
            .setText(subtitle)
            .setImage(icon, GridItem.IMAGE_TYPE_ICON)
            .setOnClickListener {
                val dispatched = KittAutoBridge.dispatchCommand(command)
                if (!dispatched) {
                    CarToast.makeText(
                        carContext,
                        "Abra o K.I.T.T. no smartphone para ativar a sessão.",
                        CarToast.LENGTH_SHORT,
                    ).show()
                }
            }
            .build()
    }
}
