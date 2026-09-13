package com.nuanlin.im

import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidNotificationIdentityTest {
    @Test
    fun fcmAutomaticMessageIdentityMatchesServerContract() {
        assertEquals(0, AndroidNotificationIdentity.fcmAutomaticNotificationId)
        assertEquals(
            "customer-message-48082",
            AndroidNotificationIdentity.messageTag(48082),
        )
    }
}
