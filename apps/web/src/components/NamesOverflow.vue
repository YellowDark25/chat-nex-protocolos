<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';

const MENU_GAP = 6;
const MENU_MAX_HEIGHT = 240;
const OPTION_HEIGHT = 32;
const MENU_PADDING = 12;

const props = defineProps({
  items: { type: Array, default: () => [] },
  emptyLabel: { type: String, default: '—' }
});

const names = computed(() => (props.items || []).map((item) => String(item || '').trim()).filter(Boolean));
const firstName = computed(() => names.value[0] || props.emptyLabel);
const extraNames = computed(() => names.value.slice(1));
const extraCount = computed(() => extraNames.value.length);

const isOpen = ref(false);
const rootRef = ref(null);
const menuRef = ref(null);
const menuStyle = ref({});

function toggle(event) {
  event.preventDefault();
  event.stopPropagation();
  isOpen.value = !isOpen.value;
}

function keepOpen(event) {
  event.stopPropagation();
}

function estimatedMenuHeight() {
  return Math.min(extraNames.value.length * OPTION_HEIGHT + MENU_PADDING, MENU_MAX_HEIGHT);
}

function placeMenu() {
  const trigger = rootRef.value?.querySelector('.names-overflow-more');
  if (!trigger) return;

  const rect = trigger.getBoundingClientRect();
  const spaceBelow = window.innerHeight - rect.bottom;
  const openUpward = spaceBelow < estimatedMenuHeight() + MENU_GAP;

  menuStyle.value = {
    position: 'fixed',
    left: `${rect.left}px`,
    minWidth: `${Math.max(rect.width, 180)}px`,
    zIndex: 80,
    ...(openUpward
      ? { bottom: `${window.innerHeight - rect.top + MENU_GAP}px`, top: 'auto' }
      : { top: `${rect.bottom + MENU_GAP}px`, bottom: 'auto' })
  };
}

function onDocumentPointerDown(event) {
  const target = event.target;
  if (rootRef.value?.contains(target) || menuRef.value?.contains(target)) return;
  isOpen.value = false;
}

function onEscape(event) {
  if (event.key === 'Escape') isOpen.value = false;
}

function bindListeners() {
  document.addEventListener('pointerdown', onDocumentPointerDown);
  document.addEventListener('keydown', onEscape);
  window.addEventListener('resize', placeMenu);
  window.addEventListener('scroll', placeMenu, true);
}

function unbindListeners() {
  document.removeEventListener('pointerdown', onDocumentPointerDown);
  document.removeEventListener('keydown', onEscape);
  window.removeEventListener('resize', placeMenu);
  window.removeEventListener('scroll', placeMenu, true);
}

watch(isOpen, async (open) => {
  if (open) {
    bindListeners();
    await nextTick();
    placeMenu();
    return;
  }
  unbindListeners();
});

onBeforeUnmount(unbindListeners);
</script>

<template>
  <div ref="rootRef" class="names-overflow" :class="{ open: isOpen }">
    <span class="names-overflow-first" :title="firstName">{{ firstName }}</span>
    <button
      v-if="extraCount"
      class="names-overflow-more"
      type="button"
      :aria-expanded="isOpen"
      aria-haspopup="listbox"
      :title="`Ver mais ${extraCount}`"
      @click="toggle"
    >
      +{{ extraCount }}
    </button>
    <Teleport to="body">
      <ul
        v-if="isOpen"
        ref="menuRef"
        class="names-overflow-menu"
        role="listbox"
        :style="menuStyle"
        @click="keepOpen"
      >
        <li v-for="(name, index) in extraNames" :key="`${name}-${index}`" class="names-overflow-item">
          {{ name }}
        </li>
      </ul>
    </Teleport>
  </div>
</template>
