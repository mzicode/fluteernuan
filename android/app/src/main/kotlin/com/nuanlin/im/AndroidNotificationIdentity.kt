package com.nuanlin.im

object AndroidNotificationIdentity {
    const val fcmAutomaticNotificationId = 0

    fun messageTag(notificationId: Int): String {
        return "customer-message-$notificationId"
    }
}
