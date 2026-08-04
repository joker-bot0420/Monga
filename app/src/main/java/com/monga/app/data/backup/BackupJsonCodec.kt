package com.monga.app.data.backup

import com.monga.app.data.local.*
import org.json.JSONArray
import org.json.JSONObject

object BackupJsonCodec {
    const val VERSION = 1

    fun encode(snapshot: DatabaseSnapshot): String = JSONObject().apply {
        put("format", "monga-backup")
        put("version", VERSION)
        put("exportedAt", System.currentTimeMillis())
        put("conversations", array(snapshot.conversations) { conversation(it) })
        put("messages", array(snapshot.messages) { message(it) })
        put("coreMemories", array(snapshot.coreMemories) { coreMemory(it) })
        put("episodicMemories", array(snapshot.episodicMemories) { episodicMemory(it) })
        put("dailySummaries", array(snapshot.dailySummaries) { dailySummary(it) })
    }.toString(2)

    fun decode(json: String): DatabaseSnapshot {
        val root = JSONObject(json)
        require(root.getString("format") == "monga-backup") { "Monga 백업 파일이 아닙니다." }
        require(root.getInt("version") == VERSION) { "지원하지 않는 백업 버전입니다." }
        return DatabaseSnapshot(
            root.getJSONArray("conversations").mapObjects { Conversation(it.long("id"), it.string("title"), it.long("createdAt"), it.long("updatedAt")) },
            root.getJSONArray("messages").mapObjects { Message(it.long("id"), it.long("conversationId"), MessageRole.valueOf(it.string("role")), it.string("content"), it.long("createdAt")) },
            root.getJSONArray("coreMemories").mapObjects { CoreMemory(it.long("id"), it.string("content"), it.long("createdAt"), it.long("updatedAt")) },
            root.getJSONArray("episodicMemories").mapObjects { EpisodicMemory(it.long("id"), it.string("title"), it.string("content"), it.long("occurredAt"), it.long("createdAt")) },
            root.getJSONArray("dailySummaries").mapObjects { DailySummary(it.long("id"), it.string("date"), it.string("content"), it.long("createdAt"), it.long("updatedAt")) },
        )
    }

    private fun conversation(v: Conversation) = obj("id" to v.id, "title" to v.title, "createdAt" to v.createdAt, "updatedAt" to v.updatedAt)
    private fun message(v: Message) = obj("id" to v.id, "conversationId" to v.conversationId, "role" to v.role.name, "content" to v.content, "createdAt" to v.createdAt)
    private fun coreMemory(v: CoreMemory) = obj("id" to v.id, "content" to v.content, "createdAt" to v.createdAt, "updatedAt" to v.updatedAt)
    private fun episodicMemory(v: EpisodicMemory) = obj("id" to v.id, "title" to v.title, "content" to v.content, "occurredAt" to v.occurredAt, "createdAt" to v.createdAt)
    private fun dailySummary(v: DailySummary) = obj("id" to v.id, "date" to v.date, "content" to v.content, "createdAt" to v.createdAt, "updatedAt" to v.updatedAt)
    private fun obj(vararg pairs: Pair<String, Any>) = JSONObject().apply { pairs.forEach { put(it.first, it.second) } }
    private fun <T> array(items: List<T>, convert: (T) -> JSONObject) = JSONArray().apply { items.forEach { put(convert(it)) } }
    private fun JSONObject.long(key: String) = getLong(key)
    private fun JSONObject.string(key: String) = getString(key)
    private fun <T> JSONArray.mapObjects(convert: (JSONObject) -> T) = (0 until length()).map { convert(getJSONObject(it)) }
}

