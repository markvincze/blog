+++
title = "ASP.NET Core 1.0: hints to get started"
slug = "getting-started-with-asp-net-core-1-0-tips-and-tricks"
description = "Some random tips and tricks I have learnt during spending a couple of weeks with getting started with ASP.NET Core."
date = "2016-02-14T16:30:58.0000000"
tags = ["asp.net", "c#", ".net", ".net-core", "asp.net-core", "dnx"]
ghostCommentId = "ghost-12"
+++

I recently started working on implementing a Web Api application using ASP.NET Core 1.0, running it on Linux with the CoreCLR.

There have been many changes introduced in this new version of ASP.NET, and there are also differences in how we are running and deploying applications using CoreCLR, so I'm going to document a couple of things you might encounter if you get started with using this new ecosystem.

## Version numbers

It is quite easy to get lost in the sea of different products and version numbers. In the following table I'll try to summarize the ones related to ASP.NET in the existing and the upcoming release.

<table>
    <tr>
        <th>
            Component
        </th>
        <th>
            Current release
        </th>
        <th>
            Upcoming version
        </th>
    </tr>
    <tr>
        <td>
            ASP.NET
        </td>
        <td>
            4.6
        </td>
        <td>
            ASP.NET Core 1.0<br/ >(Initially was called ASP.NET 5)
        </td>
    </tr>
    <tr>
        <td>
            MVC
        </td>
        <td>
            5
        </td>
        <td>
            6
        </td>
    </tr>
    <tr>
        <td>
            Web Api
        </td>
        <td>
            2
        </td>
        <td>
            No new version, merged into MVC 6
        </td>
    </tr>
    <tr>
        <td>
            Entity Framework (EF)
        </td>
        <td>
            6
        </td>
        <td>
            EF Core 1.0<br />(Initially called EF 7)
        </td>
    </tr>
</table>


One thing to keep in mind is that Core 1.0 of ASP.NET and EF shouldn't necessarily be considered as the the latest updates to which everybody should update. The reasoning behind the 1.0 version number is that these are new, standalone technologies which will live alongside the existing ASP.NET 4.6 and EF 6 releases.

The reason for this is that they have been reimplemented in a cross-platform way using .NET Core 1.0, so they are less mature, and not as full-featured as their existing counterparts. Thus, if somebody does not need to target Linux, they might be better off sticking to the older versions, since for the time being those are more reliable, and have more features and wider support.

## Api changes

ASP.NET Core 1.0 is a rewrite of the ASP.NET platform, so many of the Apis changed. If you find out that one of your favorite framework classes or methods has disappeared, don't worry. Usually, the same functionality still exists, it just has been moved or renamed.

If you can't find something, simply googling for the method or class name can often help. And because the development is being done in the open, you can also search in the source code on [Github](https://github.com/aspnet) to find a particular feature.

If you want to figure out the NuGet package in which a certain framework class resides, you can use the great [Reverse package search](http://packagesearch.azurewebsites.net/) tool.

### MVC vs Web Api

One of the reasons for the Api changes is that the distinction between Web Api and MVC will cease to exist, and from now on they are unified in a single framework called **MVC**, of which version 6 will be the current release.

I'm really happy about this change, there will be no more distinction between the types we need to use to implement MVC and Web Api controllers.

In the previous version we had to use different base classes for the different controllers, `Controller` was the base class for MVC, and `ApiController` was the one for Web Api. Similarly, we needed to use two different classes for other aspects too, for example the base class of an action filter had to be `System.Web.MVC.ActionFilterAttribute` for MVC, and `System.Web.Http.Filters.ActionFilterAttribute` for Web Api. Now all these classes are unified.

This makes it much easier and less confusing to mix and match the two, and have endpoints in a single application (or even in the same Controller) returning HTML content and Json or XML data.

## Introducing project.json

One of the new concepts introduced in ASP.NET Core 1.0 is the new project file format, project.json, which is a more human-friendly project file with Json format we can use instead of the csproj file.

The main reason to introduce this is to make development more friendly on Linux and Mac, where we don't have the rich support of Visual Studio, but only text editors, with different level of support for .NET development, but still very far from what VS provides on Windows.

Still, this is a very welcomed change on Windows too, it makes editing our project details easier and quicker. You can read about its format in more detail on the [ASP.NET Documentation](http://docs.asp.net/en/latest/conceptual-overview/understanding-aspnet5-apps.html#the-project-json-file) site.

### NuGet packages in the project.json

Another change related to the new project file format is that in projects using the new project.json we don't need to have a separate packages.config file to specify the necessary NuGet packages any more. Rather, they are pulled in from the project.json. In your project description, you can specify the dependencies of your project in the `dependencies` collection:

    "dependencies": {
        "EntityFramework.Commands": "7.0.0-rc1-final",
        "EntityFramework.MicrosoftSqlServer": "7.0.0-rc1-final",
        "MyOtherProjectInTheSolution": ""
    }

An entry in the `dependencies` can be either a reference to another project in the solution, or a reference to a NuGet package, so finally the references to packages don't live in two different places.

Previously I had many problems (and I'm sure lots of other people did) with NuGet package references living in two different places: the package to download was specified in packages.config, and the actual binary be references was specified in the csproj file. And they could really easily get out of sync, especially in large solution, where we ended up referencing different versions of the same package.

The fact that all the indirectly needed NuGet packages (packages referenced by some of the packages we need) were all separate entries in our list of references just made this more complicated and unstable.

With the new project.json these only live in a single place, so the version numbers will always be in sync, and the other advantage is that we only need to specify the top-level package we need, and all the indirect dependencies will be automatically pulled in.

And when we start typing in a reference in the project file, we get autocomplete support for both the package names and versions. I know that the NuGet Package Manager window was also redesigned, but since I started working on this new project, I didn't have to open it even once. 

## Unit testing

The support for unit testing is changing too. The library currently supporting .NET Core is XUnit, but NUnit support is also in the works. I don't know what the plan with MSTest is, but given that it's a Visual Studio specific testing library, I don't think it'll be supported for DNX-based projects.

In the [ASP.NET Documentation](http://docs.asp.net/en/latest/testing/unit-testing.html) you can find a guide about how to create a test project, write some unit tests, and run them either in Visual Studio, or from the command line. (As far as I know, ReSharper is not able to run the unit tests in a DNX project, but the support for that is also in the works.)

### Mocking

The other frameworks you are used to might not be available yet for .NET Core.  
The thing I desperately need and probably wouldn't be able to comfortable write unit tests without is a mocking framework.

As far as I know, the major mocking frameworks out there haven't been fully ported to .NET Core yet. The one I could find is called [LightMock.vNext](https://www.nuget.org/packages/LightMock.vNext/), but it seems to have much fewer features than what I'm used to in Moq.

In other .NET projects I use [Moq](https://github.com/moq/moq4) as a mocking frameworks, so I was happy to find out there is a already a working version of Moq developed by the ASP.NET team. I have been using version `4.4.0-beta8` without any problems so far.

    "dependencies": {
      "moq.netcore": "4.4.0-beta8",
      ...
    }

To be able to have this reference, there is one extra thing we have to do. We have to create a NuGet.config file in our solution folder, and add another NuGet feed, which publishes development packages coming from the ASP.NET team:

    <?xml version="1.0" encoding="utf-8"?>
    <configuration>
      <packageSources>
        <add key="AspNetVNext" value="https://www.myget.org/F/aspnetcidev/api/v3/index.json" />
        <add key="NuGet" value="https://api.nuget.org/v3/index.json" />
      </packageSources>
    </configuration>

(Source: I found this information on [Stack Overflow](http://stackoverflow.com/questions/27918305/mocking-framework-for-asp-net-core-5-0), thanks Lukasz Pyrzyk!)

#### Api changes

The Api changes can greatly affect how we are mocking certain aspects of an MVC controller. Some properties which used to have setters don't have one any more, so instead of simply setting them to a mock object, we have to go through some extra hoops to stub them.

For example we can replace the Response object with a mock using the following code:

    var sut = new MyController();

    var responseMock = new Mock<HttpResponse>();

    var httpContextMock = new Mock<HttpContext>();
    httpContextMock.SetupGet(a => a.Response).Returns(responseMock.Object);

    sut.ActionContext = new ActionContext()
    {
        HttpContext = httpContextMock.Object
    };

## Command line

Building projects, running applications and executing unit tests are all possible with the new command-line tools. Again, this is essential to support development on platforms where Visual Studio is not available.

But even on Windows, where VS is available, the command line tools can prove to be very convenient.  
The thing I like the most about the command line tools is [dnx-watch](https://github.com/aspnet/dnx-watch). You can install it by issuing the following command:

    dnu commands install Microsoft.Dnx.Watcher

Then you can execute any dnx command specified for your project by typing

    dnx-watch web

or 

    dnx-watch test

and dnx-watch will restart and execute the command every time any of the files in your solution changes. This is a great way to keep a fresh version of your site running all the time, or to automatically execute all your unit tests on every code change.

The command line I use on Windows is [cmder](http://cmder.net/). One of my favorite features is being able to split the terminal window vertically or horizontally.    
The setup I started using after a while is to split terminal into 3 parts:

 - Left: use `git` and the occasional `dnu` commands like `restore` and `build`.
 - Top-right: constantly run `dnx-watch web` to always host the latest version of the site.
 - Top-left: constantly run `dnx-watch test` to execute my unit test suite on every change.

![Screeshot illustrating cmder used with an ASP.NET Core project](/images/2016/02/asp-net-core-cmder.png)

If you are using the built-in command line in Windows, I can really recommend [cmder](http://cmder.net/), it's a great improvement with features like syntax-highlighting, better text-selection with mouse, CTRL+C and CTRL+V support, and many more.

# Conclusion

No real conclusion here, this post ended up being quite random :). I've probably written about some stuff which is not essential for everybody, and I'm sure there are some others which might be much more important for someone else. However, these are the ones which were at the forefront of my thoughts.

I might revisit this topic in a later post as I learn more and more about ASP.NET Core.
