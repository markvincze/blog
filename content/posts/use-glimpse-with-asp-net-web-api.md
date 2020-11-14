+++
title = "Use Glimpse with ASP.NET Web Api"
slug = "use-glimpse-with-asp-net-web-api"
description = "Glimpse is not fully supported for the Web Api, but it can still be a valuable tool."
date = "2015-05-14T12:56:50.0000000"
tags = ["asp.net", "mvc", "web api", "glimpse"]
+++

Glimpse is a wonderful tool for getting an insight into the mechanisms happening in an ASP.NET application. It inspects every request processed by our app, and displays its UI either embedded into our web site, or on a standalone page at a different URL.

![Example of the Glimpse UI](/images/2015/05/1example-1.png)

The current version of Glimpse (1.9.2 at the time of writing this) only has proper support for ASP.NET Web Forms and MVC, and not for the Web Api.
In this post I'm going to look at how can we use Glimpse for the Web Api, what are the features which works for Web Api as well, and what is missing.

#Getting Started

I am going to get started by creating an ASP.NET web project that contains both MVC and Web Api elements, and see how well Glimpse performs out of the box.
I created a new project by checking both MVC and Web Api in the project creation wizard.

![Creating a new ASP.NET project with both MVC and Web Api support.](/images/2015/05/20createproject.png)

##Creating a test application

In order to be able to try out Glimpse, I created a simple web application with both an MVC and a Web Api controller, that can return a list of guitars stored in the database of an instrument shop.

###Data model

For the the data model I used Entity Framework Code First with LocalDB to store some sample data. EF is no longer distributed with the .NET Framework, but rather published in a NuGet package. We can install it with the following command.

    Install-Package EntityFramework

The following data model will represent manufacturers and models of guitars sold in a guitar shop:

```csharp
namespace GlimpseTest.Models
{
    public class Guitar
    {
        public int GuitarId { get; set; }

        public GuitarType Type { get; set; }

        [JsonIgnore]
        public virtual Manufacturer Manufacturer { get; set; }

        public string Name { get; set; }

        public string Material { get; set; }

        public decimal Price { get; set; }
    }

    public class Manufacturer
    {
        public int ManufacturerId { get; set; }

        public string Name { get; set; }

        public virtual IList<Guitar> Models { get; set; }
    }

    public enum GuitarType
    {
        Classical,
        Acoustic,
        Electric,
        Bass
    }
}
```

I created the database context with EF code first and implemented a configuration class to seed the database with some test data.

```csharp
namespace GlimpseTest.Models
{
    public class GuitarShopContext : DbContext
    {
        public GuitarShopContext() : base("GuitarShopContext")
        {
        }

        public DbSet<Guitar> Guitars { get; set; }

        public DbSet<Manufacturer> Manufacturers { get; set; }
    }

    public class AlwaysDropAndCreateInitializer : DropCreateDatabaseAlways<GuitarShopContext>
    {
        protected override void Seed(GuitarShopContext context)
        {
            base.Seed(context);

            var yamaha = new Manufacturer
            {
                Name = "Yamaha",
                Models = new List<Guitar>
                {
                    new Guitar
                    {
                        Name = "C40",
                        Material = "Spruce",
                        Type = GuitarType.Classical
                    },
                    new Guitar
                    {
                        Name = "FS700S",
                        Material = "Rosewood",
                        Type = GuitarType.Acoustic
                    }
                }
            };

            var gibson = new Manufacturer
            {
                Name = "Gibson",
                Models = new List<Guitar>
                {
                    new Guitar
                    {
                        Name = "ES-175",
                        Material = "Maple",
                        Type = GuitarType.Electric
                    }
                }
            };

            context.Manufacturers.Add(yamaha);
            context.Manufacturers.Add(gibson);
        }
    }
}
```

We need to configure the database initializer in our Application_Start method class in the Global.asax.cs.

```csharp
Database.SetInitializer(new AlwaysDropAndCreateInitializer());
```

The last thing to do in order to make our data model work is to configure a connection string to the database. I used LocalDB for testing.

```xml
<connectionStrings>
  <add name="GuitarShopContext" providerName="System.Data.SqlClient" connectionString="Data Source=(localdb)\v11.0;Initial Catalog=GuitarShop;Integrated Security=True" />
</connectionStrings>
```

###Controllers

To be able to test Glimpse in its merits, we need to create some controllers as well. I implemented basically the same functionality in both an MVC and a Web Api controller.

#### MVC

The controller has a single action, that returns the list of manufacturers and guitars stored in the database. The controller action does two things.

 - Loads the data from the database
 - Imitates a service call to an external service to fetch the prices of the models

The controller:

```csharp
namespace GlimpseTest.Controllers
{
    public class GuitarController : Controller
    {
        public async Task<ActionResult> Index()
        {
            using (var ctx = new GuitarShopContext())
            {
                var manufacturers = await ctx.Manufacturers.Include("Models").ToListAsync();

                await this.LoadPrices(manufacturers.SelectMany(m => m.Models));

                return this.View(manufacturers);
            }
        }

        private async Task LoadPrices(IEnumerable<Guitar> guitars)
        {
            Random rnd = new Random();
            foreach (var guitar in guitars)
            {
                guitar.Price = rnd.Next(100, 500);
            }

            await Task.Delay(500);
        }
    }
}
```

The views consists of two parts. Views\Shared\DisplayTemplates\Guitars.cshtml contains the view for displaying a list of guitars.

```html
@model IEnumerable<GlimpseTest.Models.Guitar>

<table class="table">
    <tr>
        <th>
            @Html.DisplayNameFor(model => model.Name)
        </th>
        <th>
            @Html.DisplayNameFor(model => model.Material)
        </th>
        <th>
            @Html.DisplayNameFor(model => model.Price)
        </th>
    </tr>

@foreach (var item in Model) {
    <tr>
        <td>
            @Html.DisplayFor(modelItem => item.Name)
        </td>
        <td>
            @Html.DisplayFor(modelItem => item.Material)
        </td>
        <td>
            @Html.DisplayFor(modelItem => item.Price)
        </td>
    </tr>
}

</table>
```

View\Guitar\Index.cshtml is the main view for this action.

```html
@model IEnumerable<GlimpseTest.Models.Manufacturer>

@{
    ViewBag.Title = "Index";
}

<h2>Guitars</h2>

<div>
    @foreach (var manufacturer in Model)
    {
        <h4>
            @Html.DisplayFor(modelItem => manufacturer.Name)
        </h4>

        @Html.Partial("~/Views/Shared/DisplayTemplates/Guitars.cshtml", manufacturer.Models);
    }
</div>
```

####Web Api

The Web Api controller is very similar, but it has a different base class and method signature:

```csharp
namespace GlimpseTest.Controllers
{
    public class GuitarApiController : ApiController
    {
        public async Task<IHttpActionResult> Get()
        {
            using (var ctx = new GuitarShopContext())
            {
                var manufacturers = await ctx.Manufacturers.Include("Models").ToListAsync();

                await this.LoadPrices(manufacturers.SelectMany(m => m.Models));

                return this.Ok(manufacturers);
            }
        }

        private async Task LoadPrices(IEnumerable<Guitar> guitars)
        {
            Random rnd = new Random();
            foreach (var guitar in guitars)
            {
                guitar.Price = rnd.Next(100, 500);
            }

            await Task.Delay(500);
        }
    }
}
```

The Web Api controller returns the data in Json directly, so it does not have a corresponding view.
One convenient thing to do is to make the Json formatter be the only formatter, so we can open endpoints in our browser without having to specify the Accept header. In order to do this, we have to insert the following piece of code in the start of the Register method in our WebApiConfig class:

```csharp
// Web API configuration and services
var jsonFormatter = config.Formatters.JsonFormatter;
config.Formatters.Clear();
config.Formatters.Add(jsonFormatter);
```
This code removes every formatter, except the Json one.

##Installing Glimpse

Installing Glimpse is merely adding a NuGet package to our ASP.NET project. For using with the latest version of MVC, Glimpse can be added with the following command from the Package Manager Console:

    Install-Package Glimpse.Mvc5
Sadly, there is no official package for Web Api yet. Official Web Api support is supposed to come with version 2 of Glimpse, but no estimated release date has been announce. (However, there is active work going on in this area: https://github.com/Glimpse/Glimpse/issues/715)

###Using Glimpse with MVC
After installing Glimpse this way, we can start using it immediately. To enable Glimpse, go to the url /Glimpse.axd, and click on Turn Glimpse On.

![Turn Glimpse on](/images/2015/05/25turnonglimpse.png)

If we navigate to the index of our guitar controller, we should see the Glimpse plugin showing up on the bottom of the page, where we can see a summary of the information recorded during the request.

![Default view of the Glimpse plugin.](/images/2015/05/30glimpseinitial-1.png)

If we click on the g button in the bottom right hand corner, the full view of Glimpse is opened, where we find several tabs showing different kinds of data collected about the request:

![Full view of the Glimpse plugin.](/images/2015/05/40glimpsefull.png)

Because MVC is officially supported, these tabs all work very well out of the box: we can see the order of different events on the Execution tabs, the Routes tab shows information about the routes taken into consideration, and the Timeline tab displays timing information about the different phases of the request processing.
One thing that's missing but we would expect to see is insight into the SQL commands being executed during the request. This is not recorded out of the box, but luckily, there is a package that does just this. The package for simple ADO.NET is Glimpse.ADO, but we are using Entity Framework, which needs a different package, Glimpse.EF6 (for Entity Framework version six). We can install it with the following command.

    Install-Package Glimpse.EF6
After installing the package, we will have an additional SQL tab, on which we can see all the SQL queries executed during the request.

![Glimpse showing SQL queries with the Glimpse.EF6 package.](/images/2015/05/50glimpseef.png)

So we can see that with ASP.NET MVC, Glimpse works very well out of the box without any special customization.

###Using Glimpse with Web Api
Let's try our Web Api controller by opening it in the browser.

![Opening a Web Api action in the browser.](/images/2015/05/60jsonapi.png)

Hmm, when we send a request for a Web Api action, instead of a web page, we get back the result in its raw form, serialized to Json. So there is no place for the Glimpse plugin to get embedded into. How can we use Glimpse in this situation then?

####Standalone Glimpse page
In order to be able to use Glimpse independently from the web page itself, it also supports a standalone view, that can also be accessed from its /Glimpse.axd configuration page.

![Opening the standalone Glimpse page.](/images/2015/05/70standaloneglimpse-1.png)

On this page we can see a list of all the requests coming to our application, let them be MVC or Web Api requests.

![The standalone Glimpse page.](/images/2015/05/80standaloneglimpse.png)

When we click on the Inspect link, we can view the information collected on the different tabs the same way we did with the embedded plugin. However, when we inspect a Web Api request, we can see that the following tabs are showing no information: Execution, Metadata, Routes, Views. In addition to that, the Timeline tab doesn't show any Web Api-related information, only the events related to Entity Framework.

These are the things that should be supported in the upcoming version of Glimpse, probably the unification of the MVC and Web Api data model in ASP.NET 5 will make this simpler.

###How to improve?

There are at least two features which work just as well with Web Api as MVC: Tracing and custom Timeline messages.

####Tracing

Tracing is very easy to use with Glimpse. Any standard .NET trace message will be captured by Glimpse and displayed on the Trace tab.
The big advantage of browsing your trace messages with Glimpse is that it shows the trace messages in the context of a single request, so you don't have to filter your whole log in order to correlate the entries with a specific request.
If we add some trace messages to our application

```csharp
Trace.Write("Loading manufacturers from the database.");
...
Trace.Write("Getting price information");
```
They will show up in the Trace tab.

![Custom Trace messages.](/images/2015/05/90tracing.png)

####Custom timeline messages

The timeline tab is a great tool to see timing information and to analyze how long different parts of the request processing take. With Web Api the information displayed out of the box on the Timeline tab is rather limited.
It is possible to extend it with custom events, however, this is not as trivial as emitting trace messages.

There is no simple way in the public Glimpse API to emit our own Timeline events, we have to implement a couple of helper classes containing the necessary boilerplate code.

Let's add a code file called GlimpseTimeline.cs to our project and implement a couple of classes and methods in the Glimpse.Core namespace.

```csharp
using System;
using Glimpse.Core.Extensibility;
using Glimpse.Core.Framework;
using Glimpse.Core.Message;

namespace Glimpse.Core
{
    public class TimelineMessage : ITimelineMessage
    {
        public TimelineMessage()
        {
            Id = Guid.NewGuid();
        }

        public Guid Id { get; private set; }
        public TimeSpan Offset { get; set; }
        public TimeSpan Duration { get; set; }
        public DateTime StartTime { get; set; }
        public string EventName { get; set; }
        public TimelineCategoryItem EventCategory { get; set; }
        public string EventSubText { get; set; }
    }

    public static class GlimpseTimeline
    {
        private static readonly TimelineCategoryItem DefaultCategory = new TimelineCategoryItem("User", "green", "blue");

        public static OngoingCapture Capture(string eventName)
        {
            return Capture(eventName, null, DefaultCategory, new TimelineMessage());
        }

        public static OngoingCapture Capture(string eventName, string eventSubText)
        {
            return Capture(eventName, eventSubText, DefaultCategory, new TimelineMessage());
        }

        internal static OngoingCapture Capture(string eventName, TimelineCategoryItem category)
        {
            return Capture(eventName, null, category, new TimelineMessage());
        }

        internal static OngoingCapture Capture(string eventName, TimelineCategoryItem category, ITimelineMessage message)
        {
            return Capture(eventName, null, category, message);
        }

        internal static OngoingCapture Capture(string eventName, ITimelineMessage message)
        {
            return Capture(eventName, null, DefaultCategory, message);
        }

        internal static OngoingCapture Capture(string eventName, string eventSubText, TimelineCategoryItem category, ITimelineMessage message)
        {
            if (string.IsNullOrEmpty(eventName))
            {
                throw new ArgumentNullException("eventName");
            }

#pragma warning disable 618
            var executionTimer = GlimpseConfiguration.GetConfiguredTimerStrategy()();
            var messageBroker = GlimpseConfiguration.GetConfiguredMessageBroker();
#pragma warning restore 618

            if (executionTimer == null || messageBroker == null)
            {
                return OngoingCapture.Empty();
            }

            return new OngoingCapture(executionTimer, messageBroker, eventName, eventSubText, category, message);
        }

        public static void CaptureMoment(string eventName)
        {
            CaptureMoment(eventName, null, DefaultCategory, new TimelineMessage());
        }

        public static void CaptureMoment(string eventName, string eventSubText)
        {
            CaptureMoment(eventName, eventSubText, DefaultCategory, new TimelineMessage());
        }

        internal static void CaptureMoment(string eventName, TimelineCategoryItem category)
        {
            CaptureMoment(eventName, null, category, new TimelineMessage());
        }

        internal static void CaptureMoment(string eventName, TimelineCategoryItem category, ITimelineMessage message)
        {
            CaptureMoment(eventName, null, category, message);
        }

        internal static void CaptureMoment(string eventName, ITimelineMessage message)
        {
            CaptureMoment(eventName, null, DefaultCategory, message);
        }

        internal static void CaptureMoment(string eventName, string eventSubText, TimelineCategoryItem category, ITimelineMessage message)
        {
            if (string.IsNullOrEmpty(eventName))
            {
                throw new ArgumentNullException("eventName");
            }

#pragma warning disable 618
            var executionTimer = GlimpseConfiguration.GetConfiguredTimerStrategy()();
            var messageBroker = GlimpseConfiguration.GetConfiguredMessageBroker();
#pragma warning restore 618

            if (executionTimer == null || messageBroker == null)
            {
                return;
            }

            message
                .AsTimelineMessage(eventName, category, eventSubText)
                .AsTimedMessage(executionTimer.Point());

            messageBroker.Publish(message);
        }

        public class OngoingCapture : IDisposable
        {
            public static OngoingCapture Empty()
            {
                return new NullOngoingCapture();
            }

            private OngoingCapture()
            {
            }

            public OngoingCapture(IExecutionTimer executionTimer, IMessageBroker messageBroker, string eventName, string eventSubText, TimelineCategoryItem category, ITimelineMessage message)
            {
                Offset = executionTimer.Start();
                ExecutionTimer = executionTimer;
                Message = message.AsTimelineMessage(eventName, category, eventSubText);
                MessageBroker = messageBroker;
            }

            private ITimelineMessage Message { get; set; }

            private TimeSpan Offset { get; set; }

            private IExecutionTimer ExecutionTimer { get; set; }

            private IMessageBroker MessageBroker { get; set; }

            public virtual void Stop()
            {
                var timerResult = ExecutionTimer.Stop(Offset);

                MessageBroker.Publish(Message.AsTimedMessage(timerResult));
            }

            public void Dispose()
            {
                Stop();
            }

            private class NullOngoingCapture : OngoingCapture
            {
                public override void Stop()
                {
                }
            }
        }
    }
}
```

(There are several slightly different versions of this code around on the internet, I took this version from the following gist: https://gist.github.com/johnjuuljensen/776e61b720c2a7e5b6ef)

With this helper logic we can add our own timing events to our controller.

```csharp
using Glimpse.Core;
...
List<Manufacturer> manufacturers;
using (GlimpseTimeline.Capture("Loading from DB"))
{
    manufacturers = await ctx.Manufacturers.Include("Models").ToListAsync();
}

using (GlimpseTimeline.Capture("Fetching product prices"))
{
    await this.LoadPrices(manufacturers.SelectMany(m => m.Models));
}
```

Our custom timeline events will show up in the timeline tab.

![Custom Timeline events.](/images/2015/05/100timeline.png)

If you'd like to take a look at it, you can find the whole source code on [GitHub](https://github.com/markvincze/glimpse-web-api).
#Conclusion
We've seen that setting up Glimpse for the Web Api is just as easy as using it with MVC, however, the feature set supported is much more limited. Still, Glimpse can be a very useful tool to analyze what's going on under the hood in a Web Api application as well.
