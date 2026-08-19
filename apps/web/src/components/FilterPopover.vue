<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue';

const MENU_GAP = 6;

const props = defineProps({
  active: { type: Boolean, default: false }
});

const isOpen = ref(false);
const rootRef = ref(null);
const panelRef = ref(null);
const panelStyle = ref({});

function toggle() {
  isOpen.value = !isOpen.value;
}

function placePanel() {
  const trigger = rootRef.value?.querySelector('.filter-trigger');
  if (!trigger) return;
  const rect = trigger.getBoundingClientRect();
  const spaceBelow = window.innerHeight - rect.bottom;
  const openUpward = spaceBelow < 260;
  panelStyle.value = {
    position: 'fixed',
    left: `${Math.max(8, rect.right - 240)}px`,
    width: '240px',
    zIndex: 70,
    ...(openUpward
      ? { bottom: `${window.innerHeight - rect.top + MENU_GAP}px`, top: 'auto' }
      : { top: `${rect.bottom + MENU_GAP}px`, bottom: 'auto' })
  };
}

function isInsideFilterUi(target) {
  if (!(target instanceof Node)) return false;
  if (rootRef.value?.contains(target) || panelRef.value?.contains(target)) return true;
  return Boolean(target.closest?.('.nex-select-menu'));
}

function onDocumentPointerDown(event) {
  if (isInsideFilterUi(event.target)) return;
  isOpen.value = false;
}

function onEscape(event) {
  if (event.key === 'Escape') isOpen.value = false;
}

function bindListeners() {
  document.addEventListener('pointerdown', onDocumentPointerDown);
  document.addEventListener('keydown', onEscape);
  window.addEventListener('resize', placePanel);
  window.addEventListener('scroll', placePanel, true);
}

function unbindListeners() {
  document.removeEventListener('pointerdown', onDocumentPointerDown);
  document.removeEventListener('keydown', onEscape);
  window.removeEventListener('resize', placePanel);
  window.removeEventListener('scroll', placePanel, true);
}

watch(isOpen, async (open) => {
  if (open) {
    bindListeners();
    await nextTick();
    placePanel();
    return;
  }
  unbindListeners();
});

onBeforeUnmount(unbindListeners);
</script>

<template>
  <div ref="rootRef" class="filter-popover" :class="{ open: isOpen, active: props.active }">
    <button
      class="btn filter-trigger"
      type="button"
      aria-label="Filtros"
      :aria-expanded="isOpen"
      @click="toggle"
    >
      <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <path d="M4 5h16l-6.2 7.4V19l-3.6 1.6v-8.2L4 5z" />
      </svg>
      <span v-if="props.active" class="filter-dot" aria-hidden="true" />
    </button>
    <Teleport to="body">
      <div v-if="isOpen" ref="panelRef" class="filter-panel" :style="panelStyle">
        <slot />
      </div>
    </Teleport>
  </div>
</template>
