import { onBeforeUnmount, ref } from 'vue';

const MIME_CANDIDATES = [
  'audio/webm;codecs=opus',
  'audio/webm',
  'audio/mp4',
  'audio/ogg;codecs=opus'
];

export const AUDIO_MAX_MS = 5 * 60 * 1000;
export const AUDIO_MAX_BYTES = 10 * 1024 * 1024;

export function pickRecorderMime() {
  if (typeof MediaRecorder === 'undefined' || !MediaRecorder.isTypeSupported) return '';
  return MIME_CANDIDATES.find((type) => MediaRecorder.isTypeSupported(type)) || '';
}

export function audioExtension(mime) {
  const type = mime.split(';')[0];
  if (type.includes('mp4') || type.includes('aac') || type.includes('m4a')) return 'm4a';
  if (type.includes('mpeg')) return 'mp3';
  if (type.includes('ogg')) return 'ogg';
  if (type.includes('wav')) return 'wav';
  return 'webm';
}

export function formatClock(ms) {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const minutes = String(Math.floor(totalSeconds / 60)).padStart(2, '0');
  const seconds = String(totalSeconds % 60).padStart(2, '0');
  return `${minutes}:${seconds}`;
}

function amplitudeOf(samples) {
  let sum = 0;
  for (let index = 0; index < samples.length; index += 1) {
    const sample = (samples[index] - 128) / 128;
    sum += sample * sample;
  }
  return Math.min(1, Math.sqrt(sum / samples.length) * 4);
}

export function useAudioRecorder({ onError } = {}) {
  const recording = ref(false);
  const paused = ref(false);
  const elapsedMs = ref(0);
  const pending = ref(null);
  const waveLevel = ref(0);

  let mediaRecorder = null;
  let mediaStream = null;
  let chunks = [];
  let startedAt = 0;
  let frozenMs = 0;
  let tickId = null;
  let starting = false;
  let audioContext = null;
  let analyser = null;
  let sourceNode = null;
  let waveRaf = 0;
  let waveSamples = null;

  function reportError(message) {
    onError?.(message);
  }

  function currentElapsed() {
    if (!recording.value || paused.value) return frozenMs;
    return frozenMs + (Date.now() - startedAt);
  }

  function revokePending() {
    if (pending.value) URL.revokeObjectURL(pending.value.url);
    pending.value = null;
  }

  function stopTracks() {
    mediaStream?.getTracks().forEach((track) => track.stop());
    mediaStream = null;
  }

  function clearTick() {
    if (tickId) window.clearInterval(tickId);
    tickId = null;
  }

  function stopWaveform() {
    if (waveRaf) window.cancelAnimationFrame(waveRaf);
    waveRaf = 0;
    sourceNode?.disconnect();
    sourceNode = null;
    analyser = null;
    waveSamples = null;
    if (audioContext) {
      audioContext.close().catch(() => {});
      audioContext = null;
    }
  }

  function resetRecorder() {
    clearTick();
    stopWaveform();
    stopTracks();
    mediaRecorder = null;
    chunks = [];
    recording.value = false;
    paused.value = false;
  }

  function startWaveform() {
    const Context = window.AudioContext || window.webkitAudioContext;
    if (!Context || !mediaStream) return;
    audioContext = new Context();
    analyser = audioContext.createAnalyser();
    analyser.fftSize = 256;
    analyser.smoothingTimeConstant = 0.65;
    sourceNode = audioContext.createMediaStreamSource(mediaStream);
    sourceNode.connect(analyser);
    waveSamples = new Uint8Array(analyser.frequencyBinCount);
    audioContext.resume().catch(() => {});

    const draw = () => {
      waveRaf = window.requestAnimationFrame(draw);
      if (!analyser || paused.value) return;
      analyser.getByteTimeDomainData(waveSamples);
      waveLevel.value = amplitudeOf(waveSamples);
    };
    draw();
  }

  function buildPendingFile() {
    const mime = mediaRecorder?.mimeType || chunks[0]?.type || 'audio/webm';
    const blob = new Blob(chunks, { type: mime.split(';')[0] });
    if (!blob.size) {
      reportError('Não foi possível gravar o áudio');
      return;
    }
    if (blob.size > AUDIO_MAX_BYTES) {
      reportError('Áudio deve ter no máximo 10 MB');
      return;
    }
    const file = new File([blob], `audio-${Date.now()}.${audioExtension(mime)}`, { type: blob.type });
    revokePending();
    pending.value = {
      id: `${file.name}-${file.size}-${Math.random()}`,
      file,
      url: URL.createObjectURL(blob),
      durationMs: elapsedMs.value
    };
  }

  async function start() {
    if (recording.value || starting) return;
    if (typeof MediaRecorder === 'undefined' || !navigator.mediaDevices?.getUserMedia) {
      reportError('Este navegador não grava áudio');
      return;
    }

    starting = true;
    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      chunks = [];
      frozenMs = 0;
      elapsedMs.value = 0;
      waveLevel.value = 0;
      const mime = pickRecorderMime();
      mediaRecorder = mime ? new MediaRecorder(mediaStream, { mimeType: mime }) : new MediaRecorder(mediaStream);
      mediaRecorder.ondataavailable = (event) => {
        if (event.data?.size) chunks.push(event.data);
      };
      mediaRecorder.onstop = () => {
        elapsedMs.value = currentElapsed();
        buildPendingFile();
        resetRecorder();
      };
      mediaRecorder.onerror = () => {
        reportError('Falha ao gravar o áudio');
        resetRecorder();
      };

      startedAt = Date.now();
      recording.value = true;
      paused.value = false;
      mediaRecorder.start();
      startWaveform();
      tickId = window.setInterval(() => {
        elapsedMs.value = currentElapsed();
        if (elapsedMs.value >= AUDIO_MAX_MS) stop();
      }, 250);
    } catch (err) {
      stopTracks();
      stopWaveform();
      if (err?.name === 'NotAllowedError' || err?.name === 'PermissionDeniedError') {
        reportError('Permita o microfone no navegador para gravar áudio');
      } else {
        reportError('Não foi possível iniciar a gravação');
      }
    } finally {
      starting = false;
    }
  }

  function pause() {
    if (!recording.value || paused.value || mediaRecorder?.state !== 'recording') return;
    if (typeof mediaRecorder.pause !== 'function') {
      reportError('Este navegador não pausa a gravação');
      return;
    }
    mediaRecorder.pause();
    frozenMs = currentElapsed();
    elapsedMs.value = frozenMs;
    paused.value = true;
  }

  function resume() {
    if (!recording.value || !paused.value || mediaRecorder?.state !== 'paused') return;
    mediaRecorder.resume();
    startedAt = Date.now();
    paused.value = false;
  }

  function togglePause() {
    if (paused.value) resume();
    else pause();
  }

  function stop() {
    if (!recording.value || !mediaRecorder) return;
    elapsedMs.value = currentElapsed();
    if (mediaRecorder.state === 'recording' || mediaRecorder.state === 'paused') mediaRecorder.stop();
  }

  function cancel() {
    revokePending();
    elapsedMs.value = 0;
    waveLevel.value = 0;
    if (!recording.value) return;
    if (mediaRecorder) mediaRecorder.onstop = () => resetRecorder();
    const state = mediaRecorder?.state;
    recording.value = false;
    paused.value = false;
    if (state === 'recording' || state === 'paused') mediaRecorder.stop();
    else resetRecorder();
  }

  function clearPending() {
    revokePending();
    elapsedMs.value = 0;
    waveLevel.value = 0;
  }

  onBeforeUnmount(() => {
    cancel();
  });

  return {
    recording,
    paused,
    elapsedMs,
    pending,
    waveLevel,
    start,
    stop,
    cancel,
    togglePause,
    clearPending
  };
}
