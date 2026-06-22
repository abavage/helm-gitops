# Overprovisioning

Helm chart that reserves cluster capacity by scheduling low-priority placeholder pods. When higher-priority workloads need resources, the scheduler evicts these pods first, reducing the time required to scale up real applications.

The chart deploys:

- **`overprovisioning` namespace** — dedicated namespace for placeholder workloads
- **`PriorityClass`** — priority value `-1`, so these pods are preempted before normal workloads
- **`Deployment`** — pods that run `sleep infinity` using the Red Hat `ose-tools-rhel9` image, sized via configurable resource requests

Resources are installed into the `overprovisioning` namespace.

## Required Parameters

The following values **must** be provided via `infrastructure.yaml`. Defaults in `values.yaml` are intentionally empty; the chart will not render correctly without cluster-specific sizing.

| Parameter | Description | Mandatory |
|-----------|-------------|-----------|
| `replicas` | Number of placeholder pods to run across the cluster | true |
| `resources.requests.cpu` | CPU request per pod (for example, `500m`) | true |
| `resources.requests.memory` | Memory request per pod (for example, `512Mi`) | true |

### Example `infrastructure.yaml` entry

```yaml
  - chart: overprovisioning
    namespace: overprovisioning
    version: 0.0.1
    values:
      replicas: 3
      resources:
        requests:
          cpu: 500m
          memory: 512Mi
```

### How required parameters are used

- **`replicas`** — Sets the Deployment replica count. Increase this to reserve capacity on more nodes; each replica consumes the configured resource requests on whichever node it is scheduled.
- **`resources.requests.cpu`** — CPU reserved per placeholder pod. The scheduler uses this to place pods and to hold capacity that real workloads can claim when these pods are evicted.
- **`resources.requests.memory`** — Memory reserved per placeholder pod, with the same effect as CPU requests for capacity planning.

Total reserved capacity is approximately `replicas × (cpu request + memory request)` per cluster, subject to node availability and scheduling constraints.

## Chart-managed values

The following values are defined in the chart's `values.yaml` and are not expected to be overridden via `infrastructure.yaml`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `image` | `registry.redhat.io/openshift4/ose-tools-rhel9:v4.16.0-...` | Container image for placeholder pods |

Resource limits are not configured; only requests are set so the pods reserve scheduling capacity without imposing hard consumption caps.

## Verification

After sync, confirm the resources are healthy:

```bash
oc get namespace overprovisioning
oc get priorityclass overprovisioning
oc get deployment,pods -n overprovisioning
```

Pods should be `Running` with the `overprovisioning` priority class. When cluster load increases, expect these pods to be evicted before application workloads.

## Local testing

```bash
helm template overprovisioning charts/overprovisioning \
  --set replicas=2 \
  --set resources.requests.cpu=500m \
  --set resources.requests.memory=512Mi
```
