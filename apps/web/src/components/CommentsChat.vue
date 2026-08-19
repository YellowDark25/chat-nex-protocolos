<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { api } from '../api.js';
import AttachmentPreview from './AttachmentPreview.vue';
import AudioWaveform from './AudioWaveform.vue';
import { formatClock, useAudioRecorder } from '../useAudioRecorder.js';

const POLL_MS = 8000;
const COMMENT_MAX = 4000;
const COMMENT_IMAGES_MAX = 5;
const IMAGE_MAX_BYTES = 8 * 1024 * 1024;
const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];

const props = defineProps({
  number: { type: String, required: true },
  currentUserId: { type: [String, Number], default: null },
  readonly: { type: Boolean, default: false }
});

const NEAR_BOTTOM_PX = 80;

const comments = ref([]);
const draft = ref('');
const pendingImages = ref([]);
const error = ref('');
const sending = ref(false);
const listRef = ref(null);
const fileInput = ref(null);
const previewFile = ref(null);
const {
  recording,
  paused,
  elapsedMs,
  pending: pendingAudio,
  waveLevel,
  start: startRecording,
  stop: stopRecording,
  cancel: cancelRecording,
  togglePause,
  clearPending: clearPendingAudio
} = useAudioRecorder({
  onError: (message) => {
    error.value = message;
  }
});
const playback = ref(null);
const playing = ref(false);
let pollId = null;

const audioSession = computed(() => recording.value || !!pendingAudio.value);
const canSend = computed(
  () =>
    !sending.value &&
    !recording.value &&
    (!!draft.value.trim() || pendingImages.value.length > 0 || !!pendingAudio.value)
);

function isMine(comment) {
  return String(comment.author?.id) === String(props.currentUserId);
}

function authorName(comment) {
  return comment.author?.name || `#${comment.author?.id || '?'}`;
}

function formatTime(value) {
  return value ? new Date(value).toLocaleString('pt-BR') : '';
}

function commentImages(comment) {
  return Array.isArray(comment.images) ? comment.images : [];
}

function commentAudios(comment) {
  return Array.isArray(comment.audios) ? comment.audios : [];
}

function attachmentUrl(file) {
  return api.attachmentUrl(props.number, file.id);
}

function isNearBottom() {
  const list = listRef.value;
  if (!list) return true;
  return list.scrollHeight - list.scrollTop - list.clientHeight < NEAR_BOTTOM_PX;
}

async function scrollToBottom() {
  await nextTick();
  if (listRef.value) listRef.value.scrollTop = listRef.value.scrollHeight;
}

async function loadComments({ stickToBottom = false } = {}) {
  try {
    const shouldStick = stickToBottom || isNearBottom();
    const payload = await api.comments(props.number);
    comments.value = Array.isArray(payload.items) ? payload.items : [];
    if (shouldStick) await scrollToBottom();
  } catch (err) {
    error.value = err.message;
  }
}

function onComposeKeydown(event) {
  if (event.key !== 'Enter' || event.shiftKey) return;
  event.preventDefault();
  sendComment();
}

function openFilePicker() {
  fileInput.value?.click();
}

function onPickFiles(event) {
  addPendingImages([...event.target.files]);
  event.target.value = '';
}

function onPaste(event) {
  const images = [...(event.clipboardData?.items || [])]
    .filter((item) => item.type.startsWith('image/'))
    .map((item) => item.getAsFile())
    .filter(Boolean);
  if (!images.length) return;
  event.preventDefault();
  addPendingImages(images);
}

function addPendingImages(files) {
  error.value = '';
  const accepted = [];
  for (const file of files) {
    const reason = rejectImageReason(file);
    if (reason) {
      error.value = reason;
      continue;
    }
    accepted.push({
      id: `${file.name}-${file.size}-${file.lastModified}-${Math.random()}`,
      file,
      url: URL.createObjectURL(file)
    });
  }
  const room = COMMENT_IMAGES_MAX - pendingImages.value.length;
  if (accepted.length > room) {
    accepted.slice(room).forEach((item) => URL.revokeObjectURL(item.url));
    error.value = `No máximo ${COMMENT_IMAGES_MAX} imagens por comentário`;
  }
  pendingImages.value = [...pendingImages.value, ...accepted.slice(0, Math.max(room, 0))];
}

function rejectImageReason(file) {
  if (!IMAGE_TYPES.includes(file.type)) return 'Só imagens (JPEG, PNG, GIF ou WebP)';
  if (file.size > IMAGE_MAX_BYTES) return 'Imagem deve ter no máximo 8 MB';
  return '';
}

function removePendingImage(id) {
  const current = pendingImages.value.find((item) => item.id === id);
  if (current) URL.revokeObjectURL(current.url);
  pendingImages.value = pendingImages.value.filter((item) => item.id !== id);
}

function clearPendingImages() {
  pendingImages.value.forEach((item) => URL.revokeObjectURL(item.url));
  pendingImages.value = [];
}

function onPlaybackPlay() {
  playing.value = true;
}

function onPlaybackPause() {
  playing.value = false;
}

function togglePlayback() {
  if (!pendingAudio.value || !playback.value) return;
  if (playback.value.paused) playback.value.play().catch(() => {});
  else playback.value.pause();
}

function discardAudio() {
  if (playback.value) {
    playback.value.pause();
    playback.value.currentTime = 0;
  }
  playing.value = false;
  cancelRecording();
}

async function sendComment() {
  const body = draft.value.trim();
  const files = [
    ...pendingImages.value.map((item) => item.file),
    ...(pendingAudio.value ? [pendingAudio.value.file] : [])
  ];
  if ((!body && !files.length) || sending.value || recording.value) return;
  sending.value = true;
  error.value = '';
  try {
    const created = await api.addComment(props.number, body, files);
    comments.value = [...comments.value, created];
    draft.value = '';
    clearPendingImages();
    playing.value = false;
    clearPendingAudio();
    await scrollToBottom();
  } catch (err) {
    error.value = err.message;
  } finally {
    sending.value = false;
  }
}

function startPolling() {
  stopPolling();
  pollId = window.setInterval(loadComments, POLL_MS);
}

function stopPolling() {
  if (pollId) window.clearInterval(pollId);
  pollId = null;
}

onMounted(async () => {
  await loadComments({ stickToBottom: true });
  startPolling();
});

watch(
  () => props.number,
  async () => {
    await loadComments({ stickToBottom: true });
  }
);

onBeforeUnmount(() => {
  stopPolling();
  clearPendingImages();
  playing.value = false;
  clearPendingAudio();
});
</script>

<template>
  <div class="chat">
    <div ref="listRef" class="chat-list">
      <p v-if="!comments.length" class="muted chat-empty">Nenhum comentário ainda. Comece a conversa interna.</p>
      <article
        v-for="comment in comments"
        :key="comment.id"
        class="chat-message"
        :class="{ mine: isMine(comment) }"
      >
        <p class="chat-author">{{ isMine(comment) ? 'Você' : authorName(comment) }}</p>
        <div v-if="commentImages(comment).length" class="chat-images">
          <button
            v-for="file in commentImages(comment)"
            :key="file.id"
            class="chat-image-btn"
            type="button"
            @click="previewFile = file"
          >
            <img class="chat-image" :src="attachmentUrl(file)" :alt="file.filename" />
          </button>
        </div>
        <div v-if="commentAudios(comment).length" class="chat-audios">
          <div v-for="file in commentAudios(comment)" :key="file.id" class="chat-audio-block">
            <audio
              class="chat-audio"
              :src="attachmentUrl(file)"
              controls
              preload="metadata"
            />
            <p v-if="file.transcript" class="chat-transcript">{{ file.transcript }}</p>
          </div>
        </div>
        <p v-if="comment.body" class="chat-body">{{ comment.body }}</p>
        <p class="chat-time">{{ formatTime(comment.created_at) }}</p>
      </article>
    </div>
    <p v-if="error" class="error">{{ error }}</p>
    <div v-if="!readonly" class="chat-composer">
      <div v-if="pendingImages.length" class="chat-pending">
        <div v-for="item in pendingImages" :key="item.id" class="chat-pending-item">
          <div class="chat-pending-thumb" :style="{ backgroundImage: `url('${item.url}')` }" :title="item.file.name" />
          <button class="chat-pending-remove" type="button" aria-label="Remover imagem" @click="removePendingImage(item.id)">
            ×
          </button>
        </div>
      </div>
      <audio
        v-if="pendingAudio"
        ref="playback"
        :src="pendingAudio.url"
        preload="metadata"
        hidden
        @play="onPlaybackPlay"
        @pause="onPlaybackPause"
        @ended="onPlaybackPause"
      />
      <div class="chat-compose" :class="{ 'chat-compose-audio': audioSession }">
        <input
          ref="fileInput"
          type="file"
          accept="image/jpeg,image/png,image/gif,image/webp"
          multiple
          hidden
          @change="onPickFiles"
        />
        <AudioWaveform v-if="audioSession" :level="waveLevel" :paused="paused || !!pendingAudio" />
        <textarea
          v-else
          v-model="draft"
          class="input chat-input"
          rows="3"
          :maxlength="COMMENT_MAX"
          placeholder="Escreva um comentário interno para os agentes"
          @keydown="onComposeKeydown"
          @paste="onPaste"
        />
        <div class="chat-compose-actions">
          <div class="chat-compose-tools">
            <button
              v-if="!audioSession"
              class="btn chat-attach"
              type="button"
              aria-label="Gravar áudio"
              :disabled="sending"
              @click="startRecording"
            >
              <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
                <path
                  fill="currentColor"
                  d="M12 14a3 3 0 0 0 3-3V7a3 3 0 1 0-6 0v4a3 3 0 0 0 3 3Zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-3.08A7 7 0 0 0 19 11h-2Z"
                />
              </svg>
            </button>
            <template v-else>
              <button class="btn chat-attach" type="button" aria-label="Cancelar áudio" :disabled="sending" @click="discardAudio">
                <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
                  <path
                    fill="currentColor"
                    d="M6.4 5 5 6.4 10.6 12 5 17.6 6.4 19 12 13.4 17.6 19 19 17.6 13.4 12 19 6.4 17.6 5 12 10.6 6.4 5Z"
                  />
                </svg>
              </button>
              <button
                v-if="recording"
                class="btn chat-attach"
                type="button"
                :aria-label="paused ? 'Continuar gravação' : 'Pausar áudio'"
                :disabled="sending"
                @click="togglePause"
              >
                <svg v-if="paused" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
                  <path fill="currentColor" d="M8 5v14l11-7-11-7Z" />
                </svg>
                <svg v-else viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
                  <path fill="currentColor" d="M7 5h4v14H7V5Zm6 0h4v14h-4V5Z" />
                </svg>
              </button>
              <button
                v-else
                class="btn chat-attach"
                type="button"
                :aria-label="playing ? 'Pausar áudio' : 'Ouvir áudio'"
                :disabled="sending"
                @click="togglePlayback"
              >
                <svg v-if="playing" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
                  <path fill="currentColor" d="M7 5h4v14H7V5Zm6 0h4v14h-4V5Z" />
                </svg>
                <svg v-else viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
                  <path fill="currentColor" d="M8 5v14l11-7-11-7Z" />
                </svg>
              </button>
              <button
                v-if="recording"
                class="btn chat-record-timer"
                type="button"
                aria-label="Parar gravação"
                :disabled="sending"
                @click="stopRecording"
              >
                <svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true">
                  <path fill="currentColor" d="M8 8h8v8H8z" />
                </svg>
                {{ formatClock(elapsedMs) }}
              </button>
              <span v-else class="chat-record-clock">{{ formatClock(pendingAudio?.durationMs || elapsedMs) }}</span>
            </template>
            <button
              class="btn chat-attach"
              type="button"
              aria-label="Anexar imagem"
              :disabled="sending || recording"
              @click="openFilePicker"
            >
              <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
                <path
                  fill="currentColor"
                  d="M16.5 6.5v9.25a4.25 4.25 0 1 1-8.5 0V7.75a2.75 2.75 0 1 1 5.5 0v7.5a1.25 1.25 0 1 1-2.5 0V8.5h-1.5v6.75a2.75 2.75 0 1 0 5.5 0V7.75a4.25 4.25 0 1 0-8.5 0v8a5.75 5.75 0 1 0 11.5 0V6.5h-1.5Z"
                />
              </svg>
            </button>
          </div>
          <button class="btn primary" type="button" :disabled="!canSend" @click="sendComment">
            Enviar
          </button>
        </div>
      </div>
    </div>
    <AttachmentPreview
      :open="!!previewFile"
      :number="number"
      :file="previewFile"
      @close="previewFile = null"
    />
  </div>
</template>
