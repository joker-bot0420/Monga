package com.monga.app.data.backup

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

class SafBackupStore(private val resolver: ContentResolver) {
    fun persistTreePermission(uri: Uri) {
        runCatching {
            resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
    }

    fun read(uri: Uri): String = resolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        ?: error("백업 파일을 읽을 수 없습니다.")

    fun writeToTree(context: android.content.Context, treeUri: Uri, json: String): Uri {
        val directory = DocumentFile.fromTreeUri(context, treeUri) ?: error("선택한 폴더를 열 수 없습니다.")
        val name = "monga-backup-${LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"))}.json"
        val file = directory.createFile("application/json", name) ?: error("백업 파일을 만들 수 없습니다.")
        resolver.openOutputStream(file.uri, "w")?.bufferedWriter()?.use { it.write(json) }
            ?: error("백업 파일을 쓸 수 없습니다.")
        return file.uri
    }
}
