+++
title = "Shadow mirroring with Envoy"
slug = "shadow-mirroring-with-envoy"
description = "An overview of implementing shadow mirroring with Envoy, to safely test a service with real production traffic without affecting the end clients."
date = "2019-04-11T20:44:50.0000000"
tags = ["envoy"]
ghostCommentId = "ghost-5cafa655a26b5f5ce4856bf4"
+++

# Introduction

Shadow mirroring (also called shadow feeding, or just shadowing) is a technique when at some point in our infrastructure we duplicate the outgoing traffic to an additional destination, but we send the responses to the actual client coming from the main destination.  
This is mainly used to be able to test a service with real production traffic without affecting the end clients in any way. It's particularly useful when we are rewriting an existing service, and we want to verify if the new version can process a real variety of incoming requests in an identical way, or when we want to do a comparative benchmark between two version of the same service. And it can also be used to do some extra, out of bounds processing of our requests, which can be done asynchronously, for example collect some additional statistics, or do some extended logging.

There are some existing technologies implemented specifically for this purpose. The one I have used before is [GoReplay](https://github.com/buger/goreplay), which is a small network monitoring tool capable of—among other things—shadowing the incoming traffic to a second source.

And some of the general-purpose reverse proxies have this capability as well. In this post we'll go over how this can be implemented with [Envoy](https://www.envoyproxy.io/). First we'll see an introduction to what a basic proxy or load balancing setup with Envoy looks like, and then we'll focus on the request mirroring capabilities which allows us to implement shadowing.

# A simple Envoy setup

The following diagram illustrates a very simple setup where we use an Envoy instance as a "frontend" or reverse proxy to route traffic to a single backend service. (Envoy can be used in much more complicated routing setups, but this is enough for illustrating request mirroring.)

![A basic Envoy setup.](/images/2019/04/envoy-simple-setup.png)

An Envoy instance can be controlled by providing a static YAML configuration on startup. (Which is just one of the ways of configuring Envoy, it also supports having a dynamic configuration provider, but we won't discuss that in this post.)  
The above simple setup can be achieved with the following YAML config.

```yaml
admin:
  access_log_path: /tmp/admin_access.log
  address:
    socket_address: { address: 0.0.0.0, port_value: 9901 }

static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address: { address: 0.0.0.0, port_value: 80 }
    filter_chains:
    - filters:
      - name: envoy.http_connection_manager
        config:
          stat_prefix: ingress_http
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match: { prefix: "/" }
                route:
                  host_rewrite: myservice-backend.mycompany.com
                  cluster: myservice_cluster
          http_filters:
          - name: envoy.router
  clusters:
  - name: myservice_cluster
    type: LOGICAL_DNS
    hosts: [{ socket_address: { address: myservice-backend.mycompany.com, port_value: 80 }}]
```

This specifies one single route, which matches all incoming requests, and proxies them to the `myservice_cluster` cluster.

```yaml
            - name: local_service
              domains: ["*"]
              routes:
              - match: { prefix: "/" }
                route:
                  host_rewrite: myservice-backend.mycompany.com
                  cluster: myservice_cluster
```

And the single cluster we configured will route all requests to the address `myservice-backend.mycompany.com`.

```yaml
  - name: myservice_cluster
    type: LOGICAL_DNS
    hosts: [{ socket_address: { address: myservice-backend.mycompany.com, port_value: 80 }}]
```

# Mirroring support in Envoy

There are two specific capabilities of Envoy which are particularly interesting to us.

The first is [Traffic Shifting/Splitting](https://www.envoyproxy.io/docs/envoy/latest/configuration/http_conn_man/traffic_splitting). This allows us to route certain percentages of the traffic to different hosts. Although this is useful in many situations, it won't help us with shadowing, since this just routes the traffic in various directions, but doesn't duplicate it.

The feature which will allow us to implement shadowing is the [request mirror policy](https://www.envoyproxy.io/docs/envoy/latest/api-v2/api/v2/route/route.proto#route-routeaction-requestmirrorpolicy). With this we can specify an extra backend for every route, and configure what percentage of the traffic should be mirrored to it.

This can be enabled by adding the `request_mirror_policy` field to our route, and configure the following two keys.

 - `cluster`: The name of the cluster to which we're mirroring.
 - `runtime_fraction`: The portion of the traffic which should be mirrored. You can either configure this with a dynamic runtime value, or add a static value to your YAML config with this syntax: `runtime_fraction: { default_value: { numerator: 25 } }`.  
 The field `default_value` should contain an object of the type [FractionalPercent](https://www.envoyproxy.io/docs/envoy/latest/api-v2/type/percent.proto#envoy-api-msg-type-fractionalpercent), in which you can specify the `numerator` and the `denominator`. The final portion of the mirrored traffic will be calculated as `numerator / denominator`. The default value of `denominator` is `100`, so if you only specify the `numerator`, it'll be interpreted as a percentage. If you want to configure fractional percentages, then you need to configure `denominator` too.  
 For example this value specifies 0.03% (0.0003): `runtime_fraction: { default_value: { numerator: 3, denominator: 10000 } }`.

And the way Envoy will behave is that it'll send back the response to the original client which comes from the main cluster, and the mirrored requests happens in a fire & forget fashion, so the response is discarded. This is exactly what we want if we'd like to test a different version of our service without affecting any end users.

# The full setup

Let's say we want to configure the following setup, in which 25% of the traffic is shadow mirrored to a different upstream, accessible at `myservice-test.mycompany.com`.

![An Envoy setup with mirroring 25% of the traffic.](/images/2019/04/envoy-mirror-setup.png)

We can set this up with the following YAML configuration.

```yaml
admin:
  access_log_path: /tmp/admin_access.log
  address:
    socket_address: { address: 0.0.0.0, port_value: 9901 }

static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address: { address: 0.0.0.0, port_value: 80 }
    filter_chains:
    - filters:
      - name: envoy.http_connection_manager
        config:
          stat_prefix: ingress_http
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match: { prefix: "/" }
                route:
                  host_rewrite: myservice-backend.mycompany.com
                  cluster: myservice_cluster
                  request_mirror_policy:
                    cluster: myservice_test_cluster
                    runtime_fraction: { default_value: { numerator: 25 } }
          http_filters:
          - name: envoy.router
  clusters:
  - name: myservice_cluster
    type: LOGICAL_DNS
    hosts: [{ socket_address: { address: myservice-backend.mycompany.com, port_value: 80 }}]
  - name: myservice_test_cluster
    type: LOGICAL_DNS
    hosts: [{ socket_address: { address: myservice-test.mycompany.com, port_value: 80 }}]
```

One important thing to note is that the service discovery for the test cluster will happen with the DNS address `myservice-test.mycompany.com`, that's not going to be used as the host name (the value of the `Host` header) in the mirrored requests.  
With a request mirror policy, the host name is always what it would normally be, plus the `-shadow` suffix. Thus in this example it will become `myservice-backend.company.com-shadow`. This is something that we have to prepare for if we're mirroring traffic to a component which takes the value of the `Host` header into account. (At some point [I asked](https://groups.google.com/forum/#!topic/envoy-users/sroT9ecsCDY) if there is any way to customize this, but at the moment it is not possible.)

I hope this will be a useful introduction about request mirroring with Envoy, I found that this feature can be extremely valuable for safely testing new implementations, or carrying out comparative benchmarks.
