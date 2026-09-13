<template>
  <div
    class="circular-metric"
    :class="[
      toneClass,
      {
        compact,
        'has-progress': hasProgress,
        'is-zero-progress': normalizedProgress === 0,
        'is-complete': normalizedProgress === 100,
        'is-ring-resetting': ringResetting,
        'is-charging': charging,
        alert
      }
    ]"
    :title="title || `${label}: ${value}`"
  >
    <div class="circular-metric__content">
      <span class="circular-metric__label">{{ label }}</span>
      <ArtCountTo
        v-if="animate && typeof value === 'number'"
        class="circular-metric__value"
        :target="value"
        :duration="duration"
        :decimals="decimals"
        :separator="separator"
      />
      <strong v-else class="circular-metric__value">{{ value }}</strong>
      <div v-if="caption || change" class="circular-metric__meta">
        <span v-if="caption">{{ caption }}</span>
        <b v-if="change" :class="changeClass">{{ change }}</b>
      </div>
    </div>

    <div class="circular-metric__ring">
      <svg
        v-if="hasProgress"
        class="circular-metric__gauge"
        viewBox="0 0 100 100"
        aria-hidden="true"
      >
        <circle class="gauge-ticks" cx="50" cy="50" r="46" pathLength="100" />
        <circle class="gauge-track" cx="50" cy="50" r="38" pathLength="100" />
        <circle class="gauge-charge-pulse" cx="50" cy="50" r="27" />
        <circle
          class="gauge-value"
          cx="50"
          cy="50"
          r="38"
          pathLength="100"
          :stroke-dasharray="`${renderedProgress} 100`"
        />
        <circle class="gauge-inner" cx="50" cy="50" r="29" />
        <circle
          class="gauge-endpoint"
          :class="{ 'is-hidden': renderedProgress <= 0 }"
          cx="50"
          cy="12"
          r="3"
          :style="{ transform: `rotate(${renderedProgress * 3.6}deg)` }"
        />
      </svg>
      <div class="circular-metric__inner">
        <template v-if="hasProgress">
          <strong class="circular-metric__progress-text">{{ progressLabel }}</strong>
          <span class="circular-metric__progress-caption">占比</span>
        </template>
        <ArtSvgIcon
          v-else-if="icon"
          :icon="icon"
          class="circular-metric__icon"
          aria-hidden="true"
        />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'

  interface CircularMetricProps {
    label: string
    value: string | number
    icon?: string
    tone?: 'blue' | 'cyan' | 'violet' | 'orange' | 'rose' | 'green' | 'slate'
    progress?: number | null
    progressText?: string
    caption?: string
    change?: string
    alert?: boolean
    compact?: boolean
    animate?: boolean
    duration?: number
    decimals?: number
    separator?: string
    title?: string
    animationTrigger?: string | number
  }

  const props = withDefaults(defineProps<CircularMetricProps>(), {
    tone: 'blue',
    alert: false,
    compact: false,
    animate: false,
    duration: 900,
    decimals: 0,
    separator: ',',
    animationTrigger: 0
  })

  const toneClass = computed(() => `tone-${props.tone}`)
  const hasProgress = computed(() => props.progress !== undefined && props.progress !== null)
  const normalizedProgress = computed(() => {
    if (!hasProgress.value) return null
    return Math.min(100, Math.max(0, Number(props.progress) || 0))
  })
  const progressLabel = computed(() => {
    if (props.progressText) return props.progressText
    return `${Math.round(normalizedProgress.value || 0)}%`
  })
  const renderedProgress = ref(0)
  const ringResetting = ref(false)
  const charging = ref(false)
  let progressFrame: number | null = null
  let chargeTimer: number | null = null

  const playChargeAnimation = async (value: number | null) => {
    if (progressFrame !== null) window.cancelAnimationFrame(progressFrame)
    if (chargeTimer !== null) window.clearTimeout(chargeTimer)

    charging.value = false
    ringResetting.value = true
    renderedProgress.value = 0
    await nextTick()

    progressFrame = window.requestAnimationFrame(() => {
      ringResetting.value = false
      charging.value = (value || 0) > 0
      renderedProgress.value = value || 0
      progressFrame = null
      chargeTimer = window.setTimeout(() => {
        charging.value = false
        chargeTimer = null
      }, 920)
    })
  }

  onMounted(() => playChargeAnimation(normalizedProgress.value))
  watch(
    () => [normalizedProgress.value, props.animationTrigger] as const,
    ([value]) => playChargeAnimation(value),
    { flush: 'post' }
  )
  onBeforeUnmount(() => {
    if (progressFrame !== null) window.cancelAnimationFrame(progressFrame)
    if (chargeTimer !== null) window.clearTimeout(chargeTimer)
  })
  const changeClass = computed(() => {
    if (!props.change) return ''
    return props.change.startsWith('-') ? 'is-negative' : 'is-positive'
  })
</script>

<style scoped lang="scss">
  .circular-metric {
    --metric-color: #3b82f6;
    --metric-soft: rgb(59 130 246 / 8%);
    --metric-track: var(--el-fill-color-light);

    position: relative;
    display: flex;
    gap: 12px;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    min-width: 0;
    min-height: 124px;
    padding: 13px 12px 13px 14px;
    overflow: hidden;
    background:
      radial-gradient(circle at 100% 0%, var(--metric-soft), transparent 52%),
      linear-gradient(145deg, var(--metric-soft), transparent 42%),
      color-mix(in srgb, var(--el-bg-color) 74%, transparent);
    backdrop-filter: blur(16px) saturate(128%);
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
    box-shadow: 0 8px 24px rgb(15 23 42 / 4%);
    -webkit-backdrop-filter: blur(16px) saturate(128%);
    transition:
      transform 180ms ease,
      box-shadow 180ms ease,
      border-color 180ms ease;
    animation: metricCardIn 520ms cubic-bezier(0.22, 1, 0.36, 1) both;
    will-change: transform, box-shadow;

    &:hover {
      border-color: color-mix(in srgb, var(--metric-color) 38%, var(--el-border-color-lighter));
      box-shadow: 0 12px 28px rgb(15 23 42 / 8%);
      transform: translateY(-2px);
    }
  }

  .circular-metric__content {
    display: flex;
    flex: 1 1 auto;
    flex-direction: column;
    align-items: flex-start;
    min-width: 0;
  }

  .circular-metric__label {
    max-width: 100%;
    overflow: hidden;
    font-size: 12px;
    line-height: 1.2;
    color: var(--el-text-color-secondary);
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .circular-metric__value {
    display: block;
    max-width: 100%;
    margin-top: 6px;
    overflow: hidden;
    font-size: 22px;
    font-weight: 700;
    line-height: 1.1;
    color: var(--el-text-color-primary);
    text-overflow: ellipsis;
    white-space: nowrap;
    animation: metricValueIn 620ms 120ms cubic-bezier(0.22, 1, 0.36, 1) both;
  }

  .circular-metric.compact .circular-metric__value {
    font-size: 19px;
  }

  .circular-metric__meta {
    display: flex;
    gap: 5px;
    align-items: center;
    max-width: 100%;
    margin-top: 7px;
    overflow: hidden;
    font-size: 12px;
    line-height: 1.2;
    color: var(--el-text-color-secondary);
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .circular-metric__meta b {
    font-weight: 650;
  }

  .circular-metric__meta .is-positive {
    color: var(--el-color-success);
  }

  .circular-metric__meta .is-negative,
  .circular-metric.alert .circular-metric__value {
    color: var(--el-color-danger);
  }

  .circular-metric__ring {
    position: relative;
    display: grid;
    flex: 0 0 82px;
    place-items: center;
    width: 82px;
    height: 82px;
    border-radius: 50%;
    animation: metricRingIn 760ms cubic-bezier(0.22, 1, 0.36, 1) both;
    will-change: transform;
  }

  .circular-metric:not(.has-progress) .circular-metric__ring {
    background: var(--metric-track);
    border: 1px solid var(--el-border-color-extra-light);
  }

  .circular-metric__gauge {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    overflow: visible;
  }

  .gauge-ticks,
  .gauge-track,
  .gauge-value,
  .gauge-inner,
  .gauge-charge-pulse {
    fill: none;
  }

  .gauge-ticks {
    opacity: 0.38;
    stroke: var(--el-border-color);
    stroke-dasharray: 1.2 7.133;
    stroke-width: 1.2;
  }

  .gauge-track {
    stroke: var(--el-fill-color-dark);
    stroke-width: 6;
  }

  .gauge-value {
    stroke: var(--metric-color);
    stroke-linecap: round;
    stroke-width: 6;
    transition: stroke-dasharray 880ms cubic-bezier(0.16, 1, 0.3, 1);
    transform: rotate(-90deg);
    transform-origin: center;
  }

  .gauge-inner {
    stroke: var(--el-border-color-extra-light);
    stroke-width: 1;
  }

  .gauge-charge-pulse {
    opacity: 0;
    stroke: var(--metric-color);
    stroke-width: 1;
    transform-origin: center;
  }

  .gauge-endpoint {
    fill: var(--el-bg-color);
    stroke: var(--metric-color);
    stroke-width: 2;
    transition:
      opacity 160ms ease,
      transform 880ms cubic-bezier(0.16, 1, 0.3, 1);
    transform-origin: 50px 50px;
    transform-box: view-box;

    &.is-hidden {
      opacity: 0;
    }
  }

  .circular-metric.is-ring-resetting {
    .gauge-value,
    .gauge-endpoint {
      transition: none;
    }
  }

  .circular-metric.is-charging .gauge-charge-pulse {
    animation: gaugeChargePulse 880ms cubic-bezier(0.16, 1, 0.3, 1) both;
  }

  .circular-metric.is-zero-progress {
    .gauge-value {
      stroke: var(--el-border-color);
    }

    .circular-metric__progress-text {
      color: var(--el-text-color-regular);
    }
  }

  .circular-metric__inner {
    position: relative;
    z-index: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    width: 54px;
    height: 54px;
    text-align: center;
  }

  .circular-metric__icon {
    font-size: 20px;
    color: var(--metric-color);
  }

  .circular-metric__progress-text {
    font-size: 16px;
    font-weight: 750;
    line-height: 1;
    color: var(--metric-color);
    animation: metricProgressIn 560ms 320ms cubic-bezier(0.22, 1, 0.36, 1) both;
  }

  .circular-metric__progress-caption {
    margin-top: 4px;
    font-size: 9px;
    line-height: 1;
    color: var(--el-text-color-secondary);
    letter-spacing: 0.06em;
  }

  .tone-blue {
    --metric-color: #3b82f6;
    --metric-soft: rgb(59 130 246 / 8%);
  }

  .tone-cyan {
    --metric-color: #0891b2;
    --metric-soft: rgb(8 145 178 / 8%);
  }

  .tone-violet {
    --metric-color: #7c3aed;
    --metric-soft: rgb(124 58 237 / 8%);
  }

  .tone-orange {
    --metric-color: #d97706;
    --metric-soft: rgb(217 119 6 / 8%);
  }

  .tone-rose {
    --metric-color: #e11d48;
    --metric-soft: rgb(225 29 72 / 8%);
  }

  .tone-green {
    --metric-color: #16a34a;
    --metric-soft: rgb(22 163 74 / 8%);
  }

  .tone-slate {
    --metric-color: #64748b;
    --metric-soft: rgb(100 116 139 / 8%);
  }

  @keyframes metricCardIn {
    from {
      opacity: 0;
      transform: translateY(8px) scale(0.985);
    }

    to {
      opacity: 1;
      transform: translateY(0) scale(1);
    }
  }

  @keyframes metricValueIn {
    from {
      opacity: 0;
      transform: translateY(5px);
    }

    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @keyframes metricRingIn {
    from {
      opacity: 0;
      transform: scale(0.74) rotate(-18deg);
    }

    to {
      opacity: 1;
      transform: scale(1) rotate(0deg);
    }
  }

  @keyframes metricProgressIn {
    from {
      opacity: 0;
      transform: scale(0.72);
    }

    to {
      opacity: 1;
      transform: scale(1);
    }
  }

  @keyframes gaugeChargePulse {
    0% {
      opacity: 0;
      transform: scale(0.72);
    }

    32% {
      opacity: 0.24;
    }

    100% {
      opacity: 0;
      transform: scale(1.18);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .circular-metric,
    .circular-metric__value,
    .circular-metric__ring,
    .circular-metric__progress-text,
    .gauge-value,
    .gauge-endpoint,
    .gauge-charge-pulse {
      transition-duration: 0.01ms !important;
      animation: none !important;
    }
  }

  @media (width <= 640px) {
    .circular-metric {
      gap: 6px;
      min-height: 112px;
      padding: 10px;
    }

    .circular-metric__ring {
      flex-basis: 66px;
      width: 66px;
      height: 66px;
    }

    .circular-metric__inner {
      width: 46px;
      height: 46px;
    }

    .circular-metric__icon {
      font-size: 20px;
    }

    .circular-metric__value {
      font-size: 18px;
    }

    .circular-metric__meta {
      font-size: 10px;
    }

    .circular-metric__progress-caption {
      display: none;
    }
  }
</style>
