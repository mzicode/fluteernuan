const PENDING_REMINDER_KEY = 'admin:pending-reminder-after-login'
const REMINDER_VALID_MS = 5 * 60 * 1000

export function preparePendingReminderAudio() {
  if (typeof window === 'undefined' || !('speechSynthesis' in window)) return
  window.speechSynthesis.resume()
  window.speechSynthesis.getVoices()
}

export function markPendingReminderAfterLogin() {
  if (typeof window === 'undefined') return
  window.sessionStorage.setItem(PENDING_REMINDER_KEY, String(Date.now()))
}

export function hasPendingReminderAfterLogin() {
  if (typeof window === 'undefined') return false
  const value = Number(window.sessionStorage.getItem(PENDING_REMINDER_KEY))
  if (!Number.isFinite(value) || Date.now() - value > REMINDER_VALID_MS) {
    window.sessionStorage.removeItem(PENDING_REMINDER_KEY)
    return false
  }
  return true
}

export function consumePendingReminderAfterLogin() {
  if (typeof window === 'undefined') return
  window.sessionStorage.removeItem(PENDING_REMINDER_KEY)
}

export function speakPendingReminder(message: string) {
  if (typeof window === 'undefined' || !('speechSynthesis' in window)) return false

  const speech = window.speechSynthesis
  const utterance = new SpeechSynthesisUtterance(message)
  const voices = speech.getVoices()
  const chineseVoice = voices.find((voice) => /^zh(?:-|_)/i.test(voice.lang))

  utterance.lang = chineseVoice?.lang || 'zh-CN'
  utterance.voice = chineseVoice || null
  utterance.rate = 0.95
  utterance.pitch = 1
  utterance.volume = 0.9

  speech.cancel()
  speech.speak(utterance)
  return true
}
