# CEO Construction Monitoring & Management System

A comprehensive Flutter + Firebase mobile application for the City Engineering Office (LGU) to monitor and manage construction projects with offline-first capabilities.

## 🏗️ Features

### Multi-Role Support
- **Site Manager**: Daily reports, attendance, material usage, offline-first operations
- **Admin (Construction Division)**: Dashboard, project management, payroll generation, analytics
- **Accounting Office**: Payroll validation and processing
- **Treasury Office**: Payment processing and disbursements
- **CEO Head**: Read-only dashboard with analytics and reports

### Core Functionality
- **Offline-First Architecture**: Works without internet, syncs when online
- **Real-time Sync**: Queue-based synchronization system
- **AI Analytics**: Automated progress analysis and delay prediction
- **Role-Based Security**: Secure access control for different user types
- **Modern UI**: Material 3 design with custom 3-color theme

## 🎨 Design System

### Color Palette
- **Deep Blue (#1E3A8A)**: Primary color for headers, buttons, and branding
- **Soft Green (#10B981)**: Accents, success states, and AI analytics
- **Light Gray (#F3F4F6)**: Background and neutral elements

### Typography
- **Font Family**: Inter (clean, modern, government-friendly)
- **Responsive**: Scales appropriately across different screen sizes

## 🏗️ Architecture

### Clean Architecture Structure
```
lib/
├── core/
│   ├── constants/          # App constants and route names
│   ├── theme/             # App theme and styling
│   └── routing/           # Navigation and routing logic
├── models/                # Data models with Hive annotations
├── services/              # Business logic and external services
├── widgets/               # Reusable UI components
└── views/                 # Screen implementations
```

### Technology Stack
- **Frontend**: Flutter with Material 3
- **State Management**: Riverpod
- **Navigation**: GoRouter
- **Local Storage**: Hive (offline-first)
- **Backend**: Firebase (Auth, Firestore, Storage, Functions, FCM)
- **AI Analytics**: Cloud Functions with custom algorithms

## 📱 Modules

### 1. Authentication & Role Routing
- Firebase Auth email login
- Automatic role-based home screen routing
- Secure session management

### 2. Site Manager Module (Mobile-First)
- **Daily Accomplishment Reports**: Work progress tracking with WBS integration
- **Attendance Management**: Worker time tracking with offline support
- **Material Usage**: Real-time material consumption logging
- **Material Delivery (MDR)**: Delivery receipt management
- **Issues/NCR**: Non-conformance reporting
- **Offline Queue**: Visual sync status and manual sync options

### 3. Admin Module (Construction Division)
- **Dashboard**: Project overview with key metrics
- **Report Management**: Review and approve daily reports
- **Project Management**: Create and manage construction projects
- **Payroll Generation**: Automated payroll from attendance data
- **AI Analytics**: Progress predictions and delay analysis
- **History Logs**: Complete audit trail

### 4. Payroll Monitoring Workflow
1. Admin generates payroll from attendance
2. Accounting validates payroll data
3. Treasury processes payments
4. Automated notifications at each step

### 5. Accounting Module
- Payroll batch validation
- Discrepancy reporting
- Approval workflow management

### 6. Treasury Module
- Payment processing interface
- Disbursement tracking
- Financial reporting

### 7. CEO Head Module (Read-Only)
- Executive dashboard
- AI-powered progress charts
- Project status overview
- Material usage alerts
- Historical trend analysis

## 🔄 Offline-First Architecture

### Local Storage (Hive)
- **User Data**: Cached user profiles and permissions
- **Daily Reports**: Offline report creation and editing
- **Attendance**: Worker time tracking without internet
- **Material Usage**: Consumption logging with sync queue
- **Sync Queue**: Pending operations management

### Synchronization System
- **Automatic Sync**: Triggers when internet connection is detected
- **Manual Sync**: User-initiated sync with progress indicators
- **Conflict Resolution**: Last-write-wins with user notification
- **Retry Logic**: Exponential backoff for failed sync attempts

## 🤖 AI Analytics

### Progress Analysis
- **WBS Integration**: Work breakdown structure progress tracking
- **Delay Prediction**: Machine learning-based delay risk assessment
- **Resource Optimization**: Recommendations for resource allocation
- **Trend Analysis**: Historical performance patterns

### Cloud Functions
- **Progress Analyzer**: Triggered on daily report submission
- **Payroll Validator**: Automated payroll verification
- **History Logger**: Comprehensive audit trail maintenance

## 🔔 Notifications (FCM)

### Notification Types
- Daily report submissions
- Offline data synchronization
- Material requests and deliveries
- Low material alerts
- Payroll status updates
- AI-detected delays

## 🗄️ Database Structure

### Firestore Collections
```
/users/{userID}
/projects/{projectID}
/projects/{projectID}/daily_reports/{reportID}
/projects/{projectID}/attendance/{attendanceID}
/projects/{projectID}/payroll/{payrollID}
/projects/{projectID}/deliveries/{mdrID}
/projects/{projectID}/history/{historyID}
/notifications/{notificationID}
/ai_analysis/{aiID}
/audit_logs/{logID}
/disbursements/{disbursementID}
```

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.9.2+)
- Firebase CLI
- Node.js (for Cloud Functions)

### Installation
1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd coecons
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate Hive adapters**
   ```bash
   flutter packages pub run build_runner build
   ```

4. **Firebase Setup**
   ```bash
   firebase init
   # Select Firestore, Functions, Storage, and Hosting
   ```

5. **Configure Firebase**
   - Add your `google-services.json` (Android)
   - Add your `GoogleService-Info.plist` (iOS)
   - Update Firebase configuration in `lib/services/firebase_service.dart`

6. **Deploy Cloud Functions**
   ```bash
   cd functions
   npm install
   firebase deploy --only functions
   ```

### Running the App
```bash
flutter run
```

## 📋 Configuration

### Environment Setup
1. **Firebase Project**: Create a new Firebase project
2. **Firestore Rules**: Configure security rules for role-based access
3. **Storage Rules**: Set up file upload permissions
4. **FCM**: Configure push notifications
5. **Cloud Functions**: Deploy AI analytics and validation functions

### User Roles Setup
Create users in Firestore with the following structure:
```json
{
  "email": "user@example.com",
  "firstName": "John",
  "lastName": "Doe",
  "role": "site_manager", // or "admin", "accounting", "treasury", "ceo_head"
  "assignedProjects": ["project1", "project2"],
  "isActive": true
}
```

## 🧪 Testing

### Unit Tests
```bash
flutter test
```

### Integration Tests
```bash
flutter test integration_test/
```

### Firebase Emulator Testing
```bash
firebase emulators:start
flutter test --dart-define=USE_FIREBASE_EMULATOR=true
```

## 📦 Deployment

### Mobile App
```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

### Cloud Functions
```bash
firebase deploy --only functions
```

### Firestore Rules
```bash
firebase deploy --only firestore:rules
```

## 🔒 Security

### Authentication
- Firebase Auth with email/password
- Role-based access control
- Session management with automatic logout

### Data Security
- Firestore security rules by user role
- Encrypted local storage (Hive)
- HTTPS-only communication

### Audit Trail
- Complete user action logging
- IP address tracking
- Timestamp-based history

## 🛠️ Development

### Code Style
- Follow Flutter/Dart conventions
- Use meaningful variable names
- Comment complex business logic
- Maintain clean architecture separation

### State Management
- Riverpod for dependency injection
- Local state for UI components
- Global state for user session

### Error Handling
- Comprehensive try-catch blocks
- User-friendly error messages
- Automatic error reporting

## 📈 Performance

### Optimization
- Lazy loading for large datasets
- Image compression for uploads
- Efficient Firestore queries
- Local caching strategies

### Monitoring
- Firebase Performance Monitoring
- Crashlytics for error tracking
- Analytics for user behavior

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For technical support or questions:
- Create an issue in the repository
- Contact the development team
- Check the documentation wiki

## 🔄 Version History

### v1.0.0 (Current)
- Initial release with all core features
- Offline-first architecture
- Multi-role support
- AI analytics integration
- Complete CRUD operations for all modules

---

**Built with ❤️ for the City Engineering Office (LGU)**
