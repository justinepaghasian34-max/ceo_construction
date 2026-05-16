const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { defineSecret, defineString } = require('firebase-functions/params');
const crypto = require('crypto');

const vision = require('@google-cloud/vision');

admin.initializeApp();

const visionClient = new vision.ImageAnnotatorClient();

const geminiApiKey = defineSecret('GEMINI_API_KEY');
const geminiModel = defineString('GEMINI_MODEL', { default: 'gemini-1.5-flash' });

const openaiApiKey = defineSecret('OPENAI_API_KEY');

const visualCrossingApiKey = defineSecret('VISUAL_CROSSING_API_KEY');

const sendgridApiKey = defineSecret('SENDGRID_API_KEY');
const sendgridFromEmail = defineString('SENDGRID_FROM_EMAIL', { default: '' });

let _geminiModelCache = {
  model: null,
  expiresAtMs: 0,
};

let _geminiModelsCache = {
  supported: null,
  expiresAtMs: 0,
};

async function geminiListModels({ apiKey, apiVersion }) {
  const base = apiVersion === 'v1' ? 'https://generativelanguage.googleapis.com/v1' : 'https://generativelanguage.googleapis.com/v1beta';
  const url = `${base}/models?key=${encodeURIComponent(apiKey)}`;
  const res = await fetch(url, { method: 'GET' });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = (json && (json.error?.message || json.message)) || `Gemini ListModels error (${res.status})`;
    const err = new Error(msg);
    err.status = res.status;
    err.body = json;
    throw err;
  }

  return Array.isArray(json?.models) ? json.models : [];
}

async function sendSendGridEmail({ apiKey, fromEmail, toEmail, subject, text }) {
  if (!apiKey || typeof apiKey !== 'string' || !apiKey.trim()) {
    throw new functions.https.HttpsError('failed-precondition', 'SendGrid API key is not configured.');
  }
  const from = String(fromEmail || '').trim();
  if (!from) {
    throw new functions.https.HttpsError('failed-precondition', 'SENDGRID_FROM_EMAIL is not configured.');
  }

  const to = String(toEmail || '').trim();
  if (!to) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing recipient email.');
  }

  const res = await fetch('https://api.sendgrid.com/v3/mail/send', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      personalizations: [
        {
          to: [{ email: to }],
          subject: String(subject || 'Your OTP Code'),
        },
      ],
      from: { email: from },
      content: [{ type: 'text/plain', value: String(text || '') }],
    }),
  });

  if (res.status >= 200 && res.status < 300) return;

  const body = await res.text().catch(() => '');
  throw new functions.https.HttpsError(
    'unavailable',
    `Failed to send OTP email (SendGrid status ${res.status}). ${body}`
  );
}

function generateOtpCode() {
  // 6-digit OTP
  return String(Math.floor(100000 + Math.random() * 900000));
}

function hashOtp({ code, salt }) {
  const h = crypto.createHash('sha256');
  h.update(String(code));
  h.update(':');
  h.update(String(salt));
  return h.digest('hex');
}

exports.sendEmailOtp = functions
  .runWith({ secrets: [sendgridApiKey] })
  .https.onCall(async (data, context) => {
    const auth = await resolveAuth(context, data);
    const uid = auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const userRef = admin.firestore().collection('users').doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'User profile not found');
    }

    const userData = userSnap.data() || {};
    const email = String(userData.email || '').trim();
    if (!email) {
      throw new functions.https.HttpsError('failed-precondition', 'User has no email on file');
    }

    const nowMs = Date.now();
    const code = generateOtpCode();
    const salt = crypto.randomBytes(16).toString('hex');
    const codeHash = hashOtp({ code, salt });
    const expiresAtMs = nowMs + 10 * 60 * 1000;

    const otpRef = admin.firestore().collection('email_otps').doc(uid);
    await otpRef.set(
      {
        uid,
        email,
        codeHash,
        salt,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAtMs,
        attempts: 0,
        lastSentAtMs: nowMs,
      },
      { merge: true }
    );

    const fromEmail = sendgridFromEmail.value();
    const apiKey = sendgridApiKey.value();

    await sendSendGridEmail({
      apiKey,
      fromEmail,
      toEmail: email,
      subject: 'Your OTP Code (CEO Construction)',
      text: `Your OTP code is: ${code}\n\nThis code will expire in 10 minutes. If you did not request this, please ignore this email.`,
    });

    return { ok: true };
  });

exports.verifyEmailOtp = functions
  .runWith({ secrets: [sendgridApiKey] })
  .https.onCall(async (data, context) => {
    const auth = await resolveAuth(context, data);
    const uid = auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

    const code = String((data && data.code) || '').trim();
    if (!/^[0-9]{6}$/.test(code)) {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid code format');
    }

    const otpRef = admin.firestore().collection('email_otps').doc(uid);
    const otpSnap = await otpRef.get();
    if (!otpSnap.exists) {
      throw new functions.https.HttpsError('failed-precondition', 'No OTP request found. Please resend the code.');
    }

    const otp = otpSnap.data() || {};
    const expiresAtMs = Number(otp.expiresAtMs || 0);
    if (!expiresAtMs || Date.now() > expiresAtMs) {
      await otpRef.delete().catch(() => null);
      throw new functions.https.HttpsError('deadline-exceeded', 'Code expired. Please resend the code.');
    }

    const attempts = Number(otp.attempts || 0);
    if (attempts >= 6) {
      throw new functions.https.HttpsError('resource-exhausted', 'Too many attempts. Please resend the code.');
    }

    const salt = String(otp.salt || '').trim();
    const expectedHash = String(otp.codeHash || '').trim();
    const gotHash = hashOtp({ code, salt });

    if (!salt || !expectedHash || gotHash !== expectedHash) {
      await otpRef.set({ attempts: attempts + 1 }, { merge: true });
      throw new functions.https.HttpsError('permission-denied', 'Invalid code');
    }

    await admin.firestore().collection('users').doc(uid).set(
      {
        otpVerified: true,
        otpVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: new Date().toISOString(),
      },
      { merge: true }
    );

    await otpRef.delete().catch(() => null);
    return { ok: true };
  });

function orderGenerateContentModels(models) {
  const supported = models
    .filter((m) => {
      const methods = Array.isArray(m?.supportedGenerationMethods) ? m.supportedGenerationMethods : [];
      return methods.includes('generateContent');
    })
    .map((m) => String(m?.name || '').trim())
    .filter(Boolean);

  if (!supported.length) return [];

  // Prefer explicit versioned models over generic ones.
  const preference = [
    'gemini-2.0-flash-001',
    'gemini-2.0-flash-lite',
    'gemini-2.5',
    'gemini-1.5-flash',
    'gemini-1.5-pro',
    'gemini-2.0-pro',
    'gemini-2.0-flash',
  ];

  const scored = supported.map((name) => {
    const lower = name.toLowerCase();
    let score = 1000;
    for (let i = 0; i < preference.length; i++) {
      if (lower.includes(preference[i])) {
        score = i;
        break;
      }
    }
    // Penalize the generic gemini-2.0-flash which may be deprecated for new users.
    if (lower === 'models/gemini-2.0-flash') score += 50;
    return { name, score };
  });

  scored.sort((a, b) => a.score - b.score || a.name.localeCompare(b.name));
  return scored.map((s) => s.name);
}

async function getSupportedGenerateContentModels({ apiKey, forceRefresh = false }) {
  const now = Date.now();
  if (!forceRefresh && Array.isArray(_geminiModelsCache.supported) && _geminiModelsCache.expiresAtMs > now) {
    return _geminiModelsCache.supported;
  }

  let models = [];
  try {
    models = await geminiListModels({ apiKey, apiVersion: 'v1beta' });
  } catch (e) {
    console.warn('Gemini ListModels v1beta failed, trying v1:', { message: e?.message, status: e?.status });
    models = await geminiListModels({ apiKey, apiVersion: 'v1' });
  }

  const ordered = orderGenerateContentModels(models);
  _geminiModelsCache = {
    supported: ordered,
    expiresAtMs: now + 10 * 60 * 1000,
  };
  return ordered;
}

async function getWorkingGeminiModel({ apiKey, requestedModel, forceRefresh = false }) {
  const now = Date.now();
  if (!forceRefresh && _geminiModelCache.model && _geminiModelCache.expiresAtMs > now) {
    return _geminiModelCache.model;
  }

  const requested = typeof requestedModel === 'string' ? requestedModel.trim() : '';
  const requestedFull = requested ? `models/${requested}` : '';

  const supported = await getSupportedGenerateContentModels({ apiKey, forceRefresh });
  const requestedIsSupported = requestedFull ? supported.includes(requestedFull) : false;
  const chosen = requestedIsSupported ? requestedFull : supported[0];
  if (!chosen) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'No Gemini models available that support generateContent for this API key/project. Please enable Gemini API and ensure the API key has access.'
    );
  }

  _geminiModelCache = {
    model: chosen,
    expiresAtMs: now + 10 * 60 * 1000,
  };

  if (requestedFull && !requestedIsSupported) {
    console.warn('Gemini requested model is not available/supported; using discovered model instead.', {
      requested: requestedFull,
      used: chosen,
      supportedCount: supported.length,
    });
  } else {
    console.log('Gemini model selected:', { used: chosen });
  }

  return chosen;
}

const GOVTRACK_GEMINI_SYSTEM_INSTRUCTION =
  'You are the factual core of GovTrack AI. Your sole job is to read project statistics and provide exact data to the user.\n\n'
  + 'CRITICAL ANTI-HALLUCINATION RULES:\n'
  + '1. ONLY extract information from the structured [PROJECT DATA] block provided in the prompt (and [IMAGE DATA] only when answering about an attached image).\n'
  + '2. If the user asks for a project percentage, locate the exact "Calculated Progress" field. State that exact number. Do NOT round it up or down.\n'
  + '3. If the [PROJECT DATA] block is empty or missing the requested metric, reply exactly with: "I cannot find that information in the current project records."\n'
  + '4. Never assume, hypothesize, or invent numbers. If data says 45%, the answer is 45%.\n'
  + '5. Do not answer questions completely unrelated to construction or project tracking. If asked a non-related question, say "I can only answer questions related to this project\'s tracking data."';

const GOVTRACK_GEMINI_GENERATION_CONFIG = {
  temperature: 0.0,
};

function formatGovtrackProgressValue(value) {
  if (value == null || value === '') return '';
  const n = Number(value);
  if (Number.isFinite(n)) return String(n);
  return String(value).trim();
}

function buildGovtrackProjectDataBlock(projectId, contextObj, detailedJson) {
  const p = contextObj?.project || {};
  const calculatedProgress = formatGovtrackProgressValue(p.progressPercentage);
  const lastUpdated = p.progressUpdatedAt != null ? String(p.progressUpdatedAt) : '';
  const status = p.status != null ? String(p.status) : '';
  const docId = projectId || p.id || '';

  const detailed = detailedJson && String(detailedJson).trim()
    ? String(detailedJson).trim()
    : '{}';

  return (
    '[PROJECT DATA]\n'
    + `Project Document ID: ${docId}\n`
    + `Calculated Progress: ${calculatedProgress}%\n`
    + `Last Updated Log: ${lastUpdated}\n`
    + `Current Status Info: ${status}\n`
    + `Detailed Records JSON:\n${detailed}\n`
    + '[END OF PROJECT DATA]'
  );
}

function buildGovtrackChatUserPrompt({
  projectDataBlock,
  userQuestion,
  imageContext = '',
  chatHistoryContext = '',
  deterministicContext = '',
  isSmallTalk = false,
}) {
  const blocks = [];
  if (projectDataBlock) blocks.push(projectDataBlock);
  if (deterministicContext) blocks.push(deterministicContext.trim());
  if (imageContext) blocks.push(imageContext.trim());
  if (chatHistoryContext) blocks.push(chatHistoryContext.trim());

  const dataSection = blocks.length ? `${blocks.join('\n\n')}\n\n` : '';

  if (isSmallTalk && !projectDataBlock) {
    return (
      `${dataSection}`
      + '[INSTRUCTION]\n'
      + 'The user is greeting or asking for help. Reply briefly and explain you answer construction project tracking questions using project records when a project is selected. Do not invent project metrics.\n\n'
      + `[USER QUESTION]\n${userQuestion}`
    );
  }

  return (
    `${dataSection}`
    + '[INSTRUCTION]\n'
    + 'Answer the following user question using ONLY the metrics listed inside the [PROJECT DATA] block above. '
    + 'For image questions, you may also use [IMAGE DATA]. '
    + 'If the exact answer or percentage is not listed, reply "Data unavailable". Do not guess or hallucinate.\n\n'
    + `[USER QUESTION]\n${userQuestion}`
  );
}

async function geminiGenerateContent({ apiKey, model, contents, generationConfig, systemInstruction }) {
  if (typeof apiKey !== 'string' || !apiKey.trim()) {
    throw new functions.https.HttpsError('failed-precondition', 'Gemini API key is not configured.');
  }

  const preferredModel = await getWorkingGeminiModel({ apiKey, requestedModel: model });

  const attempt = async ({ apiVersion, modelName }) => {
    const base = apiVersion === 'v1' ? 'https://generativelanguage.googleapis.com/v1' : 'https://generativelanguage.googleapis.com/v1beta';
    const url = `${base}/${modelName}:generateContent?key=${encodeURIComponent(apiKey)}`;
    const body = {
      contents,
      generationConfig,
    };
    if (systemInstruction) {
      body.systemInstruction = systemInstruction;
    }
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });

    const json = await res.json().catch(() => ({}));
    return { res, json };
  };

  // First try v1beta, then v1, and if the model is invalid, refresh model list and retry once.
  const tries = [
    { apiVersion: 'v1beta', refresh: false },
    { apiVersion: 'v1', refresh: false },
    { apiVersion: 'v1beta', refresh: true },
    { apiVersion: 'v1', refresh: true },
  ];

  let lastStatus;
  let lastMsg;
  for (const t of tries) {
    const supported = t.refresh
      ? await getSupportedGenerateContentModels({ apiKey, forceRefresh: true })
      : await getSupportedGenerateContentModels({ apiKey, forceRefresh: false });

    // Try preferred model first (if it is in supported), then fall back to the rest.
    const candidateModels = [preferredModel, ...supported].filter((m) => typeof m === 'string' && m.trim());
    const uniq = Array.from(new Set(candidateModels));

    for (const modelName of uniq) {
      const { res, json } = await attempt({ apiVersion: t.apiVersion, modelName });
      if (res.ok) {
        _geminiModelCache = { model: modelName, expiresAtMs: Date.now() + 10 * 60 * 1000 };
        return json;
      }

      lastStatus = res.status;
      lastMsg = (json && (json.error?.message || json.message)) || `Gemini API error (${res.status})`;
      const msgLower = String(lastMsg || '').toLowerCase();
      const looksLikeModelIssue =
        res.status === 404 ||
        msgLower.includes('not found') ||
        msgLower.includes('not supported') ||
        msgLower.includes('no longer available');

      if (!looksLikeModelIssue && res.status !== 400) {
        break;
      }
    }
  }

  throw new functions.https.HttpsError('unavailable', lastMsg || `Gemini API error (${lastStatus || 'unknown'})`);
}

function geminiExtractText(result) {
  const candidates = Array.isArray(result?.candidates) ? result.candidates : [];
  const first = candidates[0];
  const parts = Array.isArray(first?.content?.parts) ? first.content.parts : [];
  return parts.map((p) => (p?.text || '')).join('').trim();
}

function geminiFinishReason(result) {
  const candidates = Array.isArray(result?.candidates) ? result.candidates : [];
  const first = candidates[0];
  const r = first?.finishReason;
  return typeof r === 'string' ? r : '';
}

async function geminiGenerateWithContinuation({
  apiKey,
  model,
  contents,
  generationConfig,
  systemInstruction,
  maxTurns = 2,
}) {
  let collected = '';
  let turn = 0;
  let lastFinish = '';
  let currentContents = contents;

  while (turn <= maxTurns) {
    const res = await geminiGenerateContent({
      apiKey,
      model,
      contents: currentContents,
      generationConfig,
      systemInstruction,
    });
    const text = geminiExtractText(res);
    lastFinish = geminiFinishReason(res);
    if (text) {
      collected = collected ? `${collected}\n${text}` : text;
    }

    const looksTruncated = lastFinish && lastFinish.toLowerCase().includes('max');
    if (!looksTruncated) break;

    // Ask the model to continue EXACTLY where it left off.
    currentContents = [
      ...currentContents,
      {
        role: 'user',
        parts: [{ text: 'Continue from where you left off. Output only the continuation (no preamble).' }],
      },
    ];
    turn += 1;
  }

  return { text: collected.trim(), finishReason: lastFinish };
}

async function openaiChatCompletions({ apiKey, payload }) {
  if (typeof apiKey !== 'string' || !apiKey.trim()) {
    throw new functions.https.HttpsError('failed-precondition', 'OpenAI API key is not configured.');
  }

  const resp = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(payload),
  });

  const json = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    const msg = (json && (json.error?.message || json.message)) || `OpenAI error (${resp.status})`;
    throw new functions.https.HttpsError('unavailable', msg);
  }
  return json;
}

function openaiExtractText(result) {
  const c = Array.isArray(result?.choices) ? result.choices : [];
  const first = c[0];
  const text = first?.message?.content;
  return typeof text === 'string' ? text.trim() : '';
}

function openaiFinishReason(result) {
  const c = Array.isArray(result?.choices) ? result.choices : [];
  const first = c[0];
  const r = first?.finish_reason;
  return typeof r === 'string' ? r : '';
}

async function openaiGenerateWithContinuation({ apiKey, payload, maxTurns = 1 }) {
  let collected = '';
  let turn = 0;
  let lastFinish = '';
  let currentPayload = payload;

  while (turn <= maxTurns) {
    const res = await openaiChatCompletions({ apiKey, payload: currentPayload });
    const text = openaiExtractText(res);
    lastFinish = openaiFinishReason(res);
    if (text) {
      collected = collected ? `${collected}\n${text}` : text;
    }

    const looksTruncated = lastFinish && lastFinish.toLowerCase().includes('length');
    if (!looksTruncated) break;

    currentPayload = {
      ...currentPayload,
      messages: [
        ...(Array.isArray(currentPayload.messages) ? currentPayload.messages : []),
        { role: 'user', content: 'Continue from where you left off. Output only the continuation (no preamble).' },
      ],
    };
    turn += 1;
  }

  return { text: collected.trim(), finishReason: lastFinish };
}

async function resolveAuth(context, data) {
  const projectId = admin.app().options && admin.app().options.projectId;
  const incomingToken = typeof data?.idToken === 'string' ? data.idToken.trim() : '';
  console.log('resolveAuth: start', {
    projectId,
    hasContextAuth: Boolean(context && context.auth),
    contextAuthUid: context?.auth?.uid || null,
    hasIdToken: Boolean(incomingToken),
    idTokenLen: incomingToken ? incomingToken.length : 0,
  });

  if (context && context.auth) {
    return { uid: context.auth.uid, token: context.auth.token || {} };
  }

  const idToken = incomingToken;
  if (!idToken) {
    console.error('resolveAuth missing auth: context.auth is null and data.idToken is empty');
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated',
      {
        hasContextAuth: Boolean(context && context.auth),
        hasIdToken: false,
        projectId,
      }
    );
  }

  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    console.log('resolveAuth: verifyIdToken ok', {
      uid: decoded?.uid || null,
      aud: decoded?.aud || null,
      iss: decoded?.iss || null,
      projectId,
    });
    return { uid: decoded.uid, token: decoded };
  } catch (e) {
    const message = typeof e?.message === 'string' ? e.message : 'Invalid authentication token';
    const code = typeof e?.code === 'string' ? e.code : undefined;
    console.error('resolveAuth verifyIdToken failed:', {
      projectId,
      code,
      message,
      name: e?.name,
    });
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Invalid authentication token',
      {
        code,
        message,
        name: e?.name,
        projectId,
        hasContextAuth: false,
        hasIdToken: true,
        idTokenLen: idToken.length,
      }
    );
  }
}

async function resolveAuthOptional(context, data) {
  try {
    return await resolveAuth(context, data);
  } catch (e) {
    if (e instanceof functions.https.HttpsError && e.code === 'unauthenticated') {
      return null;
    }
    throw e;
  }
}

async function requireGovtrackRole(auth) {
  if (!auth || !auth.uid) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const tokenRole = (auth.token || {}).role;
  if (typeof tokenRole === 'string' && tokenRole.trim()) {
    const allowed = tokenRole === 'admin' || tokenRole === 'ceo_head' || tokenRole === 'site_manager';
    if (!allowed) {
      throw new functions.https.HttpsError('permission-denied', 'Insufficient permissions');
    }
    return tokenRole;
  }

  const uid = auth.uid;
  let role;
  try {
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    role = (userDoc.data() || {}).role;
  } catch (e) {
    console.error('requireGovtrackRole Firestore lookup failed:', e);
    throw new functions.https.HttpsError(
      'unavailable',
      'Unable to verify user role right now. Please check your internet connection and try again.'
    );
  }
  const allowed = role === 'admin' || role === 'ceo_head' || role === 'site_manager';
  if (!allowed) {
    throw new functions.https.HttpsError('permission-denied', 'Insufficient permissions');
  }
  return role;
}

async function requireProjectAccess({ auth, role, projectId }) {
  if (!auth || !auth.uid) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }
  if (typeof projectId !== 'string' || !projectId.trim()) {
    throw new functions.https.HttpsError('invalid-argument', 'projectId is required');
  }

  const normalizedRole = typeof role === 'string' ? role.trim() : '';
  const isPrivileged = normalizedRole === 'admin' || normalizedRole === 'ceo_head';
  if (isPrivileged) return;

  const uid = auth.uid;
  const projectRef = admin.firestore().collection('projects').doc(projectId);
  const projectSnap = await projectRef.get();
  if (!projectSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Project not found.');
  }
  const projectData = projectSnap.data() || {};

  const siteManagerId = typeof projectData.siteManagerId === 'string' ? projectData.siteManagerId : '';
  if (siteManagerId && siteManagerId === uid) return;

  const userSnap = await admin.firestore().collection('users').doc(uid).get();
  const userData = userSnap.exists ? (userSnap.data() || {}) : {};
  const assigned = Array.isArray(userData.assignedProjects) ? userData.assignedProjects : [];
  if (assigned.includes(projectId)) return;

  throw new functions.https.HttpsError('permission-denied', 'You do not have access to this project.');
}

// AI Analytics Cloud Function
exports.analyzeProjectProgress = functions.firestore
  .document('projects/{projectId}/daily_reports/{reportId}')
  .onCreate(async (snap, context) => {
    try {
      const { projectId, reportId } = context.params;
      const reportData = snap.data();
      
      // Get project data
      const projectDoc = await admin.firestore()
        .collection('projects')
        .doc(projectId)
        .get();
      
      if (!projectDoc.exists) {
        console.log('Project not found:', projectId);
        return null;
      }
      
      const projectData = projectDoc.data();
      
      // Get all daily reports for this project
      const reportsSnapshot = await admin.firestore()
        .collection('projects')
        .doc(projectId)
        .collection('daily_reports')
        .orderBy('reportDate', 'desc')
        .limit(30) // Last 30 reports
        .get();
      
      const reports = reportsSnapshot.docs.map(doc => doc.data());
      
      // Calculate progress analytics
      const analytics = await calculateProgressAnalytics(projectData, reports, reportData);
      
      // Save AI analysis
      await admin.firestore()
        .collection('ai_analysis')
        .add({
          projectId,
          reportId,
          analysisType: 'progress_analysis',
          ...analytics,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      
      // Send notifications if delays detected
      if (analytics.delayRisk > 0.7) {
        await sendDelayNotification(projectId, analytics);
      }
      
      // Log to history
      await admin.firestore()
        .collection('projects')
        .doc(projectId)
        .collection('history')
        .add({
          action: 'ai_analysis_completed',
          details: {
            reportId,
            progressPercentage: analytics.progressPercentage,
            delayRisk: analytics.delayRisk,
          },
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      
      console.log('AI analysis completed for project:', projectId);
      return null;
      
    } catch (error) {
      console.error('Error in AI analysis:', error);
      return null;
    }
  });

// Payroll Validation Trigger
exports.validatePayroll = functions.firestore
  .document('projects/{projectId}/payroll/{payrollId}')
  .onCreate(async (snap, context) => {
    try {
      const { projectId, payrollId } = context.params;
      const payrollData = snap.data();
      
      // Get attendance records for the payroll period (stored as ISO8601 strings)
      const attendanceSnapshot = await admin.firestore()
        .collection('projects')
        .doc(projectId)
        .collection('attendance')
        .where('attendanceDate', '>=', payrollData.payrollPeriodStart)
        .where('attendanceDate', '<=', payrollData.payrollPeriodEnd)
        .get();
      
      const attendanceRecords = attendanceSnapshot.docs.map(doc => doc.data());
      
      // Validate payroll against attendance
      const validation = validatePayrollData(payrollData, attendanceRecords);
      
      // Update payroll with validation results
      await admin.firestore()
        .collection('projects')
        .doc(projectId)
        .collection('payroll')
        .doc(payrollId)
        .update({
          validationResults: validation,
          validationStatus: validation.isValid ? 'validated' : 'needs_review',
          validatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      
      // Send notification to accounting
      await sendPayrollNotification(projectId, payrollId, validation);
      
      console.log('Payroll validation completed:', payrollId);
      return null;
      
    } catch (error) {
      console.error('Error in payroll validation:', error);
      return null;
    }
  });

// Revalidate payroll when attendance changes
exports.revalidatePayrollOnAttendanceChange = functions.firestore
  .document('projects/{projectId}/attendance/{attendanceId}')
  .onWrite(async (change, context) => {
    try {
      const { projectId } = context.params;
      const afterData = change.after.exists ? change.after.data() : null;
      const beforeData = change.before.exists ? change.before.data() : null;
      const attendanceDate = (afterData && afterData.attendanceDate) || (beforeData && beforeData.attendanceDate);
      
      if (!attendanceDate) {
        console.log('No attendanceDate found for attendance change in project:', projectId);
        return null;
      }
      
      // Find payroll periods that include this attendance date
      const payrollSnapshot = await admin.firestore()
        .collection('projects')
        .doc(projectId)
        .collection('payroll')
        .where('payrollPeriodStart', '<=', attendanceDate)
        .where('payrollPeriodEnd', '>=', attendanceDate)
        .get();
      
      if (payrollSnapshot.empty) {
        console.log('No payroll documents found for attendance date in project:', projectId);
        return null;
      }
      
      // For each affected payroll, recompute validation based on all attendance in its period
      const batch = admin.firestore().batch();
      
      for (const payrollDoc of payrollSnapshot.docs) {
        const payrollData = payrollDoc.data();
        
        const attendanceRangeSnapshot = await admin.firestore()
          .collection('projects')
          .doc(projectId)
          .collection('attendance')
          .where('attendanceDate', '>=', payrollData.payrollPeriodStart)
          .where('attendanceDate', '<=', payrollData.payrollPeriodEnd)
          .get();
        
        const attendanceRecords = attendanceRangeSnapshot.docs.map(doc => doc.data());
        const validation = validatePayrollData(payrollData, attendanceRecords);
        
        batch.update(payrollDoc.ref, {
          validationResults: validation,
          validationStatus: validation.isValid ? 'validated' : 'needs_review',
          validatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      
      await batch.commit();
      
      console.log('Revalidated payroll after attendance change for project:', projectId);
      return null;
      
    } catch (error) {
      console.error('Error revalidating payroll on attendance change:', error);
      return null;
    }
  });

// AI Progress Image Verification (Cloud Vision MVP)
exports.verifyProgressImage = functions.https.onCall(async (data, context) => {
  try {
    const auth = await resolveAuth(context, data);
    const role = await requireGovtrackRole(auth);

    function normalizeText(s) {
      return typeof s === 'string' ? s.toLowerCase() : '';
    }

    function clampPct(v) {
      const n = Number(v);
      if (!Number.isFinite(n)) return 0;
      return Math.max(0, Math.min(100, n));
    }

    function computeStageProgress({ labels = [], objects = [], extractedText = '', confidence = 0 }) {
      const names = [...labels, ...objects]
        .map((x) => normalizeText(x))
        .filter(Boolean);
      const text = normalizeText(extractedText);

      const hasAny = (keywords) => keywords.some((k) => names.some((n) => n.includes(k)) || text.includes(k));

      const stageHits = {
        foundation: hasAny(['foundation', 'concrete', 'rebar', 'excavation', 'footing', 'pile', 'formwork', 'cement']),
        structural: hasAny(['column', 'beam', 'slab', 'scaffold', 'scaffolding', 'reinforced', 'steel', 'girder', 'framework', 'structure', 'truss']),
        roofing: hasAny(['roof', 'roofing', 'truss', 'sheet', 'gutter', 'metal roof', 'tiles']),
        walls: hasAny(['wall', 'brick', 'masonry', 'block', 'hollow block', 'partition', 'plaster', 'drywall']),
      };

      // If OCR contains explicit stage percentages like "Foundation 75%"
      const stageFromOcr = {};
      const patterns = [
        ['foundation', /(foundation)[^\d]{0,20}(\d{1,3})\s*%/i],
        ['structural', /(structural|columns|beams|slab|frame)[^\d]{0,20}(\d{1,3})\s*%/i],
        ['roofing', /(roof|roofing)[^\d]{0,20}(\d{1,3})\s*%/i],
        ['walls', /(wall|walls|masonry|plaster)[^\d]{0,20}(\d{1,3})\s*%/i],
      ];
      for (const [key, re] of patterns) {
        const m = extractedText && typeof extractedText === 'string' ? extractedText.match(re) : null;
        if (m && m[2]) {
          stageFromOcr[key] = clampPct(m[2]);
        }
      }

      // Heuristic baseline: if stage is detected, assign a progress range influenced by confidence.
      // This is not a measurement tool; it provides a consistent, non-zero breakdown.
      const c = Number.isFinite(confidence) ? Math.max(0, Math.min(1, confidence)) : 0;
      const baseDetected = Math.round(35 + c * 45); // 35..80
      const baseNotDetected = 0;

      const out = {
        foundation: stageFromOcr.foundation ?? (stageHits.foundation ? baseDetected : baseNotDetected),
        structural: stageFromOcr.structural ?? (stageHits.structural ? baseDetected : baseNotDetected),
        roofing: stageFromOcr.roofing ?? (stageHits.roofing ? Math.max(15, baseDetected - 15) : baseNotDetected),
        walls: stageFromOcr.walls ?? (stageHits.walls ? Math.max(20, baseDetected - 10) : baseNotDetected),
      };

      // If nothing is detected, keep zeros.
      const sum = out.foundation + out.structural + out.roofing + out.walls;
      if (sum <= 0) {
        return {
          foundation: 0,
          structural: 0,
          roofing: 0,
          walls: 0,
        };
      }

      return out;
    }

    const isEmulator =
      process.env.FUNCTIONS_EMULATOR === 'true' ||
      process.env.FIREBASE_EMULATOR_HUB ||
      process.env.FUNCTIONS_EMULATOR_HOST;

    const imageUrl = typeof data?.imageUrl === 'string' ? data.imageUrl : null;
    const storagePath = typeof data?.storagePath === 'string' ? data.storagePath : null;
    const fileName = typeof data?.fileName === 'string' ? data.fileName : null;
    const projectId = typeof data?.projectId === 'string' ? data.projectId : null;
    const projectName = typeof data?.projectName === 'string' ? data.projectName : null;

    if (!projectId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'projectId is required.'
      );
    }

    await requireProjectAccess({ auth, role, projectId });

    if (!imageUrl && !storagePath) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Either imageUrl or storagePath must be provided.'
      );
    }

    const bucketName = admin.storage().bucket().name;
    const gcsUri = storagePath ? `gs://${bucketName}/${storagePath}` : null;
    const imageSource = gcsUri || imageUrl;

    if (isEmulator) {
      const confidence = 0.82;
      const pass = true;
      const status = 'on_track';

      const stageProgress = computeStageProgress({
        labels: ['construction site', 'building', 'scaffolding', 'concrete'],
        objects: ['crane', 'worker'],
        extractedText: '',
        confidence,
      });
      const progressPercent = Math.round(
        (stageProgress.foundation + stageProgress.structural + stageProgress.roofing + stageProgress.walls) / 4
      );

      const doc = {
        userId: auth.uid,
        projectId: projectId || null,
        projectName: projectName || null,
        imageUrl: imageUrl || null,
        storagePath: storagePath || null,
        fileName: fileName || null,
        pass,
        status,
        confidence,
        progressPercent,
        stageProgress,
        labels: ['construction site', 'building', 'scaffolding'],
        objects: ['crane', 'worker'],
        extractedText: '',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        raw: {
          emulator: true,
          imageSource,
        },
      };

      const ref = await admin.firestore().collection('ai_verifications').add(doc);
      return {
        ok: true,
        pass,
        status,
        confidence,
        progressPercent,
        stageProgress,
        labels: doc.labels,
        objects: doc.objects,
        extractedText: doc.extractedText,
        verificationId: ref.id,
        emulator: true,
      };
    }

    const [result] = await visionClient.annotateImage({
      image: { source: { imageUri: imageSource } },
      features: [
        { type: 'LABEL_DETECTION', maxResults: 10 },
        { type: 'OBJECT_LOCALIZATION', maxResults: 10 },
        { type: 'TEXT_DETECTION', maxResults: 5 },
      ],
    });

    const labelAnnotations = Array.isArray(result?.labelAnnotations)
      ? result.labelAnnotations
      : [];
    const localizedObjectAnnotations = Array.isArray(result?.localizedObjectAnnotations)
      ? result.localizedObjectAnnotations
      : [];
    const textAnnotations = Array.isArray(result?.textAnnotations)
      ? result.textAnnotations
      : [];

    const labels = labelAnnotations
      .map((l) => ({ description: l.description, score: l.score }))
      .filter((l) => typeof l.description === 'string');

    const objects = localizedObjectAnnotations
      .map((o) => ({ name: o.name, score: o.score }))
      .filter((o) => typeof o.name === 'string');

    const extractedText = textAnnotations.length > 0 && typeof textAnnotations[0].description === 'string'
      ? textAnnotations[0].description
      : '';

    const topScores = labels
      .map((l) => (typeof l.score === 'number' ? l.score : 0))
      .slice(0, 5);
    const confidence = topScores.length
      ? Math.max(0, Math.min(1, topScores.reduce((a, b) => a + b, 0) / topScores.length))
      : 0;

    const combinedNames = [
      ...labels.map((l) => (l.description || '').toLowerCase()),
      ...objects.map((o) => (o.name || '').toLowerCase()),
    ];
    const constructionKeywords = [
      'construction',
      'building',
      'architecture',
      'road',
      'bridge',
      'worker',
      'worksite',
      'crane',
      'excavator',
      'concrete',
      'scaffold',
    ];

    const looksLikeConstruction = constructionKeywords.some((k) =>
      combinedNames.some((n) => n.includes(k))
    );

    const pass = looksLikeConstruction && confidence >= 0.6;
    const status = pass ? 'on_track' : 'high_risk';

    const stageProgress = computeStageProgress({
      labels: labels.map((l) => l.description).slice(0, 10),
      objects: objects.map((o) => o.name).slice(0, 10),
      extractedText,
      confidence,
    });
    const progressPercent = Math.round(
      (stageProgress.foundation + stageProgress.structural + stageProgress.roofing + stageProgress.walls) / 4
    );

    const doc = {
      userId: auth.uid,
      projectId: projectId || null,
      projectName: projectName || null,
      imageUrl: imageUrl || null,
      storagePath: storagePath || null,
      fileName: fileName || null,
      pass,
      status,
      confidence,
      progressPercent,
      stageProgress,
      labels: labels.map((l) => l.description).slice(0, 10),
      objects: objects.map((o) => o.name).slice(0, 10),
      extractedText: extractedText ? extractedText.slice(0, 2000) : '',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      raw: {
        labelScores: labels.slice(0, 10),
        objectScores: objects.slice(0, 10),
      },
    };

    const ref = await admin.firestore().collection('ai_verifications').add(doc);

    return {
      ok: true,
      pass,
      status,
      confidence,
      progressPercent,
      stageProgress,
      labels: doc.labels,
      objects: doc.objects,
      extractedText: doc.extractedText,
      verificationId: ref.id,
    };
  } catch (error) {
    console.error('verifyProgressImage error:', error);
    const msg = typeof error?.message === 'string' ? error.message : '';
    const isVisionPermissionDenied =
      msg.includes('PERMISSION_DENIED') ||
      msg.includes('vision.googleapis.com') ||
      error?.code === 7;
    if (isVisionPermissionDenied) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Cloud Vision API is disabled or not yet enabled for this project. Enable the Vision API in Google Cloud Console for the same Firebase/GCP project, then retry after a few minutes.'
      );
    }
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    const message = typeof error?.message === 'string' ? error.message : 'Verification failed';
    throw new functions.https.HttpsError('internal', message);
  }
});

exports.visualCrossingMonthlyForecast = functions
  .runWith({ secrets: [visualCrossingApiKey], timeoutSeconds: 60 })
  .https.onCall(async (data, context) => {
    if (!context || !context.auth || !context.auth.uid) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated.'
      );
    }

    const city = typeof data?.city === 'string' ? data.city.trim() : '';
    const start = typeof data?.start === 'string' ? data.start.trim() : '';
    const end = typeof data?.end === 'string' ? data.end.trim() : '';
    if (!city || !start || !end) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'city, start, and end are required.'
      );
    }

    const apiKey = visualCrossingApiKey.value();
    if (!apiKey) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'VISUAL_CROSSING_API_KEY is not configured on the server.'
      );
    }

    const base = 'https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline';
    const url = `${base}/${encodeURIComponent(city)}/${encodeURIComponent(start)}/${encodeURIComponent(end)}?unitGroup=metric&include=days&key=${encodeURIComponent(apiKey)}&contentType=json`;

    let res;
    let json;
    try {
      res = await fetch(url, { method: 'GET' });
      json = await res.json().catch(() => ({}));
    } catch (e) {
      throw new functions.https.HttpsError(
        'unavailable',
        'Unable to reach weather provider. Please try again later.'
      );
    }

    if (!res.ok) {
      const msg =
        (json && (json.error?.message || json.message)) ||
        `Weather provider error (${res.status})`;
      const code = res.status === 401 || res.status === 403 ? 'failed-precondition' : 'unavailable';
      throw new functions.https.HttpsError(code, msg);
    }

    const days = Array.isArray(json?.days) ? json.days : [];
    const mapped = days.map((d) => ({
      datetime: d?.datetime,
      tempmin: d?.tempmin,
      tempmax: d?.tempmax,
      humidity: d?.humidity,
      windspeed: d?.windspeed,
      precipprob: d?.precipprob,
      conditions: d?.conditions,
    }));

    return { days: mapped };
  });

exports.govtrackChatGemini = functions
  .runWith({ secrets: [geminiApiKey], timeoutSeconds: 180 })
  .https.onCall(async (data, context) => {
  try {
    console.log('govtrackChatGemini auth presence:', {
      hasContextAuth: Boolean(context && context.auth),
      hasIdToken: typeof data?.idToken === 'string' && data.idToken.trim().length > 0,
    });
    const message = typeof data?.message === 'string' ? data.message.trim() : '';
    if (!message) {
      throw new functions.https.HttpsError('invalid-argument', 'Message is required');
    }

    const rawHistory = Array.isArray(data?.history) ? data.history : [];
    const history = rawHistory
      .filter((h) => h && typeof h === 'object')
      .map((h) => {
        const roleRaw = typeof h.role === 'string' ? h.role.trim().toLowerCase() : '';
        const role = roleRaw === 'assistant' ? 'assistant' : 'user';
        const text = typeof h.text === 'string' ? h.text.trim() : '';
        const hasImage = Boolean(h.hasImage);
        return { role, text, hasImage };
      })
      .filter((h) => h.text);

    const projectId = typeof data?.projectId === 'string' ? data.projectId.trim() : '';
    const projectName = typeof data?.projectName === 'string' ? data.projectName.trim() : '';

    const lowerMsg = message.toLowerCase();
    // Default to in-scope unless the message is clearly unrelated.
    // This prevents false refusals when users ask using different wording.
    const outOfScopeSignals = [
      'love',
      'relationship',
      'girlfriend',
      'boyfriend',
      'crush',
      'sex',
      'anime',
      'movie',
      'song',
      'lyrics',
      'joke',
      'meme',
      'game',
      'facebook',
      'tiktok',
      'instagram',
      'politics',
      'election',
      'president',
      'crypto',
      'bitcoin',
      'astrology',
      'zodiac',
      'medical',
      'diagnose',
    ];
    const constructionSignals = [
      'construction',
      'site',
      'project',
      'progress',
      'percentage',
      'stage',
      'foundation',
      'excavation',
      'rebar',
      'formwork',
      'concrete',
      'slab',
      'beam',
      'column',
      'masonry',
      'chb',
      'plaster',
      'roof',
      'roofing',
      'waterproof',
      'paint',
      'tile',
      'electrical',
      'wiring',
      'plumbing',
      'pipe',
      'materials',
      'inventory',
      'delivery',
      'safety',
      'risk',
      'delay',
      'schedule',
      'planning',
      'qa',
      'qc',
    ];

    const isClearlyOutOfScope = outOfScopeSignals.some((k) => lowerMsg.includes(k));
    const hasConstructionSignal = constructionSignals.some((k) => lowerMsg.includes(k));
    const inScope = hasConstructionSignal || !isClearlyOutOfScope;

    const imageUrl = typeof data?.imageUrl === 'string' ? data.imageUrl.trim() : '';
    const storagePath = typeof data?.storagePath === 'string' ? data.storagePath.trim() : '';

    // Require auth if the caller wants project context OR is providing an image (Vision/GCS access).
    const requiresAuth = Boolean(projectId) || Boolean(imageUrl || storagePath);
    const auth = requiresAuth ? await resolveAuth(context, data) : await resolveAuthOptional(context, data);
    let role = null;
    if (auth) {
      role = await requireGovtrackRole(auth);
    } else if (projectId) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated to use project context.');
    }

    let ocrText = '';
    let ocrLabels = [];
    let ocrObjects = [];
    if (imageUrl || storagePath) {
      try {
        let used = 'none';
        let visionImage = null;

        if (storagePath) {
          try {
            const file = admin.storage().bucket().file(storagePath);
            const [bytes] = await file.download();
            if (bytes && bytes.length) {
              visionImage = { content: Buffer.from(bytes).toString('base64') };
              used = 'storage_bytes';
            }
          } catch (downloadErr) {
            console.warn('govtrackChatGemini: failed to download storagePath; will try URI fallback', {
              storagePath,
              message: downloadErr?.message,
            });
          }
        }

        if (!visionImage) {
          const bucketName = admin.storage().bucket().name;
          const gcsUri = storagePath ? `gs://${bucketName}/${storagePath}` : null;
          const imageSource = gcsUri || imageUrl;
          visionImage = { source: { imageUri: imageSource } };
          used = gcsUri ? 'gcs_uri' : 'http_url';
        }

        console.log('govtrackChatGemini: running Vision OCR', {
          used,
          hasUrl: Boolean(imageUrl),
          hasStoragePath: Boolean(storagePath),
        });

        const [visionResult] = await visionClient.annotateImage({
          image: visionImage,
          features: [
            { type: 'TEXT_DETECTION', maxResults: 5 },
            { type: 'LABEL_DETECTION', maxResults: 10 },
            { type: 'OBJECT_LOCALIZATION', maxResults: 10 },
          ],
        });

        const textAnnotations = Array.isArray(visionResult?.textAnnotations)
          ? visionResult.textAnnotations
          : [];
        const labelAnnotations = Array.isArray(visionResult?.labelAnnotations)
          ? visionResult.labelAnnotations
          : [];
        const localizedObjectAnnotations = Array.isArray(visionResult?.localizedObjectAnnotations)
          ? visionResult.localizedObjectAnnotations
          : [];

        const extractedText = textAnnotations.length && textAnnotations[0]?.description
          ? String(textAnnotations[0].description)
          : '';
        ocrText = extractedText.trim().slice(0, 6000);

        ocrLabels = labelAnnotations
          .map((l) => String(l?.description || '').trim())
          .filter(Boolean)
          .slice(0, 10);

        ocrObjects = localizedObjectAnnotations
          .map((o) => String(o?.name || '').trim())
          .filter(Boolean)
          .slice(0, 10);
      } catch (e) {
        const emsg = typeof e?.message === 'string' ? e.message : '';
        const isVisionPermissionDenied =
          emsg.includes('PERMISSION_DENIED') ||
          emsg.includes('vision.googleapis.com') ||
          e?.code === 7;
        if (isVisionPermissionDenied) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'Cloud Vision API is disabled or not yet enabled for this project. Enable the Vision API in Google Cloud Console for the same Firebase/GCP project, then retry after a few minutes.'
          );
        }
        console.warn('govtrackChatGemini: Vision OCR failed; continuing without image context', {
          message: e?.message,
        });
      }
    }

    let projectDataJson = '';
    let projectContextObj = null;
    if (projectId && auth) {
      const uid = auth.uid;
      const isPrivileged = role === 'admin' || role === 'ceo_head';

      const projectRef = admin.firestore().collection('projects').doc(projectId);
      const projectSnap = await projectRef.get();
      if (!projectSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Project not found.');
      }
      const projectData = projectSnap.data() || {};

      if (!isPrivileged) {
        let hasAccess = false;
        const siteManagerId = typeof projectData.siteManagerId === 'string' ? projectData.siteManagerId : '';
        if (siteManagerId && siteManagerId === uid) {
          hasAccess = true;
        }

        if (!hasAccess) {
          const userSnap = await admin.firestore().collection('users').doc(uid).get();
          const userData = userSnap.exists ? (userSnap.data() || {}) : {};
          const assigned = Array.isArray(userData.assignedProjects) ? userData.assignedProjects : [];
          hasAccess = assigned.includes(projectId);
        }

        if (!hasAccess) {
          throw new functions.https.HttpsError('permission-denied', 'You do not have access to this project.');
        }
      }

      const safeLimit = (arr, n) => (Array.isArray(arr) ? arr.slice(0, n) : []);
      const stringifySafe = (v, max) => {
        const s = JSON.stringify(v);
        return s.length > max ? s.slice(0, max) : s;
      };

      const [dailyReportsSnap, inventorySnap, deliveriesSnap, usageSnap, latestAiProgressSnap] = await Promise.all([
        projectRef.collection('daily_reports').orderBy('reportDate', 'desc').limit(10).get().catch(() => null),
        projectRef.collection('material_inventory').limit(80).get().catch(() => null),
        projectRef.collection('deliveries').limit(40).get().catch(() => null),
        admin.firestore().collectionGroup('material_usage').where('projectId', '==', projectId).limit(120).get().catch(() => null),
        admin
          .firestore()
          .collection('ai_analysis')
          .where('kind', '==', 'govtrack_progress_report')
          .where('projectId', '==', projectId)
          .orderBy('aiUpdatedAt', 'desc')
          .limit(1)
          .get()
          .catch(() => null),
      ]);

      const dailyReports = dailyReportsSnap
        ? dailyReportsSnap.docs.map((d) => (d.data() || {}))
        : [];
      const inventory = inventorySnap
        ? inventorySnap.docs.map((d) => (d.data() || {}))
        : [];
      const deliveries = deliveriesSnap
        ? deliveriesSnap.docs.map((d) => (d.data() || {}))
        : [];
      const materialUsage = usageSnap
        ? usageSnap.docs.map((d) => (d.data() || {}))
        : [];

      const compactDaily = safeLimit(dailyReports, 10).map((r) => ({
        reportDate: r.reportDate || null,
        weatherCondition: r.weatherCondition || null,
        temperatureC: r.temperatureC ?? null,
        issues: safeLimit(r.issues, 8),
        workAccomplishments: safeLimit(r.workAccomplishments, 8).map((w) => ({
          wbsCode: w.wbsCode || null,
          description: w.description || null,
          unit: w.unit || null,
          quantityAccomplished: w.quantityAccomplished ?? null,
          percentageComplete: w.percentageComplete ?? null,
        })),
        remarks: r.remarks || null,
      }));

      const compactInv = safeLimit(inventory, 60).map((i) => ({
        materialName: i.materialName || null,
        unit: i.unit || null,
        stock: i.stock ?? null,
        unitPrice: i.unitPrice ?? i.price ?? null,
        updatedAt: i.updatedAt || null,
      }));

      const compactDeliveries = safeLimit(deliveries, 30).map((d) => ({
        description: d.description || null,
        supplier: d.supplier || null,
        receivedAt: d.receivedAt || d.date || d.deliveryDate || null,
        status: d.status || null,
      }));

      const compactUsage = safeLimit(materialUsage, 100).map((u) => ({
        materialName: u.materialName || null,
        quantity: u.quantity ?? null,
        unit: u.unit || null,
        date: u.date || null,
        reportId: u.reportId || null,
        remarks: u.remarks || null,
      }));

      const latestAiProgressDoc = latestAiProgressSnap && latestAiProgressSnap.docs && latestAiProgressSnap.docs.length
        ? (latestAiProgressSnap.docs[0].data() || {})
        : null;
      const latestAiProgressPercentRaw = latestAiProgressDoc ? latestAiProgressDoc.progressPercent : null;
      const latestAiProgressPercent = typeof latestAiProgressPercentRaw === 'number'
        ? Math.max(0, Math.min(100, latestAiProgressPercentRaw))
        : (latestAiProgressPercentRaw != null ? Number(latestAiProgressPercentRaw) : NaN);
      const hasLatestAiPct = Number.isFinite(latestAiProgressPercent);
      const latestAiUpdatedAt = latestAiProgressDoc
        ? (latestAiProgressDoc.aiUpdatedAt || latestAiProgressDoc.createdAt || null)
        : null;

      const contextObj = {
        project: {
          id: projectId,
          name: projectName || projectData.name || projectData.projectName || null,
          progressPercentage: hasLatestAiPct
            ? latestAiProgressPercent
            : (projectData.progressPercentage ?? projectData.progress ?? null),
          progressSource: hasLatestAiPct
            ? 'ai_analysis.govtrack_progress_report.progressPercent'
            : 'projects.progressPercentage',
          progressUpdatedAt: hasLatestAiPct ? latestAiUpdatedAt : (projectData.updatedAt || null),
          siteManagerId: projectData.siteManagerId || null,
          status: projectData.status || null,
        },
        dailyReports: compactDaily,
        materialInventory: compactInv,
        deliveries: compactDeliveries,
        materialUsage: compactUsage,
      };

      projectContextObj = contextObj;
      projectDataJson = stringifySafe(contextObj, 14000);
    }

    // If there is no authoritative project data and no image context, avoid model speculation.
    // Return deterministic, question-relevant GENERAL guidance without any project-specific claims.
    const hasImageContext = Boolean(
      ocrText ||
      (Array.isArray(ocrLabels) && ocrLabels.length) ||
      (Array.isArray(ocrObjects) && ocrObjects.length)
    );
    if (!projectDataJson && !hasImageContext) {
      const lower = message.toLowerCase();
      const wantsMaterials =
        lower.includes('material') ||
        lower.includes('inventory') ||
        lower.includes('stock') ||
        lower.includes('delivery') ||
        lower.includes('deliveries') ||
        lower.includes('reorder') ||
        lower.includes('purchase');
      const wantsProgress =
        lower.includes('progress') ||
        lower.includes('percent') ||
        lower.includes('%') ||
        lower.includes('accomplish') ||
        lower.includes('status');
      const wantsDelay =
        lower.includes('delay') ||
        lower.includes('schedule') ||
        lower.includes('slip') ||
        lower.includes('late');
      const wantsAttendance =
        lower.includes('attendance') ||
        lower.includes('manpower') ||
        lower.includes('worker') ||
        lower.includes('labor') ||
        lower.includes('absent');
      const wantsRisk = lower.includes('risk') || lower.includes('safety') || lower.includes('hazard');

      const limited = 'Limited data available for full analysis.';
      let summary = limited;
      let keyPoints = [
        'Missing inputs: select a project for records-based answers or attach a site photo.',
        'Tell me the area/stage and today\'s goal (progress, materials, delay, attendance).',
      ];
      let recommendation = 'Select a project or attach a site photo, then ask again.';

      if (wantsMaterials) {
        summary = `${limited} Here is a materials/inventory checklist you can apply immediately.`;
        keyPoints = [
          'Check critical items vs. planned work today (cement, sand, gravel, rebars, tie wire, formworks).',
          'Verify delivery status: supplier, ETA, quantity, and who will receive/inspect on site.',
          'Confirm stock control: update stock cards, record withdrawals, and set minimum reorder levels.',
        ];
        recommendation = 'Select the project so I can check actual inventory/usage/deliveries and flag low stock precisely.';
      } else if (wantsProgress) {
        summary = `${limited} I can still guide a progress check using a simple structure.`;
        keyPoints = [
          'List today\'s work items (WBS/area) and confirm % complete per item (photo + measurement).',
          'Identify blockers (materials, manpower, access, rework, inspections) and assign owners.',
          'Capture evidence: dated photos per area + quantities accomplished to avoid disputes.',
        ];
        recommendation = 'Select the project so I can summarize progress from daily reports and highlight gaps.';
      } else if (wantsDelay) {
        summary = `${limited} Here are the most common delay signals and mitigations to check today.`;
        keyPoints = [
          'Delay signals: missing materials, low manpower, pending inspections/approvals, rework, weather constraints.',
          'Mitigation: re-sequence tasks, confirm supplier lead times, add crew/shift, and lock weekly lookahead plan.',
          'Track a short constraint log: issue, owner, due date, status, and impact.',
        ];
        recommendation = 'Select the project so I can review recent reports and identify the most likely delay drivers.';
      } else if (wantsAttendance) {
        summary = `${limited} I can guide an attendance check, but I need the project selected to compute totals.`;
        keyPoints = [
          'Verify headcount per trade (carpentry, steelworks, masonry, electrical, plumbing) vs. plan.',
          'Check missing records: late check-ins, absent workers, or duplicates; confirm with foreman.',
          'Look for productivity risk: low manpower in critical path trades.',
        ];
        recommendation = 'Select the project so I can summarize attendance records and highlight missing entries.';
      } else if (wantsRisk) {
        summary = `${limited} Here are high-priority site risk checks you can perform now.`;
        keyPoints = [
          'Safety: PPE compliance, housekeeping, scaffolding/edge protection, electrical lockout, lifting operations.',
          'QA/QC: rebar/formwork inspection before pour, curing plan, waterproofing continuity checks.',
          'Document: photo evidence + corrective actions with owner and deadline.',
        ];
        recommendation = 'Attach a site photo and I can point out visible hazards/quality issues (no guessing).';
      }

      return {
        ok: true,
        intent: 'no_project_context',
        reply: JSON.stringify({
          summary,
          keyPoints,
          recommendation,
          confidence: 'Low',
        }),
      };
    }

    const strictEvidenceMode = Boolean(projectDataJson);

    const isSmallTalk = (() => {
      const msg = String(message || '').trim().toLowerCase();
      if (!msg) return false;
      const smallTalkSignals = [
        'hi',
        'hello',
        'hey',
        'good morning',
        'good afternoon',
        'good evening',
        'kumusta',
        'kamusta',
        'thanks',
        'thank you',
        'help',
        'what can you do',
        'how to use',
      ];
      return smallTalkSignals.some((k) => msg === k || msg.startsWith(`${k} `));
    })();

    function detectIntent(msgLower) {
      const wantsMaterials =
        msgLower.includes('material') ||
        msgLower.includes('inventory') ||
        msgLower.includes('stock') ||
        msgLower.includes('delivery') ||
        msgLower.includes('deliveries') ||
        msgLower.includes('reorder') ||
        msgLower.includes('purchase');
      const wantsProgress =
        msgLower.includes('progress') ||
        msgLower.includes('percent') ||
        msgLower.includes('%') ||
        msgLower.includes('accomplish') ||
        msgLower.includes('status');
      const wantsDelay =
        msgLower.includes('delay') ||
        msgLower.includes('schedule') ||
        msgLower.includes('slip') ||
        msgLower.includes('late');
      const wantsAttendance =
        msgLower.includes('attendance') ||
        msgLower.includes('manpower') ||
        msgLower.includes('worker') ||
        msgLower.includes('labor') ||
        msgLower.includes('absent');
      const wantsRisk = msgLower.includes('risk') || msgLower.includes('safety') || msgLower.includes('hazard');

      if (wantsMaterials) return 'materials';
      if (wantsProgress) return 'progress';
      if (wantsDelay) return 'delay';
      if (wantsAttendance) return 'attendance';
      if (wantsRisk) return 'risk';
      return 'general';
    }

    function buildDeterministicInsights({ intent, ctx }) {
      const out = {
        intent,
        project: ctx?.project || null,
        facts: {},
        missing: [],
      };

      if (!ctx || typeof ctx !== 'object') {
        out.missing.push('PROJECT_DATA_JSON is missing');
        return out;
      }

      const inv = Array.isArray(ctx.materialInventory) ? ctx.materialInventory : [];
      const deliveries = Array.isArray(ctx.deliveries) ? ctx.deliveries : [];
      const usage = Array.isArray(ctx.materialUsage) ? ctx.materialUsage : [];
      const daily = Array.isArray(ctx.dailyReports) ? ctx.dailyReports : [];

      if (intent === 'materials') {
        if (!inv.length) out.missing.push('materialInventory is empty');
        const lowStock = inv
          .map((i) => {
            const name = String(i?.materialName || '').trim();
            const unit = String(i?.unit || '').trim();
            const stock = Number(i?.stock ?? NaN);
            return { name, unit, stock };
          })
          .filter((i) => i.name && Number.isFinite(i.stock))
          .sort((a, b) => a.stock - b.stock)
          .slice(0, 6);

        out.facts.lowStockCandidates = lowStock;

        const recentUsage = usage
          .map((u) => {
            const name = String(u?.materialName || '').trim();
            const unit = String(u?.unit || '').trim();
            const qty = Number(u?.quantity ?? NaN);
            const date = u?.date || null;
            return { name, unit, qty, date };
          })
          .filter((u) => u.name && Number.isFinite(u.qty))
          .slice(0, 15);
        if (!recentUsage.length) out.missing.push('materialUsage is empty');
        out.facts.recentUsage = recentUsage;

        const recentDeliveries = deliveries.slice(0, 10);
        if (!recentDeliveries.length) out.missing.push('deliveries is empty');
        out.facts.recentDeliveries = recentDeliveries;
      }

      if (intent === 'progress') {
        if (!daily.length) out.missing.push('dailyReports is empty');
        out.facts.latestDailyReports = daily.slice(0, 3);
        out.facts.projectProgressPercentage = ctx?.project?.progressPercentage ?? null;
      }

      if (intent === 'delay' || intent === 'risk') {
        if (!daily.length) out.missing.push('dailyReports is empty');
        out.facts.latestIssues = daily
          .flatMap((r) => (Array.isArray(r?.issues) ? r.issues : []))
          .slice(0, 12);
      }

      if (intent === 'attendance') {
        out.missing.push('attendance data is not included in PROJECT_DATA_JSON payload');
      }

      return out;
    }

    const intent = detectIntent(lowerMsg);
    const deterministicInsights = strictEvidenceMode
      ? buildDeterministicInsights({ intent, ctx: projectContextObj })
      : null;

    const apiKey = geminiApiKey.value();
    const model = geminiModel.value();

    function buildFallback({
      confidence,
      summary,
      keyPoints,
      recommendation,
      intent,
      hasProjectContext,
      smallTalk,
    }) {
      const safeSummary = (summary && String(summary).trim())
        ? String(summary).trim()
        : (smallTalk
            ? 'Hello! I can help you monitor construction progress, materials, deliveries, issues, and risks.'
            : (hasProjectContext
                ? 'Limited data available for full analysis.'
                : 'Tell me what you want to check (progress/materials/delay/risk), and I will guide you.'));

      const safeRec = (recommendation && String(recommendation).trim())
        ? String(recommendation).trim()
        : (smallTalk
            ? 'Select a project (or attach a site photo) and ask: “Progress today”, “Materials low stock”, or “Delay risks”.'
            : (hasProjectContext
                ? 'Add one detail (area/stage/date) and resend so I can produce a more precise, evidence-based answer.'
                : 'Select a project or attach a site photo, then ask again.'));

      const defaultKpNoProject = smallTalk
        ? [
            'You can ask about: progress, materials inventory, deliveries, usage, issues, and delay risks.',
            'For best accuracy: select a project so I can use real project records (no guessing).',
            'You can also attach a site photo for OCR-based checks (safety/quality/progress).',
          ]
        : [
            'Missing inputs: project context (select a project) or site photo (attach an image).',
            'Provide specifics: location/area, current stage, target date, and what you want to check.',
            'Use Quick Actions for faster structured analysis (Progress / Materials / Delay).',
          ];

      const defaultKpWithProject = (() => {
        switch (intent) {
          case 'materials':
            return [
              'I have project context, but the AI response format was invalid. I will summarize inventory/usage/deliveries instead.',
              'If you want exact low-stock flags, ensure material inventory has numeric stock values per item.',
              'Ask: "Show top 5 lowest stock materials" or "Show recent deliveries" for a focused output.',
            ];
          case 'progress':
            return [
              'I have project context, but the AI response format was invalid. I will summarize recent daily reports instead.',
              'If progress % is missing, ensure daily reports include work accomplishments and % complete.',
              'Ask: "What are the latest issues/blockers" for a risk-focused summary.',
            ];
          case 'delay':
          case 'risk':
            return [
              'I have project context, but the AI response format was invalid. I will summarize recent issues instead.',
              'If schedule data is missing, log target dates/milestones in project records.',
              'Ask: "Give top 3 delay risks with mitigation" for a concise plan.',
            ];
          default:
            return [
              'I have project context, but the AI response format was invalid. I will provide a safe, evidence-based fallback.',
              'Ask one clear goal (progress/materials/delay/risk) to get a tighter response.',
              'Attach a site photo if you want image-based checks (safety/quality/progress).',
            ];
        }
      })();

      const safeKp = Array.isArray(keyPoints) && keyPoints.length
        ? keyPoints.map((v) => String(v || '').trim()).filter(Boolean).slice(0, 3)
        : (hasProjectContext ? defaultKpWithProject : defaultKpNoProject);

      return {
        summary: safeSummary,
        keyPoints: safeKp.length ? safeKp : ['Limited data available for full analysis.'],
        recommendation: safeRec,
        confidence: confidence || (smallTalk ? 'Medium' : 'Low'),
      };
    }

    function normalizeAiJson(obj) {
      const readString = (v) => (v ?? '').toString().trim();
      const rawSummary = readString(obj?.summary);
      const rawRec = readString(obj?.recommendation);
      const rawConf = readString(obj?.confidence);

      const conf = rawConf === 'High' || rawConf === 'Medium' || rawConf === 'Low' ? rawConf : 'Low';
      const kpRaw = Array.isArray(obj?.keyPoints) ? obj.keyPoints : [];
      const keyPoints = kpRaw
        .map((e) => readString(e))
        .filter(Boolean)
        .slice(0, 3);

      const summary = rawSummary;
      const recommendation = rawRec;
      if (!summary || !recommendation) {
        return buildFallback({
          confidence: 'Low',
          intent,
          hasProjectContext: strictEvidenceMode,
          smallTalk: Boolean(isSmallTalk) && !strictEvidenceMode,
        });
      }

      const limitedText = 'Limited data available for full analysis.';
      const isLimited = summary.toLowerCase().includes('limited data') || recommendation.toLowerCase().includes('limited data');
      const kpSafe = keyPoints.length
        ? keyPoints
        : [
            'Limited data available for full analysis.',
            'Missing information: specify project/stage/date or attach a site photo.',
            'Ask one goal: progress check, materials needed, delay risk, or attendance status.',
          ];

      return {
        summary: summary,
        keyPoints: kpSafe,
        recommendation: recommendation,
        confidence: isLimited ? 'Low' : conf,
      };
    }

    function deterministicReplyFromInsights() {
      const limited = 'Limited data available for full analysis.';
      const pName = deterministicInsights?.project?.name || projectName || projectId || 'Selected project';
      if (!strictEvidenceMode || !projectContextObj) {
        return buildFallback({
          confidence: 'Low',
          intent,
          hasProjectContext: false,
        });
      }

      if (intent === 'materials') {
        const lows = Array.isArray(deterministicInsights?.facts?.lowStockCandidates)
          ? deterministicInsights.facts.lowStockCandidates
          : [];
        const d = Array.isArray(deterministicInsights?.facts?.recentDeliveries)
          ? deterministicInsights.facts.recentDeliveries
          : [];
        const u = Array.isArray(deterministicInsights?.facts?.recentUsage)
          ? deterministicInsights.facts.recentUsage
          : [];
        const kp = [];
        if (lows.length) {
          kp.push(
            `Lowest stock candidates (evidence: PROJECT_DATA_JSON.materialInventory): ${lows
              .slice(0, 3)
              .map((x) => `${x.name}=${x.stock} ${x.unit || ''}`.trim())
              .join(', ')}`
          );
        }
        if (d.length) {
          const first = d[0];
          kp.push(
            `Recent delivery record found (evidence: PROJECT_DATA_JSON.deliveries): ${String(first?.description || 'delivery').trim() || 'delivery'} (${String(first?.status || 'unknown').trim() || 'unknown'})`
          );
        }
        if (u.length) {
          const first = u[0];
          kp.push(
            `Recent usage record found (evidence: PROJECT_DATA_JSON.materialUsage): ${String(first?.name || '').trim() || 'material'} ${Number.isFinite(first?.qty) ? first.qty : ''} ${String(first?.unit || '').trim()}`.trim()
          );
        }
        const keyPoints = kp.filter(Boolean).slice(0, 3);
        return {
          summary: `${limited} Materials summary for ${pName}.`,
          keyPoints: keyPoints.length
            ? keyPoints
            : [
                'No material inventory/usage/delivery records were found in PROJECT_DATA_JSON.',
                'If inventory exists, ensure each item has materialName, unit, and numeric stock.',
                'Add deliveries/usage logs to enable low-stock and follow-up analysis.',
              ],
          recommendation: 'Update material inventory (stock values) and log deliveries/usage so I can flag low stock precisely.',
          confidence: 'Low',
        };
      }

      if (intent === 'progress') {
        const reports = Array.isArray(deterministicInsights?.facts?.latestDailyReports)
          ? deterministicInsights.facts.latestDailyReports
          : [];
        const pct = deterministicInsights?.facts?.projectProgressPercentage;
        const kp = [];
        if (typeof pct === 'number') {
          kp.push(`Project progressPercentage=${pct} (evidence: PROJECT_DATA_JSON.project.progressPercentage)`);
        }
        if (reports.length) {
          const r = reports[0];
          const date = r?.reportDate || 'unknown date';
          const issuesCount = Array.isArray(r?.issues) ? r.issues.length : 0;
          const worksCount = Array.isArray(r?.workAccomplishments) ? r.workAccomplishments.length : 0;
          kp.push(`Latest daily report ${date}: workItems=${worksCount}, issues=${issuesCount} (evidence: PROJECT_DATA_JSON.dailyReports)`);
        }
        return {
          summary: `${limited} Progress summary for ${pName}.`,
          keyPoints: kp.filter(Boolean).slice(0, 3).length
            ? kp.filter(Boolean).slice(0, 3)
            : [
                'No recent daily reports found in PROJECT_DATA_JSON.',
                'Submit daily reports with work accomplishments and % complete to compute progress.',
                'Attach a site photo for visual progress estimation.',
              ],
          recommendation: 'Submit today\'s daily report (work accomplished + issues) and I will generate a precise progress summary and next actions.',
          confidence: 'Low',
        };
      }

      if (intent === 'delay' || intent === 'risk') {
        const issues = Array.isArray(deterministicInsights?.facts?.latestIssues)
          ? deterministicInsights.facts.latestIssues
          : [];
        const kp = issues.slice(0, 3).map((x) => `Issue signal: ${String(x || '').trim()} (evidence: PROJECT_DATA_JSON.dailyReports.issues)`);
        return {
          summary: `${limited} Risk/delay signals for ${pName}.`,
          keyPoints: kp.length
            ? kp
            : [
                'No issues found in recent daily reports (evidence: PROJECT_DATA_JSON.dailyReports).',
                'Log site issues/blockers to detect delay risks.',
                'Ask for a specific area/stage to get tighter mitigations.',
              ],
          recommendation: 'Record blockers/issues in daily reports and I will turn them into mitigation actions with priorities.',
          confidence: 'Low',
        };
      }

      return buildFallback({
        confidence: 'Low',
        intent,
        hasProjectContext: true,
      });
    }

    const projectDataBlock = projectContextObj
      ? buildGovtrackProjectDataBlock(projectId, projectContextObj, projectDataJson)
      : '';

    const deterministicContext = (deterministicInsights && strictEvidenceMode)
      ? (
          'DERIVED_SUMMARY_JSON (computed only from [PROJECT DATA]; do not treat as new facts):\n'
          + `${JSON.stringify(deterministicInsights)}`
        )
      : '';

    const imageContext = (ocrText || (Array.isArray(ocrLabels) && ocrLabels.length) || (Array.isArray(ocrObjects) && ocrObjects.length))
      ? (
          '[IMAGE DATA]\n'
          + `OCR_TEXT:\n${ocrText || '[no text detected]'}\n`
          + `LABELS: ${(ocrLabels || []).join(', ') || '[none]'}\n`
          + `OBJECTS: ${(ocrObjects || []).join(', ') || '[none]'}\n`
          + '[END IMAGE DATA]'
        )
      : '';

    const buildTranscript = (items, maxChars) => {
      if (!Array.isArray(items) || !items.length) return '';
      const lines = [];
      for (const it of items.slice(-12)) {
        const role = it.role === 'assistant' ? 'Assistant' : 'User';
        const suffix = it.hasImage ? ' (image attached)' : '';
        const text = String(it.text || '').replace(/\s+/g, ' ').trim();
        if (!text) continue;
        lines.push(`${role}${suffix}: ${text}`);
      }
      const joined = lines.join('\n');
      if (!joined) return '';
      return joined.length > maxChars ? joined.slice(joined.length - maxChars) : joined;
    };

    const transcript = buildTranscript(history, 3500);
    const chatHistoryContext = transcript
      ? `\n\nRECENT_CHAT_TRANSCRIPT (for continuity; last turns):\n${transcript}\n`
      : '';

    if (!inScope) {
      return {
        ok: true,
        intent: 'out_of_scope',
        reply: 'I can only answer questions related to this project\'s tracking data.',
        uid: auth ? auth.uid : null,
        hasImage: Boolean(imageUrl || storagePath),
        ocrTextPreview: ocrText ? ocrText.slice(0, 300) : '',
        ocrLabels,
      };
    }

    const geminiSystemInstruction = {
      parts: [{ text: GOVTRACK_GEMINI_SYSTEM_INSTRUCTION }],
    };

    const geminiUserPrompt = buildGovtrackChatUserPrompt({
      projectDataBlock,
      userQuestion: message,
      imageContext,
      chatHistoryContext,
      deterministicContext,
      isSmallTalk: Boolean(isSmallTalk),
    });

    const { text: rawReply } = await geminiGenerateWithContinuation({
      apiKey,
      model,
      systemInstruction: geminiSystemInstruction,
      contents: [
        {
          role: 'user',
          parts: [{ text: geminiUserPrompt }],
        },
      ],
      generationConfig: {
        ...GOVTRACK_GEMINI_GENERATION_CONFIG,
        maxOutputTokens: strictEvidenceMode ? 900 : 700,
      },
      maxTurns: 1,
    });

    const reply = String(rawReply || '').trim();
    const safeReply = reply || (strictEvidenceMode
      ? JSON.stringify(deterministicReplyFromInsights(), null, 0)
      : JSON.stringify(buildFallback({
          confidence: 'Low',
          intent,
          hasProjectContext: false,
          smallTalk: Boolean(isSmallTalk),
        }), null, 0));
    return {
      ok: true,
      intent: 'gemini',
      reply: safeReply || 'I was unable to generate a response. Please try again.',
      uid: auth ? auth.uid : null,
      hasImage: Boolean(imageUrl || storagePath),
      ocrTextPreview: ocrText ? ocrText.slice(0, 300) : '',
      ocrLabels,
    };
  } catch (error) {
    console.error('govtrackChatGemini error:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError('internal', error?.message || 'Chat failed');
  }
  });

exports.generateGovTrackReportGemini = functions
  .runWith({ secrets: [geminiApiKey, visualCrossingApiKey] })
  .https.onCall(async (data, context) => {
  try {
    const auth = await resolveAuth(context, data);
    await requireGovtrackRole(auth);

    const projectId = typeof data?.projectId === 'string' ? data.projectId : '';
    const projectName = typeof data?.projectName === 'string' ? data.projectName : 'Selected Project';
    const projectData = data?.projectData && typeof data.projectData === 'object' ? data.projectData : null;
    const recentDailyReports = Array.isArray(data?.recentDailyReports) ? data.recentDailyReports : null;

    if (!projectId) {
      throw new functions.https.HttpsError('invalid-argument', 'projectId is required');
    }
    if (!projectData || !recentDailyReports) {
      throw new functions.https.HttpsError('invalid-argument', 'projectData and recentDailyReports are required');
    }

    const apiKey = geminiApiKey.value();
    const model = geminiModel.value();
    const reportJsonSchema =
      'Return STRICT JSON ONLY (no markdown) with keys:\n'
      + '- summary (string)\n'
      + '- confidence (number 0..1)\n'
      + '- pass (boolean)\n'
      + '- schedule (object {deltaPercent:string, status:string, notes:string})\n'
      + '- budget (object {deltaPercent:string, status:string, notes:string})\n'
      + '- risks (array of objects {risk:string, severity:string, evidence:string, impact:string})\n'
      + '- recommendations (array of objects {recommendation:string, priority:string, evidence:string, rationale:string})\n'
      + '- tasks (array of objects {title:string, priority:string, dueInDays:number, owner:string, rationale:string, evidence:string})\n'
      + '- delaySignals (array of objects {signal:string, severity:string, evidence:string, impact:string})\n'
      + '- materialShortages (array of objects {material:string, riskLevel:string, evidence:string, suggestedAction:string})\n'
      + '- labels (array of short strings)\n'
      + 'Use available data only; if unknown, write notes as "Insufficient data".\n'
      + 'Keep summary under 120 words.\n'
      + 'Every risk/recommendation/task/signal/shortage MUST include evidence from [PROJECT DATA]. Omit items without evidence.';

    const locationRaw = (projectData && typeof projectData.location === 'string')
      ? projectData.location.trim()
      : '';

    let weatherContext = null;
    if (locationRaw) {
      const vcKey = visualCrossingApiKey.value();
      if (vcKey) {
        const now = new Date();
        const start = new Date(now.getTime());
        const end = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
        const fmt = (d) => d.toISOString().slice(0, 10);
        const base = 'https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline';
        const url = `${base}/${encodeURIComponent(locationRaw)}/${encodeURIComponent(fmt(start))}/${encodeURIComponent(fmt(end))}?unitGroup=metric&include=days&key=${encodeURIComponent(vcKey)}&contentType=json`;
        try {
          const res = await fetch(url, { method: 'GET' });
          const json = await res.json().catch(() => ({}));
          if (res.ok) {
            const days = Array.isArray(json?.days) ? json.days : [];
            weatherContext = {
              provider: 'visualcrossing',
              location: locationRaw,
              days: days.slice(0, 7).map((d) => ({
                datetime: d?.datetime,
                tempmin: d?.tempmin,
                tempmax: d?.tempmax,
                humidity: d?.humidity,
                windspeed: d?.windspeed,
                precipprob: d?.precipprob,
                conditions: d?.conditions,
              })),
            };
          }
        } catch (e) {
          weatherContext = null;
        }
      }
    }

    const payload = {
      projectId,
      projectName,
      project: projectData,
      recentDailyReports,
      weather: weatherContext,
    };

    const progressRaw = projectData?.progressPercentage ?? projectData?.progress ?? projectData?.calculatedProgress;
    const reportContextObj = {
      project: {
        id: projectId,
        name: projectName,
        progressPercentage: progressRaw,
        progressUpdatedAt: projectData?.updatedAt ?? null,
        status: projectData?.status ?? null,
      },
    };
    const projectDataBlock = buildGovtrackProjectDataBlock(
      projectId,
      reportContextObj,
      JSON.stringify(payload),
    );

    const reportPrompt =
      `${projectDataBlock}\n\n`
      + '[INSTRUCTION]\n'
      + 'Generate a construction monitoring report using ONLY metrics in [PROJECT DATA]. '
      + 'If a metric is missing, use "Insufficient data". Do not guess or hallucinate.\n\n'
      + reportJsonSchema;

    const { text } = await geminiGenerateWithContinuation({
      apiKey,
      model,
      systemInstruction: {
        parts: [{ text: GOVTRACK_GEMINI_SYSTEM_INSTRUCTION }],
      },
      contents: [
        {
          role: 'user',
          parts: [{ text: reportPrompt }],
        },
      ],
      generationConfig: {
        ...GOVTRACK_GEMINI_GENERATION_CONFIG,
        maxOutputTokens: 1024,
      },
      maxTurns: 1,
    });

    if (!text) {
      throw new functions.https.HttpsError('internal', 'Gemini returned an empty response.');
    }

    let analysis;
    try {
      analysis = JSON.parse(text);
    } catch (e) {
      console.error('Gemini report JSON parse error. Raw:', text);
      throw new functions.https.HttpsError('internal', 'Gemini response was not valid JSON.');
    }

    if (!analysis || typeof analysis !== 'object' || Array.isArray(analysis)) {
      throw new functions.https.HttpsError('internal', 'Gemini response was not a JSON object.');
    }

    const readString = (v) => String(v == null ? '' : v).trim();
    const readMapList = (value) => (Array.isArray(value) ? value : [])
      .filter((e) => e && typeof e === 'object' && !Array.isArray(e));
    const keepWithEvidence = (items) => items.filter((e) => readString(e.evidence).length > 0);

    const clamp01 = (n) => {
      const v = Number(n);
      if (!Number.isFinite(v)) return 0;
      return Math.max(0, Math.min(1, v));
    };

    const schedule = (analysis.schedule && typeof analysis.schedule === 'object') ? analysis.schedule : {};
    const budget = (analysis.budget && typeof analysis.budget === 'object') ? analysis.budget : {};

    analysis = {
      ...analysis,
      summary: readString(analysis.summary) || 'Insufficient data',
      confidence: clamp01(analysis.confidence),
      pass: Boolean(analysis.pass),
      schedule: {
        ...schedule,
        deltaPercent: readString(schedule.deltaPercent),
        status: readString(schedule.status),
        notes: readString(schedule.notes) || 'Insufficient data',
      },
      budget: {
        ...budget,
        deltaPercent: readString(budget.deltaPercent),
        status: readString(budget.status),
        notes: readString(budget.notes) || 'Insufficient data',
      },
      risks: keepWithEvidence(readMapList(analysis.risks)).slice(0, 8),
      recommendations: keepWithEvidence(readMapList(analysis.recommendations)).slice(0, 8),
      tasks: keepWithEvidence(readMapList(analysis.tasks)).slice(0, 10),
      delaySignals: keepWithEvidence(readMapList(analysis.delaySignals)).slice(0, 10),
      materialShortages: keepWithEvidence(readMapList(analysis.materialShortages)).slice(0, 10),
      labels: Array.isArray(analysis.labels) ? analysis.labels.slice(0, 12) : [],
    };

    return {
      ok: true,
      intent: 'gemini',
      analysis,
    };
  } catch (error) {
    console.error('generateGovTrackReportGemini error:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw new functions.https.HttpsError('internal', error?.message || 'Report generation failed');
  }
  });

// Deduct material inventory stock when site manager logs material usage
exports.deductMaterialInventoryOnUsageCreate = functions.firestore
  .document('projects/{projectId}/daily_reports/{reportId}/material_usage/{usageId}')
  .onCreate(async (snap, context) => {
    try {
      const { projectId } = context.params;
      const usage = snap.data() || {};

      const materialName = typeof usage.materialName === 'string' ? usage.materialName.trim() : '';
      const inventoryItemId = typeof usage.inventoryItemId === 'string' ? usage.inventoryItemId.trim() : '';
      const quantityRaw = usage.quantity ?? usage.qty ?? usage.usedQuantity ?? 0;
      const quantity = Number(quantityRaw);
      if (!projectId || !Number.isFinite(quantity) || quantity <= 0) {
        return null;
      }

      const invCol = admin.firestore().collection('projects').doc(projectId).collection('material_inventory');

      let invDocRef = null;
      if (inventoryItemId) {
        invDocRef = invCol.doc(inventoryItemId);
      } else if (materialName) {
        const q = await invCol.where('materialName', '==', materialName).limit(1).get();
        if (!q.empty) {
          invDocRef = q.docs[0].ref;
        }
      }

      if (!invDocRef) {
        console.log('No inventory item matched for usage', projectId, inventoryItemId, materialName);
        return null;
      }

      await admin.firestore().runTransaction(async (tx) => {
        const invSnap = await tx.get(invDocRef);
        if (!invSnap.exists) {
          throw new Error('Inventory doc not found');
        }
        const inv = invSnap.data() || {};
        if (typeof inv.lastUsageId === 'string' && inv.lastUsageId === snap.id) {
          return;
        }
        const stockRaw = inv.stock ?? inv.quantity ?? 0;
        const currentStock = Number(stockRaw);
        const safeCurrent = Number.isFinite(currentStock) ? currentStock : 0;
        const newStock = Math.max(0, safeCurrent - quantity);

        tx.update(invDocRef, {
          stock: newStock,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastDeductedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastDeductedQty: quantity,
          lastUsageId: snap.id,
        });
      });

      return null;
    } catch (error) {
      console.error('deductMaterialInventoryOnUsageCreate error:', error);
      return null;
    }
  });

// AI Progress % Estimation (Cloud Vision OCR MVP)
exports.estimateProgressPercent = functions.https.onCall(async (data, context) => {
  try {
    console.log('estimateProgressPercent auth presence:', {
      hasContextAuth: Boolean(context && context.auth),
      hasIdToken: typeof data?.idToken === 'string' && data.idToken.trim().length > 0,
    });
    const auth = await resolveAuth(context, data);
    const role = await requireGovtrackRole(auth);

    const imageUrl = typeof data?.imageUrl === 'string' ? data.imageUrl : null;
    const storagePath = typeof data?.storagePath === 'string' ? data.storagePath : null;
    const fileName = typeof data?.fileName === 'string' ? data.fileName : null;
    const projectId = typeof data?.projectId === 'string' ? data.projectId : null;
    const projectName = typeof data?.projectName === 'string' ? data.projectName : null;

    if (!projectId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'projectId is required.'
      );
    }

    await requireProjectAccess({ auth, role, projectId });

    if (!imageUrl && !storagePath) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Either imageUrl or storagePath must be provided.'
      );
    }

    const bucketName = admin.storage().bucket().name;
    const gcsUri = storagePath ? `gs://${bucketName}/${storagePath}` : null;
    const imageSource = gcsUri || imageUrl;

    const [result] = await visionClient.annotateImage({
      image: { source: { imageUri: imageSource } },
      features: [{ type: 'TEXT_DETECTION', maxResults: 5 }],
    });

    const textAnnotations = Array.isArray(result?.textAnnotations)
      ? result.textAnnotations
      : [];
    const extractedText =
      textAnnotations.length > 0 && typeof textAnnotations[0].description === 'string'
        ? textAnnotations[0].description
        : '';

    // Heuristic: extract a number like "32%" from OCR
    let progressPercent = null;
    if (extractedText) {
      const match = extractedText.match(/(\d{1,3})\s*%/);
      if (match && match[1]) {
        const n = Number(match[1]);
        if (!Number.isNaN(n)) {
          progressPercent = Math.max(0, Math.min(100, n));
        }
      }
    }

    // Optional: stage-specific progress from OCR text like "Foundation 75%"
    const stageProgress = {
      foundation: null,
      structural: null,
      roofing: null,
      walls: null,
    };
    if (extractedText) {
      const patterns = [
        ['foundation', /(foundation)[^\d]{0,20}(\d{1,3})\s*%/i],
        ['structural', /(structural|columns|beams|slab|frame)[^\d]{0,20}(\d{1,3})\s*%/i],
        ['roofing', /(roof|roofing)[^\d]{0,20}(\d{1,3})\s*%/i],
        ['walls', /(wall|walls|masonry|plaster)[^\d]{0,20}(\d{1,3})\s*%/i],
      ];
      for (const [key, re] of patterns) {
        const m = extractedText.match(re);
        if (m && m[2]) {
          const n = Number(m[2]);
          if (Number.isFinite(n)) {
            stageProgress[key] = Math.max(0, Math.min(100, n));
          }
        }
      }
    }

    const stageValues = Object.values(stageProgress).filter((v) => typeof v === 'number');
    if (progressPercent == null && stageValues.length) {
      progressPercent = Math.round(stageValues.reduce((a, b) => a + b, 0) / stageValues.length);
    }

    return {
      ok: true,
      projectId: projectId || null,
      projectName: projectName || null,
      fileName: fileName || null,
      progressPercent,
      stageProgress,
      extractedText: extractedText ? extractedText.slice(0, 2000) : '',
      method: 'vision_text_detection',
    };
  } catch (error) {
    console.error('estimateProgressPercent error:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    const message = typeof error?.message === 'string' ? error.message : 'Estimation failed';
    throw new functions.https.HttpsError('internal', message);
  }
});

// GovTrack AI Chat (MVP - no external LLM)
exports.govtrackChat = functions
  .runWith({ secrets: [openaiApiKey] })
  .https.onCall(async (data, context) => {
  try {
    const auth = await resolveAuth(context, data);
    await requireGovtrackRole(auth);

    const message = typeof data?.message === 'string' ? data.message.trim() : '';
    if (!message) {
      throw new functions.https.HttpsError('invalid-argument', 'Message is required');
    }

    const openaiKey = openaiApiKey.value();
    if (typeof openaiKey === 'string' && openaiKey.trim()) {
      try {
        const systemPrompt =
          'You are GovTrack AI, a professional government-grade infrastructure monitoring assistant. '
          + 'Be concise. Provide actionable steps. If asked for data you do not have, say so and suggest where to find it.';

        const payload = {
          model: 'gpt-4o-mini',
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: message },
          ],
          temperature: 0.2,
        };

        const resp = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${openaiKey}`,
          },
          body: JSON.stringify(payload),
        });

        if (!resp.ok) {
          const errText = await resp.text();
          console.error('OpenAI error:', resp.status, errText);
          throw new Error(`OpenAI request failed (${resp.status})`);
        }

        const json = await resp.json();
        const reply =
          json && json.choices && json.choices[0] && json.choices[0].message && typeof json.choices[0].message.content === 'string'
            ? json.choices[0].message.content.trim()
            : '';

        return {
          ok: true,
          intent: 'gemini',
          reply: reply || 'I was unable to generate a response. Please try again.',
        };
      } catch (e) {
        const msg = typeof e?.message === 'string' ? e.message : '';
        const isQuota = msg.includes('quota') || msg.includes('insufficient_quota');

        console.error('Gemini call failed; falling back to MVP chat:', e);
      }
    }

    const q = message.toLowerCase();
    const db = admin.firestore();

    // Intent: active/ongoing projects
    if (q.includes('active project') || q.includes('ongoing project') || q.includes('list projects')) {
      const snap = await db
        .collection('projects')
        .where('status', '==', 'ongoing')
        .limit(10)
        .get();

      const names = snap.docs
        .map((d) => {
          const v = d.data() || {};
          return typeof v.name === 'string' ? v.name : null;
        })
        .filter(Boolean);

      const reply = names.length
        ? `Here are the top active projects (up to 10):\n\n- ${names.join('\n- ')}\n\nYou can ask: “show recent failed validations” or “analyze project risks”.`
        : 'No ongoing projects were found in Firestore (status == ongoing).';

      return { ok: true, reply, intent: 'active_projects', items: names };
    }

    // Intent: recent failed validations
    if (q.includes('failed validation') || q.includes('fail validation') || q.includes('high risk') || q.includes('recent alerts')) {
      const snap = await db
        .collection('ai_verifications')
        .orderBy('createdAt', 'desc')
        .limit(20)
        .get();

      const rows = snap.docs
        .map((d) => {
          const v = d.data() || {};
          return {
            pass: v.pass === true,
            projectName: typeof v.projectName === 'string' && v.projectName ? v.projectName : 'Unknown Project',
            confidence: typeof v.confidence === 'number' ? v.confidence : 0,
          };
        })
        .filter((r) => r.pass === false)
        .slice(0, 5)
        .map((r) => ({ projectName: r.projectName, confidence: r.confidence }));

      const reply = rows.length
        ? `Recent FAILED validations (top 5):\n\n- ${rows
            .map((r) => `${r.projectName} — ${(r.confidence * 100).toFixed(0)}% confidence`)
            .join('\n- ')}\n\nTip: open “Validation Reports” to review images and labels.`
        : 'No failed validations found in the last records.';

      return { ok: true, reply, intent: 'failed_validations', items: rows };
    }

    // Default response
    return {
      ok: true,
      intent: 'default',
      reply:
        'I’m running in MVP mode (no external AI yet). Try asking:\n\n'
        + '1) “List ongoing projects”\n'
        + '2) “Show recent failed validations”\n\n'
        + 'Or go to “AI Daily Progress” to upload a photo and generate a validation report.',
    };
  } catch (error) {
    console.error('govtrackChat error:', error);
    throw new functions.https.HttpsError('internal', error?.message || 'Chat failed');
  }
});

// History Logger
exports.logUserAction = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    
    const { projectId, action, details } = data;
    const userId = context.auth.uid;
    
    // Get user data
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(userId)
      .get();
    
    const userData = userDoc.data();
    
    // Log to audit trail
    await admin.firestore()
      .collection('audit_logs')
      .add({
        userId,
        userEmail: userData?.email || 'unknown',
        userRole: userData?.role || 'unknown',
        projectId,
        action,
        details,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        ipAddress: context.rawRequest.ip,
      });
    
    // Log to project history if projectId provided
    if (projectId) {
      await admin.firestore()
        .collection('projects')
        .doc(projectId)
        .collection('history')
        .add({
          userId,
          userEmail: userData?.email || 'unknown',
          userRole: userData?.role || 'unknown',
          action,
          details,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
    
    return { success: true };
    
  } catch (error) {
    console.error('Error logging user action:', error);
    throw new functions.https.HttpsError('internal', 'Failed to log action');
  }
});

// Helper Functions
async function calculateProgressAnalytics(projectData, reports, latestReport) {
  const totalDays = Math.ceil((new Date(projectData.endDate) - new Date(projectData.startDate)) / (1000 * 60 * 60 * 24));
  const elapsedDays = Math.ceil((new Date() - new Date(projectData.startDate)) / (1000 * 60 * 60 * 24));
  const timeProgress = Math.min(elapsedDays / totalDays, 1);
  
  // Calculate work progress from WBS accomplishments
  let totalWorkProgress = 0;
  let workItemCount = 0;
  
  reports.forEach(report => {
    if (report.workAccomplishments) {
      report.workAccomplishments.forEach(work => {
        totalWorkProgress += work.percentageComplete || 0;
        workItemCount++;
      });
    }
  });
  
  const avgWorkProgress = workItemCount > 0 ? totalWorkProgress / workItemCount / 100 : 0;
  
  // Calculate delay risk
  const progressGap = timeProgress - avgWorkProgress;
  const delayRisk = Math.max(0, Math.min(1, progressGap));
  
  // Predict completion date
  const currentRate = avgWorkProgress / timeProgress;
  const predictedDays = currentRate > 0 ? totalDays / currentRate : totalDays * 2;
  const predictedEndDate = new Date(projectData.startDate);
  predictedEndDate.setDate(predictedEndDate.getDate() + predictedDays);
  
  // Calculate velocity (work completed per day)
  const recentReports = reports.slice(0, 7); // Last 7 reports
  const recentWorkCompleted = recentReports.reduce((sum, report) => {
    return sum + (report.workAccomplishments?.reduce((workSum, work) => 
      workSum + (work.quantityAccomplished || 0), 0) || 0);
  }, 0);
  const velocity = recentWorkCompleted / Math.min(recentReports.length, 7);
  
  return {
    progressPercentage: Math.round(avgWorkProgress * 100),
    timeProgress: Math.round(timeProgress * 100),
    delayRisk: Math.round(delayRisk * 100) / 100,
    predictedEndDate: predictedEndDate.toISOString(),
    velocity: Math.round(velocity * 100) / 100,
    recommendations: generateRecommendations(delayRisk, velocity, progressGap),
  };
}

function validatePayrollData(payrollData, attendanceRecords) {
  const issues = [];
  let totalValidatedAmount = 0;
  
  // Create attendance lookup
  const attendanceLookup = {};
  attendanceRecords.forEach(attendance => {
    attendance.records?.forEach(record => {
      const key = `${record.workerId}_${attendance.attendanceDate}`;
      attendanceLookup[key] = record;
    });
  });
  
  // Validate each payroll item
  payrollData.items?.forEach(item => {
    const workerAttendance = Object.values(attendanceLookup)
      .filter(record => record.workerId === item.workerId);
    
    const totalHoursFromAttendance = workerAttendance.reduce((sum, record) => 
      sum + (record.hoursWorked || 0) + (record.overtimeHours || 0), 0);
    
    const payrollHours = item.regularHours + item.overtimeHours;
    
    if (Math.abs(totalHoursFromAttendance - payrollHours) > 0.5) {
      issues.push({
        workerId: item.workerId,
        workerName: item.workerName,
        issue: 'Hours mismatch',
        attendanceHours: totalHoursFromAttendance,
        payrollHours: payrollHours,
      });
    }
    
    totalValidatedAmount += item.netPay;
  });
  
  return {
    isValid: issues.length === 0,
    issues,
    totalValidatedAmount,
    validatedItemCount: payrollData.items?.length || 0,
  };
}

function generateRecommendations(delayRisk, velocity, progressGap) {
  const recommendations = [];
  
  if (delayRisk > 0.7) {
    recommendations.push('High delay risk detected. Consider increasing workforce or extending work hours.');
  }
  
  if (velocity < 0.5) {
    recommendations.push('Low work velocity. Review resource allocation and potential bottlenecks.');
  }
  
  if (progressGap > 0.2) {
    recommendations.push('Work progress is behind schedule. Implement catch-up strategies.');
  }
  
  if (recommendations.length === 0) {
    recommendations.push('Project is on track. Continue current pace.');
  }
  
  return recommendations;
}

async function sendDelayNotification(projectId, analytics) {
  // Get project managers and admins
  const usersSnapshot = await admin.firestore()
    .collection('users')
    .where('role', 'in', ['admin', 'project_manager'])
    .get();
  
  const notifications = usersSnapshot.docs.map(doc => ({
    userId: doc.id,
    type: 'ai_delay_detected',
    title: 'Project Delay Risk Detected',
    message: `Project ${projectId} has a ${Math.round(analytics.delayRisk * 100)}% delay risk.`,
    data: {
      projectId,
      delayRisk: analytics.delayRisk,
      progressPercentage: analytics.progressPercentage,
    },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    read: false,
  }));
  
  // Batch write notifications
  const batch = admin.firestore().batch();
  notifications.forEach(notification => {
    const ref = admin.firestore().collection('notifications').doc();
    batch.set(ref, notification);
  });
  
  await batch.commit();
}

async function sendPayrollNotification(projectId, payrollId, validation) {
  // Get accounting users
  const usersSnapshot = await admin.firestore()
    .collection('users')
    .where('role', '==', 'accounting')
    .get();
  
  const notifications = usersSnapshot.docs.map(doc => ({
    userId: doc.id,
    type: 'payroll_validation_completed',
    title: validation.isValid ? 'Payroll Validated' : 'Payroll Needs Review',
    message: validation.isValid 
      ? `Payroll ${payrollId} has been validated successfully.`
      : `Payroll ${payrollId} has ${validation.issues.length} issues that need review.`,
    data: {
      projectId,
      payrollId,
      isValid: validation.isValid,
      issueCount: validation.issues.length,
    },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    read: false,
  }));
  
  // Batch write notifications
  const batch = admin.firestore().batch();
  notifications.forEach(notification => {
    const ref = admin.firestore().collection('notifications').doc();
    batch.set(ref, notification);
  });
  
  await batch.commit();
}
