# GrindScale MVP Implementation Backlog

This backlog is organized for direct execution by a small team (1-3 engineers).

## Sprint 0 - Project Setup (1-2 days)

### Task 0.1 - App scaffold
- Create mobile project and modules:
  - `capture`
  - `pipeline`
  - `analysis`
  - `visualization`
  - `storage`
- Definition of done:
  - App runs on device.
  - Module boundaries compile.

### Task 0.2 - CI and code quality
- Add lint + format + unit-test job.
- Definition of done:
  - CI runs on each PR.

## Sprint 1 - Capture and Quality Gate

### Task 1.1 - Camera preview and ROI
- Circular ROI overlay and guidance text.
- Definition of done:
  - User can align sample into ROI before capture.

### Task 1.2 - Blur and exposure checks
- Implement Laplacian variance blur check.
- Implement exposure histogram check.
- Definition of done:
  - Capture blocked with retake prompt when failed.

### Task 1.3 - Occupancy check
- Ensure enough foreground presence in ROI.
- Definition of done:
  - Warn when too few particles are present.

## Sprint 2 - Baseline Analysis Pipeline

### Task 2.1 - Preprocess and threshold
- Grayscale + Gaussian blur + adaptive threshold.
- Definition of done:
  - Binary mask generated for internal debug view.

### Task 2.2 - Morphology cleanup
- Opening and closing with tuned kernel.
- Definition of done:
  - Noise reduced while preserving major particles.

### Task 2.3 - Contour extraction
- Extract connected components.
- Area filtering min/max.
- Definition of done:
  - Basic particle count and diameter list available.

## Sprint 3 - Touching Particle Separation

### Task 3.1 - Distance transform
- Create marker candidates for object centers.
- Definition of done:
  - Marker map visible in debug output.

### Task 3.2 - Watershed split
- Apply watershed on binary mask.
- Definition of done:
  - Touching clusters split better than contour-only baseline.

### Task 3.3 - Confidence flag
- If split quality is low, set low-confidence marker.
- Definition of done:
  - Result includes confidence level.

## Sprint 4 - Metrics, Scoring, and Result UI

### Task 4.1 - Stats engine
- Compute mean, std, CV, D10/D50/D90.
- Definition of done:
  - Unit tests with fixed sample arrays.

### Task 4.2 - Uniformity score
- Implement weighted penalty model.
- Definition of done:
  - Score range and monotonic behavior validated.

### Task 4.3 - Histogram and color overlay
- Histogram component.
- Per-particle classification overlay (blue/green/red).
- Definition of done:
  - Result screen shows chart + overlay + score.

## Sprint 5 - Calibration and Recommendation

### Task 5.1 - Coin detection
- Detect supported coin circle and estimate px/mm.
- Definition of done:
  - Calibrated mode enabled when coin is found.

### Task 5.2 - Relative vs calibrated mode
- Explicit mode badge and copy.
- Definition of done:
  - User always sees measurement confidence context.

### Task 5.3 - Recommendation engine
- Rule-based text generation from ratios and CV.
- Definition of done:
  - Returns deterministic suggestion for known scenarios.

## Sprint 6 - Validation and Release Candidate

### Task 6.1 - Dataset and benchmark
- Build labeled set of 200+ images.
- Definition of done:
  - Benchmark report generated.

### Task 6.2 - Repeatability test
- Same sample repeated shots with variance report.
- Definition of done:
  - CV drift metric documented.

### Task 6.3 - Performance optimization
- Keep analysis under target runtime budget.
- Definition of done:
  - p50 and p95 analysis time logged and within threshold.

## Acceptance Checklist (MVP Release)

- [ ] Quality gate catches invalid captures.
- [ ] Pipeline returns stable particle metrics.
- [ ] Score and histogram are visible and understandable.
- [ ] Calibration mode works with at least one coin type.
- [ ] Recommendation text maps to measured distribution.
- [ ] Benchmark and repeatability reports are documented.

