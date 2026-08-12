# ZenTrain

ZenTrain is an offline-first iOS training app. This monorepo keeps the iOS client, a thin backend, and future cross-platform contracts versioned together.

## Stage A status

- `ios/` contains the iOS 17 SwiftUI app, unit-test target, UI-test target, and Composition Root.
- `backend/` contains a TypeScript/Fastify service with a tested `GET /health` endpoint.
- `contracts/` reserves the JSON Schema boundary for the later Agent integration stage.

Domain behavior, SwiftData persistence, and the manual workout UI are intentionally deferred to stages B, C, and D.

## Run the iOS app

1. Install a full Xcode release that supports iOS 17 or later.
2. Open `ios/TrainingApp.xcodeproj`.
3. Select the `TrainingApp` scheme and an iPhone simulator.
4. Build or run the test action.

## Run the backend

Requires Node.js 20 or later.

```sh
cd backend
npm ci
npm test
npm run dev
```

The health endpoint is available at `http://localhost:3000/health`.
