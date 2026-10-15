# Public source snapshot

This repository contains a reviewed source snapshot. Original Git history, credentials, personal records, local signing identities, device diagnostics, build outputs, downloaded model weights, firmware, and unreviewed media are excluded. Existing upstream license and attribution files apply to their respective components. Publication does not grant a new license to third-party content.

Configure your own Apple signing team to run native apps on a physical device. Downloaded datasets, binary runtimes, fonts, demo media, and models may need to be obtained separately using the documented upstream sources or fetch/build tools. This publication review does not certify that this snapshot builds or runs.

## Project setup and omitted assets

Clone [OfflineIntelligenceKit](https://github.com/utkarsh-n/OfflineIntelligenceKit) beside this repository; the manifest references its core package and `MLX` subpackage. Shared text-generation model payloads are omitted. Use the shared package's documented local model setup before using generated-level features. The fixed gameplay source and tests are retained; private physical-device QA evidence is omitted.
