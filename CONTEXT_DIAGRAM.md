# CEO Construction Management System - Context Diagram

## System Overview
The CEO Construction Management System is a comprehensive construction project management platform that enables real-time monitoring, material tracking, attendance management, and AI-powered insights for construction projects.

---

## External Entities and Interactions

### 1. Site Manager (Mobile App User)
**Role:** On-site construction supervisor
<!-- **Platform:** Flutter Mobile Application (iOS/Android) -->

**Inputs to System:**
- Login credentials (email/password)
- OTP verification code (via email)
- Daily progress reports (text, photos, videos)
- Material usage records (material name, quantity, unit, date)
- Material delivery confirmations
- Material requests (when running low)
- Attendance records (worker check-in/check-out)
- GovTrack AI chat queries
- Project selection (if assigned to multiple)

**Outputs from System:**
- Project dashboard with progress metrics
- Material inventory status (budget, used, remaining)
- Attendance summaries
- GovTrack AI responses and insights
- Weather alerts and forecasts
- Notification alerts (material approvals, project updates)
- Sync status indicators
- Project milestone timelines

**Data Flows:**
- Authentication credentials → Authentication Service
- Daily reports → Firestore (daily_reports collection)
- Material usage → Firestore (material_usage subcollection)
- Attendance data → Firestore (attendance collection)
- Chat queries → Cloud Functions (govtrackChatGemini)
- ← Project data, inventory, insights from System

---

### 2. Admin (Web App User)
**Role:** Project administrator and material manager
**Platform:** Flutter Web Application

**Inputs to System:**
- Login credentials (email/password)
- OTP verification code (via email)
- Project creation details (name, location, timeline, budget)
- Material allocations/budgets per project
- Material request approvals/rejections
- Site Manager assignments to projects
- Project milestone definitions
- Material delivery schedules
- GovTrack AI chat queries

**Outputs from System:**
- Admin dashboard with project overviews
- Material monitoring dashboard
- Site Manager performance metrics
- Material request queue
- Project progress analytics
- GovTrack AI insights
- Notification alerts
- Material inventory status across projects

**Data Flows:**
- Project data → Firestore (projects collection)
- Material allocations → Firestore (material_allocations subcollection)
- Approval decisions → Firestore (material_requests status updates)
- ← Project reports, material usage, attendance data from System

---

### 3. CEO (Web App User)
**Role:** Executive oversight and decision-maker
**Platform:** Flutter Web Application

**Inputs to System:**
- Login credentials (email/password)
- OTP verification code (via email)
- GovTrack AI chat queries
- Project selection for detailed view

**Outputs from System:**
- Executive dashboard with all projects overview
- High-level progress metrics
- Material cost analytics
- Attendance summaries
- GovTrack AI strategic insights
- Project risk alerts
- Financial performance indicators

**Data Flows:**
- Chat queries → Cloud Functions (govtrackChatGemini)
- ← Aggregated project data, AI insights, analytics from System

---

### 4. Firebase (Backend Services)
**Role:** Cloud database, authentication, and storage
**Platform:** Google Cloud Platform

**Inputs from System:**
- User authentication requests
- Document writes (projects, materials, reports, attendance)
- Document queries and reads
- File uploads (photos, videos)
- Real-time subscription requests

**Outputs to System:**
- Authentication tokens and user data
- Query results (documents, collections)
- Real-time data updates (streams)
- File storage URLs
- Server timestamps

**Data Flows:**
- ← Authentication requests from all user types
- ← Document operations from all app components
- → User sessions, project data, material data, reports to System
- → Real-time sync updates to mobile clients

**Firestore Collections:**
- `users` - User profiles and role assignments
- `projects` - Project metadata and progress
- `projects/{projectId}/material_allocations` - Admin-assigned materials
- `projects/{projectId}/material_inventory` - Current stock levels
- `projects/{projectId}/material_requests` - Site Manager requests
- `projects/{projectId}/deliveries` - Material delivery records
- `projects/{projectId}/daily_reports` - Daily progress reports
- `projects/{projectId}/daily_reports/{reportId}/material_usage` - Usage records
- `projects/{projectId}/attendance` - Worker attendance
- `projects/{projectId}/milestones` - Project milestones
- `notifications` - User notifications
- `ai_analysis` - AI-generated insights

---

### 5. SendGrid (Email Service)
**Role:** Transactional email delivery
**Platform:** SendGrid API

**Inputs from System:**
- OTP verification emails (recipient, code)
- Notification emails (alerts, updates)
- Material approval notifications

**Outputs to System:**
- Email delivery status (success/failure)
- Bounce and delivery reports

**Data Flows:**
- ← Email requests from Cloud Functions (sendOTP, sendNotification)
- → Delivery confirmations to System

---

### 6. Weather API (External Service)
**Role:** Weather data provider
**Platform:** OpenWeatherMap API (or similar)

**Inputs from System:**
- Location coordinates (project site)
- Forecast requests (hourly, daily)

**Outputs to System:**
- Current weather conditions
- Hourly forecasts
- Daily forecasts
- Weather alerts (rain, storms, extreme conditions)

**Data Flows:**
- ← Location-based forecast requests from WeatherAlertService
- → Weather data and alerts to System

---

### 7. Cloud Functions (Server-Side Logic)
**Role:** Backend business logic and AI processing
**Platform:** Google Cloud Functions

**Inputs from System:**
- GovTrack AI chat queries (with project context)
- OTP generation requests
- Material request notifications
- Intent detection requests
- Data aggregation requests

**Outputs to System:**
- AI-generated responses and insights
- OTP codes
- Notification payloads
- Deterministic summaries (materials, progress, delays)
- Intent classification results

**Data Flows:**
- ← Chat queries from GovTrack AI screens
- ← OTP requests from authentication flows
- → AI responses, OTP codes, notifications to System

**Key Functions:**
- `govtrackChatGemini` - AI chat with project context and intent detection
- `sendOTP` - Generate and email OTP codes
- `sendNotification` - Send push/email notifications
- `aggregateProjectData` - Compile project metrics for AI context

---

### 8. Hive (Local Storage)
**Role:** Offline-first local database for mobile
**Platform:** Flutter (device storage)

**Inputs from System:**
- Cached project data
- Cached material inventory
- Pending sync operations
- Offline reports and usage records

**Outputs to System:**
- Offline data access
- Sync queue for pending operations

**Data Flows:**
- ← Data writes from mobile app (for offline access)
- → Cached data to mobile app (when offline)
- → Pending operations to SyncService (when online)

---

## System Boundary

```
┌─────────────────────────────────────────────────────────────────┐
│              CEO CONSTRUCTION MANAGEMENT SYSTEM                 │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Mobile App (Site Manager)              │  │
│  │  - Dashboard, Material Inventory, Attendance              │  │
│  │  - GovTrack AI, Daily Reports, Material Usage             │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              ↕                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Web App (Admin/CEO)                    │  │
│  │  - Project Management, Material Monitoring               │  │
│  │  - GovTrack AI, Analytics, Approvals                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              ↕                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                 Core Services Layer                        │  │
│  │  - AuthService, FirebaseService, SyncService              │  │
│  │  - WeatherAlertService, Hive (Local Storage)               │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

## Figures

![Context Diagram](assets/images/context_diagram.png)

![Level 0 Data Flow Diagram](assets/images/dfd_level0.svg)

**Note:** The Context Diagram (above) shows the system boundary and external entities only. The Level 0 Data Flow Diagram (DFD) shows the high-level internal processes (Attendance Monitoring, Material Management, Reporting & Analytics), the main data stores (Projects, Attendance, Materials), and service integrations. These two diagrams are intentionally different to avoid redundancy: the Context Diagram depicts external interactions, while the Level 0 DFD depicts internal data-processing flows.

**DFD levels included:**
- Context Diagram: external entities and system boundary.
- Level 0 DFD: high-level internal processes and data stores.
- Level 1 DFD: next decomposition of Level 0 if more detail is needed.
- Level 2 DFD: not included here; this documentation focuses on Context + Level 0, with Level 1 only if you choose to expand further.
```

## External Entity Connections

```
Site Manager (Mobile) ──────┐
                           ├──→ CEO Construction Management System
Admin (Web) ───────────────┤       │
                           │       │
CEO (Web) ─────────────────┤       ↓
                           │  ┌──────────────────┐
                           └──│  Firebase        │
                              │  - Auth          │
                              │  - Firestore     │
                              │  - Storage       │
                              └──────────────────┘
                                       ↕
                              ┌──────────────────┐
                              │  Cloud Functions │
                              │  - AI Chat       │
                              │  - OTP Service   │
                              │  - Notifications │
                              └──────────────────┘
                                       ↕
                              ┌──────────────────┐
                              │  SendGrid        │
                              │  (Email Service) │
                              └──────────────────┘
                                       ↕
                              ┌──────────────────┐
                              │  Weather API     │
                              │  (OpenWeatherMap)│
                              └──────────────────┘
```

## Data Flow Summary

### Authentication Flow
1. User (Site Manager/Admin/CEO) → System: Email/Password
2. System → Firebase: Authentication request
3. Firebase → System: Auth token + User data
4. System → SendGrid: OTP email request
5. SendGrid → User: OTP code
6. User → System: OTP verification
7. System → Firebase: Verify OTP
8. Firebase → System: Confirmation
9. System → User: Access granted

### Material Flow
1. Admin → System: Allocate material to project
2. System → Firebase: Create material_allocation document
3. System → Firebase: Create material_inventory document (if not exists)
4. Firebase → Site Manager: Real-time inventory update
5. Site Manager → System: Record material usage
6. System → Firebase: Create material_usage document
7. System → Firebase: Update material_inventory (reduce stock)
8. System → Firebase: Update material_allocation (increase used)
9. Firebase → Admin: Real-time usage update

### GovTrack AI Flow
1. User → System: Chat query
2. System → Cloud Functions: Query with project context
3. Cloud Functions → Firebase: Fetch project data (progress, materials, attendance)
4. Firebase → Cloud Functions: Project data
5. Cloud Functions: Intent detection + deterministic analysis
6. Cloud Functions → AI Model (Gemini): Contextualized prompt
7. AI Model → Cloud Functions: AI response
8. Cloud Functions → System: Final response with insights
9. System → User: Display response

### Weather Alert Flow
1. System (Scheduled) → Weather API: Forecast request
2. Weather API → System: Weather data
3. System → Firebase: Store weather data
4. System → Firebase: Create notification for rain alerts
5. Firebase → Site Manager: Push notification
6. Site Manager → User: Weather alert display

### Sync Flow (Offline-First)
1. Site Manager (Offline) → Hive: Cache data locally
2. Site Manager (Offline) → Hive: Queue pending operations
3. Site Manager (Online) → SyncService: Process queue
4. SyncService → Firebase: Batch write pending operations
5. Firebase → SyncService: Confirmations
6. SyncService → Hive: Clear synced operations
7. Firebase → Site Manager: Real-time updates
