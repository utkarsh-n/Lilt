# Lilt

An original, iPhone-only marble labyrinth for iOS 27. Tilt your phone to roll a steel marble across a tactile wooden board, or describe a labyrinth and play a generated version.

## Play

- Twelve original campaign boards progress from balance and braking to winding paths, holes, bumpers, magnets, and fans.
- The ball has inertia. Tilt supplies acceleration; reverse tilt brakes. Touch steering supplies the same physical force, with four accessible nudge buttons.
- Hold your phone comfortably before starting. Calibration makes that position neutral. Falls restart the same board; pause and backgrounding suspend the clock and sensors.
- Best unassisted times retain a ghost replay. Showing the safe route marks the current run as guided.

## Describe a labyrinth

Generative mode accepts a written description, optional difficulty and material overrides, and produces a checked board preview. Play immediately or save it to your collection.

Examples:

- “A peaceful jade garden with wide paths, two holes and no bumpers.”
- “A tricky wooden spiral with five holes, winding toward the center.”
- “An expert midnight maze with magnets, fans and narrow passages.”
- “A maple pinball labyrinth with four bumpers and no holes.”

The shared MLX layer interprets varied language into a typed recipe using Qwen3.5 2B by default, with optional 4B in Settings. If the selected model is unavailable or returns an invalid recipe, a local interpreter recognizes the documented vocabulary, quantities, and exclusions. The UI identifies the actual interpretation method. Neither path needs an API key or sends descriptions to an app backend. [Integration details](Documentation/OFFLINE_INTELLIGENCE.md) describe model resources and validation.

Supported route families are switchbacks, spirals, open gardens, and pinball boards. Materials are maple, jade ceramic, and midnight metal. Supported objects are holes, bumpers, magnets, and fans. Explicit quantities/exclusions are enforced after model interpretation. Object placement is capacity-bounded; the preview displays the actual counts. Unsupported sequel mechanisms such as cannons, doors, lasers, duplicators, and multiple balls are not implemented.

The deterministic generator checks continuous route clearance against the marble radius, wall thickness, holes, and bumpers. Saved mazes retain the full geometry, recipe, seed, generator version, and interpretation method, so reopening does not regenerate a different board.

## Engineering

- **Swift 6 / SwiftUI / Observation:** native navigation, tactile wood and metal controls, scoped observable state, and strict concurrency.
- **Metal / MTKView:** procedural wood and ceramic, shaded steel sphere, inset holes, chamfered rails, contact shadows, best-run ghost and dashed route. Retained triple buffers and cached static geometry keep frame work bounded. Rendering supports up to 120 Hz and adapts under Low Power Mode or thermal pressure.
- **Physics:** 240 Hz simulation, responsive acceleration with the solid-sphere 5/7 gravity factor, light viscous drag plus very low finite-stop rolling resistance, swept circle/capsule collision detection, modest wall restitution and spring bumpers. Returning to neutral lets the marble coast. Opposite tilt adds smooth dissipation along opposing travel for more controlled stopping, fading as speed reaches zero; holding that tilt still reverses naturally. Starting response and sideways momentum are preserved. Display timing does not determine the integration step. The feel is inspired by the originals; proprietary historical constants are not reproduced.
- **Core Motion:** fused device attitude, full 3D neutral calibration, fresh-sample gating and bounded sensitivity. A stateless radial response curve strengthens small tilts and eases toward the force limit at steeper angles, with only a tiny sensor-noise deadband. No additional input low-pass filter. Pause and retry preserve the calibrated holding position.
- **OfflineIntelligenceKit / MLX:** bounded, typed Qwen recipe interpretation; geometry is always constructed and validated by the deterministic core.
- **SwiftData:** saved boards, clean-run personal bests, and bounded sampled ghost replays.
- **AVAudioEngine / Core Haptics:** precomputed restrained impact/fall/win sounds and cached event patterns, with settings and lifecycle shutdown.

Metal shader source is bundled as a resource and compiled by the device on first use. The renderer also accepts a compatible precompiled default library. This keeps builds usable with the installed Xcode 27 SDK even when its optional offline Metal compiler component is absent.

## Build and verify

Use the shared build helper to stage verified model resources outside the synced workspace and build the **Lilt** scheme for iPhone. The project is generated from `project.yml` with XcodeGen. Signing currently uses the workspace's existing developer team; change it for another developer account. Direct source-project builds need locally supplied model resources to use Qwen; the local interpreter remains available.

```sh
python3 ../OfflineIntelligenceKit/Tools/build_hosts.py --app Lilt
swift test --disable-sandbox --scratch-path /private/tmp/lilt-core-build
```

The pure Swift package tests physics, seeded generation, prompt semantics, geometric clearance, independent flood-fill reachability, physically controlled route completion, and Codable exactness. See [the design study](Documentation/DesignStudy.md) for research and [the QA record](Documentation/QA/Validation.md) for the checks actually observed.

If building the Documents checkout stalls in `DVTFilePath performCoordinatedReadRecursively`, build an identical temporary copy and verify source hashes before relying on the result. This is a host file-coordination issue observed in this workspace.

Physical feedback led first to a calibration and latency correction, then to stronger small-angle response and reduced rolling resistance. The user confirmed the improved response but found stopping too slippery; the latest tune adds controlled reverse-tilt braking while preserving small-angle response. Speaker output, haptic feel, long-run battery use, and on-device language-model generation still require direct checks. Delivery and validation are recorded in the QA document.


## Public snapshot

See [PUBLICATION.md](PUBLICATION.md) for publication exclusions and setup requirements.
