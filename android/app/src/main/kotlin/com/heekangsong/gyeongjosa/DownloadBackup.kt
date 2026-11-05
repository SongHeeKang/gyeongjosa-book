package com.heekangsong.gyeongjosa

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import java.io.File
import java.io.IOException

/** Download/경조사장부/ 폴더에 자동 백업 파일을 저장한다. Android 10 이상은 권한이 필요 없다. */
@RequiresApi(Build.VERSION_CODES.Q)
object DownloadBackup {
    private const val FOLDER = "Download/경조사장부/"
    private const val KEEP = 7

    private class Saved(val uri: Uri, val name: String)

    /**
     * [sourcePath] 내용을 저장하고 실제로 저장된 이름을 돌려준다.
     * [replaceName]이 있으면 그 파일을 새 내용으로 바꾼다. 없으면 [fileName]으로 새로 만들고,
     * 같은 이름이 이미 있으면 지우지 않고 '(1)'이 붙은 새 파일로 남긴다.
     */
    fun save(context: Context, sourcePath: String, fileName: String, replaceName: String?): String {
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "작성중_${System.currentTimeMillis()}.db")
            put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
            put(MediaStore.MediaColumns.RELATIVE_PATH, FOLDER)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }) ?: throw IOException("백업 파일을 만들지 못했어요")

        try {
            val output = resolver.openOutputStream(uri, "w")
                ?: throw IOException("백업 파일을 열지 못했어요")
            output.use { out -> File(sourcePath).inputStream().use { it.copyTo(out) } }
            // 새 파일을 다 쓴 뒤에야 공개하고, 그다음에 옛 파일을 지운다.
            resolver.update(uri, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }

        if (replaceName != null) {
            ownFiles(resolver, collection)
                .filter { it.name == replaceName && it.uri != uri }
                .forEach { resolver.delete(it.uri, null, null) }
        }
        resolver.update(uri, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, replaceName ?: fileName)
        }, null, null)

        ownFiles(resolver, collection).drop(KEEP).forEach { resolver.delete(it.uri, null, null) }
        return ownFiles(resolver, collection).first { it.uri == uri }.name
    }

    /** 이 앱이 이 폴더에 만든 파일 목록 (최신이 앞) */
    private fun ownFiles(resolver: ContentResolver, collection: Uri): List<Saved> {
        val files = mutableListOf<Saved>()
        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME),
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(FOLDER),
            "${MediaStore.MediaColumns._ID} DESC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val uri = Uri.withAppendedPath(collection, cursor.getLong(0).toString())
                files.add(Saved(uri, cursor.getString(1)))
            }
        }
        return files
    }
}
