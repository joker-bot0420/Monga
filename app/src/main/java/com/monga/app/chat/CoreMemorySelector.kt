package com.monga.app.chat

import com.monga.app.data.local.CoreMemory

fun interface CoreMemorySelector {
    fun select(
        userMessage: String,
        memories: List<CoreMemory>,
    ): List<CoreMemory>
}

internal object DefaultCoreMemorySelector : CoreMemorySelector {

    private const val MAX_SELECTED_MEMORIES = 3
    private const val MIN_SCORE = 4
    private const val TOPIC_SCORE = 8
    private const val KEYWORD_SCORE = 2
    private const val MAX_KEYWORD_OVERLAP = 3

    private data class Topic(
        val markers: List<String>,
    )

    private data class ScoredMemory(
        val memory: CoreMemory,
        val score: Int,
    )

    private val topics = listOf(
        Topic(
            listOf(
                "음료",
                "녹차",
                "커피",
                "홍차",
                "차 추천",
                "차를",
                "차가",
                "차는",
                "tea",
                "drink",
                "coffee",
            )
        ),
        Topic(listOf("생일", "태어난 날", "birthday")),
        Topic(
            listOf(
                "거주",
                "사는 곳",
                "어디에 살",
                "어디 살",
                "살지",
                "살고",
                "산다",
                "살아요",
                "where do i live",
            )
        ),
        Topic(
            listOf(
                "진로",
                "직업",
                "연구자",
                "되고 싶",
                "목표",
                "career",
                "job",
                "goal",
            )
        ),
        Topic(listOf("학교", "대학", "전공", "school", "university", "major")),
        Topic(listOf("이름", "name")),
        Topic(listOf("나이", "몇 살", "age")),
        Topic(listOf("취미", "hobby")),
        Topic(listOf("음식", "먹는", "먹을", "먹어", "food", "meal")),
        Topic(listOf("추위", "더위", "춥", "덥", "temperature")),
        Topic(listOf("키", "몸무게", "체중", "height", "weight")),
    )

    private val stopWords = setOf(
        "나",
        "내",
        "내가",
        "나는",
        "나의",
        "저",
        "제",
        "제가",
        "저는",
        "저의",
        "사용자",
        "뭐",
        "뭐였지",
        "뭐였더라",
        "언제",
        "어디",
        "오늘",
        "전에",
        "예전에",
        "알려줘",
        "말해줘",
        "추천해줘",
        "remember",
        "about",
        "me",
        "my",
        "i",
    )

    private val suffixes = listOf(
        "이었나요",
        "였나요",
        "이었지",
        "였지",
        "이었어",
        "였어",
        "입니다",
        "이에요",
        "예요",
        "이다",
        "에서",
        "에게",
        "한테",
        "으로",
        "부터",
        "까지",
        "은",
        "는",
        "이",
        "가",
        "을",
        "를",
        "에",
        "로",
        "와",
        "과",
        "도",
        "의",
        "만",
        "다",
    )

    override fun select(
        userMessage: String,
        memories: List<CoreMemory>,
    ): List<CoreMemory> {
        if (userMessage.isBlank() || memories.isEmpty()) {
            return emptyList()
        }

        val normalizedQuery = normalize(userMessage)
        val queryKeywords = keywords(normalizedQuery)

        return memories
            .map { memory ->
                ScoredMemory(
                    memory = memory,
                    score = score(
                        query = normalizedQuery,
                        queryKeywords = queryKeywords,
                        memory = normalize(memory.content),
                    ),
                )
            }
            .filter { scored -> scored.score >= MIN_SCORE }
            .sortedWith(
                compareByDescending<ScoredMemory> { it.score }
                    .thenByDescending { it.memory.updatedAt }
                    .thenByDescending { it.memory.createdAt }
                    .thenByDescending { it.memory.id }
            )
            .take(MAX_SELECTED_MEMORIES)
            .map { scored -> scored.memory }
    }

    private fun score(
        query: String,
        queryKeywords: Set<String>,
        memory: String,
    ): Int {
        var score = 0

        for (topic in topics) {
            if (matchesTopic(query, topic) && matchesTopic(memory, topic)) {
                score += TOPIC_SCORE
            }
        }

        val memoryKeywords = keywords(memory)
        val overlapCount = queryKeywords
            .intersect(memoryKeywords)
            .size
            .coerceAtMost(MAX_KEYWORD_OVERLAP)

        score += overlapCount * KEYWORD_SCORE

        return score
    }

    private fun matchesTopic(
        text: String,
        topic: Topic,
    ): Boolean = topic.markers.any(text::contains)

    private fun normalize(text: String): String =
        text
            .lowercase()
            .replace(Regex("[^가-힣a-z0-9]+"), " ")
            .trim()

    private fun keywords(text: String): Set<String> =
        text
            .split(' ')
            .asSequence()
            .map(String::trim)
            .filter(String::isNotEmpty)
            .map(::stripSuffix)
            .filter { token -> token.length >= 2 }
            .filterNot(stopWords::contains)
            .toSet()

    private fun stripSuffix(token: String): String {
        for (suffix in suffixes) {
            if (
                token.endsWith(suffix) &&
                token.length - suffix.length >= 2
            ) {
                return token.dropLast(suffix.length)
            }
        }

        return token
    }
}
