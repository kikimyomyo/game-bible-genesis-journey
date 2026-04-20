// 기묘한 학습게임 공통 기록 전송
// 사용법: window.GameRecorder.submit({ game, player, score, total, answers })
(function () {
  const CONFIG = window.GAME_CONFIG || {};
  const ENDPOINT = CONFIG.endpoint || "";

  async function submit(payload) {
    if (!ENDPOINT) {
      console.warn("[recorder] endpoint not configured — skipping");
      return { ok: false, reason: "no-endpoint" };
    }
    const body = {
      game: CONFIG.game || payload.game || "unknown",
      sheet_tab: CONFIG.sheet_tab || CONFIG.game || "기타",
      timestamp: new Date().toISOString(),
      ...payload,
    };
    try {
      const res = await fetch(ENDPOINT, {
        method: "POST",
        mode: "no-cors",
        headers: { "Content-Type": "text/plain;charset=utf-8" },
        body: JSON.stringify(body),
      });
      return { ok: true };
    } catch (e) {
      console.error("[recorder] failed", e);
      return { ok: false, reason: String(e) };
    }
  }

  window.GameRecorder = { submit };
})();
