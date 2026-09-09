# prometheus-ada

[![CI](https://github.com/kokhlo/prometheus-ada/actions/workflows/build-test.yml/badge.svg)](https://github.com/kokhlo/prometheus-ada/actions/workflows/build-test.yml)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Prometheus text-format metrics client library for Ada. Zero dependencies, text exposition only (v0.0.4).

## What / Why

Observability-ready services need metrics. This library provides:

- **Counter**, **Gauge**, and **Histogram** metric types
- **Labels** for dimensional metrics
- **Prometheus text exposition format v0.0.4** (the wire format Prometheus scrapes)
- **Deterministic output** (reproducible for testing)
- **Zero dependencies** (only Ada standard library)

## Status

**Text-format client only** — no HTTP server, no OpenMetrics. This is the foundation; an HTTP endpoint will be layered on top (via a simple TCP listener or integration with an Ada web framework).

As of 2026-08-29, `alr search prometheus` returns zero hits. This is the first Prometheus client library published for Ada.

## Installation

With [Alire](https://alire.ada.dev):

```bash
alr with prometheus
```

> **Note:** `prometheus` is available after the alire-index merge
> ([PR](https://github.com/alire-project/alire-index/pull/2099)). Until then, use the repository directly:
> `alr with --use /path/to/prometheus-ada`

## Usage

### Counter

```ada
with Prometheus; use Prometheus;

Reg : Registry_Type;
Cnt : Counter_Access;
Labels : Label_Set;

Labels.Append (Label'(Name => To_Unbounded_String ("method"),
                      Value => To_Unbounded_String ("GET")));
Cnt := Register_Counter (Reg, "http_requests_total",
                         "Total HTTP requests", Labels);
Inc (Cnt.all);  --  Increment by 1.0 (default)
Inc (Cnt.all, 100.0);  --  Custom increment
```

### Gauge

```ada
Gauge := Register_Gauge (Reg, "temperature_celsius", "Current temperature", Empty_Vector);
Set (Gauge.all, 23.5);
Inc (Gauge.all, 2.0);
Dec (Gauge.all, 0.5);
```

### Histogram

```ada
Hist := Register_Histogram (Reg, "request_duration_seconds",
                            "Request duration distribution", Empty_Vector);
--  Default buckets: .005, .01, .025, .05, .075, .1, .25, .5, .75, 1.0, 2.5, 5.0, 7.5, 10.0, +Inf
Observe (Hist.all, 0.123);
Observe (Hist.all, 0.456);
```

### Exposition

```ada
Output : constant String := Collect (Reg);
--  Returns Prometheus text format v0.0.4:
--  # HELP http_requests_total Total HTTP requests
--  # TYPE http_requests_total counter
--  http_requests_total{method="GET"} 1.01000E+02
```

## Design

### Thread safety

Metric types (`Counter_Type`, `Gauge_Type`, `Histogram_Type`) are **limited** records (non-copyable). The registry is also **limited**. This design keeps the API simple: the caller owns concurrency. To instrument a multi-task service, either:

- Share one registry across tasks and wrap metric operations in a protected object, or
- Give each task its own registry and aggregate at collection time.

### Labels

Label sets are vectors of `(name, value)` pairs. The exposition formatter sorts them by name for determinism (Prometheus requires unique `{metric, labels}` combinations, and sorting makes collisions obvious).

### Float formatting

Ada's `Float'Image` outputs scientific notation (`1.02700E+03`). Prometheus accepts this (it's valid per the spec), and it's more compact than decimal for large/small values. If you need decimal-only output, replace `Format_Float` in `prometheus.adb`.

## Roadmap

- [x] Core metric types (Counter, Gauge, Histogram)
- [x] Text exposition format v0.0.4
- [x] Label escaping (backslash, quote, newline)
- [x] HELP escaping
- [x] Validation (metric/label name format)
- [x] Tests (27 checks, all PASS)
- [ ] Publish to alire-index at github.com/kokhlo/prometheus-ada
- [ ] HTTP server integration (simple TCP listener)
- [ ] OpenMetrics format (for native histograms, exemplars)
- [ ] Push gateway client (for batch jobs)

## Testing

```bash
gprbuild -p -P prometheus_ada_tests.gpr
./bin/prometheus-tests
```

Expected: `All tests passed!` (27 checks).

## License

MIT License — see [LICENSE](LICENSE)

## Contributing

PRs welcome. For major changes, open an issue first to discuss the design. Follow Ada Quality and Style Guide conventions.
