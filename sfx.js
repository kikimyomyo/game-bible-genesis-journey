// 기묘한 학습게임 공통 효과음 (Web Audio API, 외부 파일 불필요)
// window.GameSFX = { click, tap, correct, partial, wrong, finish, playTone }
(function () {
  let _ctx = null;
  function getCtx() {
    if (!_ctx) _ctx = new (window.AudioContext || window.webkitAudioContext)();
    return _ctx;
  }

  function playTone(freqs, totalMs = 250) {
    try {
      const ctx = getCtx();
      const list = Array.isArray(freqs) ? freqs : [freqs];
      const per = totalMs / list.length / 1000;
      const now = ctx.currentTime;
      list.forEach((f, i) => {
        const o = ctx.createOscillator();
        const g = ctx.createGain();
        o.type = 'sine';
        o.frequency.value = f;
        g.gain.setValueAtTime(0.001, now + per * i);
        g.gain.exponentialRampToValueAtTime(0.25, now + per * i + 0.01);
        g.gain.exponentialRampToValueAtTime(0.001, now + per * (i + 1));
        o.connect(g); g.connect(ctx.destination);
        o.start(now + per * i);
        o.stop(now + per * (i + 1));
      });
    } catch (e) {}
  }

  window.GameSFX = {
    playTone,
    click: () => playTone(1400, 45),
    tap: () => playTone(1000, 60),
    correct: () => playTone([659, 784, 988], 320),   // E5 G5 B5
    partial: () => playTone([784, 659], 220),          // G5 E5
    wrong: () => playTone([220, 180], 320),            // 저음
    finish: () => playTone([523, 659, 784, 1047], 600), // C5 E5 G5 C6
  };
})();
