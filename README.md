# Timely - AI-Powered Personal Time Assistant

## Inspiration
Timely was inspired by a simple problem: people do not struggle because they lack to-do lists, they struggle because plans do not adapt to real life. Deadlines shift, energy dips, and priorities collide. We wanted to build an assistant that understands natural language, schedules intelligently, and checks in like a supportive coach, not just a reminder app.

## What it does
Timely is an AI-powered personal time assistant that helps users turn messy thoughts into actionable schedules.

It can:
- Parse natural-language tasks into structured plans (title, priority, deadline, estimated duration).
- Auto-schedule tasks into open time slots while avoiding overload.
- Generate a daily brief and read it aloud with voice audio.
- Send diagnostic check-ins (e.g., "What are you doing?") through interactive notifications.
- Log behavior signals to improve future scheduling and personalization.

## Tech Stack
We built Timely as a full-stack system with resilience in mind, ensuring it works in development or partial-config environments:

- **Frontend**: Flutter app with Riverpod state management
- **Backend**: FastAPI with async architecture
- **Database**: MongoDB (via async Motor driver)
- **AI parsing & briefing**: Gemini integration with robust fallback parsing
- **Voice output**: ElevenLabs text-to-speech (with gTTS fallback)
- **Notifications**: Firebase Cloud Messaging (FCM) + local notification actions
- **Scheduling**: Custom engine handling overlap detection, priority balancing, wake/sleep windows, and day-load awareness

## Features & Accomplishments
- End-to-end working flow from task input to scheduled timeline to daily voice brief.
- Human-aware scheduling engine (beyond naive first-fit placement).
- Interactive diagnostic notifications that act as behavioral feedback.
- Strong fallback strategy for missing API keys (Firebase, Gemini, ElevenLabs).
- Clean separation of concerns across services, routers, providers, and UI modules.

## What's Next
- Richer personalization using diagnostics and completion trends.
- Real-time schedule re-planning when users snooze or miss blocks.
- Collaborative and external calendar integrations (school/work).
- Expressive voice experience enhancements.
- Analytics dashboards for habit insights and burnout risk detection.

## Getting Started / How to Use

The project consists of a FastAPI backend and a Flutter frontend.

### Prerequisites
- Python 3.9+
- Flutter SDK
- MongoDB instance (local or Atlas)

### Backend Setup
1. Navigate to the `backend` directory:
   ```bash
   cd backend
   ```
2. Create and activate a virtual environment:
   ```bash
   python -m venv .venv
   # Windows:
   .venv\Scripts\activate
   # macOS/Linux:
   source .venv/bin/activate
   ```
3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
4. Configure environment variables:
   Copy `.env.example` to `.env` and fill in necessary keys (MongoDB URI, Gemini, ElevenLabs, etc.).
   ```bash
   copy .env.example .env
   ```
5. Run the FastAPI server:
   ```bash
   uvicorn app.main:app --reload --port 8000
   ```
   > **Note:** The backend uses graceful fallbacks. If API keys for Gemini, ElevenLabs, or Firebase are missing, the app will degrade to deterministic local logic so you can still run it!

### Frontend Setup
1. Navigate to the `frontend` directory:
   ```bash
   cd frontend
   ```
2. Fetch Flutter dependencies:
   ```bash
   flutter pub get
   ```
3. Run the Flutter application on your desired device/emulator:
   ```bash
   flutter run
   ```
