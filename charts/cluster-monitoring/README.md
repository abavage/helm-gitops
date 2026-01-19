### Alertmanager

```
$ oc -n openshift-user-workload-monitoring rsh alertmanager-user-workload-0 

# list alerts
sh-5.1$ amtool  alert  query --alertmanager.url  http://127.0.0.1:9093
Alertname                                  Starts At                Summary                                                                                  State
Watchdog                                   2026-01-18 23:35:11 UTC  An alert that should always be firing to certify that Alertmanager is working properly.  active

# silence alerts
sh-5.1$ amtool silence add alertname=Watchdog --duration=1h --comment="testa" --author="abavage@redhat.com" --alertmanager.url  http://127.0.0.1:9093
7ac4bb95-69e5-48ca-821c-bde56a888b4b

# query silenced alerts
sh-5.1$ amtool silence query --alertmanager.url  http://127.0.0.1:9093
ID                                    Matchers              Ends At                  Created By          Comment
7ac4bb95-69e5-48ca-821c-bde56a888b4b  alertname="Watchdog"  2026-01-19 03:26:20 UTC  abavage@redhat.com  testa

# expire silences
sh-5.1$ amtool silence expire 7ac4bb95-69e5-48ca-821c-bde56a888b4b --alertmanager.url  http://127.0.0.1:9093

# list silences
sh-5.1$ amtool silence query --alertmanager.url  http://127.0.0.1:9093
ID  Matchers  Ends At  Created By  Comment

```

```
$ helm template . --set roleArn=arn:aws:iam::281359555390:role/one-rosa-monitoring-sns-role --set snsRoleArn=arn:aws:sns:ap-southeast-2:281359555390:one-rosa-monitoring-sns-topic --set region=ap-southeast-2
```
