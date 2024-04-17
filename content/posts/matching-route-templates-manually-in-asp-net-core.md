+++
title = "Matching route templates manually in ASP.NET Core"
slug = "matching-route-templates-manually-in-asp-net-core"
description = "It can come handy to manually match a request path to route templates, and extract the arguments. This post describes how it can be done with ASP.NET Core."
date = "2016-06-18T21:17:15.0000000"
tags = ["asp.net", "mvc"]
ghostCommentId = "ghost-21"
aliases = ["how-to-match-route-templates-manually-in-asp-net-2"]
+++

We can use routing in ASP.NET to define paths on which we want to respond to HTTP requests. In ASP.NET Core we have two common ways to specify routing in our application.

We can use the `Route` attribute on the action methods:

```csharp
[HttpGet("test/{myParam}"]
public IActionResult Get(int myParam)
{
    // ...
}
```

Or if we don't want to use MVC, we can directly set up some responses in our `Startup` class by creating a `RouteBuilder` and adding it to the pipeline with the `UseRouter` method.

```csharp
RouteBuilder builder = new RouteBuilder(app);

builder.MapVerb(
    HttpMethod.Get.Method,
    "test/{myParam}",
    async context =>
    {
        var arg = context.GetRouteData().Values["myParam"];

        // ...
    });

app.UseRouter(builder.Build());
```

## Using route matching manually

In usual development the methods above are enough, since most often we'll use MVC to implement our application. On the other hand sometimes it can be handy if we're able to manually match a URL path to a template and extract the arguments.

Recently I needed to do this in the [Stubbery](https://github.com/markvincze/Stubbery) library, to set up stubbed replies for various request paths.

I looked around in the ASP.NET Routing codebase quite a while in an attempt to figure out how the routing worked internally and whether the classes doing the template matching are  `public`, so I can use them in my code.

### TLDR version

You can manually do the template matching and extract the route arguments with this [little helper class](https://github.com/markvincze/Stubbery/blob/master/src/Stubbery/RequestMatching/RouteMatcher.cs).

```csharp
public class RouteMatcher
{
    public RouteValueDictionary Match(string routeTemplate, string requestPath)
    {
        var template = TemplateParser.Parse(routeTemplate);

        var matcher = new TemplateMatcher(template, GetDefaults(template));

        var values = matcher.Match(requestPath);

        return values;
    }

    // This method extracts the default argument values from the template.
    private RouteValueDictionary GetDefaults(RouteTemplate parsedTemplate)
    {
        var result = new RouteValueDictionary();

        foreach (var parameter in parsedTemplate.Parameters)
        {
            if (parameter.DefaultValue != null)
            {
                result.Add(parameter.Name, parameter.DefaultValue);
            }
        }

        return result;
    }
}
```

Fortunately, the necessary framework classes (`TemplateParser` and `TemplateMatcher`) are public.

### Some more detail

There are quite a handful of classes participating in the routing process, I needed to debug the code and step over the different calls to wrap my head around them. On a high level this is what happening during setting up our routes.

![Set up routing in ASP.NET](/images/2016/06/aspnet-routing.png)

When we specify a route by calling `RouteBuilder.MapVerb` a new `Route` is created, and added to the builder's collection. The `Route` object has a delegate to the handler processing the request and producing the response.
If we use `UseMvc`, then the routes are automatically created based on the action methods we have (this is done by a method called `CreateAttributeMegaRoute` :)), and then `UseRouter` is called.
  
When we call the `UseRouter` extension method, a middleware is registered called `RouterMiddleware`, to which a `RouteCollection` is passed with the configured routes.

This middleware is added to the pipeline, and its `Invoke` method is called during request processing. This method checks if any of the route templates match, and then calls the appropriate handler.

At this point it wasn't much more work to find the classes doing the actual route matching and extract them into my own codebase.
