/**
 * Care Coach call transcription (OpenAI Whisper).
 *
 * POST raw audio (one speaker track per request) with headers:
 *   Content-Type:         audio/webm | audio/mp4 | audio/ogg ...
 *   X-Care-Coach-Ticket:  "<userId>.<expiryEpochSeconds>.<base64url HMAC-SHA256>" issued by
 *                         CareCoachTelephonyController.getDialerConfig in Salesforce
 *   X-Speaker:            Coach | Patient (echoed back)
 * Returns { speaker, durationSec, language, segments: [{ start, end, text }] }.
 *
 * Netlify env:
 *   OPENAI_API_KEY      required
 *   TRANSCRIBE_SECRET   required, same value as Care_Coach_Telephony__c.Transcribe_Secret__c
 *   WHISPER_MODEL       optional, default gpt-4o-transcribe (Egyptian Arabic stays colloquial;
 *                       set whisper-1 if you need per-segment timestamps)
 *   WHISPER_LANGUAGE    optional ISO-639-1 hint. The dialler sends X-Language: ar | en
 *
 * Must use ESM `export` - offline/package.json has "type": "module".
 */
import crypto from 'node:crypto';

const MAX_AUDIO_BYTES = 5.5 * 1024 * 1024;
// Whisper hallucinates short phrases ("Thank you.") on silence; drop low-confidence segments.
const MAX_NO_SPEECH_PROB = 0.6;
const MIN_AVG_LOGPROB = -1.2;

const EXTENSIONS = {
  'audio/webm': 'webm',
  'audio/ogg': 'ogg',
  'audio/mp4': 'm4a',
  'audio/x-m4a': 'm4a',
  'audio/m4a': 'm4a',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
  'audio/x-wav': 'wav'
};

export async function handler(event) {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: corsHeaders(), body: '' };
  }
  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  const apiKey = process.env.OPENAI_API_KEY;
  const secret = process.env.TRANSCRIBE_SECRET;
  if (!apiKey || !secret) {
    return json(503, { error: 'Transcription is not configured on the server (OPENAI_API_KEY / TRANSCRIBE_SECRET).' });
  }

  const headers = lowerCaseKeys(event.headers || {});
  const ticketCheck = verifyTicket(headers['x-care-coach-ticket'], secret);
  if (!ticketCheck.ok) {
    return json(401, { error: ticketCheck.error });
  }

  const audio = event.isBase64Encoded ? Buffer.from(event.body || '', 'base64') : Buffer.from(event.body || '', 'binary');
  if (!audio.length) {
    return json(400, { error: 'No audio received.' });
  }
  if (audio.length > MAX_AUDIO_BYTES) {
    return json(413, { error: 'The recording is too long to transcribe in one request.' });
  }

    const mime = String(headers['content-type'] || 'audio/webm').split(';')[0].trim().toLowerCase();
    const speaker = String(headers['x-speaker'] || 'Speaker').slice(0, 20);
    const model = process.env.WHISPER_MODEL || 'gpt-4o-transcribe';
    const language = String(headers['x-language'] || process.env.WHISPER_LANGUAGE || '').toLowerCase();
    const whisper = model.startsWith('whisper');

    try {
      const form = new FormData();
      form.append('file', new Blob([audio], { type: mime }), `${speaker.toLowerCase()}.${EXTENSIONS[mime] || 'webm'}`);
      form.append('model', model);
      if (whisper) {
        form.append('response_format', 'verbose_json');
        form.append('timestamp_granularities[]', 'segment');
      } else {
        form.append('response_format', 'json');
      }
      if (language && language !== 'auto') {
        form.append('language', language);
      }
      if (language === 'ar') {
        form.append(
          'prompt',
          'Egyptian colloquial Arabic (عامية مصرية), as spoken in Cairo. Keep the dialect. Do not rewrite it into formal Arabic.'
        );
      }
    const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      const message = (body.error && body.error.message) || `Whisper error ${res.status}`;
      return json(502, { error: message });
    }
    const segments = (body.segments || [])
      .filter((s) => (s.no_speech_prob ?? 0) <= MAX_NO_SPEECH_PROB && (s.avg_logprob ?? 0) >= MIN_AVG_LOGPROB)
      .map((s) => ({ start: round(s.start), end: round(s.end), text: String(s.text || '').trim() }))
      .filter((s) => s.text);
    if (!segments.length && body.text && !(body.segments || []).length) {
      segments.push({ start: 0, end: round(body.duration || 0), text: String(body.text).trim() });
    }
    return json(200, {
      speaker,
      userId: ticketCheck.userId,
      durationSec: round(body.duration || 0),
      language: body.language || language || null,
      model,
      segments
    });
  } catch (err) {
    return json(502, { error: err instanceof Error ? err.message : String(err) });
  }
}

export function verifyTicket(ticket, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  const parts = String(ticket || '').split('.');
  if (parts.length !== 3) {
    return { ok: false, error: 'Missing or malformed transcription ticket.' };
  }
  const [userId, expires, signature] = parts;
  const expected = crypto
    .createHmac('sha256', secret)
    .update(`${userId}.${expires}`)
    .digest('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return { ok: false, error: 'Invalid transcription ticket.' };
  }
  if (Number(expires) < nowSeconds) {
    return { ok: false, error: 'The transcription ticket has expired. Reopen the dialler and try again.' };
  }
  return { ok: true, userId };
}

function round(n) {
  return Math.round(Number(n || 0) * 100) / 100;
}

function lowerCaseKeys(obj) {
  const out = {};
  Object.keys(obj).forEach((k) => {
    out[k.toLowerCase()] = obj[k];
  });
  return out;
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: { ...corsHeaders(), 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  };
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, X-Care-Coach-Ticket, X-Speaker',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400'
  };
}
