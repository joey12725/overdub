/**
 * Spoken count-in ("five, six, seven, eight"; UI-04) through the Web Speech API.
 *
 * Only voices that synthesise on the device (`localService`) are used, so the game never sends
 * anything over the network; when there is no such voice, or no speechSynthesis at all, the
 * spoken words are skipped silently and the pitched ticks carry the count alone.
 */
const WORDS: Record<5 | 6 | 7 | 8, string> = { 5: 'five', 6: 'six', 7: 'seven', 8: 'eight' };

type Synth = Pick<SpeechSynthesis, 'speak' | 'cancel' | 'getVoices'>;

function synth(): Synth | null {
  const g = globalThis as { speechSynthesis?: Synth; SpeechSynthesisUtterance?: unknown };
  return g.speechSynthesis && typeof g.SpeechSynthesisUtterance === 'function' ? g.speechSynthesis : null;
}

function pickVoice(s: Synth): SpeechSynthesisVoice | null {
  let voices: SpeechSynthesisVoice[] = [];
  try {
    voices = s.getVoices();
  } catch {
    return null;
  }
  const local = voices.filter((v) => v.localService);
  if (!local.length) return null;
  return local.find((v) => /^en(-|_|$)/i.test(v.lang) && v.default) ?? local.find((v) => /^en/i.test(v.lang)) ?? null;
}

/**
 * Browsers fill the voice list asynchronously (Chrome returns [] until 'voiceschanged'), so ask for
 * it early, from unlock(), so the first count-in already has a voice.
 */
export function primeSpeech(): void {
  const s = synth() as (Synth & Partial<Pick<SpeechSynthesis, 'addEventListener'>>) | null;
  if (!s) return;
  try {
    s.getVoices();
    s.addEventListener?.('voiceschanged', () => s.getVoices(), { once: true });
  } catch {
    /* no speech on this device */
  }
}

/** Speaks one count word. `rate` > 1 speeds speech up for fast tempos. Never throws. */
export function speakCount(n: 5 | 6 | 7 | 8, volume: number, bpm: number): void {
  const s = synth();
  if (!s || volume <= 0.001) return;
  try {
    const voice = pickVoice(s);
    if (!voice) return;
    // A word should fit inside one beat; speech is roughly 0.35 s per short word at rate 1.
    const beat = 60 / Math.max(40, bpm);
    const u = new SpeechSynthesisUtterance(WORDS[n]);
    u.voice = voice;
    u.lang = voice.lang;
    u.rate = Math.min(2, Math.max(1, 0.4 / beat));
    u.pitch = 1;
    u.volume = Math.min(1, Math.max(0, volume));
    if (n === 5) s.cancel();
    s.speak(u);
  } catch {
    /* speech unavailable: the ticks still count */
  }
}

export function cancelSpeech(): void {
  try {
    synth()?.cancel();
  } catch {
    /* nothing to cancel */
  }
}
