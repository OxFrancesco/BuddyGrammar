package com.francescooddo.buddygrammar.core

/**
 * Grants one opaque pointer token exclusive ownership of a stateful input
 * session. Move, release, and cancel events from every other token are ignored.
 */
class SinglePointerInteractionOwner<Token : Any> {
    var activeToken: Token? = null
        private set

    fun acquire(token: Token): Boolean {
        if (activeToken != null) return false
        activeToken = token
        return true
    }

    fun owns(token: Token): Boolean = activeToken == token

    fun release(token: Token): Boolean {
        if (!owns(token)) return false
        activeToken = null
        return true
    }

    fun reset() {
        activeToken = null
    }
}
