# Creating an OADP backup 

The intention is to backup the postreqsql database used by AAP in the event of an AZ outage. The database will be restored in a functional AZ where all operations can continue.

 OADP (velero) can backup the entire namespace or a select list of objects. The desired state is to only backup the `persistentvolume(s)` used by AAP. All other components in the aap namespace will be managed by configuration in git and applied by argo. 
 
 When the backup is initiated it will backup the `persistentvolume` ojbect as yaml (`oc get pv <pv_name> -o yaml`) and create an EBS snapshot of the source volume. The backup is stored in an S3 bucket as defined in the `CloudStorage` ojbect.

Due to limitations in oadp, persistentvolumes can't be restored into other AZ's. 

*example: If the source persistentvolumes was created in ap-southeast-4a it can't be restore into ap-southeast-4b.*

A vailid work around is available to resolve the limitation.

## Assumptions
The source persistentvolume was created in ap-southeast-4a and will be restored in ap-southeast-4b.

## High Level Steps

1. Create a new volume from the EBS snapshot OADP created in ap-southeast-4b.
2. Create a persistentvolume using the EBS volume ID produced in (1).
3. Create a persistentvolumeclaim using the persistentvolume name defined in (2). Reuse the same persistentvolumeclaim name.
4. Scale up the postgresql database deployment or statefulset.
5. Review the pod logs for errors. 

## Low Level Steps

### Initiate the backup
OADP backup can be initiated via one off backup job or schedule. 
The following example will be via a schedule.

`aap-backup-schedule.yaml`
```apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: aap-backup
  namespace: openshift-adp
spec:
  schedule: "* 4 * * *"
  template:
    hooks: {}
    includedNamespaces:
    - aap
     includedResources:
    - persistentvolumes
    - persistentvolumeclaims
    # oc get backupstoragelocations -n openshift-adp
    storageLocation: one-aap-1
    # 30 days retention
    ttl: 720h0m0s
```

`oc apply -f aap-backup-schedule.yaml`

The schedule will: 
1. Run every four (4) hours
2. Target the namespace `aap`
3. Backup persistentvolumeclaims as a yaml file
4. Backup persistentvolumes assocated with persistentvolumeclaims as yaml files.
5. The backup will create a tar archive with all the yamls files and metadata and be uploaded into `CloudStorage` bucket.
6. Create an EBS snapshot of the EBS volumes associated with the persistentvolumes.

Backups as be listed and reviewed using the `oc` command or preferably the `velero` binary. The `velero` binary is is far more feature rich than the `oc` command.

```
$ velero get backup -n openshift-adp
NAME                STATUS      ERRORS   WARNINGS   CREATED                          EXPIRES   STORAGE LOCATION   SELECTOR
test-postgresql-5   Completed   0        0          2025-09-11 14:37:03 +1000 AEST   29d       one-aap-1          <none>
```

```
$ velero describe backup test-postgresql-5 -n openshift-adp
Name:         test-postgresql-5
Namespace:    openshift-adp
Labels:       velero.io/storage-location=one-aap-1
Annotations:  kubectl.kubernetes.io/last-applied-configuration={"apiVersion":"velero.io/v1","kind":"Backup","metadata":{"annotations":{},"name":"test-postgresql-5","namespace":"openshift-adp"},"spec":{"includedNamespaces":["andrew"],"includedResources":["deployment","persistentvolumes","persistentvolumeclaims","secrets"],"storageLocation":"one-aap-1","ttl":"720h0m0s"}}

  velero.io/resource-timeout=10m0s
  velero.io/source-cluster-k8s-gitversion=v1.32.6
  velero.io/source-cluster-k8s-major-version=1
  velero.io/source-cluster-k8s-minor-version=32

Phase:  Completed


Namespaces:
  Included:  andrew
  Excluded:  <none>

Resources:
  Included:        deployment, persistentvolumes, persistentvolumeclaims, secrets
  Excluded:        <none>
  Cluster-scoped:  auto

Label selector:  <none>

Or label selector:  <none>

Storage Location:  one-aap-1

Velero-Native Snapshot PVs:    auto
File System Backup (Default):  false
Snapshot Move Data:            false
Data Mover:                    velero

TTL:  720h0m0s

CSISnapshotTimeout:    10m0s
ItemOperationTimeout:  4h0m0s

Hooks:  <none>

Backup Format Version:  1.1.0

Started:    2025-09-11 14:37:03 +1000 AEST
Completed:  2025-09-11 14:38:06 +1000 AEST

Expiration:  2025-10-11 14:37:03 +1000 AEST

Total items to be backed up:  10
Items backed up:              10

Backup Item Operations:  1 of 1 completed successfully, 0 failed (specify --details for more information)
Backup Volumes:
  Velero-Native Snapshots: <none included>

  CSI Snapshots:
    andrew/postgresql:
      Snapshot: included, specify --details for more information

  Pod Volume Backups: <none included>

HooksAttempted:  0
HooksFailed:     0
```

```
$ velero backup logs test-postgresql-5 -n openshift-adp | wc
  855   10538  217930
```

