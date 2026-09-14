package com.monga.app.chat

fun interface CoreMemoryRelevanceGate {
    fun shouldInclude(userMessage: String): Boolean
}

internal object DefaultCoreMemoryRelevanceGate : CoreMemoryRelevanceGate {

    private val recallMarkers = listOf(
        "기억",
        "뭐였지",
        "뭐였더라",
        "전에 말",
        "예전에 말",
        "말했었",
        "알고 있",
        "나에 대해",
        "저에 대해",
        "remember",
        "about me",
        "did i tell",
        "what did i",
    )

    private val selfReferences = listOf(
        "내 ",
        "내가",
        "나는",
        "나의",
        "제 ",
        "제가",
        "저는",
        "저의",
        "my ",
        "i ",
    )

    private val personalMarkers = listOf(
        "좋아",
        "싫어",
        "취향",
        "선호",
        "이름",
        "생일",
        "나이",
        "사는",
        "살고",
        "거주",
        "직업",
        "학교",
        "전공",
        "목표",
        "계획",
        "습관",
        "취미",
        "음식",
        "음료",
        "색",
        "키",
        "몸무게",
        "favorite",
        "prefer",
        "preference",
        "name",
        "birthday",
        "hobby",
    )

    override fun shouldInclude(userMessage: String): Boolean {
        val normalized = userMessage.trim().lowercase()
        if (normalized.isEmpty()) return false

        if (recallMarkers.any(normalized::contains)) {
            return true
        }

        val referencesSelf = selfReferences.any(normalized::contains)
        val asksAboutPersonalFact = personalMarkers.any(normalized::contains)

        return referencesSelf && asksAboutPersonalFact
    }
}
