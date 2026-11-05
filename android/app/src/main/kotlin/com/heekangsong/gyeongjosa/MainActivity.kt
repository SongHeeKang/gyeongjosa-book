package com.heekangsong.gyeongjosa

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gyeongjosa/auto_backup")
            .setMethodCallHandler { call, result ->
                val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                when {
                    call.method == "isSupported" -> result.success(supported)
                    call.method == "save" && supported -> {
                        // 파일 쓰기가 화면을 멈추지 않도록 별도 스레드에서 한다.
                        val sourcePath = call.argument<String>("sourcePath")!!
                        val fileName = call.argument<String>("fileName")!!
                        val replaceName = call.argument<String>("replaceName")
                        Thread {
                            try {
                                val saved = DownloadBackup.save(
                                    applicationContext, sourcePath, fileName, replaceName)
                                runOnUiThread { result.success(saved) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("save_failed", e.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
