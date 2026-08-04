package com.monga.app.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverter
import androidx.room.TypeConverters

@Database(
    entities = [Conversation::class, Message::class, CoreMemory::class, EpisodicMemory::class, DailySummary::class],
    version = 1,
    exportSchema = true,
)
@TypeConverters(MongaConverters::class)
abstract class MongaDatabase : RoomDatabase() {
    abstract fun dao(): MongaDao
    companion object {
        fun create(context: Context): MongaDatabase = Room.databaseBuilder(
            context.applicationContext, MongaDatabase::class.java, "monga.db"
        ).build()
    }
}

class MongaConverters {
    @TypeConverter fun roleToString(role: MessageRole): String = role.name
    @TypeConverter fun stringToRole(value: String): MessageRole = MessageRole.valueOf(value)
}

