## Inspiration

Timely was inspired by a simple problem: people do not struggle because they lack to-do lists, they struggle because plans do not adapt to real life. Deadlines shift, energy dips, and priorities collide. We wanted to build an assistant that understands natural language, schedules intelligently, and checks in like a supportive coach, not just a reminder app.

## What it does

Timely is an AI-powered personal time assistant that helps users turn messy thoughts into actionable schedules.

It can:
- Parse natural-language tasks into structured plans (title, priority, deadline, estimated duration)
- Auto-schedule tasks into open time slots while avoiding overload
- Generate a daily brief and read it aloud with voice audio
- Send diagnostic check-ins (for example, "What are you doing?") through interactive notifications
- Log behavior signals to improve future scheduling and personalization

## How we built it

We built Timely as a full-stack system:

- Frontend: Flutter app with Riverpod state management
- Backend: FastAPI with async architecture
- Database: MongoDB (via async Motor driver)
- AI parsing and briefing: Gemini integration with robust fallback parsing
- Voice output: ElevenLabs text-to-speech with gTTS fallback when external keys are unavailable
- Notifications: Firebase Cloud Messaging plus local notification actions in-app
- Scheduling: custom engine that handles overlap detection, priority balancing, wake/sleep windows, and day-load awareness
- Automation: scheduled jobs for recurring daily brief workflows

We also focused heavily on resilience so the app still works in development or partial-config environments.

## Challenges we ran into

- Making AI output reliable and schema-safe for real task parsing
- Handling scheduling conflicts while preserving user intent (fixed-time events vs flexible deadlines)
- Balancing urgency with burnout prevention in schedule generation
- Coordinating notification actions across foreground, background, and device-specific behavior
- Building graceful degradation paths when API keys/services are missing (Firebase, Gemini, ElevenLabs)

## Accomplishments that we're proud of

- End-to-end working flow from task input to scheduled timeline to daily voice brief
- A scheduling engine that is more human-aware than naive first-fit placement
- Interactive diagnostic notifications that turn passive reminders into behavioral feedback
- Strong fallback strategy so the product remains usable even with incomplete cloud setup
- Clean separation of concerns across services, routers, providers, and UI modules

## What we learned

- Reliability matters as much as intelligence in AI products
- Fallback-first architecture dramatically improves developer experience and demo stability
- Notifications are not just delivery channels; they can be core UX for behavior change
- Timezone and temporal logic become complex quickly and must be designed early
- Personalization signals are powerful even before full ML fine-tuning

## What's next for Timely

- Add richer personalization from diagnostics and completion trends
- Improve schedule re-planning in real time when users snooze or miss blocks
- Expand to cross-platform production readiness with stronger auth and account linking
- Add collaborative and calendar integrations (school/work calendars)
- Improve voice experience with more expressive briefing styles
- Build analytics dashboards for habit insights and burnout risk detection
