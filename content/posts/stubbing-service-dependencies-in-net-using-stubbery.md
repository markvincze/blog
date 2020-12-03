+++
title = "Stubbing service dependencies in .NET using Stubbery"
slug = "stubbing-service-dependencies-in-net-using-stubbery"
description = "Stubbery is a library for creating and running Api stubs in .NET. The post shows how it can be used to stub service dependencies during integration tests."
date = "2016-06-12T15:27:28.0000000"
tags = ["asp.net", ".net", ".net-core", "asp.net-core", "testing", "integration-testing"]
ghostCommentId = "ghost-20"
+++

# Introduction

When writing integration tests for a service (especially if we are running a long, end-to-end test), it often causes a problem that the external dependencies of our service fail.

Let's say we have a service handling customer payments and the actual payments are handled by an external provider.

![Diagram illustrating integration testing an api with an external dependency.](/images/2016/06/payment-integration-test-1.png)

Very often, we cannot use the actual production system of our external dependency. For example, when we want to test payments, we cannot make real purchases every time we run our integration test suite.

Thus, we resort to using the test system of our dependency (if there is one).  
The problem with this is that the test system of any provider is usually not 100% reliable. There will be occasional downtimes, performance problems, or other problems due to configuration changes or general tinkering.

Because of this, from time to time our tests will fail due to the failure of the dependency.
This means that if we have a substantial number of tests in our suite, one or two of them will fail in every run, which will cause our test suite to be always red.

When I first faced this problem I was surprised to see there was no .NET library for programmatically creating Api stubs, so I decided to  create a simple library for this purpose.

# Stubbery

[Stubbery](http://markvincze.github.io/Stubbery/) is a library with which we can simply configure and start a web server that responds on particular routes with the configured results. It supports .NET Core and the full .NET Framework up from .NET 4.5.1.

## How to use

The central class of the library is `ApiStub`. In order to start a new server we have to create an instance of `ApiStub`, set up some routes using the methods `Get`, `Post`, `Put` and `Delete`, and start the server by calling `Start`.

The server listens on localhost on a randomly picked free port. The full address is returned by the `Address` property.

After usage the server should be stopped to free up the TCP port. This can be done by calling `Dispose` (or using the stub in a `using` block).

### Basic usage

```csharp
using (var stub = new ApiStub())
{
    stub.Get(
        "/testget",
        (req, args) => "testresponse");

    stub.Start();

    var result = await httpClient.GetAsync(new UriBuilder(new Uri(stub.Address)) { Path = "/testget" }.Uri);

    // resultString will contain "testresponse"
    var resultString = await result.Content.ReadAsStringAsync();
}
```

More examples can be found on the [GitHub page](https://github.com/markvincze/Stubbery).

# End to end example

## The dependency

Let's say we have an endpoint in our Api that depends on getting the name of an UK county based on a postcode, for which we are using the [Postcodes.io](http://postcodes.io/) api.

The endpoint I'm interested in returns the details of a certain postcode. Given the request

```plain
GET http://api.postcodes.io/postcodes/OX49%205NU
```

it returns the details in the form:

```javascript
{
    "status": 200,
    "result": {
        "postcode": "OX49 5NU",
        "admin_county": "Oxfordshire"
        ...
    }
}
```

This is the dependency we'd like to replace in our test with a stub.

## The api under test

Our own Api is an ASP.NET Core application, which implements an endpoint that returns the name of the county. Given the request

```plain
GET http://our-own-api/countyname/OX49%205NU
```

it returns the name of the county as a raw string:

```plain
Oxfordshire
```

Internally, our API is calling out to `postcodes.io` to get the details of the county. If our application is calling an external dependency, it's introducing the following problems if we want to implement integration tests.

 - We have no control over the external API, it might be down any time due to an outage or maintanance, which would break our integration tests.
 - The exact data returned by our dependency might change over time. In the case of `postcodes.io`, this change will be infrequent, only when the set of UK postcodes change. On the other hand, with other APIs (imagine using a weather data provider), the dataset returned will be different every day.  
This will make it difficult to implement reliable assertions in our tests, since the data we're expecting can change any time.
 - Since we're using a real API, it's going to be difficult to test non-happy flows. Maybe we want to test what happens if the dependency is returning a `404`, or a `500`, or if it doesn't respond at all. Or we might want to test what happens if it works, but it responds very slowly. If our API is calling directly the real dependency, we have no way to emulate these scenarios.

These problem can all be solved by replacing the dependecy during our integration test with a stub.

## Starting the stub

We have to add reference to the [Stubbery library](https://www.nuget.org/packages/Stubbery/).

The stub for the post code api can be created and set up in constructor of the unit test class. I'll configure a response for the case when the postcode is found, one for when it's not found, and one for when some other error happens. (An additional benefit of using a stub is to be able to imitate responses which cannot be reproduced with the real system.)

```csharp
private ApiStub StartStub()
{
    var postcodeApiStub = new ApiStub();

    postcodeApiStub.Get(
        "/postcodes/{postcode}",
        (request, args) =>
        {
            if (args.Route.postcode == "postcodeOk")
            {
                return "{ \"status\": 200, \"result\": { \"admin_county\": \"CountyName\" } }";
            }

            if (args.Route.postcode == "postcodeNotFound")
            {
                return "{ \"status\": 404 }";
            }

            return "{ \"status\": 500 }";
        });

    postcodeApiStub.Start();

    return postcodeApiStub;
}
```

(The `postcodes.io` API returns the status in a field in the body, and we're depending on that in our implementation, so that's what we configure on the stub.  
The API is also returning proper status codes. If we depended on those, we could set up the stub to respond with the specific status codes by calling the `StatusCode` method.)

## Starting the api under test

Then we start our web application for testing (there is a little more ceremony to it than this, the details can be found in [the documentation](https://docs.asp.net/en/latest/testing/integration-testing.html), or the [sample project](https://github.com/markvincze/Stubbery/tree/master/samples/Stubbery.Samples.BasicSample)).

```csharp
private TestServer StartApiUnderTest(ApiStub postcodeApiStub)
{
    var server = new TestServer(
        WebHost.CreateDefaultBuilder()
            .UseStartup<Startup>()
            .ConfigureAppConfiguration((ctx, b) =>
            {
                b.Add(new MemoryConfigurationSource
                {
                    InitialData = new Dictionary<string, string>
                    {
                        // Replace the real api URL with the stub.
                        ["PostCodeApiUrl"] = postcodeApiStub.Address
                    }
                });
            }));

    return server;
}
```

## Implement the test

For implementing the test, I'll use xUnit as the test runner.  
We can implement the actual test and verify that we're getting the responses that we expect.

```csharp
[Fact]
public async Task GetCountyName_CountyFound_CountyNameReturned()
{
    using (var stub = StartStub())
    using (var server = StartApiUnderTest(stub))
    using (var client = server.CreateClient())
    {
        var response = await client.GetAsync("/countyname/postcodeOk");

        var responseString = await response.Content.ReadAsStringAsync();

        Assert.Equal("CountyName", responseString);
    }
}
```

The complete example can be found in the [sample project](https://github.com/markvincze/Stubbery/tree/master/samples/Stubbery.Samples.BasicSample).

# Conclusion

Thanks to the changes in how hosting works in ASP.NET Core, writing integration tests became much easier.  
External dependencies can make our integration tests brittle, which can be mitigated by replacing them with a hardwired, reliable stub—which is easy to do with the pluggable proramming model of ASP.NET Core.

And the [Stubbery](https://markvincze.github.io/Stubbery/) library makes it more convenient to set up and start such stubs for HTTP APIs.
