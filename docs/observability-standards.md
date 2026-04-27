# Observability Standards

## Metrics Naming

- Use Prometheus metric naming conventions: `snake_case` with base unit suffixes.
- Prefix custom metrics by domain, for example `app_http_requests_total`.
- Use counters for monotonic events (`_total`), gauges for current state, histograms for latency.

## Required Labels

Every custom metric and every shipped log stream must include:

- `cluster`
- `env`
- `namespace`
- `service`

These labels are mandatory to support cross-cluster filtering in Grafana.

## Logging Format

- Application logs must be JSON formatted.
- JSON payload should include `timestamp`, `level`, `message`, `service`, `namespace`, and `cluster`.
- Avoid multiline logs unless stack traces are required.

Example:

```json
{
  "timestamp": "2026-04-27T09:30:25Z",
  "level": "error",
  "message": "database timeout",
  "service": "payments-api",
  "namespace": "payments",
  "cluster": "prod-eu1",
  "trace_id": "abc123"
}
```

## Alert Severity

- `info`: Informational conditions, no immediate action required.
- `warning`: Degraded behavior that needs triage.
- `critical`: User-impacting or platform-risk condition that requires immediate action.

## Example Alerts

- `TargetDown` (`warning`): Scrape target unavailable for more than 5 minutes.
- `PodCrashLooping` (`warning`): Pod restarts exceed safe threshold.
- `NodeHighCpuUsage` (`critical`): Node CPU saturation above 90%.
