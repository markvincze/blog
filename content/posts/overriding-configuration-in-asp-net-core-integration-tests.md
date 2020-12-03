+++
title = "Overriding configuration in ASP.NET Core integration tests"
slug = "overriding-configuration-in-asp-net-core-integration-tests"
description = "This post gives an overview of the various ways to override configuration values in ASP.NET Core integration tests."
date = "2020-02-24T23:25:09.0000000"
tags = ["asp.net-core", "testing", "integration-testing"]
ghostCommentId = "ghost-5e545aeea26b5f5ce4856c6a"
+++

The pluggable and modular nature of ASP.NET Core made integration testing a much more accessible and convenient tool than it was in classic .NET. We can spin up our whole application with the full ASP.NET middleware pipeline in-process, with a couple of lines of code, and send HTTP requests to it for testing purposes.

During the integration test, we often want to use different application configuration than what we have in the `appsettings.json` in our repository, which is usually tailored for local development. In the integration test, we might want to do the following.

 - Connect to a different database.
 - Replace the URL of an upstream dependency with a mock or stub.
 - Disable certain features which might not be needed, or don't work in the test environment.

There are various different ways to override the configuration for the duration of our integration tests. The approaches have different caveats you have to look out for, which I always tend to forget, and have to look up in old projects. Hence I decided to write this down in a post for future reference.

# The project setup

First I'm going to quickly describe what my project setup looks like. For the web and the test project setup I'm mostly following the patterns provided by the built-in `dotnet` CLI templates, so you won't see anything surprising here. I tend to prefer trimming down the default generated skeletons even further, to contain only the minimal amount of necessary setup code.

## The web project

In this example I'll show a very basic and simple project setup for an MVC application, which will have one Json API endpoint. The integration testing strategy would be the same for more complicated projects as well, even the ones also containing HTML endpoints and `cshtml` files.

In the `Program` class I like using an empty new `HostBuilder()` instance instead of the built-in `Host.CreateDefaultBuilder(args)` helper, just in order to have all the setup code explicitly visible in the repository. But the testing approach shown here works the same way if you're using `Host.CreateDefaultBuilder(args)`.

```csharp
    public class Program
    {
        public static void Main(string[] args)
        {
            CreateHostBuilder(args).Build().Run();
        }

        public static IHostBuilder CreateHostBuilder(string[] args) =>
            new HostBuilder()
                .ConfigureAppConfiguration((context, config) =>
                {
                    config
                        .AddJsonFile("appsettings.json")
                        .AddEnvironmentVariables();
                })
                .ConfigureWebHostDefaults(webBuilder =>
                {
                    webBuilder
                        .UseStartup<Startup>()
                        .UseUrls($"http://*:5000/");
                });
    }
```

The `Startup` is a very minimal MVC setup. The only additional configuration is registering the options type `DemoOptions`, which I'll use to demonstrate the overriding of the configuration.

*(In this post I'm not covering the details of using the Options pattern for configuration, you can find the details [in the documentation](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/configuration/options).)*

```csharp
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            this.configuration = configuration;
        }

        private readonly IConfiguration configuration;

        public void ConfigureServices(IServiceCollection services)
        {
            services.Configure<DemoOptions>(configuration.GetSection("Demo"));

            services.AddRouting();
            services.AddControllers();
        }

        public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
        {
            app.UseRouting();
            app.UseEndpoints(opt =>
            {
                opt.MapControllers();
            });
        }
    }
```

This is an MVC setup, but the testing approach would work the same way if we were using Endpoint routing, or just custom middlewares.

The `DemoOptions` type used to demonstrate the Options pattern is a simple POCO with one property.

```csharp
    public class DemoOptions
    {
        public string OptionsConfigProperty { get; set; }
    }
```

Given that overriding the configuration in the tests will be different for values that we bind to an Options type, and for values that we access directly via the `IConfiguration`, we have one example for both in the `appsettings.json`.

```json
{
  "Demo": {
    "OptionsConfigProperty": "OptionsConfigProperty_Default"
  },
  "RawConfigProperty": "RawConfigProperty_Default"
}
```

And we have one controller with a single endpoint, in which we retrieve and return these configuration values, just so that we can test how they are overridden.

```csharp
    [Route("[controller]")]
    public class DemoController : Controller
    {
        private readonly IOptions<DemoOptions> demoOptions;

        private readonly IConfiguration configurationRoot;

        public DemoController(IOptions<DemoOptions> demoOptions, IConfiguration configurationRoot)
        {
            this.demoOptions = demoOptions;
            this.configurationRoot = configurationRoot;
        }

        [HttpGet]
        public IActionResult Get()
        {
            return Ok(
                new
                {
                    OptionsConfigProperty = demoOptions.Value.OptionsConfigProperty,
                    RawConfigProperty = configurationRoot["RawConfigProperty"]
                });
        }
    }
```

If we call our `/demo` endpoint, it returns the values of the configuration properties we've set in the `appsettings.json`.

```json
{
    "optionsConfigProperty": "OptionsConfigProperty_Default",
    "rawConfigProperty": "RawConfigProperty_Default"
}
```

## The integration test project

The details of integration testing with ASP.NET Core can be found [in the documentation](https://docs.microsoft.com/en-us/aspnet/core/test/integration-tests). Here I'll show only the parts relevant for this post.

In most approaches (except when using a dedicated `appsettings.json` file in our test project) I'll use the `WebApplicationFactory<T>` helper provided by the `Microsoft.AspNetCore.Mvc.Testing` package to start our application under test. With this approach a basic test looks like this.

```csharp
    public class SimpleTest
    {
        private readonly WebApplicationFactory<Startup> factory = new WebApplicationFactory<Startup>();

        [Fact]
        public async Task SimpleTestCase()
        {
            var client = factory.CreateClient();

            var response = await client.GetAsync("/example");

            // Do the verifications
        }
    }
```

In some of the approaches I'll show you we'll need to customize the factory with some extra calls on the `IWebHostBuilder` (and this is useful for other purposes as well, for example injecting some mocked services into DI). One important capability is the `ConfigureTestServices` extension method, with which we can register an extra lambda in which we can further customize the setup of our we application, and the extension makes it sure that our lambda will run *after* the `Startup.ConfigureServices()` method has been executed.

```csharp
public class SimpleTest
{
    private readonly WebApplicationFactory<Startup> factory;

    public SimpleTest()
    {
        factory = new WebApplicationFactory<Startup>().WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                // We can further customize our application setup here.
            });
        });
    }

    [Fact]
    public async Task SimpleTestCase()
    {
        // ...
    }
}
```

If we want to do the same customization in multiple places, we can also create a custom derived factory type, and use it everywhere.

```csharp
public class CustomWebApplicationFactory<TStartup> : WebApplicationFactory<TStartup> where TStartup : class
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureTestServices(services => 
        {
            // We can further customize our application setup here.
        });
    }
}

public class SimpleTest
{
    private readonly CustomWebApplicationFactory<Startup> factory = new CustomWebApplicationFactory<Startup>();

    [Fact]
    public async Task SimpleTestCase()
    {
        // ...
    }
}
```

# Overriding our configuration

Now comes the main part of the post, where I'll show the various approaches to override our configuration values for the execution of the integration tests.

## Override the property of an Options type

Changing the value of a property on a configuration type using the Options pattern is very straightforward. We can add an extra `Configure()` call to the lambda we're passing to `ConfigureTestServices()`, where we set the property to the desired new value.

```csharp
    public class OverrideOptionsProperty
    {
        private readonly WebApplicationFactory<Startup> factory;

        public OverrideOptionsProperty()
        {
            factory = new WebApplicationFactory<Startup>().WithWebHostBuilder(builder =>
            {
                builder.ConfigureTestServices(services =>
                {
                    services.Configure<DemoOptions>(opts =>
                    {
                        opts.OptionsConfigProperty = "OverriddenValue";
                    });
                });
            });
        }

        [Fact]
        public async Task TestCase()
        {
            // ...
        }
    }
```

This is a very preferable approach, because it's simple and straightforward. And another benefit is that we're setting the actual property of our POCO in a lambda, so we're not depending on having to specify the name of the overridden property in a string, in which we could make a typo without the compiler being able to verify it (which will be the case for all other approaches).  
But this can only be used if the configuration we want to override is used with the Options pattern, and not when the configuration value is accessed directly via `IConfiguration`.  
This is another reason to prefer using the Options pattern whenever possible.

The other 3 approaches shown here will all work for the case when we access our configuration value directly via `IConfiguration`.

## Add an additional in-memory collection

When we customize the setup of our application, we can register an extra in-memory collection on our configuration builder, which will be applied on top of all the configured providers, so we can use this to override any value.

```csharp
    public class OverridePropertyWithInMemoryCollection
    {
        private readonly WebApplicationFactory<Startup> factory;

        public OverridePropertyWithInMemoryCollection()
        {
            factory = new WebApplicationFactory<Startup>().WithWebHostBuilder(builder =>
                {
                    builder.ConfigureAppConfiguration((context, configBuilder) =>
                    {
                        configBuilder.AddInMemoryCollection(
                            new Dictionary<string, string>
                            {
                                ["RawConfigProperty"] = "OverriddenValue"
                            });
                    });
                });
        }

        [Fact]
        public async Task TestCase()
        {
            // ...
        }
    }
```

## Set the config values via environment variables

If we use the default configuration setup with the `WebApplicationFactory<T>`, then the environment variable based configuration provider is registered in our configuration pipeline by default. This means that we can easily override configuration values by setting environment variables.

```csharp
    public class OverridePropertyWithEnvVar : IDisposable
    {
        private readonly WebApplicationFactory<Startup> factory;

        public OverridePropertyWithEnvVar()
        {
            Environment.SetEnvironmentVariable("RawConfigProperty", "OverriddenValue");
            factory = new WebApplicationFactory<Startup>();
        }

        [Fact]
        public async Task TestCase()
        {
            // ...
        }
        
        public void Dispose()
        {
            Environment.SetEnvironmentVariable("RawConfigProperty", "");
            factory?.Dispose();
        }
    }
```

An important gotcha is that you have to implement `IDisposable`, and clear the environment variable after the test ran, otherwise it could affect subsequent tests.  
And in order for this to be reliable, we have to disable parallel test execution, otherwise tests running at the same time could affect each other. In xUnit, we can disable parallel execution by adding the following attribute to our test project.

```csharp
[assembly: CollectionBehavior(DisableTestParallelization = true)]
```

## Add a dedicated `appsettings.json` to our test project

The last approach I am going to show is adding a dedicated `appsettings.json` file to our test project, in which we can freely customize the configuration.  
We have to set the file's Build Action to be Content, and set the "Copy to Output Directory" to "Copy if newer".

One important thing is that with this approach we cannot use the `WebApplicationFactory<T>` helper, because that conveniently sets the [content root path](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/?view=aspnetcore-3.1&tabs=windows#content-root) to the Web project folder. Which is usually preferable, but in this case it would cause our custom `appsettings.json` file to not being picked up.

Thus we have to use the lower-level `TestServer` class, which doesn't adjust the content root path.

```csharp
    public class OverridePropertyWithAppsettingsJson
    {
        private readonly TestServer testServer;

        public OverridePropertyWithAppsettingsJson()
        {
            testServer = new TestServer(new WebHostBuilder()
                .ConfigureAppConfiguration((context, builder) =>
                {
                    builder.AddJsonFile("appsettings.json");
                })
                .UseStartup<Startup>());
        }

        [Fact]
        public async Task TestCase()
        {
            // ...
        }
    }
```

# Summary

In this post we've seen some different ways to override configuration values in our integration tests.  
My preferred approach is the first one, customizing the property of our Options type with an extra `Configure<TOptions>()` call. But this can only be applied if we use the Options pattern.  
Otherwise I'd recommend registering the extra in-memory collection—simply because the other two approaches have some extra quirks we'll have to work around.

I've uploaded a full sample illustrating all the 4 approaches to [this repository](https://github.com/markvincze/AspNetCoreIntegrationTestConfig).

In my experience integration testing in ASP.NET Core is a great and versatile tool to protect ourselves against bugs and regression issues, so I highly recommend using it, especially given how easy and convenient it became in Core compared to classic ASP.NET. And I hope this post will help with further customizing your tests, and making them even more reliable.
