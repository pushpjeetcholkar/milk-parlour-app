# 🥛 HKMC Milk Parlour App

**Milk Collection & Invoice Management Android Application**  
For: **Hemant Kumawat Milk Center**, Khargone, Madhya Pradesh  
Mobile: 9993991979

---

## 📱 About

A fully offline Android app for managing milk collection, auto-calculating KG FAT & amounts, generating PDF invoices, and producing daily/monthly reports.

---

## ✨ Features

| Module | Features |
|--------|----------|
| 👥 **Customer Management** | Add, edit, delete, search customers |
| 🥛 **Milk Entry** | Daily entry with date picker & customer dropdown |
| 🧮 **Auto Calculation** | KG FAT = (Qty × FAT) / 100 · Amount = Qty × FAT × Rate |
| 🧾 **Invoice Generation** | Professional PDF invoices (HKMC-YYYY-XXXX format) |
| 📄 **PDF Export** | Download, share via WhatsApp, print |
| 📊 **Reports** | Daily & monthly reports with customer-wise summary |
| 💾 **Backup & Restore** | SQLite database backup to device storage |
| 📴 **100% Offline** | No internet required — SQLite on-device |

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Dart) |
| Database | SQLite via `sqflite` |
| State Management | Provider |
| PDF Generation | `pdf` + `printing` packages |
| File Sharing | `share_plus` |
| Backup | `file_picker` + `path_provider` |

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
| quantity | REAL |
| clr | REAL |
| fat | REAL |
| rate | REAL |
| kgfat | REAL |
| amount | REAL |

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
| pdf_path | TEXT |
| created_at | TEXT |

---

## 🔢 Invoice Number Format

```
HKMC-YYYY-0001
Example: HKMC-2026-0001
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.3.0
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

---

## 📂 Project Structure

```
lib/
├── main.dart                    # Entry point
├── app.dart                     # App routing & theme
├── core/
│   ├── constants/               # App & DB constants
│   ├── database/                # SQLite database helper
│   └── utils/                   # Calculators, validators, invoice numbering
├── models/                      # Customer, MilkEntry, Invoice
├── repositories/                # Database CRUD operations
├── providers/                   # State management (Provider)
├── screens/                     # All UI screens
│   ├── splash/
│   ├── dashboard/
│   ├── customers/
│   ├── milk_entry/
│   ├── invoice/
│   ├── reports/
│   ├── backup/
│   └── settings/
└── services/                    # PDF generation, backup/restore
```

---

## 🗺️ MVP Roadmap

- [x] Customer Management
- [x] Milk Entry with Auto Calculation
- [x] PDF Invoice Generation
- [x] Daily & Monthly Reports
- [x] Backup & Restore
- [ ] Phase 2: Cloud sync, Bluetooth printing, Multi-language

---

## 📜 License

Private — Hemant Kumawat Milk Center. All rights reserved.
