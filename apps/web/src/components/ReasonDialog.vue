<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, required: true },
  description: { type: String, default: '' },
  confirmLabel: { type: String, default: 'Confirmar' },
  danger: { type: Boolean, default: false }
});

const emit = defineEmits(['cancel', 'confirm']);
const reason = ref('');
const fieldRef = ref(null);

function cancel() {
  emit('cancel');
}

function confirm() {
  const value = reason.value.trim();
  if (!value) return;
  emit('confirm', value);
}

function onDocumentKeydown(event) {
  if (event.key === 'Escape') cancel();
}

watch(
  () => props.open,
  async (isOpen) => {
    if (!isOpen) {
      document.removeEventListener('keydown', onDocumentKeydown);
      return;
    }
    reason.value = '';
    document.addEventListener('keydown', onDocumentKeydown);
    await nextTick();
    fieldRef.value?.focus();
  }
);

onBeforeUnmount(() => {
  document.removeEventListener('keydown', onDocumentKeydown);
});
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="dialog-backdrop" @click.self="cancel">
      <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="reason-dialog-title">
        <h2 id="reason-dialog-title" class="dialog-title">{{ title }}</h2>
        <p v-if="description" class="dialog-description">{{ description }}</p>
        <label class="field">
          <span>Motivo</span>
          <textarea
            ref="fieldRef"
            v-model="reason"
            rows="4"
            maxlength="2000"
            placeholder="Descreva o motivo"
            @keydown.ctrl.enter="confirm"
          />
        </label>
        <div class="dialog-actions">
          <button class="btn" type="button" @click="cancel">Cancelar</button>
          <button
            class="btn"
            :class="danger ? 'danger' : 'primary'"
            type="button"
            :disabled="!reason.trim()"
            @click="confirm"
          >
            {{ confirmLabel }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
