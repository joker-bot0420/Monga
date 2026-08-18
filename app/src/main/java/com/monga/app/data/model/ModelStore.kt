package com.monga.app.data.model

import android.content.ContentResolver
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class ImportedModel(
    val file: File,
    val displayName: String,
)

class ModelStore(
    private val contentResolver: ContentResolver,
    private val modelsDirectory: File,
) {
    suspend fun importModel(
        uri: Uri,
    ): ImportedModel = withContext(Dispatchers.IO) {
        val displayName = resolveDisplayName(uri)
        val safeName = File(displayName).name

        require(safeName.endsWith(".gguf", ignoreCase = true)) {
            "GGUF 모델 파일만 가져올 수 있습니다."
        }

        check(modelsDirectory.exists() || modelsDirectory.mkdirs()) {
            "모델 저장 폴더를 만들 수 없습니다."
        }

        val target = createAvailableTarget(safeName)

        val temporary = File.createTempFile(
            "monga-model-",
            ".importing",
            modelsDirectory,
        )

        try {
            contentResolver.openInputStream(uri)?.use { input ->
                temporary.outputStream().use { output ->
                    input.copyTo(output)
                }
            } ?: error("선택한 모델 파일을 읽을 수 없습니다.")

            check(temporary.inputStream().use { input ->
                val magic = ByteArray(4)
                input.read(magic) == 4 &&
                        magic.contentEquals(
                            byteArrayOf(
                                'G'.code.toByte(),
                                'G'.code.toByte(),
                                'U'.code.toByte(),
                                'F'.code.toByte(),
                            )
                        )
            }) {
                "올바른 GGUF 모델 파일이 아닙니다."
            }

            try {
                Files.move(
                    temporary.toPath(),
                    target.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                )
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(
                    temporary.toPath(),
                    target.toPath(),
                )
            }
        } finally {
            temporary.delete()
        }

        ImportedModel(
            file = target,
            displayName = target.name,
        )
    }

    fun getModelFile(fileName: String): File {
        val safeName = File(fileName).name
        val file = File(modelsDirectory, safeName)

        check(file.isFile) {
            "선택한 모델 파일을 찾을 수 없습니다."
        }

        return file
    }

    private fun createAvailableTarget(fileName: String): File {
        val original = File(fileName)
        val baseName = original.nameWithoutExtension
        val extension = original.extension

        var candidate = File(modelsDirectory, original.name)
        var suffix = 2

        while (candidate.exists()) {
            candidate = File(
                modelsDirectory,
                "$baseName ($suffix).$extension",
            )
            suffix++
        }

        return candidate
    }

    private fun resolveDisplayName(uri: Uri): String {
        val displayName = contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)

            if (nameIndex >= 0 && cursor.moveToFirst()) {
                cursor.getString(nameIndex)
            } else {
                null
            }
        }

        return displayName
            ?.takeIf { it.isNotBlank() }
            ?: error("선택한 모델 파일의 이름을 확인할 수 없습니다.")
    }
}
