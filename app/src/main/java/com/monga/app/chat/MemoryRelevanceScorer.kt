package com.monga.app.chat

internal object MemoryRelevanceScorer {

    private const val TOPIC_SCORE = 8
    private const val KEYWORD_SCORE = 2
    private const val MAX_KEYWORD_OVERLAP = 3

    private data class Topic(
        val markers: List<String>,
    )

    private val topics = listOf(
        Topic(
            listOf(
                "음료",
                "녹차",
                "커피",
                "홍차",
                "차 추천",
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
                "에 산다",
                "에서 산다",
                "에 살고",
                "에서 살고",
                "에 살아요",
                "에서 살아요",
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

    fun score(
        query: String,
        memory: String,
    ): Int {
        val normalizedQuery = normalize(query)
        val normalizedMemory = normalize(memory)
        val queryKeywords = keywords(normalizedQuery)

        var score = 0

        for (topic in topics) {
            if (
                matchesTopic(normalizedQuery, topic) &&
                matchesTopic(normalizedMemory, topic)
            ) {
                score += TOPIC_SCORE
            }
        }

        val memoryKeywords = keywords(normalizedMemory)
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
    ): Boolean {
        val tokens = topicTokens(text)

        return topic.markers.any { marker ->
            val normalizedMarker = normalize(marker)

            if (' ' in normalizedMarker) {
                text.contains(normalizedMarker)
            } else {
                normalizedMarker in tokens
            }
        }
    }

    private fun normalize(text: String): String =
        text
            .lowercase()
            .replace(Regex("[^가-힣a-z0-9]+"), " ")
            .trim()

    private fun topicTokens(text: String): Set<String> =
        text
            .split(' ')
            .asSequence()
            .map(String::trim)
            .filter(String::isNotEmpty)
            .flatMap { token ->
                sequenceOf(
                    token,
                    stripSuffix(
                        token = token,
                        minimumStemLength = 1,
                    ),
                )
            }
            .filter(String::isNotEmpty)
            .toSet()

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

    private fun stripSuffix(token: String): String =
        stripSuffix(
            token = token,
            minimumStemLength = 2,
        )

    private fun stripSuffix(
        token: String,
        minimumStemLength: Int,
    ): String {
        for (suffix in suffixes) {
            if (
                token.endsWith(suffix) &&
                token.length - suffix.length >= minimumStemLength
            ) {
                return token.dropLast(suffix.length)
            }
        }

        return token
    }
}
