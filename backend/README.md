# KaraOK Backend

Flask REST API connecting the Flutter app to MySQL.

## Setup

### 1. Create the database
Open MySQL Workbench or any MySQL client and run:
```sql
source database/schema.sql
```
Or from terminal:
```bash
mysql -u root -p12345678 < ../database/schema.sql
```

### 2. Install Python dependencies
```bash
pip install -r requirements.txt
```

### 3. Start the server
```bash
python app.py
```
Server runs on **http://localhost:5000**

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/health | DB connection check |
| GET | /api/audio-tests | List all tests |
| POST | /api/audio-tests | Save a new test result |
| GET | /api/audio-tests/:id | Get one test |
| DELETE | /api/audio-tests/:id | Delete a test |
| GET | /api/genre-settings?genre=Rock | Get settings for genre |
| POST | /api/genre-settings | Save genre settings |
| GET | /api/audio-uploads | List uploads |
| POST | /api/audio-uploads | Save upload record |

## Flutter device config

- **Android emulator** → uses `10.0.2.2:5000` (already set)
- **Physical device** → change `baseUrl` in `lib/services/api_service.dart` to your PC's LAN IP, e.g. `http://192.168.1.x:5000`
