package com.heekangsong.gyeongjosa

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import java.io.File

/** 다른 앱(카카오톡 등)에서 장부 파일을 눌러 열거나 공유했을 때 그 파일을 앱 안으로 복사한다. */
object IncomingFile {
    private const val MAX_BYTES = 20L * 1024 * 1024

    /** 장부 파일을 연 Intent가 아니면 null. 읽지 못하면 "" (화면에서 안내). */
    fun read(context: Context, intent: Intent?): String? {
        val uri = uriOf(intent) ?: return null
        return try {
            val out = File(context.cacheDir, "incoming_ledger.json")
            val input = context.contentResolver.openInputStream(uri) ?: return ""
            input.use { stream ->
                out.outputStream().use { target ->
                    val buffer = ByteArray(16 * 1024)
                    var total = 0L
                    while (true) {
                        val n = stream.read(buffer)
                        if (n < 0) break
                        total += n
                        if (total > MAX_BYTES) return ""
                        target.write(buffer, 0, n)
                    }
                }
            }
            out.absolutePath
        } catch (e: Exception) {
            ""
        }
    }

    private fun uriOf(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
            else -> null
        }
    }
}
