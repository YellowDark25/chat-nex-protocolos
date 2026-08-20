<script setup>
import { onBeforeUnmount, ref } from 'vue';
import { api } from '../api.js';

const MIME_CANDIDATES = [
  'audio/webm;codecs=opus',
  'audio/webm',
  'audio/mp4',
  'audio/ogg;codecs=opus'
];

const props = defineProps({
  modelValue: { type: String, default: '' },
  maxLength: { type: Number, default: 2000 }
});

const emit = defineEmits(['update:modelValue', 'error']);
const mode = ref('idle');
const transcribing = ref(false);

const playing = ref(false);
const player = ref(null);

let recorder = null;
let stream = null;
let chunks = [];
let pendingFile = null;
let pendingUrl = null;
let starting = false;
let baseText = '';

function joinText(...parts) {
  return parts
    .map((part) => String(part || '').trim())
    .filter(Boolean)
    .join(' ');
}

function pickMime() {
  if (typeof MediaRecorder === 'undefined' || !MediaRecorder.isTypeSupported) return '';
  return MIME_CANDIDATES.find((type) => MediaRecorder.isTypeSupported(type)) || '';
}

function write(extra) {
  emit('update:modelValue', joinText(baseText, extra).slice(0, props.maxLength));
}

function stopTracks() {
  stream?.getTracks().forEach((track) => track.stop());
  stream = null;
}

function resetRecorder() {
  recorder = null;
  chunks = [];
  stopTracks();
}

function stopPlayback() {
  const audio = player.value;
  if (!audio) return;
  audio.pause();
  audio.currentTime = 0;
  playing.value = false;
}

function revokePendingUrl() {
  stopPlayback();
  if (pendingUrl) URL.revokeObjectURL(pendingUrl);
  pendingUrl = null;
  if (player.value) player.value.removeAttribute('src');
}

function attachPendingPlayback(file) {
  revokePendingUrl();
  pendingUrl = URL.createObjectURL(file);
  if (player.value) player.value.src = pendingUrl;
}

function togglePlayback() {
  const audio = player.value;
  if (!pendingFile || transcribing.value || !audio) return;
  if (audio.paused) {
    audio.play().catch(() => emit('error', 'Não foi possível reproduzir o áudio'));
    return;
  }
  audio.pause();
}

function onPlaybackEnded() {
  if (player.value) player.value.currentTime = 0;
  playing.value = false;
}

function buildPendingFile() {
  const mime = recorder?.mimeType || chunks[0]?.type || 'audio/webm';
  const blob = new Blob(chunks, { type: mime.split(';')[0] });
  if (!blob.size) return null;
  const extension = mime.includes('mp4') || mime.includes('m4a') ? 'm4a' : 'webm';
  return new File([blob], `audio-${Date.now()}.${extension}`, { type: blob.type });
}

async function startRecorder() {
  if (typeof MediaRecorder === 'undefined' || !navigator.mediaDevices?.getUserMedia) {
    throw new Error('Este navegador não grava áudio');
  }
  revokePendingUrl();
  pendingFile = null;
  stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  chunks = [];
  const mime = pickMime();
  recorder = mime ? new MediaRecorder(stream, { mimeType: mime }) : new MediaRecorder(stream);
  recorder.ondataavailable = (event) => {
    if (event.data?.size) chunks.push(event.data);
  };
  recorder.onstop = () => {
    pendingFile = buildPendingFile();
    resetRecorder();
    if (!pendingFile) {
      mode.value = 'idle';
      emit('error', 'Não foi possível gravar o áudio');
      return;
    }
    attachPendingPlayback(pendingFile);
    mode.value = 'paused';
  };
  baseText = props.modelValue;
  recorder.start();
  mode.value = 'recording';
}

function pauseRecorder() {
  if (!recorder || recorder.state !== 'recording') return;
  recorder.stop();
}

async function onMicClick() {
  if (transcribing.value || starting) return;
  if (mode.value === 'recording') {
    pauseRecorder();
    return;
  }
  starting = true;
  try {
    await startRecorder();
  } catch (err) {
    resetRecorder();
    revokePendingUrl();
    pendingFile = null;
    mode.value = 'idle';
    if (err?.name === 'NotAllowedError' || err?.name === 'PermissionDeniedError') {
      emit('error', 'Permita o microfone no navegador para gravar');
    } else {
      emit('error', err.message || 'Não foi possível iniciar o microfone');
    }
  } finally {
    starting = false;
  }
}

async function transcribeAudio() {
  if (transcribing.value || !pendingFile) return;
  transcribing.value = true;
  stopPlayback();
  try {
    const payload = await api.transcribe(pendingFile);
    write(payload.text || '');
    revokePendingUrl();
    pendingFile = null;
    mode.value = 'idle';
  } catch (err) {
    emit('error', err.message || 'Não foi possível transcrever o áudio');
  } finally {
    transcribing.value = false;
  }
}

onBeforeUnmount(() => {
  if (recorder && recorder.state !== 'inactive') {
    try {
      recorder.onstop = null;
      recorder.stop();
    } catch {
      /* já parado */
    }
  }
  stopTracks();
  revokePendingUrl();
});
</script>

<template>
  <span class="dictation-actions">
    <button
      class="dictation-mic"
      :class="{ listening: mode === 'recording' }"
      type="button"
      :disabled="transcribing"
      :aria-pressed="mode === 'recording'"
      :aria-label="mode === 'recording' ? 'Pausar áudio' : 'Gravar assunto'"
      :title="mode === 'recording' ? 'Pausar' : 'Gravar assunto'"
      @click="onMicClick"
    >
      <svg v-if="mode === 'recording'" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
        <path fill="currentColor" d="M7 5h4v14H7V5Zm6 0h4v14h-4V5Z" />
      </svg>
      <svg v-else viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
        <path
          fill="currentColor"
          d="M12 14a3 3 0 0 0 3-3V7a3 3 0 1 0-6 0v4a3 3 0 0 0 3 3Zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-3.08A7 7 0 0 0 19 11h-2Z"
        />
      </svg>
    </button>
    <button
      v-show="mode === 'paused'"
      class="dictation-play"
      type="button"
      :disabled="transcribing"
      :aria-label="playing ? 'Pausar reprodução' : 'Ouvir áudio'"
      :title="playing ? 'Pausar' : 'Ouvir áudio'"
      @click="togglePlayback"
    >
      <svg v-if="playing" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
        <path fill="currentColor" d="M7 5h4v14H7V5Zm6 0h4v14h-4V5Z" />
      </svg>
      <svg v-else viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
        <path fill="currentColor" d="M8 5v14l11-7-11-7Z" />
      </svg>
    </button>
    <button
      v-show="mode === 'paused'"
      class="dictation-transcribe"
      type="button"
      :disabled="transcribing"
      @click="transcribeAudio"
    >
      {{ transcribing ? 'Transcrevendo…' : 'Transcrever' }}
    </button>
    <audio
      ref="player"
      hidden
      preload="metadata"
      @play="playing = true"
      @pause="playing = false"
      @ended="onPlaybackEnded"
    />
  </span>
</template>
