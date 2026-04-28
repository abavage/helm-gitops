# Alermanager.yaml

## Alerting Best Practices
* For the `source_matchers` and `target_matchers` to work correctly make the alertname identical between between critical & warning.



## Break down

```
global:
  http_config:
    proxy_from_environment: true
```

`global`: This tells Alertmanager to look at the environment variables of its container/pod (specifically HTTP_PROXY, HTTPS_PROXY, and NO_PROXY) to determine how to route outbound HTTP traffic.

If the cluster sits behind a corporate firewall and requires a proxy to reach external services (like AWS SNS, PagerDuty, or Slack), this setting ensures Alertmanager automatically uses that proxy without you having to hardcode proxy URLs into every single receiver configuration.


```
- equal:
    - namespace
    - alertname
    source_matchers:
      - severity = critical
    target_matchers:
      - severity =~ warning|info
```
* `source_matchers`: This rule activates if there is an actively firing alert with a label of severity = critical.
* `target_matchers`: If the trigger is active, Alertmanager will suppress any alerts that have a severity of either warning OR info (using the regex =~).
* `equal`: This ensures the rule only applies to alerts related to the exact same issue. For a warning/info alert to be muted by a critical alert, both alerts must have the exact same namespace label and alertname label.


```
- equal:
    - namespace
    - alertname
  source_matchers:
    - severity = warning
  target_matchers:
    - severity = info
```
* `source_matchers`: This rule activates if there is an actively firing alert with a label of severity = warning.
* `target_matchers`: If the trigger is active, Alertmanager will suppress any alerts that have a severity of info.
* `equal`: This ensures the rule only applies to alerts related to the exact same issue. For a info alert to be muted by a warning alert, both alerts must have the exact same namespace label and alertname label.

