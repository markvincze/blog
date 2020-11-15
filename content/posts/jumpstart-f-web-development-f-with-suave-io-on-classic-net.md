+++
title = "Jumpstart F# web development: F# with Suave.IO on classic .NET"
slug = "jumpstart-f-web-development-f-with-suave-io-on-classic-net"
description = "An introduction to get started with web development in F#, using Suave.IO on the classic .NET Framework."
date = "2017-02-11T15:12:50.0000000"
tags = [".net", "f#", "suave"]
ghostCommentId = "ghost-31"
+++

In the second part of [the series](/series-jumpstart-f-web-development) we take a look at how we can develop a web application using Sauve on the classic .NET Framework.

![Suave logo](/images/2017/02/suave-logo.png)

[Suave](https://suave.io/) is a lightweight web framework and server, which was implemented in F# from the ground up with functional programming in mind, using constructs which fit the F# word nicely, so we won't have to create .NET classes or use inheritence and state mutation to configure our application (as we had to do with ASP.NET).

And based on its logo, you can already tell it's more hipster and cool to use Suave than anything else ;).

# Create a new project with Visual Studio

I mentioned that Suave is not just a framework, but also a web *server* in one library. This means that we don't need another server, like IIS to start up our application, so we don't need any special Visual Studio integration either.

Thus we can go ahead and simply create a new F# Console application, which, by default contains a `Program.fs` file with the following content.

```fsharp
[<EntryPoint>]
let main argv =
    printfn "%A" argv
    0 // return an integer exit code
```

We have to add the `Suave` nuget package to our project (by typing `Install-Package Suave` into the Package Manager Console, or using the GUI).

Then we can implement a basic web application by replacing the default `main` function with the following code.

```fsharp
open Suave

[<EntryPoint>]
let main argv = 
    startWebServer defaultConfig (Successful.OK "Hello from Suave!")
    0
```

Or we can implement something more complicated by handling some different http methods and routes.

```fsharp
let app =
    choose
        [ GET >=> choose
            [ path "/status" >=> OK "Service is UP"
              path "/hello" >=> OK "Hello World!" ]
          POST >=> OK "This was a POST" ]

[<EntryPoint>]
let main argv = 
    startWebServer defaultConfig app
    0 // return an integer exit code
```

The cool thing about Suave that it's programming model fits the functional constructs snugly, so it feels much more like a first-class citizen in the F# world than ASP.NET.  
Functions and the composability features of F# really shine when setting up our routes and the various endpoints of our web application, and a complicated app can be described with surprisingly little, terse code.

You can read much more about Suave's capabilities on the [official site](https://suave.io/).

# Without VS: embrace the open tools

Since we don't need intricate Visual Studio integration to start up our web server, it's also an option to develop completely without VS, which comes especially handy if we want to work on a Mac with Mono (which is also supported by F# and Suave).

In order to do this we can utilize two open source tools.

 - [Paket](https://fsprojects.github.io/Paket/): A dependency manager for .NET and Mono, which is easy to use from the command line, and supports using Nuget too as the source of our dependencies.
 - [Fake](http://fsharp.github.io/FAKE/): "Make for F", a scriptable, CLI-friendly build automation tool for F#.

With these tools it's relatively easy to set up a project with a couple of scripts, which is completely usable from the terminal without Visual Studio.

You can find a minimal example of this setup in my [jumpstart-suave](https://github.com/markvincze/jumpstart-suave) repository. It contains the following elements.

 - build.cmd: The main startup script, it does the following steps.
    1. If it's not present yet, it installs paket.
    2. If we don't have a `paket.lock` file (we don't have the actual package versions fixed, and haven't discovered the transitive dependencies), installs all the packages.
    3. Restores the actual packages.
    4. Starts up our main script by calling `FAKE`.
 - build.fsx: Defines the `"run"` default target, which simply starts up the Suave web application (the same way we did in our VS Console project).
 - app.fsx: The implementation of our main `app` function, which in this example returns the same 200 OK for every request.
 - paket.dependencies: Specifies the external packages we want to install with Paket.
 - paket.lock: The fixed down versions of all our direct and transitive dependencies. (This file is normally also commited to source control.)

(I based this solution on a [more complicated repo](https://github.com/tpetricek/suave-xplat-gettingstarted) set up by Tomas Petricek, which also includes automatic reloading in case of a file change, and deployment to Azure and Heroku.)

This is a completely self-contained example, simply executing `build.cmd` will download all the dependencies, build the project and start up our webserver, straight from the command line.

# Conclusion

With these examples we can see that Suave is a cool, lightweight and fun to use web framework, which fits really nicely into the functional F# world. And because the web server is also part of the library, and we have some CLI tools to install our dependencies and build the project, we can even do the whole development flow without Visual Studio.

Whether to use Suave or ASP.NET is not a trivial question though. If we start a greenfield development project, I'd probably give Suave a go, just because it is more suitable for functional programming, but if we are migrating an existing ASP.NET application to F#, or we depend on existing libraries which are ASP.NET-specific, we might be better off sticking to Microsoft's framework.

In the next post of [this series](/series-jumpstart-f-web-development) we'll move from the classic .NET Framework to .NET Core, and take a look at how we can use F# with ASP.NET there.
