const functions = require('firebase-functions');
const admin = require('firebase-admin');

const vision = require('@google-cloud/vision');

admin.initializeApp();

const visionClient = new vision.ImageAnnotatorClient();

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
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }

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
      userId: context.auth.uid,
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
      id: ref.id,
      ...doc,
      createdAt: new Date().toISOString(),
    };
  } catch (error) {
    console.error('Error in verifyProgressImage:', error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError('internal', error?.message || 'Verification failed');
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
