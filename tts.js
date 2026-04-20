// 기묘한 학습게임 공통 TTS 유틸
// window.GameTTS = { speak, speakQueue, pickVoice, toEnglish, toKorean }
(function () {
  let _voices = [];
  function ensureVoices() {
    if (!('speechSynthesis' in window)) return [];
    if (_voices.length) return _voices;
    _voices = window.speechSynthesis.getVoices() || [];
    return _voices;
  }
  if ('speechSynthesis' in window) {
    ensureVoices();
    window.speechSynthesis.addEventListener('voiceschanged', () => {
      _voices = window.speechSynthesis.getVoices() || [];
    });
  }

  // 자연어 읽기에 부적합한 노벨티 음성 (macOS 내장)
  const NOVELTY_RE = /^(Albert|Bad News|Bahh|Bells|Boing|Bubbles|Cellos|Deranged|Good News|Hysterical|Organ|Pipe Organ|Trinoids|Whisper|Zarvox|Junior|Kathy|Princess|Ralph|Fred|Superstar|Wobble|Jester|Eddy|Flo|Grandma|Grandpa|Reed|Rocko|Sandy|Shelley)/i;

  // 선호 자연 음성 이름 (있으면 우선 선택)
  const PREFERRED = {
    en: ['Samantha', 'Alex', 'Daniel', 'Karen', 'Moira', 'Tessa', 'Victoria', 'Aaron', 'Nicky',
         'Google US English', 'Google UK English Female', 'Google UK English Male',
         'Microsoft Zira', 'Microsoft David', 'Microsoft Mark', 'Microsoft Aria'],
    ko: ['Yuna', 'Jihye', 'Heami', 'Sora', 'Google 한국의', 'Microsoft Heami', 'Microsoft SunHi'],
    ja: ['Kyoko', 'Otoya', 'Google 日本語'],
    zh: ['Ting-Ting', 'Sin-ji', 'Google 普通话', 'Google 國語'],
  };

  function pickVoice(lang) {
    const vs = ensureVoices();
    if (!vs.length) return null;
    const prefix = (lang || 'en-US').split('-')[0].toLowerCase();
    const langMatches = vs.filter((v) => v.lang && v.lang.toLowerCase().startsWith(prefix));
    if (!langMatches.length) return null;
    const ok = (v) => !NOVELTY_RE.test(v.name);
    const preferred = (PREFERRED[prefix] || [])
      .map((name) => langMatches.find((v) => ok(v) && v.name.includes(name)))
      .find(Boolean);
    if (preferred) return preferred;
    const exact = langMatches.find((v) => v.lang === lang && ok(v));
    if (exact) return exact;
    const local = langMatches.find((v) => v.localService && ok(v));
    if (local) return local;
    const nonNov = langMatches.find(ok);
    if (nonNov) return nonNov;
    return langMatches[0];
  }

  function makeUtterance(text, lang) {
    const u = new SpeechSynthesisUtterance(text);
    u.lang = lang || 'en-US';
    const v = pickVoice(u.lang);
    if (v) u.voice = v;
    u.rate = lang === 'ko-KR' ? 1.0 : 0.92;
    u.pitch = 1.0;
    return u;
  }

  function speak(text, lang) {
    try {
      if (!('speechSynthesis' in window)) return;
      window.speechSynthesis.cancel();
      window.speechSynthesis.speak(makeUtterance(text, lang || 'en-US'));
    } catch (e) {}
  }

  // chunks: [{ text, lang }, ...]
  function speakQueue(chunks) {
    try {
      if (!('speechSynthesis' in window)) return;
      window.speechSynthesis.cancel();
      chunks.forEach(({ text, lang }) => {
        window.speechSynthesis.speak(makeUtterance(text, lang || 'en-US'));
      });
    } catch (e) {}
  }

  // "형용사 (Adjective)" → "Adjective"
  function toEnglish(option) {
    const m = String(option).match(/\(([^)]+)\)/);
    return m ? m[1] : option;
  }
  // "형용사 (Adjective)" → "형용사"
  function toKorean(option) {
    return String(option).replace(/\s*\([^)]*\)\s*/, '').trim();
  }

  window.GameTTS = { speak, speakQueue, pickVoice, toEnglish, toKorean, ensureVoices };
})();
