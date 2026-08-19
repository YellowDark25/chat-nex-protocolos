<script setup>
import { onBeforeUnmount, watch } from 'vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, required: true },
  description: { type: String, default: '' },
  confirmLabel: { type: String, default: 'Confirmar' },
  danger: { type: Boolean, default: false }
});

const emit = defineEmits(['cancel', 'confirm']);

function cancel() {
  emit('cancel');
}

function confirm() {
  emit('confirm');
}

function onDocumentKeydown(event) {
  if (event.key === 'Escape') cancel();
}

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) document.addEventListener('keydown', onDocumentKeydown);
    else document.removeEventListener('keydown', onDocumentKeydown);
  }
);

onBeforeUnmount(() => {
  document.removeEventListener('keydown', onDocumentKeydown);
});
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @click.self="cancel">
      <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="confirm-dialog-title">
        <h2 id="confirm-dialog-title" class="dialog-title">{{ title }}</h2>
        <p v-if="description" class="dialog-description">{{ description }}</p>
        <div class="dialog-actions">
          <button class="btn" type="button" @click="cancel">Cancelar</button>
          <button class="btn" :class="danger ? 'danger' : 'primary'" type="button" @click="confirm">
            {{ confirmLabel }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
