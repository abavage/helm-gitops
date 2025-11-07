# ROSA HCP Helm Charts
## Overview
This repository contains the Helm charts used to bootstrap Red Hat OpenShift Service on AWS (ROSA) Hosted Control Plane (HCP) clusters.

These charts are responsible for deploying and configuring all core cluster services and Operators required for a production-ready environment.

## Bootstrap Process & Architecture
The bootstrapping of a cluster follows a specific GitOps-driven workflow, orchestrated by Terraform and managed by ArgoCD (OpenShift GitOps) on the ROSA cluster.

### The end-to-end flow is as follows:

All configuration is passed dynamically: Terraform variables (like cluster region, AWS account, etc.) are fed into the gitops-bootstrap.tf file, which then injects them as arguments or environment variables for the gitops-bootstrap.sh script to use.

* `Terraform Initiation:` Terraform process begins the bootstrap of the cluster.

* `Script Execution:` Terraform executes a shell script that installs one critical Helm chart on the cluster: [gitops-operator-bootstrap](https://github.com/VG-CTX-StorageUnixServices/awsvicgovprd01-rosa-helm/tree/main/charts/gitops-operator-bootstrap). The script is executed by the [Scott Winkler Shell Provider](https://registry.terraform.io/providers/scottwinkler/shell/latest/docs/resources/shell_script_resource)

* `Script Executed:` This step acts as the bridge between the Terraform plan and the on-cluster Helm installation.

   * [gitops-bootstrap.tf](https://github.com/VG-CTX-StorageUnixServices/awsvicgovprd01-rosa-terraform/blob/main/gitops-bootstrap.tf): This Terraform file defines a shell_script resource using the external scottaw/shell provider (by Scott Winkler). Its job is to execute the local bootstrap script.

   * [gitops-bootstrap.sh](https://github.com/VG-CTX-StorageUnixServices/awsvicgovprd01-rosa-terraform/blob/main/scripts/gitops-bootstrap.sh): This is the shell script executed by the provider. It is responsible for running the helm commands that apply the gitops-operator-bootstrap chart to the target cluster.

* `ArgoCD Instantiation:` The [gitops-operator-bootstrap](https://github.com/VG-CTX-StorageUnixServices/awsvicgovprd01-rosa-helm/tree/main/charts/gitops-operator-bootstrap) chart's primary job is to deploy the OpenShift GitOps Operator and create the central ArgoCD instance.

* `App of Apps Deployment:` The gitops-operator-bootstrap chart then applies the root "App of Apps" application to ArgoCD.

* `Cluster Configuration:` This "App of Apps" instructs ArgoCD to synchronize and deploy all other core Operators and their supporting configurations, completing the cluster build-out.

## Core Design: Multi-Source GitOps
The `"App of Apps"` framework is configured using ArgoCD's multi-source application feature. This is a critical design choice that separates the "what" from the "where" and "how."

This pattern separates the version-controlled application logic (the Helm charts) from the cluster-specific configuration (the values):

* All chelm chart variables are sourced from the [rosa-helm-config git repository](https://github.com/VG-CTX-StorageUnixServices/awsvicgovprd01-rosa-helm-config/tree/main) where clusters are seperated by regions and name.
    * eg prod/rosaprd01

* Chart Source (This Repo): Contains the "master" Helm charts. These are templates intended to be identical across all clusters.

* [rosa-helm-config git repository](https://github.com/VG-CTX-StorageUnixServices/awsvicgovprd01-rosa-helm-config/tree/main): Contains the `prod/rosaprd01/infrastructure.yaml` overrides for each specific cluster.

### Benefits of this Pattern
This separation provides significant flexibility and maintainability:

* Consistency: All clusters consume the exact base Helm charts, ensuring a consistent footprint.

* Targeted Customization: Cluster-specific variables (such as AWS account IDs, regions, or desired Operator versions) are managed entirely in their own Git repositories.

* Maintainability: You can deploy different Operator versions or modify configurations for a single cluster by updating its values file without ever touching the source Helm charts. This prevents chart drift and simplifies upgrades.

### Helm Chart Design
The Helm charts in this repository are intentionally lightweight. They contain minimal default variables in their values.yaml files. The vast majority of configuration is designed to be passed in from the separate, cluster-specific values repositories during the ArgoCD sync process.