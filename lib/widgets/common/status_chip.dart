import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  final String label;
  final StatusType status;
  final bool isSmall;

  const StatusChip({
    super.key,
    required this.label,
    required this.status,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _getStatusColors(status);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 8 : 12,
        vertical: isSmall ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: colors.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.borderColor,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.textColor,
          fontSize: isSmall ? 10 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  StatusColors _getStatusColors(StatusType status) {
    switch (status) {
      case StatusType.success:
        return StatusColors(
          backgroundColor: AppTheme.softGreen.withValues(alpha: 0.1),
          borderColor: AppTheme.softGreen.withValues(alpha: 0.3),
          textColor: AppTheme.softGreen,
        );
      case StatusType.warning:
        return StatusColors(
          backgroundColor: AppTheme.warningOrange.withValues(alpha: 0.1),
          borderColor: AppTheme.warningOrange.withValues(alpha: 0.3),
          textColor: AppTheme.warningOrange,
        );
      case StatusType.error:
        return StatusColors(
          backgroundColor: AppTheme.errorRed.withValues(alpha: 0.1),
          borderColor: AppTheme.errorRed.withValues(alpha: 0.3),
          textColor: AppTheme.errorRed,
        );
      case StatusType.info:
        return StatusColors(
          backgroundColor: AppTheme.deepBlue.withValues(alpha: 0.1),
          borderColor: AppTheme.deepBlue.withValues(alpha: 0.3),
          textColor: AppTheme.deepBlue,
        );
      case StatusType.neutral:
        return StatusColors(
          backgroundColor: AppTheme.mediumGray.withValues(alpha: 0.1),
          borderColor: AppTheme.mediumGray.withValues(alpha: 0.3),
          textColor: AppTheme.mediumGray,
        );
    }
  }
}

class SyncStatusChip extends StatelessWidget {
  final String syncStatus;
  final bool isSmall;

  const SyncStatusChip({
    super.key,
    required this.syncStatus,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getSyncStatusInfo(syncStatus);
    
    return StatusChip(
      label: statusInfo.label,
      status: statusInfo.type,
      isSmall: isSmall,
    );
  }

  SyncStatusInfo _getSyncStatusInfo(String status) {
    switch (status) {
      case 'completed':
        return SyncStatusInfo('Synced', StatusType.success);
      case 'pending':
        return SyncStatusInfo('Pending', StatusType.warning);
      case 'syncing':
        return SyncStatusInfo('Syncing', StatusType.info);
      case 'failed':
        return SyncStatusInfo('Failed', StatusType.error);
      default:
        return SyncStatusInfo('Unknown', StatusType.neutral);
    }
  }
}

class ReportStatusChip extends StatelessWidget {
  final String reportStatus;
  final bool isSmall;

  const ReportStatusChip({
    super.key,
    required this.reportStatus,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getReportStatusInfo(reportStatus);
    
    return StatusChip(
      label: statusInfo.label,
      status: statusInfo.type,
      isSmall: isSmall,
    );
  }

  SyncStatusInfo _getReportStatusInfo(String status) {
    switch (status) {
      case 'approved':
        return SyncStatusInfo('Approved', StatusType.success);
      case 'submitted':
        return SyncStatusInfo('Submitted', StatusType.info);
      case 'draft':
        return SyncStatusInfo('Draft', StatusType.neutral);
      case 'rejected':
        return SyncStatusInfo('Rejected', StatusType.error);
      default:
        return SyncStatusInfo('Unknown', StatusType.neutral);
    }
  }
}

class PayrollStatusChip extends StatelessWidget {
  final String payrollStatus;
  final bool isSmall;

  const PayrollStatusChip({
    super.key,
    required this.payrollStatus,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getPayrollStatusInfo(payrollStatus);
    
    return StatusChip(
      label: statusInfo.label,
      status: statusInfo.type,
      isSmall: isSmall,
    );
  }

  SyncStatusInfo _getPayrollStatusInfo(String status) {
    switch (status) {
      case 'paid':
        return SyncStatusInfo('Paid', StatusType.success);
      case 'validated':
        return SyncStatusInfo('Validated', StatusType.info);
      case 'generated':
        return SyncStatusInfo('Generated', StatusType.warning);
      case 'returned':
        return SyncStatusInfo('Returned', StatusType.error);
      default:
        return SyncStatusInfo('Unknown', StatusType.neutral);
    }
  }
}

class PriorityChip extends StatelessWidget {
  final String priority;
  final bool isSmall;

  const PriorityChip({
    super.key,
    required this.priority,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getPriorityInfo(priority);
    
    return StatusChip(
      label: statusInfo.label,
      status: statusInfo.type,
      isSmall: isSmall,
    );
  }

  SyncStatusInfo _getPriorityInfo(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return SyncStatusInfo('High', StatusType.error);
      case 'medium':
        return SyncStatusInfo('Medium', StatusType.warning);
      case 'low':
        return SyncStatusInfo('Low', StatusType.info);
      default:
        return SyncStatusInfo('Normal', StatusType.neutral);
    }
  }
}

// Helper classes
enum StatusType { success, warning, error, info, neutral }

class StatusColors {
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;

  StatusColors({
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
  });
}

class SyncStatusInfo {
  final String label;
  final StatusType type;

  SyncStatusInfo(this.label, this.type);
}
