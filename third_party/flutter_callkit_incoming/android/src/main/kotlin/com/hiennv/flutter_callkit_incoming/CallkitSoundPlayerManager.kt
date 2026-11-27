package com.hiennv.flutter_callkit_incoming

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.text.TextUtils
import android.util.Log

/**
 * Incoming-call sound/vibration.
 *
 * OEM notes (Samsung / Xiaomi / Huawei):
 * - Do **not** stop on SCREEN_OFF — locked phones commonly blank the display while
 *   the call is still ringing; stopping here was a common "no ringtone" report.
 * - Prefer the bundled `raw/ringtone_default` over system ringtone URIs (often
 *   null / permission-gated on Samsung).
 * - Prefer [MediaPlayer] with notification-ringtone attributes over [Ringtone],
 *   which silently no-ops on many devices when ringer mode is vibrate/silent.
 */
class CallkitSoundPlayerManager(private val context: Context) {

    private var vibrator: Vibrator? = null
    private var audioManager: AudioManager? = null
    private var ringtone: Ringtone? = null
    private var mediaPlayer: MediaPlayer? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var isPlaying: Boolean = false

    fun play(data: Bundle) {
        this.isPlaying = true
        this.prepare()
        this.playSound(data)
        this.playVibrator()
    }

    fun stop() {
        this.isPlaying = false
        stopPlayers()
        vibrator?.cancel()
        vibrator = null
        abandonAudioFocus()
    }

    fun destroy() {
        stop()
    }

    private fun prepare() {
        stopPlayers()
        vibrator?.cancel()
    }

    private fun stopPlayers() {
        try {
            ringtone?.stop()
        } catch (_: Exception) {
        }
        ringtone = null
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {
        }
        try {
            mediaPlayer?.release()
        } catch (_: Exception) {
        }
        mediaPlayer = null
    }

    private fun playVibrator() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager =
                context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        when (audioManager?.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> {
                // Still vibrate lightly so silent users notice an incoming VoIP call.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(
                        VibrationEffect.createWaveform(longArrayOf(0L, 600L, 1400L), 0)
                    )
                }
            }
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(
                        VibrationEffect.createWaveform(
                            longArrayOf(0L, 1000L, 1000L),
                            0
                        )
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(longArrayOf(0L, 1000L, 1000L), 0)
                }
            }
        }
    }

    private fun playSound(data: Bundle?) {
        val sound = data?.getString(
            CallkitConstants.EXTRA_CALLKIT_RINGTONE_PATH,
            ""
        ) ?: ""
        val uri = resolveRingtoneUri(sound)
        if (uri == null) {
            Log.w(TAG, "No ringtone URI resolved for path=$sound")
            return
        }
        requestAudioFocus()
        if (playWithMediaPlayer(uri)) {
            return
        }
        playWithRingtoneApi(uri)
    }

    private fun playWithMediaPlayer(uri: Uri): Boolean {
        return try {
            val player = MediaPlayer()
            player.setDataSource(context, uri)
            val attrs = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setLegacyStreamType(AudioManager.STREAM_RING)
                .build()
            player.setAudioAttributes(attrs)
            player.isLooping = true
            player.setOnErrorListener { mp, what, extra ->
                Log.w(TAG, "MediaPlayer error what=$what extra=$extra")
                try {
                    mp.reset()
                    mp.release()
                } catch (_: Exception) {
                }
                if (mediaPlayer === mp) {
                    mediaPlayer = null
                }
                // Fall back to Ringtone API once.
                playWithRingtoneApi(uri)
                true
            }
            player.prepare()
            player.start()
            mediaPlayer = player
            true
        } catch (e: Exception) {
            Log.w(TAG, "MediaPlayer ringtone failed: ${e.message}")
            try {
                mediaPlayer?.release()
            } catch (_: Exception) {
            }
            mediaPlayer = null
            false
        }
    }

    private fun playWithRingtoneApi(uri: Uri) {
        try {
            ringtone = RingtoneManager.getRingtone(context, uri)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val attribution = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setLegacyStreamType(AudioManager.STREAM_RING)
                    .build()
                ringtone?.audioAttributes = attribution
            } else {
                @Suppress("DEPRECATION")
                ringtone?.streamType = AudioManager.STREAM_RING
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ringtone?.isLooping = true
            }
            ringtone?.play()
        } catch (e: Exception) {
            Log.w(TAG, "Ringtone API failed: ${e.message}")
        }
    }

    private fun resolveRingtoneUri(fileName: String): Uri? {
        // Always prefer the packaged asset first — works across OEMs.
        bundledRingtoneUri()?.let { return it }

        if (TextUtils.isEmpty(fileName)) {
            return getSystemRingtoneUri()
        }
        if (fileName.equals("system_ringtone_default", true)) {
            return getSystemRingtoneUri()
        }
        try {
            val resId = context.resources.getIdentifier(fileName, "raw", context.packageName)
            if (resId != 0) {
                return Uri.parse("android.resource://${context.packageName}/$resId")
            }
        } catch (_: Exception) {
        }
        return getSystemRingtoneUri()
    }

    private fun bundledRingtoneUri(): Uri? {
        return try {
            val resId = context.resources.getIdentifier(
                "ringtone_default",
                "raw",
                context.packageName
            )
            if (resId != 0) {
                Uri.parse("android.resource://${context.packageName}/$resId")
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun getSystemRingtoneUri(): Uri? {
        return try {
            RingtoneManager.getActualDefaultRingtoneUri(
                context,
                RingtoneManager.TYPE_RINGTONE
            ) ?: getSafeSystemRingtoneUri()
        } catch (_: Exception) {
            getSafeSystemRingtoneUri()
        }
    }

    private fun getSafeSystemRingtoneUri(): Uri? {
        try {
            val rm = RingtoneManager(context)
            rm.setType(RingtoneManager.TYPE_RINGTONE)
            val cursor = rm.cursor ?: return null
            if (cursor.moveToFirst()) {
                val fallback = rm.getRingtoneUri(cursor.position)
                cursor.close()
                return fallback
            }
            cursor.close()
        } catch (e: Exception) {
            Log.w(TAG, "Safe system ringtone lookup failed: ${e.message}")
        }
        return null
    }

    private fun requestAudioFocus() {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        audioManager = am
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    .setOnAudioFocusChangeListener { }
                    .build()
                audioFocusRequest = req
                am.requestAudioFocus(req)
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    null,
                    AudioManager.STREAM_RING,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Audio focus request failed: ${e.message}")
        }
    }

    private fun abandonAudioFocus() {
        val am = audioManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(null)
            }
        } catch (_: Exception) {
        }
        audioFocusRequest = null
    }

    companion object {
        private const val TAG = "CallkitSoundPlayer"
    }
}
