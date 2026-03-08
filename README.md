# Expense Tracker Flutter

A mobile expense tracker app built with Flutter and Supabase as the backend.

## Tech Stack
- Flutter
- Supabase (Auth + Database)
- Riverpod (State Management)
- fl_chart (Charts)

## Features
- Login & Register
- Google Login
- Dashboard with total balance
- Add transactions (income & expense)
- Transaction history with filter
- Analytics with charts
- Profile management

## Screenshots

![Dashboard](screenshots/dashboard.jpeg)
![Transaction](screenshots/transaction.jpeg)
![Analytics](screenshots/analytics.jpeg)

## Setup

1. Clone this repository
2. Run `flutter pub get`
3. Create a new project at [supabase.com](https://supabase.com)
4. Run the SQL schema located in `supabase/schema.sql`
5. Open `lib/main.dart` and replace:
```dart
   url: 'YOUR_SUPABASE_URL',
   anonKey: 'YOUR_SUPABASE_ANON_KEY',
```
   with your Supabase project URL and anon key
6. Run `flutter run`

## Build APK
```
flutter build apk --release
```

## Developer
Developed by YRJ & Claude
