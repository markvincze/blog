+++
title = "Running ASP.NET Core in auto-scaling containers? Warm up!"
description = "The first request to an ASP.NET Core API is always slow. This post shows a way how to warm up our application before deploying it to production."
date = "2017-07-29T18:32:34.0000000"
tags = ["web api", "asp.net-core", "kubernetes"]
+++

ASP.NET Core APIs are not warmed up by default. This is easy to illustrate, let's scaffold a brand new empty api.

```bash
mkdir warmuptest
cd warmuptest
dotnet new webapi
dotnet restore
dotnet run
```

Then let's do two consecutive requests against the `/values` endpoint, and measure the response times. This is what we'll see.

```
$ curl -o /dev/null -s -w %{time_total}\\n http://localhost:5000/values
0.594

$ curl -o /dev/null -s -w %{time_total}\\n http://localhost:5000/values
0.000

$ curl -o /dev/null -s -w %{time_total}\\n http://localhost:5000/values
0.000
```

So you can see that the first request takes a disproportionately long time, around half a second, while the subsequent requests are much faster, they take a couple of milliseconds (for some requests `curl` reports `0.016` or `0.015`, and for some others, it says `0.000`, so I guess the measurement is not granular enough).

I tried also to run the api with the flag `-c Release`, I also tried to publish `dotnet publish`, and I even tried to publish a self-contained exe (by adding the `RuntimeIdentifiers` to the csproj and using the `--runtime` flag with `dotnet publish`), but all of them had the same behavior.

This can generally be an annoyance since the first request to our application will always be slightly slower.
Still, if we have a monolithic application that we deploy to a server machine—let's say—once a day, we can probably live with this.

On the other hand, if we have smaller APIs (I'm trying to avoid using the term microservices ^^), and especially if we are running them in auto-scaling containers, for example in Kubernetes, this can become not just a slight annoyance, but a severe problem. Due to having many small APIs which we deploy often, we'll have more "first requests" than in a monolith, and if we are using auto-scaling, then this is going to happen not just after deployments, but every time our API is scaled out, or a container is recycled for any reason.

And in more complex applications I encountered much worse first request response times, even more than 5 seconds. This resulted in having at least a handful of timeout errors in our logs every day.

# The cause (?)

Let's get it out of the way: I don't know exactly what's causing the slowness of the first request.

 - I suspected that the necessary assemblies were being loaded, so I added a piece of code to `Startup` which forced the loading of the assemblies, but that didn't help.
 - JITting seemed to be another obvious offender. I was looking at forcing the JITting with `RuntimeHelpers.PrepareMethod`, but unfortunately that method is not available in .NET Core, so that wasn't an option.  
We also looked at using [crossgen](https://github.com/dotnet/coreclr/blob/master/Documentation/building/crossgen.md) to JIT the assembly at build time (thanks to my colleague, [Jaanus](https://twitter.com/discosultan) for getting it to work and doing the test!), but that didn't help either.

The only thing I can think of is that this caused by ASP.NET itself warming something up internally. I tried to set the log level to the most verbose but didn't get any message indicating what was going on. (The next step, of course, would be to grab the ASP.NET source and start measuring what's happening under the hood, but I haven't done that yet, especially since the 2.0 release is just around the corner, which might bring changes to the situation.)

# A solution

The only reliable solution I could find is not very scientific: after deployment, simply send a couple of warmup requests to the endpoints of the api. It's important to only send real traffic to the deployed instance (only add it to the load balancer, if we're using one) after the warmup is done so that our production system is not affected by the first slow requests.

The way we can do this completely depends on what kind of hosting and deployment technique we are using. If we are using a script, which deploys the API to a server instance, and then adds it to the load balancer, then we'll simply have to do some warmup calls—for example with `curl`—between the deployment, and the load-balancer configuration.
(If the deployment itself, and then enabling production traffic to the instance is not separated during our deployment, then we cannot do this, but in that case, we don't have zero-downtime deployments, so probably don't care that much about warming up anyway.)

## Warm up with a readiness probe in Kubernetes

One specific setup I'd like to show is the one when we use Kubernetes. That's the environment we're using to run our ASP.NET Core APIs at [Travix](https://www.travix.com), where I work.

Kubernetes has the concept of a [readiness probe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/#define-readiness-probes). The way it works is that a pod with a readiness probe will only get traffic once it's readiness probe has successfully returned a result. This is exactly what we need to do a warmup.

In order to set this up, we'll need an endpoint in our application which will act as the readiness probe. We can implement this in a designated controller, in which we'll send a dummy request to our endpoint we want to exercise.

```csharp
using System;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;

namespace dotnettest.Controllers
{
    [Route("[controller]")]
    public class ReadyController : Controller
    {
        private static bool isWarmedUp = false;

        private string GetFullUrl(string relativeUrl) =>
            $"{Request.Scheme}://{Request.Host}{relativeUrl}";

        private async Task Warmup()
        {
            using (var httpClient = new HttpClient())
            {
                // Warm up the /values endpoint.
                var valuesUrl = GetFullUrl(Url.Action("Get", "Values"));
                await httpClient.GetAsync(valuesUrl);

                // Here we could warm up some other endpoints too.
            }

            isWarmedUp = true;
        }

        [HttpGet, HttpHead]
        public async Task<IActionResult> Get()
        {
            if (!isWarmedUp)
            {
                await Warmup();
            }

            return Ok("API is ready!");
        }
    }
}
```
(Note: I'm aware that the implementation is not thread-safe, but the worst thing that can happen if we send two parallel requests to this endpoint is that we'll do the warmup multiple times, which I didn't consider to be a huge issue.)

Now if we start the API, then send a request first to `/ready`, then to our actual endpoint, the first real API request will be fast.

```bash
$ curl -o /dev/null -s -w %{time_total}\\n http://localhost:5000/ready
1.094

$ curl -o /dev/null -s -w %{time_total}\\n http://localhost:5000/values
0.000
```

The last step is to add the readiness probe to our `kubernetes.yaml` file.

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 5000
  initialDelaySeconds: 10
  timeoutSeconds: 60
  periodSeconds: 60
```

This way Kubernetes will first send a request to `/ready`, and only start sending real traffic to our pod once that request is completed.

## Discover our endpoints automatically

When doing this warmup for all of our various APIs, it became tedious to implement sending the actual requests since, in every API, the set of endpoints to warm up is different.

To mitigate this, I implemented a simple [`ApiWarmer`](https://github.com/markvincze/rest-api-helpers/blob/master/src/RestApiHelpers/Warmup/ApiWarmer.cs), which does the following.

 - It discovers all the `Controller` types we have.
 - Gets all the `GET` action methods of all the controllers.
 - Sends a dummy request to all the endpoints.

When sending the requests, it fills every input argument with a `default(T)` value, so for a string, it sends `""`, for an int, it sends `0`, for a Guid, it sends `00000000-0000-0000-0000-000000000000`, etc.
Now, this might be problematic in your use case, but in my experience, it's usually fine. It might result in some 404s if we pass in `0` as an identifier, or a 400 Bad Request if we send an empty Guid, but as long as the warm up works, that's fine.
(Still, you'll have to verify if this is not a problem in your scenario, it can still be an issue for example if you're logging any `4xx` response, then this can mess up your statistics, etc.)

In order to use the `ApiWarmer`, we have to set up the dependency in our `Startup`.

```csharp
services.AddSingleton<IApiWarmer, ApiWarmer>();
```

And instead of manually sending a request in `ReadyController`, use the `IApiWarmer`.

```csharp
        private readonly IServiceProvider serviceProvider;
        private readonly IApiWarmer apiWarmer;

        public ReadyController(IServiceProvider serviceProvider, IApiWarmer apiWarmer)
        {
            this.serviceProvider = serviceProvider;
            this.apiWarmer = apiWarmer;
        }

        [HttpGet, HttpHead]
        public async Task<IActionResult> Get()
        {
            if (!isWarmedUp)
            {
                await apiWarmer.WarmUp<Startup>(serviceProvider, Url, Request, "Ready");

                isWarmedUp = true;
            }

            return Ok("API is ready!");
        }
```

The last argument in the `WarmUp` call is the name of the controller from which we are initiating the warmup. This is important to pass in, otherwise, we might end up in an infinite loop of calls to `/ready`.

The solution we've seen is not super scientific, but it seems to work well in practice, so we can avoid getting random timeout errors on our first API requests.

Did you find a more sophisticated way to do the warmup, or did you figure out what's the underlying cause of the first slow request? Any information is welcome in the comments! ;)
