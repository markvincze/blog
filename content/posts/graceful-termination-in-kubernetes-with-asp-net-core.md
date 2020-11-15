+++
title = "Graceful termination in Kubernetes with ASP.NET Core"
slug = "graceful-termination-in-kubernetes-with-asp-net-core"
description = "An overview of the challenges and solutions for implementing graceful termination when using ASP.NET Core in Kubernetes."
date = "2019-01-06T16:56:05.0000000"
tags = ["asp.net-core", "kubernetes"]
ghostCommentId = "ghost-5c32318aa26b5f5ce4856be0"
+++

Using a container-orchestration technology like Kubernetes, running applications in small containers, and scaling out horizontally rather than scaling a single machine up has numerous benefits, such as flexible allocation of the raw resources among different services, being able to precisely adjust the number of instances we're running according to the volume of traffic we're receiving, and forcing us to run our applications in immutable containers, thereby making our releases repeatable, thus easier to reason about.

On the other hand, we also face several challenges inherent to this architectural style, due to our components being inevitably distributed, and our containers constantly being shuffled around on the "physical" (technically, most probably still virtual) nodes.

One of these challenges is that due to Kubernetes constantly scaling our services up and down, and possible evicting our pods from certain nodes and moving them to another, instances of our services will constantly be stopped and then started up.  
This is something we have to worry about much less if we have a fixed number of server machines to which we're directly deploying our application. In that case, our services will only be stopped when we're deploying, or in some exceptional cases like if they crash, or the server machines have to be restarted for some reason.

This requires a mental shift. When implementing a service, we always have to think it through how it will behave if it's suddenly stopped. Will it leave something in an inconsistent state that we have to clean up? Can it be doing a long-running operation that we need to cancel? Do we have to send a signal to notify some other component that this instance is stopping?

In this post I'd like to focus only on the simplest scenario: we have a REST API implemented in ASP.NET Core, which doesn't have any of the above issues. It's stateless, it doesn't run any background processes, it only works in the request-response model, through some HTTP endpoints.

Even in this simplest scenario there is an important issue: at the point in time when our application is stopped, there might be some requests being processed. We have to ensure that ASP.NET Core (or Kubernetes) waits with killing our instance until they are completed.

In the rest of the post I'd like to describe the facilities Kubernetes provides to handle this scenario, and the way we can utilize them in ASP.NET Core.

*I did all the testing on the Google Kubernetes Engine. Since this is related to networking, which to some extent depends on where and how we're hosting Kubernetes, I can imagine that this might work differently depending on where we run, let's say Amazon, Azure, etc.*

# Graceful termination in Kubernetes

Kubernetes implements a specific order of events when it terminates any pod, so that we can set up our containers in a way that they have a chance to gracefully terminate.

The process is documented in [this section](https://kubernetes.io/docs/concepts/workloads/pods/pod/#termination-of-pods). I have to say that this part of the documentation has always been a bit confusing to me, and some parts I could figure out only through experimentation.

The basic idea is that when the pod is stopped, a grace period starts (which has the default length 30 seconds), during which the pod has a chance to do any necessary cleanup. If the containers terminate faster then that, then the pod is deleted as soon as all the containers exited, so Kubernetes doesn't necessarily waits for the full grace period. And if the containers don't terminate until the grace period passes, then Kubernetes forcefully stops all the containers, and deletes the pod.

We have two ways to run custom operations on shutdown, and prolong the termination of the container (but no longer than the full grace period):

 - We can specify a `preStop` hook for our container, in which we can run an arbitrary shell command. (Or execute a script file we included in our Docker image.)
 - The container receives a `TERM` signal, which we can handle in our application code. This is something we'll have to figure out how to properly do in the technology of our choice, it'll be different in .NET, NodeJS, Go, etc. In this post we'll see the specificities of ASP.NET Core.

We can use either of these approaches, or even both of them. It's important to remember that they *don't* happen in parallel, but rather sequentially (starting with the `preStop` hook), and they are confined by the same grace period together, not individually. So if the `preStop` hook uses up all the time in the grace period, we might not have enough time left to properly handle the `TERM` signal. *(If the `preStop` hook uses up all the time, then the `TERM` handler gets an extra 2 seconds to run.)*

And on top of all this, at some point the pod is removed from the list of Endpoints of the service objects.

An important detail is that the removal of the Endpoint is happening in parallel with `preStop` hook and the `TERM` signal, so there is no guarantee the load balancer won't send new requests to the pod being stopped, even after the `preStop` hook and the `TERM` signal was handled. (I couldn't find much official information on when this happens exactly, for example in [this tutorial video](https://cloud.google.com/blog/products/gcp/kubernetes-best-practices-terminating-with-grace) it's not mentioned at all.)

All this being said, I think this description leaves a lot up to interpretation regarding how this works in practice, so I decided to try to test what actually happens in an ASP.NET Core application.

# ASP.NET Core

What I set out to do was to test what the proper way is to handle pod termination if our container is running an ASP.NET Core application.

I particularly wanted to find an answer to these questions:

 - How can we handle the `TERM` signal in our C# code?
 - If we don't implement a custom `TERM` handler, *and* there are requests in flight when Kubernetes sends the `TERM`, does our application stop immediately, or does ASP.NET Core do the "right" thing, and wait for all current requests to finish (draining)?
 - In Kubernetes, can it happen that the load balancer still sends requests to our pod after we received `TERM`?

To be able to test these questions, I created a simple ASP.NET Core application, which simply logs a message to the console on every request, and has two endpoints.

```csharp
app.Run(async (context) =>
{
    PrintRequestLog();

    if (context.Request.Path.Value.Contains("slow"))
    {
        await SleepAndPrintForSeconds(10);
    }
    else
    {
        await Task.Delay(100);
    }

    await context.Response.WriteAsync(message);
});
```

 - The endpoint `/slow` responds after 10 seconds, and prints a log message every seconds while it's waiting. We can use this to test what happens to requests in flight when we receive the `TERM` signal.
 - Any other route responds much quicker (after 100ms), and prints one message. By constantly polling this endpoint we can check if our pod still receives request after the `TERM` signal.

If we keep polling the "slow" endpoint, the output looks like this:

```bash
1/6/19 1:50:22 PM: Incoming request at /slow, State: Running
1/6/19 1:50:22 PM: Sleeping (10 seconds left)
1/6/19 1:50:23 PM: Sleeping (9 seconds left)
1/6/19 1:50:24 PM: Sleeping (8 seconds left)
...
1/6/19 1:50:30 PM: Sleeping (2 seconds left)
1/6/19 1:50:31 PM: Sleeping (1 seconds left)
1/6/19 1:50:32 PM: Incoming request at /slow, State: Running
1/6/19 1:50:32 PM: Sleeping (10 seconds left)
1/6/19 1:50:33 PM: Sleeping (9 seconds left)
1/6/19 1:50:34 PM: Sleeping (8 seconds left)
...
1/6/19 1:50:40 PM: Sleeping (2 seconds left)
1/6/19 1:50:41 PM: Sleeping (1 seconds left)
1/6/19 1:50:42 PM: Incoming request at /slow, State: Running
1/6/19 1:50:42 PM: Sleeping (10 seconds left)
1/6/19 1:50:43 PM: Sleeping (9 seconds left)
...
```

And if we poll the quick endpoint, we only get one log message per request.

```bash
1/6/19 1:52:49 PM: Incoming request at /, State: Running
1/6/19 1:52:50 PM: Incoming request at /, State: Running
1/6/19 1:52:50 PM: Incoming request at /, State: Running
1/6/19 1:52:50 PM: Incoming request at /, State: Running
1/6/19 1:52:50 PM: Incoming request at /, State: Running
```

## Handle `TERM` in ASP.NET Core

In order to handle the `TERM` signal with custom C# code, we have to use the [`IApplicationLifetime`](https://github.com/aspnet/AspNetCore/blob/master/src/Hosting/Abstractions/src/IApplicationLifetime.cs) interface, which we can inject in our `Startup.Configure()` method. It provides 2 events related to termination, that we can register to. The documentation specifies these as the following.

 - ApplicationStopping: "Triggered when the application host is performing a graceful shutdown. Requests may still be in flight. Shutdown will block until this event completes."
 - ApplicationStopped: "Triggered when the application host is performing a graceful shutdown. All requests should be complete at this point. Shutdown will block until this event completes."

To test how these events work, I added a console print to both of them.

```csharp
appLifetime.ApplicationStopping.Register(() => Console.WriteLine("ApplicationStopping called"));
appLifetime.ApplicationStopped.Register(() => Console.WriteLine("ApplicationStopped called"));
```

These are the events we can use to sort out any custom cleanup before the application terminates. The way they work is that the ASP.NET Core process does not terminate until these event handlers return. But they have a timeout, which we'll see in a second.

If we send a `TERM` signal by executing `kill PID` to a running ASP.NET Core application—which is not executing any requests at the moment—this is the output we'll see.

```bash
Hosting environment: Production
Content root path: /home/mvincze/K8sGracefulShutdownTester/src/K8sGracefulShutdownTester
Now listening on: http://[::]:5000
Application started. Press Ctrl+C to shut down.
...
Application is shutting down...
1/6/19 1:58:51 PM: ApplicationStopping called
1/6/19 1:58:51 PM: ApplicationStopped called
```

The line `Application is shutting down...` is printed by the framework when it receives `TERM`, and we get the next two lines in short succession, which are coming from our custom handlers, and then the process exits immediately.

The next thing to see is what happens if we try the same when there is a request being processed.

## Wait for requests in flight to finish

The first thing I tested was what happens if our application receives the `TERM` signal when a request is being processed. I kept polling the `/slow` endpoint, and sent the `TERM` signal by executing `kill PID` when the app was in the middle of processing on of the slow requests. This was the output.

```bash
1/6/19 1:43:39 PM: Incoming request at /slow, State: Running
1/6/19 1:43:39 PM: Sleeping (10 seconds left)
1/6/19 1:43:40 PM: Sleeping (9 seconds left)
1/6/19 1:43:41 PM: Sleeping (8 seconds left)
1/6/19 1:43:42 PM: Sleeping (7 seconds left)
1/6/19 1:43:43 PM: Sleeping (6 seconds left)
1/6/19 1:43:44 PM: Sleeping (5 seconds left)
1/6/19 1:43:45 PM: Sleeping (4 seconds left)
Application is shutting down...
1/6/19 1:43:45 PM: ApplicationStopping called
1/6/19 1:43:46 PM: Sleeping (3 seconds left)
1/6/19 1:43:47 PM: Sleeping (2 seconds left)
1/6/19 1:43:48 PM: Sleeping (1 seconds left)
1/6/19 1:43:49 PM: ApplicationStopped called
```

This illustrates that if the `TERM` comes in when there is a request being processed, the framework waits and doesn't let the process terminate until the requests in flight finish. So this is taken care of by ASP.NET Core (I believe it's implemented in [`KestrelServer`](https://github.com/aspnet/AspNetCore/blob/master/src/Servers/Kestrel/Core/src/KestrelServer.cs#L172)), we don't have to implement custom code to achieve this.

One important thing to consider is that there is a timeout period until the framework is willing to wait for the pending requests. If I send the `TERM` when there is still more than 5 seconds left from the current request, this is what happens.

```bash
1/6/19 2:14:45 PM: Incoming request at /slow, State: Running
1/6/19 2:14:45 PM: Sleeping (10 seconds left)
1/6/19 2:14:46 PM: Sleeping (9 seconds left)
Application is shutting down...
1/6/19 2:14:46 PM: ApplicationStopping called
1/6/19 2:14:47 PM: Sleeping (8 seconds left)
1/6/19 2:14:48 PM: Sleeping (7 seconds left)
1/6/19 2:14:49 PM: Sleeping (6 seconds left)
1/6/19 2:14:50 PM: Sleeping (5 seconds left)
1/6/19 2:14:51 PM: Sleeping (4 seconds left)
1/6/19 2:14:52 PM: Sleeping (3 seconds left)
1/6/19 2:14:52 PM: ApplicationStopped called
```

So ASP.NET Core is not willing to wait infinitely for the pending requests to finish, after some timeout period it forcefully terminates the application, regardless of the requests in flight. (And this causes a failed request, the `HttpClient` I was using to poll threw an exception.)

The default timeout is [5 seconds](https://github.com/aspnet/AspNetCore/blob/master/src/Hosting/Hosting/src/Internal/WebHostOptions.cs#L70), but we can increase it by calling the [`UseShutdownTimeout()`](https://github.com/aspnet/AspNetCore/blob/d852e10293c0fbd3dfbf82be455c2cde683ec0de/src/Hosting/Abstractions/src/HostingAbstractionsWebHostBuilderExtensions.cs#L179) extension method on the `WebHostBuilder` in our `Program.Main()` method.

## Use this in Kubernetes

Based on the above, it seems that we're good to go without implementing anything custom. Kubernetes sends a `TERM` signal before it kills our pods, and is willing to wait 30 seconds. And ASP.NET Core doesn't exit until the pending requests are finished. And if the 5 second default timeout is not enough, because we anticipate having slower requests (which is not commonplace in REST APIs anyway), then we can increase it in `Program.Main`.

There is an issue though. Kubernetes sending `TERM`, and removing the pod from the service Endpoint pool happens in parallel. So the following order of events can happen.

1. Kubernetes sends the `TERM` signal.
2. Let's say there are no pending requests, so our container terminates immediately.
3. The pod has not been removed from the service endpoint pool yet, so it tries to send a request to the terminated pod, which will fail.

First let's verify if we indeed receive more incoming requests after `TERM`. To test this, I added a 10 second sleep to our `ApplicationStopping` handler.

```csharp
appLifetime.ApplicationStopping.Register(() =>
{
    Log("ApplicationStopping called, sleeping for 10s");
    Thread.Sleep(10000);
});
```

Then I deployed two pods of the application, and kept polling the quick endpoint through a LoadBalancer service, then at some point stopped one of the pods by executing `kubectl delete pod`.

This was the output of the pod:

```bash
01/06/2019 14:40:44: Incoming request at /, State: Running
01/06/2019 14:40:45: Incoming request at /, State: Running
Application is shutting down...
01/06/2019 14:40:45: ApplicationStopping called, sleeping for 10s
01/06/2019 14:40:46: Incoming request at /, State: AfterSigterm
01/06/2019 14:40:47: Incoming request at /, State: AfterSigterm
01/06/2019 14:40:48: Incoming request at /, State: AfterSigterm
01/06/2019 14:40:49: Incoming request at /, State: AfterSigterm
01/06/2019 14:40:51: Incoming request at /, State: AfterSigterm
01/06/2019 14:40:53: Incoming request at /, State: AfterSigterm
01/06/2019 14:40:55: ApplicationStopped called
```

This clearly shows that Kubernetes doesn't wait for the `LoadBalancer` endpoints to be updated before it sends the `TERM` signal (possibly causing the application to terminate), so it is very much possible that we will keep receiving some requests after `TERM`.

If we remove the 10 second sleep from the `TERM` handler, and execute the same test, we'll see the following output.

```bash
01/06/2019 14:36:07: Incoming request at /, State: Running
01/06/2019 14:36:07: Incoming request at /, State: Running
01/06/2019 14:36:07: Incoming request at /, State: Running
Application is shutting down...
01/06/2019 14:36:08: ApplicationStopped called
01/06/2019 14:36:08: ApplicationStopping called
```

At the time of receiving the `TERM`, there happened to be no pending requests, so the process exited immediately.  
And this is what I've seen in the little console tool doing the polling:

```bash
2019-01-06 2:36:08 PM: Successful request
2019-01-06 2:36:09 PM: Successful request
2019-01-06 2:36:11 PM: Error! Exception: The operation was canceled.
2019-01-06 2:36:11 PM: Successful request
2019-01-06 2:36:13 PM: Error! Exception: The operation was canceled.
2019-01-06 2:36:13 PM: Successful request
```

By chance, there were 2 request which were still sent to the old pod, in which the container has already stopped, thus the requests failed.  
I repeated this test a couple of times, and this is happening quite randomly. Sometime there were no failed requests, other times there were a couple of them. I guess it depends on how quickly the Endpoints of the LoadBalancer gets updated. Sometimes that happens early enough to prevent failed requests, sometimes it doesn't.

This means that the default behavior we get when we run an ASP.NET Core container in Kubernetes is not the best, it can result in a couple of failed requests, not just when we deploy a new service version, but also every time a pod is stopped, for any reason.

## How quickly does the LB get updated?

To see how quickly the endpoints of the LB get updated, let's prolong the grace period close to the maximum 30 seconds, and test how long the pod is still receiving requests.

We can keep the pod living for almost the default 30 second grace period by increasing the sleep duration in `ApplicationStopping` to 25 seconds (Not 30, because then the container might get forcefully killed, and we wouldn't observe the `ApplicationStopped` event). (Alternatively, we could add a `/bin/sleep 25` preStop hook, but the problem with that is that it doesn't show up in the container logs, so it's harder to follow what's happening.)

This was the result.

```bash
01/06/2019 15:36:26: Incoming request at /, State: Running
01/06/2019 15:36:26: Incoming request at /, State: Running
01/06/2019 15:36:27: Incoming request at /, State: Running
Application is shutting down...
01/06/2019 15:36:27: ApplicationStopping called, sleeping for 25s
01/06/2019 15:36:27: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:27: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:28: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:28: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:28: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:29: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:29: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:30: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:31: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:31: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:31: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:32: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:33: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:33: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:33: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:34: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:34: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:35: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:35: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:36: Incoming request at /, State: AfterSigterm
01/06/2019 15:36:52: ApplicationStopped called
```

Based on this we can see that it takes approximately 10 seconds until the pod is removed from the endpoint pool, until then it keeps receiving requests.  
I repeated the test a couple of times, and the time needed until the requests stopped coming in was always around 10 seconds.

# Conclusion and future work

After learning all these details, the question is simple: what should we do as a maintainer of an ASP.NET Core application to avoid losing some requests on every pod termination?

I haven't seen any official recommendation on this topic, so this is only my conclusion. Based on all the things I've described in this post, I don't think there is any "sophisticated" solution to this. We don't have to implement any smart logic which would wait until the pending requests are drained, that's handled by the framework out of the box.

The only thing we have to take care of is to make sure the container doesn't terminate until the Endpoints of our services are updated. And the only way I could find to do this was to sleep for an arbitrary amount of time.  
Since it seems that it takes around 10 seconds for the service Endpoints to get updated, we can sleep for—let's say—20 seconds, and then with the 30 seconds default grace period that still leaves 10 seconds for the termination of the application process.

We can implement this sleeping either with a `preStop` hook:

```yaml
  containers:
  - name: containername
    lifecycle:
      preStop:
        exec:
          command: [ "/bin/sleep", "20" ]
```

Or—in case of ASP.NET Core—we can do it in the `ApplicationStopping` event.

```csharp
    appLifetime.ApplicationStopping.Register(() =>
    {
        Log("ApplicationStopping called, sleeping for 20s");
        Thread.Sleep(20000);
    });
```

Doing it in the `preStop` hook probably makes it easier to automate for every service we host.  
On the other hand, doing it in our C# code gives us more options to do some custom logging or metric publishing to be able to collect some information about how the termination behaves in production. (For example it would be interesting to record the time of termination, and the time of the last request we receive, to have an estimate of how long it can take until production pods stop receiving requests.)

I have uploaded the code of both the test service, and the console test tool I used for this experiment to [this repository](https://github.com/markvincze/K8sGracefulShutdownTester).

What would still be interesting to test is how this behaves with other networking solutions. I've only did the tests with a `service` of type `LoadBalancer`, but I'd be interested to see how a `ClusterIP` service, or an `ingress` behaves. And doing the same experiment on different clouds, such as Amazon or Azure, or on a self-hosted Kubernetes cluster could also give valuable insights.

If you have additional information on this topic, or just any feedback, I'd love to hear about it in the comments.
