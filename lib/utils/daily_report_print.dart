import 'print_html.dart';

String escapeHtml(String raw) {
  return raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _row(String label, String value) {
  return '<tr><th>${escapeHtml(label)}</th><td>${escapeHtml(value)}</td></tr>';
}

void printDailyReportForm({
  required String projectName,
  required String reporterName,
  required DateTime reportDate,
  required String weather,
  required String temperature,
  required String remarks,
  required List<Map<String, String>> accomplishments,
  required List<String> issues,
  String geoTag = '',
}) {
  final dateText =
      '${reportDate.year}-${reportDate.month.toString().padLeft(2, '0')}-${reportDate.day.toString().padLeft(2, '0')}';

  final workRows = accomplishments.isEmpty
      ? '<tr><td colspan="4">None recorded.</td></tr>'
      : accomplishments.map((item) {
          return '<tr>'
              '<td>${escapeHtml(item['description'] ?? '')}</td>'
              '<td>${escapeHtml(item['quantity'] ?? '')}</td>'
              '<td>${escapeHtml(item['progress'] ?? '')}</td>'
              '<td>${escapeHtml(item['remarks'] ?? '')}</td>'
              '</tr>';
        }).join();

  final issueHtml = issues.isEmpty
      ? '<p>None reported.</p>'
      : '<ul>${issues.map((e) => '<li>${escapeHtml(e)}</li>').join()}</ul>';

  final html = '''
  <div class="letterhead">
    <h1>CITY ENGINEERING OFFICE</h1>
    <p>Construction Monitoring &amp; Management System</p>
    <p>Daily Accomplishment Report</p>
  </div>
  <h2>Send Report — Paper Form</h2>
  <table>
    ${_row('Project', projectName)}
    ${_row('Resident Engineer', reporterName)}
    ${_row('Report date', dateText)}
    ${_row('Weather', weather)}
    ${_row('Temperature', temperature)}
    ${_row('Geo-tag', geoTag.isEmpty ? 'Not captured' : geoTag)}
  </table>
  <div class="section">Work accomplished</div>
  <table>
    <tr><th>Description</th><th>Quantity</th><th>Progress</th><th>Remarks</th></tr>
    $workRows
  </table>
  <div class="section">Issues / delays</div>
  $issueHtml
  <div class="section">Additional remarks</div>
  <p>${escapeHtml(remarks.isEmpty ? 'None.' : remarks)}</p>
  <div class="sign">
    <div><div class="line"></div>Prepared by<br>Resident Engineer</div>
    <div><div class="line"></div>Noted by<br>Admin / City Engineering Office</div>
  </div>
''';

  printHtmlDocument('Daily Report — $projectName — $dateText', html);
}
