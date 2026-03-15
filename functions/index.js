const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { defineSecret, defineString } = require('firebase-functions/params');

const vision = require('@google-cloud/vision');

admin.initializeApp();

const visionClient = new vision.ImageAnnotatorClient();

const geminiApiKey = defineSecret('GEMINI_API_KEY');
const geminiModel = defineString('GEMINI_MODEL', { default: 'gemini-1.5-flash-latest' });

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

async function geminiGenerateContent({ apiKey, model, contents, generationConfig }) {
  if (typeof apiKey !== 'string' || !apiKey.trim()) {
    throw new functions.https.HttpsError('failed-precondition', 'Gemini API key is not configured.');
  }

  const preferredModel = await getWorkingGeminiModel({ apiKey, requestedModel: model });

  const attempt = async ({ apiVersion, modelName }) => {
    const base = apiVersion === 'v1' ? 'https://generativelanguage.googleapis.com/v1' : 'https://generativelanguage.googleapis.com/v1beta';
    const url = `${base}/${modelName}:generateContent?key=${encodeURIComponent(apiKey)}`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contents,
        generationConfig,
      }),
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
    const auth = await resolveAuthOptional(context, data);

    const isEmulator =
      process.env.FUNCTIONS_EMULATOR === 'true' ||
      process.env.FIREBASE_EMULATOR_HUB ||
      process.env.FUNCTIONS_EMULATOR_HOST;

    const imageUrl = typeof data?.imageUrl === 'string' ? data.imageUrl : null;
    const storagePath = typeof data?.storagePath === 'string' ? data.storagePath : null;
    const fileName = typeof data?.fileName === 'string' ? data.fileName : null;
    const projectId = typeof data?.projectId === 'string' ? data.projectId : null;
    const projectName = typeof data?.projectName === 'string' ? data.projectName : null;

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

      const doc = {
        userId: auth?.auth?.uid || null,
        projectId: projectId || null,
        projectName: projectName || null,
        imageUrl: imageUrl || null,
        storagePath: storagePath || null,
        fileName: fileName || null,
        pass,
        status,
        confidence,
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

    const doc = {
      userId: auth?.auth?.uid || null,
      projectId: projectId || null,
      projectName: projectName || null,
      imageUrl: imageUrl || null,
      storagePath: storagePath || null,
      fileName: fileName || null,
      pass,
      status,
      confidence,
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
      labels: doc.labels,
      objects: doc.objects,
      extractedText: doc.extractedText,
      verificationId: ref.id,
    };
  } catch (error) {
    console.error('verifyProgressImage error:', error);
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    const message = typeof error?.message === 'string' ? error.message : 'Verification failed';
    throw new functions.https.HttpsError('internal', message);
  }
});

exports.govtrackChatGemini = functions
  .runWith({ secrets: [geminiApiKey] })
  .https.onCall(async (data, context) => {
  try {
    console.log('govtrackChatGemini auth presence:', {
      hasContextAuth: Boolean(context && context.auth),
      hasIdToken: typeof data?.idToken === 'string' && data.idToken.trim().length > 0,
    });
    const auth = await resolveAuthOptional(context, data);
    if (auth) {
      await requireGovtrackRole(auth);
    }

    const message = typeof data?.message === 'string' ? data.message.trim() : '';
    if (!message) {
      throw new functions.https.HttpsError('invalid-argument', 'Message is required');
    }

    const imageUrl = typeof data?.imageUrl === 'string' ? data.imageUrl.trim() : '';
    const storagePath = typeof data?.storagePath === 'string' ? data.storagePath.trim() : '';

    let ocrText = '';
    let ocrLabels = [];
    let ocrObjects = [];
    if (imageUrl || storagePath) {
      try {
        const bucketName = admin.storage().bucket().name;
        const gcsUri = storagePath ? `gs://${bucketName}/${storagePath}` : null;
        const imageSource = gcsUri || imageUrl;
        console.log('govtrackChatGemini: running Vision OCR', {
          hasGcs: Boolean(gcsUri),
          hasUrl: Boolean(imageUrl),
          storagePath: storagePath || null,
        });

        const [visionResult] = await visionClient.annotateImage({
          image: { source: { imageUri: imageSource } },
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
        console.warn('govtrackChatGemini: Vision OCR failed; continuing without image context', {
          message: e?.message,
        });
      }
    }

    const apiKey = geminiApiKey.value();
    const model = geminiModel.value();
    const systemPrompt =
      'You are GovTrack AI, a professional government-grade infrastructure monitoring assistant. '
      + 'Be concise. Provide actionable steps. If asked for data you do not have, say so and suggest where to find it.';

    const imageContext = (ocrText || (Array.isArray(ocrLabels) && ocrLabels.length) || (Array.isArray(ocrObjects) && ocrObjects.length))
      ? (
          `\n\nBlueprint/Image context (OCR + Vision):\n`
          + `OCR_TEXT:\n${ocrText || '[no text detected]'}\n\n`
          + `LABELS: ${(ocrLabels || []).join(', ') || '[none]'}\n`
          + `OBJECTS: ${(ocrObjects || []).join(', ') || '[none]'}\n`
        )
      : '';

    const result = await geminiGenerateContent({
      apiKey,
      model,
      contents: [
        {
          role: 'user',
          parts: [{ text: `${systemPrompt}${imageContext}\n\nUser: ${message}` }],
        },
      ],
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 512,
      },
    });

    const reply = geminiExtractText(result);
    return {
      ok: true,
      intent: 'gemini',
      reply: reply || 'I was unable to generate a response. Please try again.',
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
  .runWith({ secrets: [geminiApiKey] })
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
    const systemPrompt =
      'You are GovTrack AI. Generate a concise construction monitoring report. '
      + 'Return STRICT JSON ONLY (no markdown) with keys: '
      + 'summary (string), confidence (number 0..1), pass (boolean), '
      + 'schedule (object {deltaPercent:string, status:string, notes:string}), '
      + 'budget (object {deltaPercent:string, status:string, notes:string}), '
      + 'risks (array of strings), recommendations (array of strings), labels (array of short strings). '
      + 'Use available data only; if unknown, write notes as "Insufficient data". Keep summary under 120 words.';

    const payload = {
      projectId,
      projectName,
      project: projectData,
      recentDailyReports,
    };

    const result = await geminiGenerateContent({
      apiKey,
      model,
      contents: [
        {
          role: 'user',
          parts: [{ text: `${systemPrompt}\n\nDATA:\n${JSON.stringify(payload)}` }],
        },
      ],
      generationConfig: {
        temperature: 0.2,
        maxOutputTokens: 1024,
      },
    });

    const text = geminiExtractText(result);
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
    await resolveAuthOptional(context, data);

    const imageUrl = typeof data?.imageUrl === 'string' ? data.imageUrl : null;
    const storagePath = typeof data?.storagePath === 'string' ? data.storagePath : null;
    const fileName = typeof data?.fileName === 'string' ? data.fileName : null;
    const projectId = typeof data?.projectId === 'string' ? data.projectId : null;
    const projectName = typeof data?.projectName === 'string' ? data.projectName : null;

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

    return {
      ok: true,
      projectId: projectId || null,
      projectName: projectName || null,
      fileName: fileName || null,
      progressPercent,
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
exports.govtrackChat = functions.https.onCall(async (data, context) => {
  try {
    const auth = await resolveAuth(context, data);
    await requireGovtrackRole(auth);

    const message = typeof data?.message === 'string' ? data.message.trim() : '';
    if (!message) {
      throw new functions.https.HttpsError('invalid-argument', 'Message is required');
    }

    const openaiKey = functions.config()?.openai?.key;
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
          intent: 'openai',
          reply: reply || 'I was unable to generate a response. Please try again.',
        };
      } catch (e) {
        console.error('OpenAI call failed; falling back to MVP chat:', e);
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
