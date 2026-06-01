# 🥛 HKMC Milk Parlour App

**Milk Collection & Invoice Management Android Application**  
For: **Hemant Kumawat Milk Center**, Khargone, Madhya Pradesh  
Mobile: 9993991979

---

## 📱 About

A fully offline Android app for managing milk collection, auto-calculating KG FAT & amounts, generating PDF invoices, and producing daily/monthly reports. Includes a scan module for OCR-based register digitization with handwriting support via Google Cloud Vision API.

---

## ✨ Features

| Module | Features |
|--------|----------|
| 👥 **Customer Management** | Add, edit, delete, search customers |
| 🥛 **Milk Entry** | Daily entry with date picker & customer dropdown |
| 🧮 **Auto Calculation** | KG FAT = (Qty × FAT) / 100 · Amount = Qty × FAT × Rate |
| 📷 **Scan Register** | Camera/gallery capture with frame overlay, auto-tilt correction, crop, rotate, OCR extraction |
| 🤖 **Dual OCR Engine** | ML Kit (offline, printed text) + Google Cloud Vision API (handwriting) with auto-fallback |
| 🧾 **Invoice Generation** | Professional PDF invoices (HKMC-YYYY-XXXX format) |
| 📄 **PDF Export** | Download, share via WhatsApp, print |
| 📊 **Reports** | Customer report, collection report (day/shift/week/month/custom), analytics, avg price/litre |
| 🖨️ **Collection Report** | Printable report filtered by day, morning/evening shift, week, month, or custom range with PDF export |
| ☁️ **Google Drive Backup** | Auto-backup with Google Sign-In + manual backup/restore |
| 💾 **Local Backup** | SQLite database backup to device storage |
| 📴 **100% Offline** | No internet required for core features — SQLite on-device |

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart) |
| Database | SQLite via `sqflite` |
| State Management | Provider |
| PDF Generation | `pdf` + `printing` packages |
| OCR (Printed Text) | Google ML Kit Text Recognition (offline) |
| OCR (Handwriting) | Google Cloud Vision API (online) |
| Camera | `camera` + `image_cropper` + `image` packages |
| Cloud Backup | Google Sign-In + Google Drive API |
| File Sharing | `share_plus` |
| Background Tasks | `workmanager` (daily auto-backup) |
| Settings | `shared_preferences` |

---

## 📐 Calculation Engine

```
KG FAT  = (Quantity × FAT) / 100
Amount  = Quantity × FAT × Rate
```

---

## 🗄️ Database Schema

### `customers`
| Column | Type |
|--------|------|
| id | INTEGER PK AUTOINCREMENT |
| name | TEXT NOT NULL |
| mobile | TEXT |
| address | TEXT |
| created_at | TEXT |

### `milk_entries`
| Column | Type |
|--------|------|
| id | INTEGER PK AUTOINCREMENT |
| customer_id | INTEGER FK |
| date | TEXT |
| shift | TEXT (Morning/Evening) |
| milk_type | TEXT (Cow/Buffalo) |
| quantity | REAL |
| clr | REAL |
| fat | REAL |
| rate | REAL |
| kgfat | REAL |
| amount | REAL |
| item_name | TEXT |
| item_amount | REAL |
| entry_time | TEXT |

### `invoices`
| Column | Type |
|--------|------|
| id | INTEGER PK AUTOINCREMENT |
| invoice_number | TEXT UNIQUE |
| customer_id | INTEGER FK |
| from_date | TEXT |
| to_date | TEXT |
| total_quantity | REAL |
| total_amount | REAL |
| milk_amount | REAL |
| discount | REAL |
| extra_amount | REAL |
| adjustment_note | TEXT |
| pdf_path | TEXT |
| created_at | TEXT |

---

## 🔢 Invoice Number Format

```
HKMC-YYYY-0001
Example: HKMC-2026-0001
```

---

## 📷 Scan Module

The scan module allows digitizing handwritten milk register pages:

1. **Capture** — Camera with frame overlay or pick from gallery
2. **Prepare** — Rotate (90°/180°) and crop to select data rows
3. **OCR** — ML Kit (offline, printed text) or Cloud Vision API (handwriting)
4. **Review** — Parsed entries shown as editable cards with validation
5. **Save** — Batch save valid entries to database

### OCR Engine Toggle
- **ML Kit** (default) — Free, offline, works with printed text
- **Cloud Vision** — Requires API key, handles handwriting, auto-falls back to ML Kit on failure

### Date Parsing
Handles all Indian handwritten date formats: `dd/mm`, `dd/m`, `dd-mm`, `dd.mm`, `dd/mm/yy`, `dd/mm/yyyy`, and no-separator formats.

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) >= 3.3.0
- Android Studio or VS Code with Flutter extension
- Android device or emulator (API 21+)

### Setup

```bash
# Clone the repo
git clone https://github.com/pushpjeetcholkar/milk-parlour-app.git
cd milk-parlour-app

# Install dependencies
flutter pub get

# Run on connected Android device
flutter run

# Build release APK
flutter build apk --release
```

### Cloud Vision API (Optional)
To enable handwriting OCR:
1. Create a project on [Google Cloud Console](https://console.cloud.google.com/)
2. Enable the **Cloud Vision API**
3. Create an API key under APIs & Services > Credentials
4. In the app: Settings > Scan & OCR > enter the API key

---

## 📂 Project Structure

```
lib/
├── main.dart                    # Entry point
├── app.dart                     # App routing & theme
├── core/
│   ├── constants/               # App & DB constants
│   ├── database/                # SQLite database helper
│   └── services/                # Settings service
├── models/                      # Customer, MilkEntry, Invoice, ScannedEntry
├── repositories/                # Database CRUD operations
├── providers/                   # State management (Provider)
├── screens/                     # All UI screens
│   ├── splash/
│   ├── dashboard/
│   ├── customers/
│   ├── milk_entry/              # Add entry, scan entry, camera frame, scan review
│   ├── invoice/
│   ├── reports/                 # Customer, collection, analytics, avg price
│   ├── backup/
│   └── settings/
└── services/                    # PDF generation, OCR, backup/restore
```

---

## 🗺️ Roadmap

- [x] Customer Management
- [x] Milk Entry with Auto Calculation (Shift, Milk Type, Items/Deductions)
- [x] PDF Invoice Generation with Edit Invoice support
- [x] Customer Reports & Collection Reports (day/shift/week/month/custom)
- [x] Analytics Dashboard with Charts
- [x] Average Price per Litre Report
- [x] Local Backup & Restore
- [x] Google Drive Auto-Backup
- [x] Scan Register Pages (Camera + OCR)
- [x] Dual OCR: ML Kit (offline) + Cloud Vision (handwriting)
- [x] Printable Collection Reports with PDF export
- [ ] Phase 2: Bluetooth printing, Multi-language support

---

## 📜 License

Private — Hemant Kumawat Milk Center. All rights reserved.
