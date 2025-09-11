# Turtles integration suite example

This repository contains an example of how to verify the Rancher Turtles integration of CAPI providers. At the moment we only require one test that uses a GitOps flow.

For more information about the Rancher Turtles test framework and how to use it, please follow the instructions in the [Rancher Turtles repository](https://github.com/rancher/turtles/tree/main/test/e2e#e2e-tests).

This is a simplified example on how to consume the test framework, to validate Cluster provisioning and import into Rancher.

Running this suite for a CAPI provider will:

1. Download all required tools, like `ginkgo`, `helm`, and more.
1. Create a managment cluster in the desired environment type.
1. Install Rancher and Turtles with all prerequisites.
1. Install additional CAPIProviders.
1. Apply a CAPI Cluster template to provision a new Cluster.
1. Verify that the CAPI Cluster is initialized correctly.
1. Verify that the CAPI Cluster has been successfully imported in Rancher.
1. Verify that the CAPI Cluster can be deleted correctly.

## Prerequisites

- docker
- kind

## Run this example

To run the suite, execute the following command:

```bash
make test-e2e
```

## Management Cluster types

`MANAGEMENT_CLUSTER_ENVIRONMENT` environment variable supports the following values:

- `isolated-kind` (Default)  
    Provision a local, isolated, management Cluster using kind.
- `kind`  
    Provision a local management Cluster using kind. `ngrok-operator` is also deployed to provide external connectivity to Rancher.  
    Note this requires `NGROK_AUTHTOKEN`, `NGROK_API_KEY`, and `RANCHER_HOSTNAME` to be set.
- `eks`  
    Provision a EKS Cluster.
    Note this requires `eksctl` to be installed.

## Artifacts Collection

Test artifacts will be collected in the `ARTIFACTS_FOLDER`, by default `_artifacts`.  
[crust-gather](https://github.com/crust-gather/crust-gather) is used to collect all events and logs.  

## Troubleshooting

- Can't find `github.com/rancher/turtles v0.0.0-00010101000000-000000000000` dependency.

    Import `turtles` directly in your `go.mod`:

    ```txt
    require (
        github.com/rancher/turtles v0.24.0-rc.0
        github.com/rancher/turtles/test v0.24.0-rc.0
    )
    ```

- Skip test environment cleanup.

    In case of test failures it's useful to debug the environment before it's deleted.  
    You can skip both management cluster and downstream cluster.  
    For more information please read the [documentation](https://github.com/rancher/turtles/tree/main/test/e2e#cluster-and-resource-cleanup).

    ```bash
    SKIP_RESOURCE_CLEANUP=true SKIP_DELETION_TEST=true make test-e2e
    ```

- The Rancher import test validation is failing.

    Failures at the `Waiting for the rancher cluster to have a deployed agent` step, normally indicate that the downstream Cluster has not been initialized correctly. The `cattle-cluster-agent` Pod needs a working cluster, for example with a CNI installed, in order to start. Another common problem is the `RANCHER_HOSTNAME` setup. The `cattle-cluster-agent` may not be able to connect to the configured endpoint, if the Rancher Ingress was not configured correctly, depending on the `MANAGEMENT_CLUSTER_ENVIRONMENT` type.  
