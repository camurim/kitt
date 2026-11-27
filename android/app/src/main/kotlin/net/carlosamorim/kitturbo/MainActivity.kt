package net.carlosamorim.kitturbo

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import net.carlosamorim.kitturbo.auto.KittAutoBridge
import net.carlosamorim.kitturbo.auto.KittAutoForegroundService
import net.carlosamorim.kitturbo.auto.KittEngineManager
import net.carlosamorim.kitturbo.notifications.KittNotificationBridge
import java.io.ByteArrayOutputStream
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {
    private val auxAppsChannel = "net.carlosamorim.kitturbo/aux_apps"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentActivity = WeakReference(this)
        requestNotificationPermissionIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        currentActivity = WeakReference(this)
        // Ao voltar para a tela do app, oculta a notificação de "segundo plano"
        if (KittAutoForegroundService.isBackgroundOnly()) {
            KittAutoForegroundService.stop(applicationContext)
        }
    }

    override fun onStop() {
        super.onStop()
        // Quando o app vai para segundo plano (Home ou Voltar) e não está encerrando
        // permanentemente, exibe a notificação persistente com o botão "ENCERRAR".
        if (!isChangingConfigurations && !KittAutoForegroundService.isShuttingDown) {
            KittAutoForegroundService.start(
                applicationContext,
                mode = KittAutoForegroundService.MODE_BACKGROUND,
            )
        }
    }

    override fun onDestroy() {
        if (currentActivity?.get() === this) {
            currentActivity = null
        }
        super.onDestroy()
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQ_POST_NOTIFICATIONS,
                )
            }
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        return KittEngineManager.ensureEngine(context)
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        // Preserva o FlutterEngine compartilhado quando a tela do celular apaga ou
        // a Activity é fechada, mantendo a sessão Android Auto / segundo plano ativa.
        return false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        KittAutoBridge.attach(flutterEngine.dartExecutor.binaryMessenger)
        KittNotificationBridge.attach(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, auxAppsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> {
                        val includeSystem = call.argument<Boolean>("includeSystemApps") ?: false
                        Thread {
                            try {
                                val apps = queryLaunchableApps(includeSystem)
                                runOnUiThread { result.success(apps) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("QUERY_ERROR", e.message, null)
                                }
                            }
                        }.start()
                    }

                    "launchApp" -> {
                        val pkg = call.argument<String>("packageName")?.trim().orEmpty()
                        if (pkg.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = packageManager.getLaunchIntentForPackage(pkg)
                            if (intent != null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun queryLaunchableApps(includeSystemApps: Boolean): List<Map<String, Any?>> {
        val pm = packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolved = pm.queryIntentActivities(mainIntent, 0)
        val seenPackages = HashSet<String>()
        val output = ArrayList<Map<String, Any?>>()

        for (ri in resolved) {
            val activityInfo = ri.activityInfo ?: continue
            val pkg = activityInfo.packageName ?: continue
            if (pkg == applicationContext.packageName || !seenPackages.add(pkg)) {
                continue
            }

            val appInfo = activityInfo.applicationInfo
            val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (!includeSystemApps && isSystem) {
                continue
            }

            val label = ri.loadLabel(pm)?.toString()?.takeIf { it.isNotBlank() } ?: pkg
            val iconBytes = try {
                drawableToPngBytes(ri.loadIcon(pm))
            } catch (_: Exception) {
                null
            }

            output.add(
                mapOf(
                    "name" to label,
                    "packageName" to pkg,
                    "icon" to iconBytes,
                )
            )
        }
        return output
    }

    private fun drawableToPngBytes(drawable: Drawable): ByteArray {
        val size = 64
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        } else {
            Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { bmp ->
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
            }
        }
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 85, out)
        return out.toByteArray()
    }

    companion object {
        private const val REQ_POST_NOTIFICATIONS = 2082

        @Volatile
        private var currentActivity: WeakReference<MainActivity>? = null

        fun finishIfActive() {
            currentActivity?.get()?.let { activity ->
                activity.runOnUiThread {
                    try {
                        activity.finishAndRemoveTask()
                    } catch (_: Exception) {
                        activity.finish()
                    }
                }
            }
        }
    }
}
