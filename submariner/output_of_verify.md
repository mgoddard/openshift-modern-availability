```
Showing information for cluster "cluster1":
    Discovered network details:
        Network plugin:  OpenShiftSDN
        Service CIDRs:   [172.30.0.0/16]
        Cluster CIDRs:   [10.128.0.0/14]

CLUSTER ID                    ENDPOINT IP     PUBLIC IP       CABLE DRIVER        TYPE            
cluster1                      10.0.82.209     3.16.15.224     libreswan           local           
cluster2                      10.0.75.243     54.212.140.209  libreswan           remote          

GATEWAY                         CLUSTER                 REMOTE IP       CABLE DRIVER        SUBNETS                                 STATUS          
ip-10-0-75-243                  cluster2                10.0.75.243     libreswan           172.31.0.0/16, 10.132.0.0/14            connecting      

NODE                            HA STATUS       SUMMARY                         
ip-10-0-82-209                  active          0 connections out of 1 are established

COMPONENT                       REPOSITORY                                            VERSION         
submariner                      quay.io/submariner                                    0.7.0           
submariner-operator             quay.io/submariner                                    0.7.0           
service-discovery               quay.io/submariner                                    0.7.0           

Showing information for cluster "cluster2":
    Discovered network details:
        Network plugin:  OpenShiftSDN
        Service CIDRs:   [172.31.0.0/16]
        Cluster CIDRs:   [10.132.0.0/14]

No resources found.

No resources found.

No resources found.

COMPONENT                       REPOSITORY                                            VERSION         
submariner                      quay.io/submariner                                    0.7.0           
submariner-operator             quay.io/submariner                                    0.7.0           
service-discovery               quay.io/submariner                                    0.7.0           

Showing information for cluster "cluster3":
    Discovered network details:
        Network plugin:  OpenShiftSDN
        Service CIDRs:   [172.32.0.0/16]
        Cluster CIDRs:   [10.136.0.0/14]

No resources found.

No resources found.

No resources found.

COMPONENT                       REPOSITORY                                            VERSION         
submariner                      quay.io/submariner                                    0.7.0           
submariner-operator             quay.io/submariner                                    0.7.0           
service-discovery               quay.io/submariner                                    0.7.0
```


