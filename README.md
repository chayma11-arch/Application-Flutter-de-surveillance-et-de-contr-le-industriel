## Mobile Application - Flutter

### Overview

The mobile application is developed using **Flutter**, a cross-platform framework by Google. It serves as the user interface for the IoT platform, allowing users to monitor environmental data in real-time, view historical records, receive alerts, and control actuators remotely.

The application communicates with the ESP32-S3 central node via the **MQTT protocol**, ensuring low-latency and reliable data transmission.

---

### Key Features

**User Authentication**
- Secure login and registration using **Firebase Authentication**
- Email/password authentication
- Session management for persistent login

**Real-time Dashboard**
- Live display of sensor data:
  - Temperature (°C)
  - Humidity (%)
  - Pressure (hPa)
  - Light intensity (Lux)
  - Angle(deg)
    
- Real-time updates via MQTT
- Visual indicators for threshold alerts

**Historical Data Visualization**
- Interactive graphs and charts
- Customizable time ranges 
- Export data as **PDF reports**
- Data persistence with local storage (HIVE)

**Alerts and Notifications**
- Push notifications when thresholds are exceeded
- Local notification system (no internet required)
- Customizable alert thresholds
- Visual alerts on the dashboard

**Device Control**
- Remote control of actuators (Servo motor, LEDs)
- Manual override for industrial control
- Scheduled automation
---

### Architecture
