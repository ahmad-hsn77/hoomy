import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';

export function createEmailAuth(secret, { apiKey, from, send = fetch }) {
  const challenges = new Map();
  const requestLimits = new Map();
  const ready = Boolean(apiKey && from);
  const lifetime = 10 * 60_000;

  function prune(entries, now) {
    for (const [key, entry] of entries) {
      if (entry.expiresAt <= now) entries.delete(key);
    }
  }

  function digest(key, code) {
    return createHmac('sha256', secret).update(key).update(':').update(code).digest();
  }

  async function issue({ key, purpose, email, ip, arabic, eligible }) {
    if (!eligible) return 202;
    const now = Date.now();
    prune(challenges, now);
    prune(requestLimits, now);
    if (requestLimits.size >= 10_000 || challenges.size >= 10_000) return 429;
    const scopes = [`ip:${ip}`, `email:${purpose}:${email}`];
    const limits = scopes.map((scope) =>
      requestLimits.get(scope) || { count: 0, expiresAt: now + lifetime });
    if (limits[0].count >= 20 || limits[1].count >= 4 ||
        now - (limits[1].lastSentAt || 0) < 60_000) return 429;
    for (const [index, limit] of limits.entries()) {
      limit.count++;
      limit.lastSentAt = now;
      requestLimits.set(scopes[index], limit);
    }

    const code = String(randomInt(0, 100_000_000)).padStart(8, '0');
    const previous = challenges.get(key);
    const entry = { hash: digest(key, code), attempts: 5, expiresAt: now + lifetime };
    challenges.set(key, entry);
    try {
      const response = await send('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        signal: AbortSignal.timeout(10_000),
        body: JSON.stringify({
          from,
          to: [email],
          subject: arabic ? 'رمز التحقق من Hoomy' : 'Your Hoomy verification code',
          text: arabic
            ? `رمز التحقق: ${code}\nتنتهي صلاحيته خلال 10 دقائق. لا تشاركه مع أحد.`
            : `Your verification code is ${code}. It expires in 10 minutes. Do not share it.`,
        }),
      });
      if (response.ok) return 202;
    } catch {
      // Provider errors can contain recipient information.
    }
    if (challenges.get(key) === entry) {
      if (previous && previous.expiresAt > Date.now()) challenges.set(key, previous);
      else challenges.delete(key);
    }
    return 502;
  }

  function consume(key, code) {
    const entry = challenges.get(key);
    if (!entry || entry.expiresAt <= Date.now() || typeof code !== 'string' ||
        !/^\d{8}$/.test(code)) return false;
    const matches = timingSafeEqual(entry.hash, digest(key, code));
    if (matches || --entry.attempts <= 0) challenges.delete(key);
    return matches;
  }

  return { ready, issue, consume };
}
