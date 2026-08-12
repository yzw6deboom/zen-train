# Project context

## Current objective

Build the first manual workout-recording chain in dependency order. Stage A establishes only the monorepo, minimum iOS project, Composition Root, backend health check, and contracts boundary.

## Architecture boundaries

- SwiftUI Views depend on Feature Models, never directly on SwiftData.
- Feature Models invoke the Application interface and do not own business rules.
- Application commands coordinate pure Swift Domain types through Repository ports.
- SwiftData entities and mapping stay inside Infrastructure.
- The App directory is the Composition Root and is the only place that selects concrete adapters.
- Manual actions and future Agent candidates must use the same commands.
- Agent candidates require schema validation, business validation, and user confirmation before execution.
- The complete manual workout chain must work without backend, network, or AI availability.

## Stage boundaries

- Stage B: Domain and Application with an in-memory Repository.
- Stage C: SwiftData Schema V1 and persistence adapter.
- Stage D: four SwiftUI Features covering the frozen seven-screen flow.
- Stage E: stable Agent command DTOs, JSON Schemas, and examples.

Do not implement a later stage merely to fill an empty directory.
