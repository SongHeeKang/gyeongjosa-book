package com.heekangsong.gyeongjosa

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** 안드로이드 설정의 '공간 관리'를 누르면 열리는 화면. 화면 자체는 Flutter(manageSpaceMain)에 있다. */
class ManageSpaceActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName() = "manageSpaceMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gyeongjosa/manage_space")
            .setMethodCallHandler { call, result ->
                if (call.method == "clearAppData") {
                    // 성공하면 DB와 설정이 모두 지워지고 앱이 바로 종료된다.
                    val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    result.success(manager.clearApplicationUserData())
                } else {
                    result.notImplemented()
                }
            }
    }
}
