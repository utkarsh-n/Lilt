# Shared offline maze interpretation

Lilt uses OfflineIntelligenceKit and its MLX backend for description-to-recipe inference. Settings persist Qwen3.5 2B by default and expose optional 4B. The model proposes a typed `MazeInterpretation`; supported enums, title length and feature counts are checked before constructing a recipe. Explicit player counts and material/difficulty/style choices override the proposal, and the existing generator checks the continuous route geometry.

If the model is unavailable or cannot return a valid recipe, the existing local interpreter builds a version with an explicit provenance note. Cancellation returns before publishing a maze. Inactivity and memory warnings unload the shared session; model weights are released after each interpretation so gameplay retains its memory budget.

Build from the canonical workspace with `python3 ../OfflineIntelligenceKit/Tools/build_hosts.py --app Lilt`. Resources are cloned only into the build mirror. Both models are bundled by default; `--models 2b` omits 4B until it is supplied locally. No downloader or cloud generation is involved.

41 core/persistence tests pass, including bounded JSON interpretation, rejection of unsupported requests and preservation of explicit counts/preferences. Native signed-build and physical-delivery status are recorded in OfflineIntelligenceKit/Documentation/IntegrationVerification.json; build evidence does not imply a new phone install or interaction test.
