<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { api } from '../api.js';

const props = defineProps({
  open: { type: Boolean, default: false },
  number: { type: String, default: '' },
  file: { type: Object, default: null }
});

const emit = defineEmits(['close']);

const objectUrl = ref('');
const contentType = ref('');
const loading = ref(false);
const error = ref('');

const isImage = computed(() => contentType.value.startsWith('image/'));
const isAudio = computed(() => contentType.value.startsWith('audio/'));
const isPdf = computed(
  () => contentType.value === 'application/pdf' || props.file?.filename?.toLowerCase().endsWith('.pdf')
);

function revokeUrl() {
  if (!objectUrl.value) return;
  URL.revokeObjectURL(objectUrl.value);
  objectUrl.value = '';
}

function close() {
  revokeUrl();
  emit('close');
}

function onEscape(event) {
  if (event.key === 'Escape') close();
}

function download() {
  if (!objectUrl.value || !props.file) return;
  const link = document.createElement('a');
  link.href = objectUrl.value;
  link.download = props.file.filename;
  link.click();
}

async function loadAttachment() {
  revokeUrl();
  error.value = '';
  contentType.value = props.file?.content_type || '';
  if (!props.open || !props.number || !props.file) return;

  loading.value = true;
  try {
    const payload = await api.attachmentBlob(props.number, props.file.id);
    objectUrl.value = URL.createObjectURL(payload.blob);
    contentType.value = payload.type || contentType.value;
  } catch (err) {
    error.value = err.message;
  } finally {
    loading.value = false;
  }
}

watch(
  () => [props.open, props.file?.id, props.number],
  () => {
    if (props.open) document.addEventListener('keydown', onEscape);
    else document.removeEventListener('keydown', onEscape);
    loadAttachment();
  }
);

onBeforeUnmount(() => {
  document.removeEventListener('keydown', onEscape);
  revokeUrl();
});
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @click.self="close">
      <div class="dialog preview-dialog" role="dialog" aria-modal="true" aria-labelledby="attachment-preview-title">
        <h2 id="attachment-preview-title" class="dialog-title">{{ file?.filename || 'Anexo' }}</h2>
        <div class="preview-body">
          <p v-if="loading" class="muted">Carregando anexo…</p>
          <p v-else-if="error" class="error">{{ error }}</p>
          <img v-else-if="isImage && objectUrl" class="preview-media" :src="objectUrl" :alt="file.filename" />
          <audio v-else-if="isAudio && objectUrl" class="preview-audio" :src="objectUrl" controls />
          <iframe
            v-else-if="isPdf && objectUrl"
            class="preview-frame"
            :src="objectUrl"
            title="Pré-visualização do PDF"
          />
          <p v-else-if="objectUrl" class="muted">Este arquivo não tem pré-visualização. Use Baixar para abrir.</p>
        </div>
        <div class="dialog-actions">
          <button class="btn" type="button" :disabled="!objectUrl" @click="download">Baixar</button>
          <button class="btn primary" type="button" @click="close">Fechar</button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
