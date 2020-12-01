# Cluster preparation

In this step of the tutorial we are going to stand up the clusters and configure
them with a global load balancer and a network tunnel.  This step has the
following prerequisites:

1. A running OCP cluster deployed in AWS
   - This cluster will be the control cluster
   - You need to be logged in to it as an administrator (the `kubeadmin` account will work)
1. Valid AWS credentials
1. Sufficient quota to deploy on the AWS regions you intend to use
   - Control cluster: 3 m4.xlarge, 6 m4.large (9 VMs)
   - Each regional cluster: 3 c5d.4xlarge, 3 m5.xlarge, 1 m5n.xlarge, 3 m5.large (10 VMs)
1. An SSH key (e.g. `ssh-keygen -b 2048 -t rsa -f ~/.ssh/ocp_rsa -q -N ""`)
1. A [OCP pull secret](https://cloud.redhat.com/openshift/install/pull-secret)
   - We'll assume you've downloaded the pull secret to `~/pullsecret.json`

## Deploy RHACM

[Red Hat Advanced Cluster Management](https://www.redhat.com/en/technologies/management/advanced-cluster-management)
allows, among other things, declarative cluster lifecycle management.

```shell
oc new-project open-cluster-management
oc apply -f ./acm/operator.yaml -n open-cluster-management
oc apply -f ./acm/acm.yaml -n open-cluster-management
```

RHACM requires significant resources. Check that the RHACM pods are not stuck in `container creating`.
Wait until all pods are started successfully.

## Create three managed clusters

Prepare some variables:

```shell
export ssh_key=$(cat ~/.ssh/ocp_rsa | sed 's/^/  /')
export ssh_pub_key=$(cat ~/.ssh/ocp_rsa.pub)
export pull_secret=$(cat ~/pullsecret.json)
export aws_id=$(cat ~/.aws/credentials | grep aws_access_key_id | awk '{print $3}')
export aws_key=$(cat ~/.aws/credentials | grep aws_secret_access_key | awk '{print $3}')
export base_domain=$(oc get dns cluster -o jsonpath='{.spec.baseDomain}' | perl -ne 's/^[^\.]+\.//; print;')
export cluster_release_image=quay.io/openshift-release-dev/ocp-release:$(oc get clusteroperator config-operator -o jsonpath='{.status.versions[0].version}')-x86_64
```

Create clusters:

```shell
export region="us-east-2"
export network_cidr="10.128.0.0/14"
export service_cidr="172.30.0.0/16"
envsubst < ./acm/acm-cluster-values.yaml > /tmp/values.yaml
helm upgrade cluster1 ./charts/acm-aws-cluster --create-namespace -i -n cluster1  -f /tmp/values.yaml

export region="us-west-2"
export network_cidr="10.132.0.0/14"
export service_cidr="172.31.0.0/16"
envsubst < ./acm/acm-cluster-values.yaml > /tmp/values.yaml
helm upgrade cluster2 ./charts/acm-aws-cluster --create-namespace -i -n cluster2  -f /tmp/values.yaml

export region="us-west-1"
export network_cidr="10.136.0.0/14"
export service_cidr="172.32.0.0/16"
envsubst < ./acm/acm-cluster-values.yaml > /tmp/values.yaml
helm upgrade cluster3 ./charts/acm-aws-cluster --create-namespace -i -n cluster3  -f /tmp/values.yaml
```

Here's an example of the output from the third cluster create operation:
```
Release "cluster3" has been upgraded. Happy Helming!
NAME: cluster3
LAST DEPLOYED: Tue Dec  1 16:42:46 2020
NAMESPACE: cluster3
STATUS: deployed
REVISION: 2
TEST SUITE: None
```

Wait until the clusters are ready (about 40 minutes). You can watch the progress with the following command:

```shell
while : ; do clear ; oc get clusterdeployment --all-namespaces ; sleep 15 ; done
```

This output will have this form:
```
NAMESPACE   NAME       CLUSTERNAME   CLUSTERTYPE   BASEDOMAIN         INSTALLED   INFRAID                       AGE
cluster1    cluster1   cluster1                    la-cucaracha.net   false       cluster1-acm-aws-clus-xxz5z   3m19s
cluster2    cluster2   cluster2                    la-cucaracha.net   false       cluster2-acm-aws-clus-nb6c8   2m45s
cluster3    cluster3   cluster3                    la-cucaracha.net   false       cluster3-acm-aws-clus-lw8gg   2m29s
```

At this point your architecture should look like the below image:

![RHACM](./media/RHACM.png)

Collect the cluster metadata. This is useful if something goes wrong and you need to force the deletion of the clusters.

```shell
for cluster in cluster1 cluster2 cluster3; do
  export cluster_name=$(oc get secret ${cluster}-install-config -n ${cluster} -o jsonpath='{.data.install-config\.yaml}' | base64 -d | jq -r '.metadata.name')
  export cluster_id=$(oc get clusterdeployment ${cluster} -n ${cluster} -o jsonpath='{.spec.clusterMetadata.clusterID}')
  export region=$(oc get clusterdeployment ${cluster} -n ${cluster} -o jsonpath='{.spec.platform.aws.region}')
  export infra_id=$(oc get clusterdeployment ${cluster} -n ${cluster} -o jsonpath='{.spec.clusterMetadata.infraID}')
  envsubst < ./acm/metadata.tpl.json > ./${cluster}-metadata.json
done
```

### Prepare login config contexts

```shell
export control_cluster=$(oc config current-context)
for cluster in cluster1 cluster2 cluster3; do
  password=$(oc --context ${control_cluster} get secret $(oc --context ${control_cluster} get clusterdeployment ${cluster} -n ${cluster} -o jsonpath='{.spec.clusterMetadata.adminPasswordSecretRef.name}') -n ${cluster} -o jsonpath='{.data.password}' | base64 -d)
  url=$(oc --context ${control_cluster} get clusterdeployment ${cluster} -n ${cluster} -o jsonpath='{.status.apiURL}')
  console_url=$(oc --context ${control_cluster} get clusterdeployment ${cluster} -n ${cluster} -o jsonpath='{.status.webConsoleURL}')
  oc login -u kubeadmin -p ${password} --insecure-skip-tls-verify=true ${url}
  oc config set-cluster ${cluster} --insecure-skip-tls-verify=true --server ${url}
  oc config set-credentials admin-${cluster} --token $(oc whoami -t)
  oc config set-context $cluster --cluster ${cluster} --user=admin-${cluster}
  echo cluster: ${cluster}
  echo api url: ${url}
  echo console url ${console_url}
  echo admin account: kubeadmin/${password}
done
oc config use-context ${control_cluster}
```

## Deploy global-load-balancer-operator

The [global-load-balancer-operator](https://github.com/redhat-cop/global-load-balancer-operator#global-load-balancer-operator) programs route53 based on the global routes found on the managed clusters.

### Create global zone

This will create a global zone called `global.<cluster-base-domain>` with associated zone delegation.

```shell
export cluster_base_domain=$(oc --context ${control_cluster} get dns cluster -o jsonpath='{.spec.baseDomain}')
export cluster_zone_id=$(oc --context ${control_cluster} get dns cluster -o jsonpath='{.spec.publicZone.id}')
export global_base_domain=global.${cluster_base_domain#*.}
aws route53 create-hosted-zone --name ${global_base_domain} --caller-reference $(date +"%m-%d-%y-%H-%M-%S-%N")
export global_zone_res=$(aws route53 list-hosted-zones-by-name --dns-name ${global_base_domain} | jq -r '.HostedZones[0].Id')
export global_zone_id=${global_zone_res##*/}
export delegation_record=$(aws route53 list-resource-record-sets --hosted-zone-id ${global_zone_id} | jq '.ResourceRecordSets[0]')
envsubst < ./global-load-balancer-operator/delegation-record.json > /tmp/delegation-record.json
aws route53 change-resource-record-sets --hosted-zone-id ${cluster_zone_id} --change-batch file:///tmp/delegation-record.json
```

### Deploy operator

```shell
export namespace=global-load-balancer-operator
oc --context ${control_cluster} new-project ${namespace}
oc --context ${control_cluster} apply -f https://raw.githubusercontent.com/kubernetes-sigs/external-dns/master/docs/contributing/crd-source/crd-manifest.yaml
oc --context ${control_cluster} apply -f ./global-load-balancer-operator/operator.yaml -n ${namespace}
```

### Deploy global dns configuration for route53

```shell
export cluster1_service_name=router-default
export cluster2_service_name=router-default
export cluster3_service_name=router-default
export cluster1_service_namespace=openshift-ingress
export cluster2_service_namespace=openshift-ingress
export cluster3_service_namespace=openshift-ingress
export cluster1_secret_name=$(oc --context ${control_cluster} get clusterdeployment cluster1 -n cluster1 -o jsonpath='{.spec.clusterMetadata.adminKubeconfigSecretRef.name}')
export cluster2_secret_name=$(oc --context ${control_cluster} get clusterdeployment cluster2 -n cluster2 -o jsonpath='{.spec.clusterMetadata.adminKubeconfigSecretRef.name}')
export cluster3_secret_name=$(oc --context ${control_cluster} get clusterdeployment cluster3 -n cluster3 -o jsonpath='{.spec.clusterMetadata.adminKubeconfigSecretRef.name}')
```

```shell
envsubst < ./global-load-balancer-operator/route53-credentials-request.yaml | oc --context ${control_cluster} apply -f - -n ${namespace}
envsubst < ./global-load-balancer-operator/route53-dns-zone.yaml | oc --context ${control_cluster} apply -f -
envsubst < ./global-load-balancer-operator/route53-global-route-discovery.yaml | oc --context ${control_cluster} apply -f - -n ${namespace}
```

At this point your architecture should look like the below image:

![Global Load Balancer](./media/GLB.png)

## Deploy Submariner

[Submariner](https://submariner.io/) creates an IPSec-based network tunnel between the managed clusters' SDNs.

### Prepare nodes for submariner

```shell
git -C /tmp clone https://github.com/submariner-io/submariner
for context in cluster1 cluster2 cluster3; do
  cluster_id=$(oc --context ${context} get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
  cluster_region=$(oc --context ${context} get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')
  echo $cluster_id $cluster_region
  mkdir -p /tmp/${cluster_id}
  cp -R /tmp/submariner/tools/openshift/ocp-ipi-aws/* /tmp/${cluster_id}
  sed -i "s/\"cluster_id\"/\"${cluster_id}\"/g" /tmp/${cluster_id}/main.tf
  sed -i "s/\"aws_region\"/\"${cluster_region}\"/g" /tmp/${cluster_id}/main.tf
  pushd /tmp/${cluster_id}
  terraform init -upgrade=true
  terraform apply -auto-approve
  popd
  oc --context=${context} apply -f /tmp/${cluster_id}/submariner-gw-machine*.yaml
done
```

### Upgrade the node machine to a network optimized machine type

```shell
for context in cluster1 cluster2 cluster3; do
  export gateway_machine_set=$(oc --context ${context} get machineset -n openshift-machine-api | grep submariner | awk '{print $1}')
  oc --context ${context} scale machineset ${gateway_machine_set} -n openshift-machine-api --replicas=0
  oc --context ${context} patch MachineSet ${gateway_machine_set} --type='json' -n openshift-machine-api -p='[{"op" : "replace", "path" : "/spec/template/spec/providerSpec/value/instanceType", "value" : "m5n.xlarge"}]'
  oc --context ${context} scale machineset ${gateway_machine_set} -n openshift-machine-api --replicas=1
done
```

### Deploy submariner via CLI

```shell
curl -Ls https://get.submariner.io | VERSION=0.7.0 bash
subctl deploy-broker --kubecontext ${control_cluster} --service-discovery
mv broker-info.subm /tmp/broker-info.subm
for context in cluster1 cluster2 cluster3; do
  subctl join --kubecontext ${context} /tmp/broker-info.subm --no-label --clusterid $(echo ${context} | cut -d "/" -f2 | cut -d "-" -f2) --cable-driver libreswan
done
```

verify submariner

```shell
for context in cluster1 cluster2 cluster3; do
  subctl show --kubecontext ${context} all
done
```

At this point your architecture should look like the below image:

![Network Tunnel](./media/Submariner.png)

## Troubleshooting Submariner

### Restarting submariner pods

```shell
for context in cluster1 cluster2 cluster3; do
  oc --context ${context} rollout restart daemonset -n submariner-operator
  oc --context ${context} rollout restart deployment -n submariner-operator
done
```

### Uninstalling submariner

```shell
for context in cluster1 cluster2 cluster3; do
  oc --context ${context} delete project submariner-operator
done
oc --context ${control_cluster} delete project submariner-k8s-broker
```

### Install kube-ops-view

This can be useful to quickly troubleshoot issues

```shell
for context in cluster1 cluster2 cluster3; do
  export OCP_OPS_VIEW_ROUTE=ocp-ops-view.apps.$(oc --context ${context} get dns cluster -o jsonpath='{.spec.baseDomain}')
  helm --kube-context ${context} upgrade kube-ops-view stable/kube-ops-view -i --create-namespace -n ocp-ops-view --set redis.enabled=true --set rbac.create=true --set ingress.enabled=true --set ingress.hostname=$OCP_OPS_VIEW_ROUTE --set redis.master.port=6379
  oc --context ${context} adm policy add-scc-to-user anyuid -z default -n ocp-ops-view
done
```

## Cleaning up

If you need to uninstall the clusters, run the following:

```shell
for cluster in cluster1 cluster2 cluster3; do
  oc delete clusterdeployment ${cluster} -n ${cluster}
done
```

if for any reason that does not work, run the following:

```shell
for cluster in cluster1 cluster2 cluster3; do
  mkdir -p ./${cluster}
  cp ${cluster}-metadata.json ./${cluster}/medatada.json
  openshift-install  destroy cluster --log-level=debug --dir ./${cluster}
done
```

