<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';

const BAR_WIDTH = 2;
const BAR_GAP = 1;
const WAVE_COLOR = '#1f93ff';

const props = defineProps({
  level: { type: Number, default: 0 },
  paused: { type: Boolean, default: false }
});

const canvasRef = ref(null);

let buffer = [];
let observer = null;
let rafId = 0;

function barCount(width) {
  return Math.max(8, Math.floor(width / (BAR_WIDTH + BAR_GAP)));
}

function resizeBuffer(count) {
  if (buffer.length === count) return;
  if (buffer.length < count) {
    buffer = Array(count - buffer.length).fill(0).concat(buffer);
    return;
  }
  buffer = buffer.slice(buffer.length - count);
}

function sizeCanvas() {
  const canvas = canvasRef.value;
  if (!canvas) return;
  const rect = canvas.getBoundingClientRect();
  const pixelRatio = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, Math.floor(rect.width * pixelRatio));
  canvas.height = Math.max(1, Math.floor(rect.height * pixelRatio));
  resizeBuffer(barCount(rect.width));
  paint();
}

function paint() {
  const canvas = canvasRef.value;
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const { width, height } = canvas;
  const pixelRatio = window.devicePixelRatio || 1;
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = WAVE_COLOR;
  const mid = height / 2;
  const step = (BAR_WIDTH + BAR_GAP) * pixelRatio;
  const barWidth = BAR_WIDTH * pixelRatio;
  for (let index = 0; index < buffer.length; index += 1) {
    const amplitude = buffer[index] * (height - 4 * pixelRatio);
    if (amplitude < 1) continue;
    ctx.fillRect(index * step, mid - amplitude / 2, barWidth, amplitude);
  }
}

function tick() {
  rafId = window.requestAnimationFrame(tick);
  if (props.paused || !buffer.length) return;
  buffer.copyWithin(0, 1);
  buffer[buffer.length - 1] = props.level;
  paint();
}

onMounted(() => {
  sizeCanvas();
  observer = new ResizeObserver(sizeCanvas);
  if (canvasRef.value) observer.observe(canvasRef.value);
  tick();
});

onBeforeUnmount(() => {
  observer?.disconnect();
  observer = null;
  if (rafId) window.cancelAnimationFrame(rafId);
});
</script>

<template>
  <div class="chat-wave" :class="{ paused }" aria-hidden="true">
    <canvas ref="canvasRef" class="chat-wave-canvas" />
  </div>
</template>
