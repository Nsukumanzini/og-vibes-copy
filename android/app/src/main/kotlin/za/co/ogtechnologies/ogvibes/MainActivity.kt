package za.co.ogtechnologies.ogvibes

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val sosDisplayChannel = "ogvibes/sos_display"
    private var savedWindowBrightness: Float? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, sosDisplayChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "setStealthMode") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val enabled = call.argument<Boolean>("enabled") ?: false
                val attributes = window.attributes
                if (enabled) {
                    if (savedWindowBrightness == null) {
                        savedWindowBrightness = attributes.screenBrightness
                    }
                    attributes.screenBrightness = 0.04f
                } else {
                    attributes.screenBrightness = savedWindowBrightness
                        ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    savedWindowBrightness = null
                }
                window.attributes = attributes
                result.success(null)
            }
    }
}
