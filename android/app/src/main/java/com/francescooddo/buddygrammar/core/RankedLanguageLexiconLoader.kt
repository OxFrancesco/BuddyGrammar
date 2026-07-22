package com.francescooddo.buddygrammar.core

import android.content.res.Resources
import com.francescooddo.buddygrammar.R

object RankedLanguageLexiconLoader {
    fun bundled(resources: Resources): RankedLanguageLexicon =
        RankedLanguageLexicon.parse(
            mapOf(
                "en" to resources.readRawUtf8(R.raw.swipe_lexicon_en_v1),
                "it" to resources.readRawUtf8(R.raw.swipe_lexicon_it_v1),
            ),
        )

    private fun Resources.readRawUtf8(resourceId: Int): String =
        openRawResource(resourceId).bufferedReader(Charsets.UTF_8).use { it.readText() }
}
