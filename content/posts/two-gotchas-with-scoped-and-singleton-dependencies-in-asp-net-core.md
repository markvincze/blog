+++
title = "Two gotchas with scoped and singleton dependencies in ASP.NET Core"
slug = "two-gotchas-with-scoped-and-singleton-dependencies-in-asp-net-core"
description = "Two possible problems (and their solutions) we can run into when registering objects with various lifecycles with the DI container of ASP.NET Core."
date = "2017-04-17T14:31:27.0000000"
tags = ["c#", "asp.net-core", "dependency-injection"]
ghostCommentId = "ghost-35"
+++

With ASP.NET Core a new built-in lightweight Dependency Injection framework was introduced in the `Microsoft.Extensions.DependencyInjection` package, thus in ASP.NET Core applications we don't necessarily need an external library such as Ninject or Unity to do DI, we can simply use the built-in package (which—although being framework-agnostic—plays really nicely with ASP.NET Core).
Its feature set is rather simple compared to other more full-blown DI frameworks, but it gets the job done in most applications.

When we register our dependencies, we can choose from three different lifecycle settings.

 - **Transient**: A new instance of the dependency is going to be created upon every retrieval.
 - **Scoped**: One instance of the dependency is going to be used per scope. In ASP.NET this means that one instance is going to be created per HTTP request. This comes handy if our class depends on some property of the `HttpContext`.
 - **Singleton**: Only one single instance of the dependency is going to be created and used for all retrievals.

I'll introduce two gotchas related to the lifecycle of our dependencies that we can run into, and describe how we can avoid them.

# Depending on a scoped dependency from a singleton

If we have a DI graph in which classes with various lifecycles depending on each other, we can run into an issue, that might be tricky to troubleshoot if we don't know where to look for the problem.

Assume the following setup.

We have an `IFoo` interface registered as a *singleton*, which depends on `IBar`, which is registered as *scoped* (for example because it depends on the current HTTP request).
And from our controller (which we can consider *scoped*, since it is created per request), we require `IFoo`.

![Class diagram illustrating the erroneous setup.](/images/2017/04/aspnetcore_di_issue.png)

The problem with this setup is that the first time we retrieve `IFoo`, a new instance of `Foo` and transitively `Bar` is going to be created. Since `Foo` is singleton, no new instances of it are going to be created on further retrievals, the single instance created at first will always be retrieved.
But this means—since the reference to `IBar` is stored by the instance of `Foo`—that the singleton `Foo` is going to "capture" the scoped `IBar`, so no new instance of `Bar` is going to be created either, in spite of it being registered as *scoped*.

This is a bug in our application, since if we retrieve `IFoo` in a subsequent request, we would need a new instance of `IBar` to be created, because it might depend on the context of the HTTP request.

## Example

Let's illustrate this with an example. We implement an api with MVC, and we want to log some messages, prefixing every log message with the path of the current request.
To do this we define the following interface.

```csharp
public interface ISmartLogger
{
    void Log(string message);
}
```

And write its implementation.

```csharp
public class SmartLogger : ISmartLogger
{
    private readonly string requestPath;

    public SmartLogger(IHttpContextAccessor httpContextAccessor)
    {
        requestPath = httpContextAccessor?.HttpContext?.Request?.Path.ToString() ?? "No path";
    }

    public void Log(string message)
    {
        Console.WriteLine("{0}: {1}", requestPath, message);
    }
}
```

The implementation is very straightforward. We depend on `IHttpContextAccessor` to access the `HttpContext`, and we save the path of the request (if there is any).
(**Note**: of course we don't necessarily have to do this in the constructor, we could retrieve the path on the fly in the `Log` method, but the approach I've chosen is important to illustrate the issue.)

Let's say we have a single controller, `PeopleController`, in which we depend on our `ISmartLogger`, and log some messages.

```csharp
[Route("[controller]")]
public class PeopleController : Controller
{
    private readonly ISmartLogger smartLogger;
    
    public PeopleController(ISmartLogger smartLogger)
    {
        this.smartLogger = smartLogger;
    }

    [HttpGet("person1")]
    public string Person1()
    {
        smartLogger.Log("Retrieving person 1");
        return "Jane Smith";
    }

    [HttpGet("person2")]
    public string Person2()
    {
        smartLogger.Log("Retrieving person 2");
        return "John Doe";
    }
}
```

The last thing we have to do is to register our logger in `Startup.ConfigureService()`. Since we retrieve the request path in the constructor of our logger, we have to register the service as *scoped*, so that a new instance is created on every request.

```csharp
public void ConfigureServices(IServiceCollection services)
{
    services.AddMvc();
    services.AddSingleton<IHttpContextAccessor, HttpContextAccessor>();
    services.AddScoped<ISmartLogger, SmartLogger>();
}
```

If our start up the application and do a couple of requests:

```bash
$ curl http://localhost:5000/people/person1
Jane Smith
$ curl http://localhost:5000/people/person2
John Doe
$ curl http://localhost:5000/people/person1
Jane Smith
```

Then in the terminal of the web app we can see that our log messages correctly contain the request path.

```bash
/people/person1: Retrieving person 1
/people/person2: Retrieving person 2
/people/person1: Retrieving person 1
```

So far everything is good. But let's say later we decide to extract the retrieval of the people to a separate service, called `PeopleService`.

```csharp
public class PeopleService : IPeopleService
{
    private readonly ISmartLogger smartLogger;

    public PeopleService(ISmartLogger smartLogger)
    {
        this.smartLogger = smartLogger;
    }

    public string GetPerson1()
    {
        smartLogger.Log("Retrieving person 1");
        return "Jane Smith";
    }

    public string GetPerson2()
    {
        smartLogger.Log("Retrieving person 2");
        return "John Doe";
    }
}
```

And we also change our controller to depend on this service.

```csharp
[Route("[controller]")]
public class PeopleController : Controller
{
    private readonly IPeopleService peopleService;

    public PeopleController(IPeopleService peopleService)
    {
        this.peopleService = peopleService;
    }

    [HttpGet("person1")]
    public string Person1()
    {
        return peopleService.GetPerson1();
    }

    [HttpGet("person2")]
    public string Person2()
    {
        return peopleService.GetPerson2();
    }
}
```

Note that we moved the logging from the controller to the service.
To make this work, we have to also register `IPeopleService` as a dependency.
Since `PeopleService` itself is not concerned about the current HTTP request at all, it seems to make sense to register it as a singleton. **This is wrong** and it causes a bug. Let's see what happens if we do this.

```csharp
public void ConfigureServices(IServiceCollection services)
{
    services.AddMvc();
    services.AddSingleton<IHttpContextAccessor, HttpContextAccessor>();
    services.AddScoped<ISmartLogger, SmartLogger>();
    services.AddSingleton<IPeopleService, PeopleService>();
}
```

Now if we start the server and issue the same three requests.

```bash
$ curl http://localhost:5000/people/person1
Jane Smith
$ curl http://localhost:5000/people/person2
John Doe
$ curl http://localhost:5000/people/person1
Jane Smith
```

Then this is what we'll see in the terminal of the server.

```bash
/people/person1: Retrieving person 1
/people/person1: Retrieving person 2
/people/person1: Retrieving person 1
```

Notice that the request path in the second log message is incorrect. The reason for this is that `PeopleService` is a singleton instance, and it "captures" the `SmartLogger` instantiated for the first request, so on all subsequent `Log()` calls (done from `PeopleService`) till the end of time, the only request path we'll see in the logs is the one retrieved upon the first request, `/people/person1`.

The solution is simple, we just have to change the lifecycle of the `IPeopleService` dependency to be scoped (or transient would also work, but it would do more instantiations than necessary):

```csharp
services.AddScoped<IPeopleService, PeopleService>();
```
In general, we must not depend on a transient or scoped dependency (either directly or transitively) from a singleton, and we must not depend on a transient dependency from a scoped object.

In a more complicated application it might seem troublesome to manually look through our whole DI graph to figure out where we might have made this mistake. Luckily in the 2.0 version of ASP.NET Core this is going to be validated by the DI framework, and we'll get an exception if we mess it up (this change cannot be done in the 1.* versions, since it'd be a breaking change).

# Inject non-singleton dependencies into middlewares

The second issue I'd like to describe can happen when we try to inject a non-singleton dependency into a middleware. Let's see an example right away.

We implement a custom middleware, in which we want to use the previously implemented `SmartLogger`. We accept `ISmartLogger` as a constructor parameter.

```csharp
public class CustomMiddleware
{
    private readonly ISmartLogger smartLogger;

    public CustomMiddleware(RequestDelegate next, ISmartLogger smartLogger)
    {
        this.smartLogger = smartLogger;
    }

    public async Task Invoke(HttpContext context)
    {
        smartLogger.Log("Custom middleware called");
        await context.Response.WriteAsync("Custom response");
    }
}
```

Change `Startup.Configure` to use this middleware instead of the MVC router.

```csharp
public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory)
{
    app.UseMiddleware<CustomMiddleware>();
    // app.UseMvc();
}
```

If we start the server and send two test requests:

```bash
$ curl http://localhost:5000/foo
Custom response
$ curl http://localhost:5000/bar
Custom response
```

We'll see the following output in the terminal of the server.

```bash
No path: Custom middleware called
No path: Custom middleware called
```

Something is wrong, since our logger is not printing the path of the requests.
The reason for this is that only one single instance of the middleware gets created, and it's instantiated when the pipeline is set up, prior to the first request, so the `HttpContext` is not even populated yet.

Since only one instance of the middleware is created, the injection through the constructor is not going to work for dependencies which are not singletons.

We can easily fix this. We can accept dependencies not just in the constructor of the middleware, but also in the `Invoke` method, so we can fix the problem by modifying the class the following way.

```csharp
public class CustomMiddleware
{
    public CustomMiddleware(RequestDelegate next)
    {
    }

    public async Task Invoke(HttpContext context, ISmartLogger smartLogger)
    {
        smartLogger.Log("Custom middleware called");
        await context.Response.WriteAsync("Custom response");
    }
}
```

These two problems are pretty easy to run into, but luckily they are not difficult to fix if you know what to look for. I hope this post we'll save you some time when troubleshooting these DI issues in ASP.NET Core.
