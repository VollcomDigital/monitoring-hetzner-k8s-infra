# Loki Log Shipping Notes

- Promtail pushes logs to `/loki/api/v1/push`.
- Every log stream should include `cluster`, `env`, `namespace`, and `service` labels.
- JSON logs are recommended to support structured parsing in Grafana Explore.
