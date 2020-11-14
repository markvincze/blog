+++
title = "Jumpstart F# web development: F# with Suave.IO on .NET Core"
slug = "jumpstart-f-web-development-f-with-suave-io-on-net-core"
description = "An introduction to get started with web development in F#, using the Suave web framework on .NET Core."
date = "2017-03-12T12:51:45.0000000"
tags = [".net-core", "f#", "suave"]
+++

In a [previous post](/jumpstart-f-web-development-f-with-suave-io-on-classic-net/) we've seen how we can create a simple web application with Suave on the full .NET Framework.
In the last post of the [series](/series-jumpstart-f-web-development) we'll take a look at how we can do the same thing on .NET Core.

This is gonna be a short post, since there are no real gotchas in this scenario, it's really easy to set everything up.

**Note**: In this post I will use the new csproj-based .NET tooling. Since the project.json-based tooling is deprecated, I don't think anybody should invest in using it any more. I was using version **1.0.1** of the `dotnet` CLI when writing this post.

# Create a Suave app on .NET Core

Let's start by creating a new F# project. Since a Suave web app is just a Console app in which we fire up our web server, we can use the Console project template.

```bash
mkdir mysuaveapp
cd mysuaveapp
dotnet new console -lang f#
```

Then add the package Suave as a dependency.

```bash
dotnet add package Suave
```

Now we can implement a simple web application.
This is what the `console` template scaffolded for us by default in the `Program.fs` file:

```fsharp
open System

[<EntryPoint>]
let main argv =
    printfn "Hello World from F#!"
    0
```

Modify this to have the following content, starting up a Suave web app with a couple of routes.

```fsharp
open Suave
open Suave.Filters
open Suave.Operators
open Suave.Successful

let app =
    choose
        [ GET >=> choose
            [ path "/" >=> OK "Index"
              path "/hello" >=> OK "Hello!" ]
          POST >=> choose
            [ path "/hello" >=> OK "Hello POST!" ] ]

[<EntryPoint>]
let main argv =
    startWebServer defaultConfig app
    0
```

The last thing we have to do is restore the dependencies and start up our app.

```bash
dotnet restore
dotnet run
```

That's it! Our app should be running, and we can open it by navigating to http://localhost:8080.
I also uploaded a working example to [this Github repository](https://github.com/markvincze/jumpstart-netcore-suave).

# Different ways to run Suave

In the above example we are running Suave directly on top of .NET Core using the web server built-in the library. However, since .NET Core is modular, that's not the only option. We can also run Suave on top of the web server created for ASP.NET Core called Kestrel, or we can even run it on top of ASP.NET Core using a special middleware.

![Different options to run Suave on .NET Core](/images/2017/03/suave-options.png)

We can do this with the following packages.

 - [Suave.Kestrel](https://github.com/Krzysztof-Cieslak/Suave.Kestrel): Run Suave on top of the Kestrel web server. (This is a early proof of concept implementation, and doesn't seem to be actively worked on any more.)
 - [Suave.AspNetCore](https://github.com/SuaveIO/Suave.AspNetCore): Run Suave on top of ASP.NET Core, using a middleware to connect the two frameworks together. This library seems to be more actively developed, and with this we can even combine ASP.NET and Suave endpoints in the same application.

# F# tooling issues

As described on [this Github page](https://github.com/dotnet/netcorecli-fsc/wiki/.NET-Core-SDK-1.0.1#ide-support), at the moment there are some issues with the current version of the FSharp SDK and the Ionide extension (which is used in VSCode for F# development). The extension does not work with the 1.0 version of the SDK.
The workaround to get it to work is to change the version to `1.0.0-beta-060000`, and to add a reference to the tool `dotnet-compile-fsc`. I did this change in the repo on the [this branch](https://github.com/markvincze/jumpstart-netcore-suave/tree/vscode-inoide-workaround).

Also, if you are using VSCode, you have to do `dotnet build` from the terminal before starting the editor to make it work properly.

With the release of the 1.0 version of the new csproj-based dotnet tooling, I expect all the problems related to editor integration and tooling to be fixed soon.
