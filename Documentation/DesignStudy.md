# Lilt: design study and implementation contract

Research checked on October 12, 2026. Lilt is an original iPhone marble labyrinth inspired by the physical control and readable boards of Illusion Labs' Labyrinth games. It uses its own name, art, layouts, and level rules.

## What made the originals work

Illusion Labs describes its first Labyrinth as a digital version of the classic maze driven by the iPhone accelerometer. The central interaction is therefore the device becoming the board: small changes in angle produce small changes in the marble's acceleration. The interesting skill is managing momentum and braking near corners and traps. [Illusion Labs, The Studio](https://illusionlabs.com/the-studio)

The original game goal was to guide the ball across a wooden board to the finish while avoiding holes; falling meant starting that board again. Contemporary coverage also records beginner boards and a growing supply of community levels. This is direct historical gameplay observation rather than a claim about the original physics source code, which is unavailable here. [TouchArcade, July 25, 2008](https://toucharcade.com/2008/07/25/labyrinth-lite-takes-top-spot-in-app-store/)

A preserved original product description lists 60 FPS, tilt-dependent wall perspective, shadows, calibration, sound, tactile feedback, and hole-edge physics that allow grazing a hole without automatically falling. The original App Store page is no longer accessible through this research tool, so that feature list is supported by a secondary preservation of the description. It motivates the acceptance criteria below; it does not establish exact historical constants. [Preserved Labyrinth description, GameFAQs](https://gamefaqs.gamespot.com/iphone/962409-labyrinth)

Labyrinth 2 expanded the toy with cannons, bumpers, several balls, doors, magnets, fans, ball-size changes, rotating platforms, duplicators, and lasers. Its developer-authored store listing also specifies community creation/sharing/rating, four-player local play, a ghost of the player's best run, and achievements. These are sequel features, not requirements for every classic board. [Labyrinth 2, App Store](https://apps.apple.com/us/app/labyrinth-2/id307758884)

**Design inference:** the essential promise is a convincing physical object with immediate retries, not a maze-solving interface that teleports a token. Lilt should retain the steel marble, tactile impact cues, clear trap/goal distinction, and uninterrupted full-board visibility. A modern shell can frame that object without covering the route.

## Faithful core acceptance criteria

- Tilt changes acceleration, not absolute ball position. Neutral calibration must work at a comfortable holding angle. Sensitivity should be adjustable; touch steering supplies the same acceleration input for Simulator and players who prefer it.
- The marble retains momentum, slows through rolling resistance, rebounds with restrained energy, and cannot pass through walls. Use a fixed simulation step independent of display frequency and sufficiently small substeps or swept collision checks at high speed.
- Traps use circular geometry. A glancing edge overlap must not count as an immediate loss; sufficient center penetration begins a visible drop. The goal uses a distinct finish marker and capture state.
- A trap ends the current run and restarting restores the exact same board, start, and physical state. Completing records elapsed time and makes replay easy. Suspend both simulation and timing while paused or backgrounded.
- Shadows, ball highlight, wall depth, and restrained board parallax should agree on one light/material vocabulary. Tilt must never alter collision geometry through visual projection.
- Sounds/haptics correspond to impact, fall, and completion, with strength tied to collision energy where practical. Settings must allow disabling them.
- Every built-in or generated board has valid dimensions, a clear start/finish, free start/goal space, and a route wide enough for the marble. Solvability validation must consider the finite ball radius and lethal holes, not only maze cells.
- Automated physics/generation checks, a successful iOS build, observed Simulator play, and direct iPhone tilt/haptic/audio feel remain separate evidence claims.

These are engineering targets inferred from the observed design. Lilt cannot claim numerical parity with proprietary original physics without comparative device measurements.

## Generative mode

The player's description becomes a **semantic recipe**: difficulty, shape/route emphasis, palette/material, hazard density, and supported obstacle types. Apple Foundation Models can interpret varied language into a typed recipe on supported devices. A deterministic generator then constructs geometry, evaluates the route, places hazards with clearance, and validates the result before offering Play.

The language model does not emit unchecked wall coordinates or arbitrary executable logic. Typed generation constrains syntax and parameter ranges; the geometry validator supplies spatial correctness. Keep the original description, recipe, generator version, and seed with the saved level so replay does not depend on another model response.

If Apple Intelligence is disabled, the model is not downloaded, the device is ineligible, or generation fails, a local description interpreter plus the same deterministic generator can still produce a playable board. The UI must clearly identify the interpretation method. That fallback supports a defined vocabulary rather than pretending to have unrestricted language understanding. Supported prompt examples should be visible.

## Meaningful modern implementation

| Advancement | Purpose and limit |
| --- | --- |
| SwiftUI and Observation | Native navigation, generation sheet, settings, accessibility controls, and a single owned game model. Keep per-frame rendering out of expensive body recomputation. |
| Metal / MTKView | Procedural materials, hole depth, sphere shading, shadows, and board rendering on the GPU without imported legacy artwork. Rendering sophistication must not obscure collision readability. |
| Fixed-step simulation | Predictable physics and collision behavior across 60/120 Hz displays, deterministic regression checks, and repeatable generated seeds. |
| Core Motion device gravity | Responsive tilt input with neutral calibration and filtering that avoids excessive lag. Real-device feel still needs hands-on tuning. |
| Core Haptics and native audio | Events that communicate wall contact, falls, and wins; continuous rolling feedback can follow after battery/feel measurements. |
| Foundation Models guided generation | On-device interpretation into a constrained recipe when the runtime reports availability, with a local fallback. Model availability cannot be assumed from OS version alone. |
| Local persistence | Saved generated boards and best times survive relaunch; preserve generator version and recipe. |
| Lifecycle and performance discipline | Pause when inactive, release sensor/audio activity, keep bounded buffers, and use thermal/display-aware frame rates where appropriate. Profile before claiming a performance benefit. |

Lilt's first implementation includes the classic single-marble maze, the prompt-to-play pipeline, twelve original boards, bumpers, magnets, fans, and a personal-best ghost using persisted position samples. The full sequel catalogue, community backend, local multiplayer, advanced ball transformations, and achievements remain outside this implementation.

## Verified local iOS 27 Foundation Models API

The selected developer installation is `/Applications/Xcode-beta.app`; `xcrun --sdk iphoneos --show-sdk-version` returns `27.0`, and the Swift toolchain reports Apple Swift 6.4. The following interfaces were read directly from:

`/Applications/Xcode-beta.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface`

- `SystemLanguageModel.default.availability` returns `.available` or `.unavailable(reason)`. Reasons are `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, and `.modelNotReady`.
- `@Generable` creates a typed generation schema. `@Guide(description: ..., .range(1...3))` constrains `Int`; `.anyOf(["wood", "stone", "metal"])` constrains `String`. Array count guides also exist.
- `LanguageModelSession(model: SystemLanguageModel.default, instructions: String)` is available.
- `respond(to: String, generating: Recipe.self, options: GenerationOptions(...)) async throws` returns a `Response<Recipe>` with the typed `content` property.
- `GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 200)` is the current spelling. The older `sampling:` spelling is deprecated in this SDK.
- iOS 27 also exposes `ContextOptions` and response usage, but the simple typed pipeline above needs neither. Public interfaces for other model types do not imply that those services are enabled or suitable for this initial app.

A small probe using `@Generable`, both `@Guide` forms above, availability checking, session creation, greedy options, typed `respond`, and `response.content` passed `swiftc -typecheck` for `arm64-apple-ios27.0` with the selected iPhoneOS SDK. The initial nested-sandbox run blocked Apple's macro plugin; the authorized direct compiler run exited 0. Probe source is `/private/tmp/lilt-fm-probe/FMProbe.swift`.

This confirms compile-time API presence and syntax. A compiled app and an eligible device reporting `.available` are still required to prove real generation. Check availability again immediately before a request, handle thrown errors, and keep generation outside the simulation loop.


## Classic interface revision

The interface now uses an original wooden cabinet, large metal menu buttons, a three-column board selector, plywood panels and bold conventional game labels. Gameplay gives the board most of the screen, with a compact timer and pause rail. The Metal surface uses pale plywood, raised flat-top walls, a reflective chrome marble, black drilled holes and a checkered finish. These choices follow the material hierarchy and board emphasis visible in the [official Labyrinth 2 gallery](https://apps.apple.com/us/app/labyrinth-2/id307758884); Lilt uses original generated graphics.

## First iPhone steering correction

The first physical feedback was that acceleration felt slow and delayed. Raw XY gravity subtraction was incorrectly treating a comfortable upright hold as a horizontal calibrated board. Near upright, forward and backward tilts could produce the same sign. The revised input uses the full relative attitude matrix: current rotation multiplied by the transpose of the neutral rotation. The resulting gravity projection retains direction and gain at flat, 45°, 70° and 90° holds. Core Motion supplies a fused signal; the extra application low-pass filter was removed. Sensors warm up before Play, calibration uses a fresh sample, and pause/resume preserves the neutral position.

The response also has stronger acceleration and lighter drag. These constants are a game-control tune, not a claim to reproduce Illusion Labs' proprietary constants. The simulation retains inertia and reverse-tilt braking.

## Small-angle response revision

Further physical feedback identified sluggish response to modest tilts. Removing the input filter alone had left too little early travel: the previous default response moved a marble only about 0.15 screen points in the first 100 ms at a 1° tilt on a 390-point-wide board. The new radial force curve is stateless, odd and direction-preserving: `0.7 * tanh(3.4 * max(0, magnitude * sensitivity - 0.0006) / 0.7)`. Its magnitude replaces the raw tilt magnitude. Small tilts gain useful force immediately; steep tilts smoothly approach the existing maximum force. The default 1.3 sensitivity gives a sensor deadband of approximately 0.026°.

Rolling resistance falls from 0.035 to 0.008 board widths/s², while viscous drag stays at 0.50/s. In the unobstructed deterministic model, a 1° tilt now travels about 1.30 points in 150 ms on a 330-point-wide board. This is a model result, not a measured device latency. The curve changes acceleration only: neutral coasting, finite stopping, collisions and gradual reverse-tilt braking still come from the physics engine. Regression checks cover first-step motion at 0.25°, 0.5°, 1° and 3°, visible early travel, direction symmetry, natural braking and equivalent 60/120 Hz trajectories.

## Controlled reverse-tilt braking

The user confirmed that build 2 responded better but described the marble as too slippery to stop. Build 3 preserves its input curve, deadband, starting acceleration, baseline drag and rolling resistance. While tilt opposes travel, an additional dissipative force acts only on the opposing component of velocity. Its rate smoothly increases with tilt magnitude toward 3.0/s, using `magnitude / (magnitude + 0.06)`. Each physics substep applies exponential decay to that component before the ordinary gravity/drag integration. This damping cannot reverse velocity by itself and fades continuously at zero speed/input. Perpendicular travel and neutral coasting keep their existing behavior; sustained gravity then produces a natural reversal.

At an initial speed of 0.4 board widths/s, an opposing 1° tilt in the 240 Hz model reaches reversal in approximately 0.55 s rather than 0.86 s, travelling about 0.088 rather than 0.158 board widths before stopping. An opposing 3° tilt stops in approximately 0.25 s rather than 0.34 s. These values guide the controllability tune; they do not measure physical sensor latency or establish numerical parity with the original game.
