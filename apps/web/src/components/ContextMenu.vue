<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue';

const MENU_GAP = 4;

const props = defineProps({
  open: { type: Boolean, default: false },
  x: { type: Number, default: 0 },
  y: { type: Number, default: 0 },
  items: { type: Array, default: () => [] }
});

const emit = defineEmits(['close', 'select']);
const menuRef = ref(null);
const menuStyle = ref({});

function close() {
  emit('close');
}

function select(item) {
  if (!item || item.divider || item.disabled) return;
  emit('select', item);
}

function menuPosition(left, top) {
  return {
    position: 'fixed',
    left: `${Math.max(MENU_GAP, left)}px`,
    top: `${Math.max(MENU_GAP, top)}px`,
    zIndex: 80
  };
}

function placeMenu() {
  const menu = menuRef.value;
  if (!menu) return;
  const rect = menu.getBoundingClientRect();
  const left = Math.min(props.x, window.innerWidth - rect.width - MENU_GAP);
  const top = Math.min(props.y, window.innerHeight - rect.height - MENU_GAP);
  menuStyle.value = menuPosition(left, top);
}

function onDocumentPointerDown(event) {
  if (menuRef.value?.contains(event.target)) return;
  close();
}

function onEscape(event) {
  if (event.key === 'Escape') close();
}

function bindListeners() {
  document.addEventListener('pointerdown', onDocumentPointerDown);
  document.addEventListener('keydown', onEscape);
  window.addEventListener('resize', close);
  window.addEventListener('scroll', close, true);
}

function unbindListeners() {
  document.removeEventListener('pointerdown', onDocumentPointerDown);
  document.removeEventListener('keydown', onEscape);
  window.removeEventListener('resize', close);
  window.removeEventListener('scroll', close, true);
}

watch(
  () => [props.open, props.x, props.y, props.items],
  async ([isOpen]) => {
    unbindListeners();
    if (!isOpen) return;
    menuStyle.value = menuPosition(props.x, props.y);
    bindListeners();
    await nextTick();
    placeMenu();
  }
);

onBeforeUnmount(unbindListeners);
</script>

<template>
  <Teleport to="body">
    <ul
      v-if="open && items.length"
      ref="menuRef"
      class="context-menu"
      role="menu"
      :style="menuStyle"
      @contextmenu.prevent
    >
      <li v-for="(item, index) in items" :key="item.id || `divider-${index}`" role="none">
        <div v-if="item.divider" class="context-menu-divider" />
        <button
          v-else
          class="context-menu-item"
          :class="{ danger: item.danger }"
          type="button"
          role="menuitem"
          @click="select(item)"
        >
          <span class="context-menu-icon" aria-hidden="true">
            <svg v-if="item.icon === 'assume'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
              <circle cx="9" cy="7" r="4" />
              <path d="M19 8v6M16 11h6" />
            </svg>
            <svg v-else-if="item.icon === 'watch'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z" />
              <circle cx="12" cy="12" r="3" />
            </svg>
            <svg v-else-if="item.icon === 'unwatch'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M3 3l18 18" />
              <path d="M10.6 10.6A3 3 0 0 0 12 15a3 3 0 0 0 2.4-4.4" />
              <path d="M9.9 5.1A11 11 0 0 1 12 5c6.5 0 10 7 10 7a18 18 0 0 1-3.2 4.1" />
              <path d="M6.1 6.1C3.8 7.8 2 12 2 12s3.5 7 10 7a10 10 0 0 0 4.2-.9" />
            </svg>
            <svg v-else-if="item.icon === 'leave'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
              <path d="M16 17l5-5-5-5" />
              <path d="M21 12H9" />
            </svg>
            <svg v-else-if="item.icon === 'delete'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M3 6h18" />
              <path d="M8 6V4h8v2" />
              <path d="M19 6l-1 14H6L5 6" />
            </svg>
            <svg v-else-if="item.icon === 'restore'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M3 12a9 9 0 1 0 3-6.7" />
              <path d="M3 4v5h5" />
            </svg>
          </span>
          <span>{{ item.label }}</span>
        </button>
      </li>
    </ul>
  </Teleport>
</template>
