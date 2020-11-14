+++
title = "How to gracefully fall back to cache on 5xx responses with Varnish"
slug = "how-to-gracefully-fall-back-to-cache-on-5xx-responses-with-varnish"
description = "Varnish can gracefully fall  back to cached values in case our backend is down. This post describes how we can handle 5xx errors this way."
date = "2018-07-28T19:12:24.0000000"
tags = ["varnish"]
+++

# Introduction

Varnish is a widely used reverse proxy and *HTTP accelerator*. It sits in front of an HTTP service, and caches the responses to improve the response times observed by the clients, and possibly to reduce the load on the upstream backend service.

Besides bringing performance improvements, Varnish can be also useful for shielding the clients from any outage of the backend service, since if the upstream is temporarily out of service, Varnish can keep serving the cached content, so the clients don't have to notice anything (if the data they need is already present in the cache).

In order to use the basic caching capability, and to also gracefully fall back when the backend is down, we have to control two properties of the response object.

 - `beresp.ttl`: This is the amount of time until Varnish keeps an object in cache, and serves it up from there to the clients until it tries to fetch it again from the upstream.
 - `beresp.grace`: This is the amount of time an object is kept in the cache even after the ttl is expired. This is interpreted on top of the ttl, so for example if both `ttl` and `grace` is set to `1m`, then the objects can stay in the cache for a total of 2 minutes.

If a request comes in for which the response is already in the cache, and the `ttl` has not passed yet, then Varnish returns the cached value to the client without trying to fetch a fresh one from the backend.

On the first request that comes after `ttl` expired, if `grace` is set and is not expired yet, then Varnish will immediately return the cached value to the client, and at the same time it will trigger a background fetch for a fresh response. If the fetch is successful, it replaces the stale object in the cache with the fresh one.

![Sequence diagram showing how Varnish returns the cached content to the clients.](/images/2018/07/happy-flow.png)

This behavior means that if the backend is not available, that won't affect the end clients until the end of the `grace` period, since Varnish will always return the cached object to the client, and only do a background fetch asynchronously. Which will fail if the backend is down, but that won't hurt the object already stored in the cache.  
And if the `grace` period is over, Varnish will purge the cached object, and won't return it to clients any more. So if the backend is down, the clients will receive a `503 Service Unavailable` response from Varnish.

![Sequence diagram showing how Varnish behaves when the backend is down during the grace period.](/images/2018/07/backend-down.png)

In practice, `grace` can be much longer than `ttl`. For example we can set `ttl` to a couple of minutes to make sure the clients regularly get fresh data, but we can set `grace` to multiple hours, to give us time to fix the backend in case of an outage.

# 5xx responses

By default Varnish only falls back to the cached values during the grace period if the backend can't be connected to, or if the request times out. If the backend returns a `5xx` error, Varnish considers that normal response, and returns it to the client (it might even store it in the cache, depending on our configuration).  
This is an understandable default, it might be confusing if our clients did not receive some server errors which could contain valuable information about the problem with the backend.

On the other hand, we might also consider 5xx responses outages, and want to gracefully fall back to the cached values instead. I wanted to achieve the following objectives.

 - Never cache `5xx` responses. This is important, because this'll make Varnish try to fetch the response again upon every request. (It would be wasteful to cache a `500` response for 10 minutes, when the outage might only last 1-2 minutes.)
 - If we are in the grace period, and the backend returns a `5xx`, fall back to the cached response and send that to the client.
 - If we don't have the response in the cache at all, then return to the client the actual `5xx` error that was given by the backend.

This can be achieved with Varnish pretty easily, but it needs some configuration.

# Configuration

In order to customize the behavior of Varnish, we have to edit its configuration file (which usually resides at `/etc/varnish/default.vcl`).

The config file is using the VCL syntax, which is a C-like domain specific language specifically for the customization of Varnish. It took me some getting used to before I could wrap my head around it, an actual production configuration can get complicated, which can be a bit intimidating at first. In this post I won't talk about the basics, but will just rather show the bits necessary for this particular setup. If you'd like to learn the basics of VCL, I recommend reading a comprehensive guide, for example [The Varnish Book](https://info.varnish-software.com/the-varnish-book).

In the VCL configuration we can customize various *subroutines*, with which we can hook into varios steps of the request lifecycle. The only subrouting we're going to look at is `sub vcl_backend_response`, which is triggered right after a response was received from the backend.

A very simple version of this would be the following, which enables caching for 1 minute, and enables graceful fallback for 10 minutes on top of that.

```
sub vcl_backend_response {
    set beresp.ttl = 1m;
    set beresp.grace = 10m;
}
```

In order to achieve the objective of gracefull fallback on `5xx` errors, we'll need to use the following additional tools.

 - `beresp.status`: With this we can check the status code returned by the backend. This will be used to handle `5xx` responses specially.
 - `bereq.is_bgfetch`: This field shows whether this was a backend request sent asynchronously when the client received a response already from the cache, or if it's a synchronous request that was sent when we didn't find the response in the cache.
 - `beresp.uncacheable`: We can set this to true to prevent a response from being cached.
 - `abandon`: This is a *return keyword* that we can use to make Varnish completely abandon the request, and return a *synthesized* `503` to the client (or just do nothing, in case of an asynchronous background fetch).

With all these tools in our belt we can implement the requirements with the following logic.

```
sub vcl_backend_response {
    set beresp.ttl = 1m;
    set beresp.grace = 10m;

    # This block will make sure that if the upstream returns a 5xx, but we have the response in the cache (even if it's expired),
    # we fall back to the cached value (until the grace period is over).
    if (beresp.status == 500 || beresp.status == 502 || beresp.status == 503 || beresp.status == 504)
    {
        # This check is important. If is_bgfetch is true, it means that we've found and returned the cached object to the client,
        # and triggered an asynchoronus background update. In that case, if it was a 5xx, we have to abandon, otherwise the previously cached object
        # would be erased from the cache (even if we set uncacheable to true).
        if (bereq.is_bgfetch)
        {
            return (abandon);
        }

        # We should never cache a 5xx response.
        set beresp.uncacheable = true;
    }
}
```

In the above code I'm only handling the standard `500`, `502`, `503` and `504` codes, but of course you can extend it if your backend is returning something else.

The key of the solution is using `abandon` in combination with `if (bereq.is_bgfetch)`. If we returned `abandon` on every `5xx` without checking `bereq.is_bgfetch`, then Varnish would always return its built-in `503` response to the client instead of the `5xx` sent by the backend, so our client could never see the actual backend errors.  

**Important**: The field `bereq.is_bgfetch` is only available starting from Varnish 5.2.0. And depending on our OS version and installation method, we might be on an earlier version, so this is important to check with `varnishd -V`.

The configuration syntax of Varnish takes a bit of getting used to, but if set up properly, it provides an invaluable tool for improving the performance of our services, and meanwhile protecting our clients from outages. And I hope this post will be helpful when handling server side errors.
