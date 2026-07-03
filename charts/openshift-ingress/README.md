# OpenShift Ingress Controller

## openshift-ingress Helm Chart

### Description
The openshift-ingress chart configures a secondary or multiple additional IngressControllers. For each entry in the `ingresscontroller` list, the chart creates:

- A cert-manager `Certificate` (TLS via Let's Encrypt)
- An `IngressController` custom resource
- A `LoadBalancer` `Service` in the `openshift-ingress` namespace

### Values
| Variable Name | Description | Mandatory |
|------|---------|-------|
| `name` | Name of the IngressController | true |
| `scope` | NLB scope: `Internal` or `External` | true |
| `domain` | Domain associated with the IngressController and Route53 record | true |
| `certificateCommonName` | Wildcard FQDN for the cert (e.g. `*.apps.example.com`) | true |

### Cluster configuration
Values are defined per cluster in [helm-gitops-cluster-config](https://github.com/abavage/helm-gitops-cluster-config/blob/main/nonprod/one/infrastructure.yaml):

```
  - chart: openshift-ingress
    namespace: openshift-ingress
    version: 0.0.10
    values:
      ingresscontroller:
        - name: apps
          scope: External
          domain: apps.sandbox1467.opentlc.com
          certificateCommonName: '*.apps.sandbox1467.opentlc.com'
```

Multiple IngressControllers are supported by adding more entries to the list:

```
  - chart: openshift-ingress
    namespace: openshift-ingress
    version: 0.0.10
    values:
      ingresscontroller:
        - name: apps
          scope: Internal
          domain: one.apps.sierra-espresso.net
          certificateCommonName: '*.one.apps.sierra-espresso.net'
        - name: customer
          scope: Internal
          domain: custom.apps.sierra-espresso.net
          certificateCommonName: '*.custom.apps.sierra-espresso.net'
```

### How values are passed
The chart accepts values from two sources:

1. **Argo CD (production)** — the app-of-apps chart passes only the `values` block for this chart, so Helm receives `.Values.ingresscontroller` directly.
2. **Local testing** — pass the full cluster `infrastructure.yaml` file. The templates locate the `openshift-ingress` entry and use its `values.ingresscontroller` list.

### Prerequisites
- cert-manager operator installed (e.g. via the `certificate-manager` chart)
- A `ClusterIssuer` named `letsencrypt-production` available in the cluster

## IngressController and NLB integration
When a new IngressController is defined, the operator automatically provisions the necessary networking stack to expose the traffic.

**Provisioning workflow**

1. **Service creation** — a `LoadBalancer` Service is created in the `openshift-ingress` namespace.
2. **Cloud integration** — OpenShift triggers the AWS cloud provider to provision a Network Load Balancer (NLB).
3. **Connectivity** — the NLB is configured with listeners (80/443) and target groups pointing at the Ingress Controller pods.

Track status with:

* `oc get svc -n openshift-ingress`
* `oc get pods -n openshift-ingress`

## Required steps after creation

Two additional steps are required after additional IngressControllers are added.

### Patch the default IngressController
The `default` IngressController accepts all routes unless configured otherwise, which is not desirable with multiple IngressControllers on a cluster.

When an additional IngressController is added, `default` (`oc get ingresscontroller default -n openshift-ingress-operator`) must be patched to deny routes destined for the new controller.

**Example** — adding an IngressController named `customer`:

```
$ oc patch ingresscontroller default -n openshift-ingress-operator --type='merge' -p ' {"spec": {"namespaceSelector": {"matchExpressions": [{ "key": "ingress", "operator": "NotIn", "values": ["'customer'"]}]}}}'

$ oc get ingresscontroller default -n openshift-ingress-operator -o json | jq '.spec.namespaceSelector'

{
  "matchExpressions": [
    {
      "key": "ingress",
      "operator": "NotIn",
      "values": [
        "customer"
      ]
    }
  ]
}
```

```
# Patch default with an additional controller
oc patch ingresscontrollers default -n openshift-ingress-operator --type='json' -p'[{"op":"add", "path":"/spec/namespaceSelector/matchExpressions/-", "value": {"key": "ingress", "operator": "NotIn", "values": ["apps1"] }}]'
```

### Add namespace label
Each IngressController is configured with a `namespaceSelector`. Routes in namespaces with a matching label are served by that controller.

```
  namespaceSelector:
    matchLabels:
      ingress: customer
```

Label namespaces that should use the `customer` IngressController:

```
$ oc label namespace customer-api ingress=customer
```

### Test templates locally

**Option 1 — full cluster infrastructure file** (matches how values are stored in git):

```
helm template . -f ~/git/helm-gitops-cluster-config/nonprod/one/infrastructure.yaml
```

**Option 2 — chart values only** (matches how Argo CD passes values):

```
$ cat <<EOF > extra-values.yaml
ingresscontroller:
  - name: apps
    scope: External
    domain: thisandthat.int
    certificateCommonName: '*.thisandthat.int'
EOF

helm template . -f extra-values.yaml
```

Or via `--set`:

```
helm template local-test . \
  --set 'ingresscontroller[0].name=apps' \
  --set 'ingresscontroller[0].scope=Internal' \
  --set 'ingresscontroller[0].domain=one.apps.example.com' \
  --set 'ingresscontroller[0].certificateCommonName=*.one.apps.example.com'
```

### Linting
Linting uses the same values as templating:

```
helm lint . -f ~/git/helm-gitops-cluster-config/nonprod/one/infrastructure.yaml
```

```
helm lint . \
  --set 'ingresscontroller[0].name=apps' \
  --set 'ingresscontroller[0].scope=Internal' \
  --set 'ingresscontroller[0].domain=one.apps.example.com' \
  --set 'ingresscontroller[0].certificateCommonName=*.one.apps.example.com'
```
