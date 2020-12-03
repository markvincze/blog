+++
title = "Jumpstart F# web development: F# with ASP.NET Core"
slug = "jumpstart-f-web-development-f-with-asp-net-core"
description = "An introduction to get started with web development in F#, using ASP.NET Core."
date = "2017-02-26T20:25:14.0000000"
tags = ["asp.net-core", "f#"]
ghostCommentId = "ghost-32"
+++

In this third part of the [series](/series-jumpstart-f-web-development) we'll look at how we can get started with developing an ASP.NET Core application using F#. This scenario is pretty straightforward, there are no extra hoops to jump over. In this post I'll describe the steps necessary to create a new ASP.NET application.

In ASP.NET Core we typically use the Kestrel web server to host our application, which is technically started up from a Console application. This is important for .NET Core, since the platform has to enable developers working on Linux or Mac, who don't have Visual Studio. So the developer experience have to be streamlined from the terminal as well.

This is good news, since we won't have any more problems with project types or Visual Studio (as we had [when we did F# and ASP.NET on the full .NET Framework]()).

# Create the project

We can simply create a new empty F# project using the `dotnet` CLI by issuing the following command.

```bash
dotnet new --lang fsharp
```

This command scaffolds an empty Console application for us. In order to use ASP.NET, add the following package dependencies to our `projet.json`.

```json
      "dependencies": {
        ...
        "Microsoft.AspNetCore.Mvc": "1.1.0",
        "Microsoft.AspNetCore.Server.Kestrel": "1.1.0",
        "Microsoft.AspNetCore.Diagnostics": "1.1.0",
        "Microsoft.AspNetCore.Hosting": "1.1.0",
        "Microsoft.Extensions.Logging.Console": "1.1.0"
      }
```

# F# source files in .NET Core

It's a bit inconvenient that with the current tooling we manually have to manage the list of our source files in the `project.json` file. Every source file in the project has to be listed in the `buildOptions/compile/includeFiles` property. It's important that the files have to be listed in the proper order. If a source file depends on another one, then it has to come later in the list than the one it depends on.

For at the end of this post, when we have the `Program.fs`, `Startup.fs` and the `HelloController.fs` files, the configuration should look like this.

```json
{
  "buildOptions": {
    ...
    "compile": {
      "includeFiles": [
        "Controllers/HelloController.fs",
        "Startup.fs",
        "Program.fs"
      ]
    }
  },
  ...
}
```

# Bootstrap the application

In our `Program.fs` file we have to start up the hosting of our application with Kestrel. In order to do that, replace the `main` function with the following code.

```fsharp
open JumpstartAspnetCoreFsharp
open System
open System.IO
open Microsoft.AspNetCore.Hosting

[<EntryPoint>]
let main argv =
  let host =
    WebHostBuilder()
      .UseKestrel()
      .UseUrls("http://*:5000/")
      .UseContentRoot(Directory.GetCurrentDirectory())
      .UseStartup<Startup>()
      .Build()

  host.Run()
  0 // return an integer exit code
```

# Set up our application

The type `Startup` should describe what our application is going to do. Let's add a new source file, `Startup.fs` to the project, create the `Startup` type, and add the calls necessary to use MVC.

```fsharp
namespace JumpstartAspnetCoreFsharp

open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Hosting
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Logging
open System
open System.IO

type Startup() =
    member __.ConfigureServices(services: IServiceCollection) =
        services.AddMvc() |> ignore
    member __.Configure (app : IApplicationBuilder)
                        (env : IHostingEnvironment)
                        (loggerFactory : ILoggerFactory) =
        loggerFactory.AddConsole() |> ignore
        app.UseMvc() |> ignore
```

# Implement our controller

The last step is to implement our controller. The usual pattern is to put our controllers into a folder called `Controllers`. We can add a file to the project called `HelloController.fs`. The implementaion will be very similar to the one used in full .NET.

```fsharp
namespace JumpstartAspnetCoreFsharp.Controllers

open System
open Microsoft.AspNetCore.Mvc

[<Route("[controller]")>]
type HelloController() =
    inherit Controller()
    member this.Get() =
        this.Ok "Hello from F# and ASP.NET Core!"
```

# Start the application

There is nothing else to do, we can go ahead restore the Nuget packages and start our application by issuing the following commands.

```bash
dotnet restore
dotnet run
```

Then we can navigate to [http://localhost:5000/Hello](http://localhost:5000/Hello) to open the endpoint we implemented.

# Tooling

The F# tooling for .NET Core seems to have some rough edges at this point. I tried using Visual Studio on Windows, and also VSCode with the [ionide-fsharp](http://ionide.io/) extensions. They both tend to be a bit flaky, occasionally the IntelliSense and the autocomplete stops working. In this case we should rebuild the project, and restart the editor.

Once the tooling of .NET Core projects gets finalized with the release of VS2017 and the new version of the `dotnet` CLI, I expect the F# tooling to catch up and fix these issues quickly.

**Source**: I uploaded a complete working example to [this repository](https://github.com/markvincze/jumpstart-aspnetcore-fsharp).

We've seen that F# + ASP.NET Core is a good match, and works nicely out of the box.
In the last part we will take a look at how to create a new project on .NET Core using Suave.IO.
