/* ATINA pseudonym-only cloud progression client. No Auth accounts or XP writes from the browser. */
(() => {
  const TOKEN_KEY = 'atinaPlayerTokenV1';
  const NICK_KEY = 'atinaPlayerNicknameV1';
  const $ = id => document.getElementById(id);

  function randomToken() {
    const bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);
    return Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
  }

  function getToken() {
    let token = localStorage.getItem(TOKEN_KEY);
    if (!/^[0-9a-f]{64}$/.test(token || '')) {
      token = randomToken();
      localStorage.setItem(TOKEN_KEY, token);
    }
    return token;
  }

  function render(profile) {
    if (!profile) return;
    const xp = Number(profile.xp || 0);
    const level = Math.floor(xp / 250) + 1;
    const progress = xp % 250;
    const levelEl = $('atinaLevelValue');
    const xpEl = $('atinaXpValue');
    const fill = $('atinaXpFill');
    const meta = $('atinaXpMeta');
    if (levelEl) levelEl.textContent = 'Nível ' + level;
    if (xpEl) xpEl.textContent = xp + ' XP';
    if (fill) fill.style.width = (progress / 250 * 100) + '%';
    if (meta) meta.textContent = progress + ' / 250 XP para o próximo nível';
    const total = $('dailyTotal');
    if (total) total.textContent = String(profile.total_challenges || 0);
    const streak = $('dailyStreak');
    if (streak) streak.textContent = String(profile.streak || 0) + ' dias';
    const daily = $('dailyMissionProgress');
    if (daily) daily.textContent = Math.min(3, Number(profile.daily_count || 0)) + ' de 3 desafios';
    const status = $('dailyMissionStatus');
    if (status) status.textContent = Number(profile.daily_count || 0) >= 3 ? 'Missão concluída' : 'Missão por concluir';
    const bar = $('dailyMissionFill');
    if (bar) bar.style.width = (Math.min(3, Number(profile.daily_count || 0)) / 3 * 100) + '%';
    const badgeBox = $('atinaBadges');
    if (badgeBox) {
      const thresholds = [1, 10, 25, 50, 100];
      const labels = ['Primeiros passos', 'Mente ativa', 'Persistente', 'Veterano', 'Lenda ATINA'];
      badgeBox.replaceChildren();
      thresholds.forEach((threshold, index) => {
        const badge = document.createElement('span');
        badge.className = 'atina-badge' + (Number(profile.total_challenges || 0) >= threshold ? ' earned' : '');
        badge.textContent = labels[index];
        badgeBox.append(badge);
      });
    }
  }

  function getSupabase() { return typeof supabaseClient !== 'undefined' ? supabaseClient : null; }

  async function saveNickname() {
    const input = $('atinaPlayerNickname');
    const status = $('atinaPlayerStatus');
    const nickname = String(input?.value || '').trim();
    if (!nickname || nickname.length > 20) {
      if (status) status.textContent = 'Escolhe um pseudónimo entre 1 e 20 caracteres.';
      return null;
    }
    if (!getSupabase()) {
      if (status) status.textContent = 'A ligação ao servidor não está disponível.';
      return null;
    }
    if (status) status.textContent = 'A guardar a progressão…';
    try {
      const token = getToken();
      const { data, error } = await getSupabase().rpc('atina_v2_player_profile', {
        p_nickname: nickname,
        p_player_token: token
      });
      if (error) throw error;
      localStorage.setItem(NICK_KEY, nickname);
      render(data);
      if (status) status.textContent = 'Progressão associada ao pseudónimo ' + data.nickname + '. Guarda o código de recuperação quando estiver disponível.';
      return data;
    } catch (error) {
      if (status) status.textContent = error.message || 'Não foi possível guardar a progressão na nuvem.';
      return null;
    }
  }

  async function copyRecoveryCode() {
    const status = $('atinaPlayerStatus');
    const token = getToken();
    try {
      await navigator.clipboard.writeText(token);
      if (status) status.textContent = 'Código de recuperação copiado. Guarda-o num local seguro; permite recuperar este pseudónimo noutro dispositivo.';
    } catch (_) {
      if (status) status.textContent = 'Não foi possível copiar automaticamente. Usa a opção de recuperar com o código neste dispositivo.';
    }
  }

  async function restoreFromCode() {
    const code = String($('atinaPlayerRecovery')?.value || '').trim().toLowerCase();
    const status = $('atinaPlayerStatus');
    if (!/^[0-9a-f]{64}$/.test(code)) {
      if (status) status.textContent = 'O código de recuperação deve ter 64 caracteres hexadecimais.';
      return null;
    }
    localStorage.setItem(TOKEN_KEY, code);
    return saveNickname();
  }

  async function restore() {
    const nickname = localStorage.getItem(NICK_KEY);
    const input = $('atinaPlayerNickname');
    if (input && nickname) input.value = nickname;
    if (!nickname || !getSupabase()) return null;
    return saveNickname();
  }

  async function recordCorrect(state, session) {
    if (!state?.session_id || !session?.token || !getSupabase()) return null;
    const nickname = localStorage.getItem(NICK_KEY);
    const token = localStorage.getItem(TOKEN_KEY);
    if (!nickname || !/^[0-9a-f]{64}$/.test(token || '')) return null;
    const { data, error } = await getSupabase().rpc('atina_v2_record_local_progress', {
      p_session_id: state.session_id,
      p_session_token: session.token,
      p_player_token: token
    });
    if (error) throw error;
    render(data);
    return data;
  }

  window.atinaCloudProgression = { saveNickname, restore, recordCorrect, copyRecoveryCode, restoreFromCode };
  document.addEventListener('DOMContentLoaded', () => {
    $('atinaPlayerSave')?.addEventListener('click', () => saveNickname());
    $('atinaPlayerCopyRecovery')?.addEventListener('click', () => copyRecoveryCode());
    $('atinaPlayerRestore')?.addEventListener('click', () => restoreFromCode());
    const saved = localStorage.getItem(NICK_KEY);
    if ($('atinaPlayerNickname') && saved) $('atinaPlayerNickname').value = saved;
  });
})();
