# OpenShift Ingress Controller

## openshift-ingress Helm Chart

### Description
The openshift-ingress chart will configue a secondary or many additonal ingressControllers. It acceptes five (5) mandatory variables as a list which will configure the ingressController and the secret containing certificate. 

### Values
| Variable Name | Description | Mandatory |
|------|---------|-------|
|name| Name of the ingressController| true |
|scope| NLB Internal or External facing | true |
|domain| Domain name to be associated with the ingressController and route53 record | true |
|tls_crt| base64 encoded string (single line) with the server certificate and intermediate certificate | true |
|tls_key| base64 encoded string (single line) with the private key | true |

### Building a single new ingressController
The helm chart values are passed in via the cluser specific  [awsvicgovprd01-rosa-helm-config](https://github.com/VG-CTX-StorageUnixServices/awsvicgovprd01-rosa-helm-config/blob/main/prod/rosaprd01/infrastructure.yaml) infrastructure file. 

```
  - chart: openshift-ingress
    namespace:
    values:
      ingresscontroller:
        - name: apps
          scope: Internal
          domain: rosaprd01.apps.internal.cenitex
          tls_crt: b64-encoded
          tls_key: b64-encoded
```

### Adding additional ingressController
The helm chart values are passed in via the cluser specific  [awsvicgovprd01-rosa-helm-config](https://github.com/VG-CTX-StorageUnixServices/awsvicgovprd01-rosa-helm-config/blob/main/prod/rosaprd01/infrastructure.yaml) infrastructure file. The chart will accept a list and loop through and create the required objects. 

```
  - chart: openshift-ingress
    namespace:
    values:
      ingresscontroller:
        - name: apps
          scope: Internal
          domain: rosaprd01.apps.internal.cenitex
          tls_crt: b64-encoded
          tls_key: b64-encoded
        - name: customer
          scope: Internal
          domain: rosaprd01.apps.internal.customer
          tls_crt: b64-encoded
          tls_key: b64-encoded
```

## Required Steps After Creation

Two additional steps are required after additonal ingressController are added.

### Patch the default ingressController
The `default` ingressController will accept all routes unless otherwise configured which is not desirable with multiple ingressControllers on a cluster. 

When an additional ingressController is added to the cluster, the `default` ingressController `(oc get ingresscontroller default -n openshift-ingress-operator)` needs to be configured to deny any route that is destined for the `new` ingressContoller. 

### Example
Adding a new ingressContoller named `customer`. Run the following command which will patch default ingressController to deny any routes destined for the `customer` ingressController.

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

### Add namespace label
When an ingressController is added, it is configured with a `namespaceSelector`. Where every route in the matching namespace name will be added to the `new` ingressContoller. This is acheived via a label on the namespace. Having this label takes away administrative overhead for users.

### Example
The new ingressController has the following namespaceSelector. 

```
  namespaceSelector:
    matchLabels:
      ingress: customer
```
For projects/namespaces requiring the route to be accepted onto the `customer` ingressController add the following.
```
$ oc label namespace customer-api ingress=customer
```


      
