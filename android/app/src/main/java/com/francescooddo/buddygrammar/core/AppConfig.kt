package com.francescooddo.buddygrammar.core

object AppConfig {
    const val API_BASE_URL = "https://buddygrammar-api.oddofrancesco000.workers.dev"
    const val DEFAULT_MODEL = "openai/gpt-5.4-nano"
    const val PENDING_TRANSCRIPT_LIFETIME_MS = 24L * 60L * 60L * 1_000L

    const val DEFAULT_CORRECTION_INSTRUCTION = """
        Fix grammar, spelling, punctuation, and capitalization only.
        Preserve the original language, wording, tone, and meaning as much as possible.
        Do not add explanations, quotes, prefixes, or suffixes.
        Return only the corrected text.
    """
}
