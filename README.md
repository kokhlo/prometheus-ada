# prometheus-ada

[![CI](https://github.com/kokhlo/prometheus-ada/actions/workflows/build-test.yml/badge.svg)](https://github.com/kokhlo/prometheus-ada/actions/workflows/build-test.yml)
[![alire](https://img.shields.io/endpoint?url=https://alire.ada.dev/badges/prometheus.json)](https://alire.ada.dev/crates/prometheus.html)
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

Available in the Alire index — the first Prometheus client library published for Ada:

```bash
alr with prometheus
```

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
--  http_requests_total{method="GET"} 101
```

## Design

### Thread safety

Metric types (`Counter_Type`, `Gauge_Type`, `Histogram_Type`) are **limited** records (non-copyable). The registry is also **limited**. This design keeps the API simple: the caller owns concurrency. To instrument a multi-task service, either:

- Share one registry across tasks and wrap metric operations in a protected object, or
- Give each task its own registry and aggregate at collection time.

### Labels

Label sets are vectors of `(name, value)` pairs. Registration validates each label name (`[a-zA-Z_][a-zA-Z0-9_]*`, ASCII only) and rejects duplicates; the set is sorted by name so exposition output is deterministic.

### Float formatting

Values are rendered as plain decimals (`1027`, `0.05`, `-0.15`) rather than
Ada's native scientific notation (`1.02700E+03`). Non-finite values use the
spec tokens `NaN`, `+Inf`, `-Inf`.

## Roadmap

- [x] Core metric types (Counter, Gauge, Histogram)
- [x] Text exposition format v0.0.4
- [x] Label escaping (backslash, quote, newline)
- [x] HELP escaping
- [x] Validation (metric/label name format)
- [x] Tests (74 checks, all PASS)
- [x] Publish to alire-index (`alr with prometheus`)
- [ ] HTTP server integration (simple TCP listener)
- [ ] OpenMetrics format (for native histograms, exemplars)
- [ ] Push gateway client (for batch jobs)

## Testing

```bash
gprbuild -p -P prometheus_tests.gpr
./bin/prometheus-tests
```

Expected: `All tests passed!` (74 checks).

## License

MIT License — see [LICENSE](LICENSE)

## Contributing

PRs welcome. For major changes, open an issue first to discuss the design. Follow Ada Quality and Style Guide conventions.
