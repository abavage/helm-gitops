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

### Database Pre Steps
For the checkpoint to work the superuser role needs to added to the  user of the database in the connect string.

```
sh-4.4$ psql -U postgres
ALTER USER andrew WITH SUPERUSER;
\du+
```

```
postgres=# \du+
                                          List of roles
 Role name |                         Attributes                         | Member of | Description
-----------+------------------------------------------------------------+-----------+-------------
 admin     | Superuser                                                  | {}        |
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS | {}        |
 ```

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
    # $(oc get backupstoragelocations -n openshift-adp)
    storageLocation: one-aap-1
    # 30 days retention
    ttl: 720h0m0s
```

`oc apply -f aap-backup-schedule.yaml`

`aap-backup-schedule-hook.yaml`
```
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: aap-backup-schedule-hook
  namespace: openshift-adp
spec:
  includedNamespaces:
  - aap
  includedResources:
  - deployment
  - persistentvolumes
  - persistentvolumeclaims
  - secrets
  # pods is mandatory for the hook to work
  - pods
  storageLocation: one-aap-1
  ttl: 720h0m0s
  hooks:
    resources:
      - name: app-postgresql-hook
        includedNamespaces:
        - aap
        includedResources:
        - pods
        labelSelector:
          matchLabels:
            app: postgresql
        pre:
          - exec:
              container: postgresql
              command:
                - /bin/bash
                - -c
                - |
                  psql -h 127.0.0.1 -p 5432 -U admin -d sampledb -c CHECKPOINT | tee /var/lib/pgsql/data/checkpoint-$(date "+%Y-%m-%d-%H-%u-%S")
              onError: Fail
              timeout: 1m
```
`oc apply -f ap-backup-schedule-hook.yaml`





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
aap-backup-schedule-hook   Completed   0        0          2025-09-11 14:37:03 +1000 AEST   29d       one-aap-1          <none>
```

```
$ velero describe backup aap-backup-schedule-hook -n openshift-adp

```
Name:         aap-backup-schedule-hook
Namespace:    openshift-adp
Labels:       velero.io/storage-location=one-aap-1
Annotations:  kubectl.kubernetes.io/last-applied-configuration={"apiVersion":"velero.io/v1","kind":"Backup","metadata":{"annotations":{},"name":"aap-backup-schedule-hook","namespace":"openshift-adp"},"spec":{"hooks":{"resources":[{"includedNamespaces":["andrew"],"includedResources":["pods"],"labelSelector":{"matchLabels":{"app":"ab-postgresql"}},"name":"pg-checkpoint-hook","pre":[{"exec":{"command":["/bin/bash","-c","psql -h 127.0.0.1 -p 5432 -U admin -d sampledb -c CHECKPOINT | tee /var/lib/pgsql/data/checkpoint-$(date \"+%Y-%m-%d-%H:%M:%S\")\n"],"container":"postgresql","onError":"Fail","timeout":"1m"}}]}]},"includedNamespaces":["andrew"],"includedResources":["deployment","persistentvolumes","persistentvolumeclaims","secrets","pods"],"storageLocation":"one-aap-1","ttl":"1h"}}

  velero.io/resource-timeout=10m0s
  velero.io/source-cluster-k8s-gitversion=v1.32.6
  velero.io/source-cluster-k8s-major-version=1
  velero.io/source-cluster-k8s-minor-version=32

Phase:  Completed


Namespaces:
  Included:  aap
  Excluded:  <none>

Resources:
  Included:        deployment, persistentvolumes, persistentvolumeclaims, secrets, pods
  Excluded:        <none>
  Cluster-scoped:  auto

Label selector:  <none>

Or label selector:  <none>

Storage Location:  one-aap-1

Velero-Native Snapshot PVs:    auto
File System Backup (Default):  false
Snapshot Move Data:            false
Data Mover:                    velero

TTL:  1h0m0s

CSISnapshotTimeout:    10m0s
ItemOperationTimeout:  4h0m0s

Hooks:
  Resources:
    pg-checkpoint-hook:
      Namespaces:
        Included:  andrew
        Excluded:  <none>

      Resources:
        Included:  pods
        Excluded:  <none>

      Label selector:  app=ab-postgresql

      Pre Exec Hook:
        Container:  postgresql
        Command:    /bin/bash -c psql -h 127.0.0.1 -p 5432 -U admin -d sampledb -c CHECKPOINT | tee /var/lib/pgsql/data/checkpoint-$(date "+%Y-%m-%d-%H:%M:%S")

        On Error:  Fail
        Timeout:   1m0s

Backup Format Version:  1.1.0

Started:    2025-09-12 13:22:51 +1000 AEST
Completed:  2025-09-12 13:23:57 +1000 AEST

Expiration:  2025-09-12 14:22:51 +1000 AEST

Total items to be backed up:  11
Items backed up:              11

Backup Item Operations:  1 of 1 completed successfully, 0 failed (specify --details for more information)
Backup Volumes:
  Velero-Native Snapshots: <none included>

  CSI Snapshots:
    andrew/postgresql:
      Snapshot: included, specify --details for more information

  Pod Volume Backups: <none included>

HooksAttempted:  1
HooksFailed:     0



```
$ velero backup logs aap-backup-schedule-hook -n openshift-adp | wc
  855   10538  217930
```

### Locate & Create an EBS volume from the snapshot
The 

```
$ aws ec2 describe-snapshots \
  --owner-ids self \
  --query "Snapshots | sort_by(@, &StartTime) | reverse(@)[].{ID:SnapshotId, Volume:VolumeId, Created:StartTime, State:State, Size:VolumeSize}" \
  --output table \
  --region ap-southeast-4
  ```

```
--------------------------------------------------------------------------------------------------------------
|                                              DescribeSnapshots                                             |
+-----------------------------------+-------------------------+-------+------------+-------------------------+
|              Created              |           ID            | Size  |   State    |         Volume          |
+-----------------------------------+-------------------------+-------+------------+-------------------------+
|  2025-09-11T04:37:05.236000+00:00 |  snap-0cc0cac4950983b5b |  2    |  completed |  vol-05d8ee55d2850c8eb  |
|  2025-09-10T23:02:55.580000+00:00 |  snap-0732cdca8dd99e284 |  1    |  completed |  vol-059b4c70911e774cb  |
|  2025-09-10T05:45:35.882000+00:00 |  snap-08dbe37efb55bd37b |  1    |  completed |  vol-0409e82a915feab64  |
|  2025-09-10T05:20:51.387000+00:00 |  snap-096f552c230287036 |  1    |  completed |  vol-088df938cd450afcc  |
|  2025-09-10T02:12:02.954000+00:00 |  snap-035842e0f53d98f04 |  1    |  completed |  vol-07b114512d78ecfa1  |
|  2025-09-09T05:55:38.979000+00:00 |  snap-0960b94f07976656a |  1    |  completed |  vol-04b8426b0ee1aca31  |
|  2025-09-09T05:45:27.759000+00:00 |  snap-02c1bf5a83179a4d6 |  1    |  completed |  vol-04b8426b0ee1aca31  |
+-----------------------------------+-------------------------+-------+------------+-------------------------+
```


Create the volume from the snap
Extremely important to add the tag `red-hat-managed: true` wtithout this tag the following steos will fail.

```
$ aws ec2 create-volume \
  --snapshot-id snap-0cc0cac4950983b5b \
  --availability-zone ap-southeast-4b \
  --volume-type gp3 \
  --size 2 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=red-hat-managed,Value=true}]' \
  --region ap-southeast-2
  ```

  ```
$ aws ec2 describe-volumes \
  --volume-ids vol-0a4da5278992f850c \
  --region ap-southeast-4 \
--output table
```

```
--------------------------------------------------------------------------------------------------------------
|                                               DescribeVolumes                                              |
+------------------------------------------------------------------------------------------------------------+
||                                                  Volumes                                                 ||
|+--------------------+-------------------------------------------------------------------------------------+|
||  AvailabilityZone  |  ap-southeast-2b                                                                    ||
||  CreateTime        |  2025-09-11T06:24:55.690000+00:00                                                   ||
||  Encrypted         |  True                                                                               ||
||  Iops              |  3000                                                                               ||
||  KmsKeyId          |  arn:aws:kms:ap-southeast-2:913524947756:key/a87b2f47-41be-44b8-a475-08787267b4c4   ||
||  MultiAttachEnabled|  False                                                                              ||
||  Size              |  2                                                                                  ||
||  SnapshotId        |  snap-0cc0cac4950983b5b                                                             ||
||  State             |  available                                                                          ||
||  Throughput        |  125                                                                                ||
||  VolumeId          |  vol-0a4da5278992f850c                                                              ||
||  VolumeType        |  gp3                                                                                ||
|+--------------------+-------------------------------------------------------------------------------------+|
|||                                                Operator                                                |||
||+--------------------------------------------------------+-----------------------------------------------+||
|||  Managed                                               |  False                                        |||
||+--------------------------------------------------------+-----------------------------------------------+||
|||                                                  Tags                                                  |||
||+--------------------------------+-----------------------------------------------------------------------+||
|||  Key                           |  red-hat-managed                                                      |||
|||  Value                         |  true                                                                 |||
||+--------------------------------+-----------------------------------------------------------------------+||
```


### Create the persistentvolume from the EBS volume 

`persistentvolume-ap-southeast-4b.yaml`
```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgresql-0
spec:
  accessModes:
  - ReadWriteOnce
  capacity:
    storage: 2Gi
  csi:
    driver: ebs.csi.aws.com
    fsType: ext4
    volumeHandle: vol-0a4da5278992f850c
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: topology.kubernetes.io/zone
          operator: In
          values:
          - ap-southeast-4b
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gp3-csi
  volumeMode: Filesystem

```

` oc apply -f persistentvolume-ap-southeast-4b.yaml`


### Create the persistentvolumeclaim from the persistentvolume

`persistentvolumeclaim-postgresql.yaml`
```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql
  namespace: aap
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: gp3-csi
  volumeName: postgresql-0
```

`oc apply -f persistentvolumeclaim-postgresql.yaml`