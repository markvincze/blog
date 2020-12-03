+++
title = "Tear down your ASP.NET Core api between integration tests"
slug = "tear-down-your-asp-net-core-api-between-integration-tests"
description = "Static state in an ASP.NET Core application can cause problems when running subsequent integration tests. In this post we take a look at how to solve this."
date = "2017-06-21T20:20:00.0000000"
tags = ["c#", "couchbase", "asp.net-core", "testing", "integration-testing", "quartz.net"]
ghostCommentId = "ghost-39"
+++

The way to write integration tests for ASP.NET applications has been made much easier with the advent of ASP.NET Core. This is mainly due to the programming model becoming super modular, which means that it is really easy to spin up an instance of our whole web application for testing purposes and start sending HTTP requests to it from a simple unit test.

The following code illustrates a unit test method, which starts up an ASP.NET Core api, sends an HTTP request to it, and verifies the response, assuming that the api returns the string `"Hello World!"` on the route `/api/hello`.

```csharp
[Fact]
public async Task Hello_Called_HelloWorldReturned()
{
    using (var server = new TestServer(new WebHostBuilder().UseStartup<Startup>()))
    using (var client = server.CreateClient())
    {
        var response = await client.GetAsync("/api/hello");
        var responseString = await response.Content.ReadAsStringAsync();
        
        Assert.Equal("Hello World!", responseString);
    }
}
```

Keep in mind that the above test is not a usual unit test. Nothing is stubbed or mocked, the whole web application is started up, so this is a great tool to verify that our dependency injection, configuration, routing works properly (which we would typically not cover with unit tests).

There is an important thing we have to watch out for, which can cause us some problems, and initially, it might be tricky to figure out why.

# The problem

There are multiple ways to encounter this issue, one of the ways I came across this was when I used Quartz.NET in one of our projects, which is a library for scheduling periodically running background tasks.

This is an example of starting up a background task in our `Startup` class which prints a message to the screen every 5 seconds.

```csharp
public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory)
{
    StartBackgroundTask().Wait();

    ...
}

private async Task StartBackgroundTask()
{
    StdSchedulerFactory factory = new StdSchedulerFactory();
    var scheduler = await factory.GetScheduler();

    await scheduler.Start();

    IJobDetail job = JobBuilder.Create<DummyJob>()
        .WithIdentity("job1", "group1")
        .Build();

    ITrigger trigger = TriggerBuilder.Create()
        .WithIdentity("trigger1", "group1")
        .StartNow()
        .WithSimpleSchedule(x => x
            .WithIntervalInSeconds(5)
            .RepeatForever())
        .Build();

    await scheduler.ScheduleJob(job, trigger);
}

public class DummyJob : IJob
{
    public Task Execute(IJobExecutionContext context)
    {
        Console.WriteLine("Ping!");
        
        return Task.CompletedTask;
    }
}
```

Then let's imagine we have two endpoints (they are not really important in this example), `/api/hello` and `/api/dummy`, for which we implement these tests.

```csharp
public class ApiTests
{
    [Fact]
    public async Task Hello_Called_HelloWorldReturned()
    {
        using (var server = new TestServer(new WebHostBuilder().UseStartup<Startup>()))
        using (var client = server.CreateClient())
        {
            var response = await client.GetAsync("/api/hello");
            var responseString = await response.Content.ReadAsStringAsync();
            
            Assert.Equal("Hello World!", responseString);
        }
    }

    [Fact]
    public async Task Dummy_Called_FooReturned()
    {
        using (var server = new TestServer(new WebHostBuilder().UseStartup<Startup>()))
        using (var client = server.CreateClient())
        {
            var response = await client.GetAsync("/api/dummy");
            var responseString = await response.Content.ReadAsStringAsync();
            
            Assert.Equal("Foo", responseString);
        }
    }
}
```

If we execute our tests with `dotnet test`, we'll get the following error:

```plain
System.AggregateException : One or more errors occurred. (Unable to store Job: 'group1.job1', because one already exists with this identification.)
---- Quartz.ObjectAlreadyExistsException : Unable to store Job: 'group1.job1', because one already exists with this identification.
```

The reason for this exception is that even though we create a completely new Job and Factory in our `Startup`, apparently Quartz is storing some data related to these jobs statically. And we start a completely new `TestServer` in every test, but because everything happens in the same process, if the first test saves something in a static field, that will affect the subsequent tests.

One thing I tried to solve this was to add an attribute to disable XUnit parallel test execution.

```csharp
[assembly: CollectionBehavior(DisableTestParallelization = true)]
```

But this is not enough, even if the execution is not happening in parallel, the tests can trip each other up.

# The solution

The fix is to properly tear down any library or component when our application stops. This can be done by injecting `IApplicationLifetime` into out `Configure` method, and registering a handler to the `ApplicationStopped` event, and tearing down whatever library we're using, in this case, the scheduler of Quartz.NET.

```csharp
public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory, IApplicationLifetime appLifetime)
{
    StartBackgroundTask(appLifetime).Wait();

    ...
}

private async Task StartBackgroundTask(IApplicationLifetime appLifetime)
{
    StdSchedulerFactory factory = new StdSchedulerFactory();
    var scheduler = await factory.GetScheduler();

    await scheduler.Start();
    
    // Register a handler which shuts the scheduler down when the api is stopped.
    appLifetime.ApplicationStopped.Register(() => scheduler.Shutdown().Wait());
    
    ...
}
```

With this simple change, our tests are successful.

So far I encountered this problem with the above described Quartz library, and the SDK of Couchbase (using the `ClusterHelper` class, which does static connection pooling), but I think there are many more libraries out there which can cause this issue, and we might run into problems with our own code too if we are storing data in static fields.

Of course, the actual code we have to write in the `ApplicationStopped` handler varies from library to library, in the case of Quartz we had to call `scheduler.Shutdown()`, with the Couchbase SDK I had to do `ClusterHelper.Close()`, in your scenario it might be something else, that has to be figured out for the specific library causing the issue.

If you encounter the same issue with any other library, I'd appreciate it if you could leave a comment with the way it had to be shut down to fix this problem, so that we can save time for anybody else looking for a solution.
