+++
title = "Couchbase Server: tips for troubleshooting issues"
slug = "couchbase-server-tips-for-troubleshooting-issues"
description = "This blog post describes some quirks and issues with Couchbase Server which can make getting started with it more difficult and troublesome."
date = "2016-01-10T15:45:00.0000000"
tags = ["c#", ".net", "couchbase"]
ghostCommentId = "ghost-10"
+++

Recently at work we started using Couchbase Server to replace a rather outdated caching solution in our architecture. This was the first time I had to use Couchbase and its .NET SDK, and I have encountered a couple of issues along the way.

This post is a recollection of the problems we faced. (If you are interested in a "getting started" tutorial, I recommend reading the [official documentation](http://docs.couchbase.com/developer/dotnet-2.0/dotnet-intro.html) of the .NET SDK, it has a pretty good description about what you can with the SDK, and the API is rather simple, so you shouldn't have a hard time getting started with it.)

# Logging

Probably the single most important tool for troubleshooting problems for me was using the built-in logging of the .NET SDK. It can give much more detailed insights into the mechanisms going on in the SDK than what you can get from the `IDocumentResult` or `OperationResult` object you get from the API.

The SDK uses `Common.Logging` and `log4net`. Enabling file-based logging is very simple, you basically just have to add the following section to your app or web configuration file.

```xml
<configuration>
  <configSections>
    <sectionGroup name="common">
      <section name="logging" type="Common.Logging.ConfigurationSectionHandler, Common.Logging" />
    </sectionGroup>
    <section name="log4net" type="log4net.Config.Log4NetConfigurationSectionHandler, log4net" />
  </configSections>

  <common>
    <logging>
      <factoryAdapter type="Common.Logging.Log4Net.Log4NetLoggerFactoryAdapter, Common.Logging.Log4Net">
        <arg key="configType" value="INLINE" />
      </factoryAdapter>
    </logging>
  </common>
  
  <log4net>
    <appender name="FileAppender" type="log4net.Appender.FileAppender">
    <param name="File" value="C:\temp\log.txt" />
    <layout type="log4net.Layout.PatternLayout">
      <conversionPattern value="%date [%thread] %level %logger - %message%newline" />
    </layout>
    </appender>
    <root>
      <level value="INFO" />
      <appender-ref ref="FileAppender" />
    </root> 
  </log4net>
</configuration>
```

Source and more details on the official Couchbase blog: [Couchbase .NET SDK 2.0 Development Series: Logging](http://blog.couchbase.com/couchbase-net-sdk-20-development-series-logging)

# Using Fiddler

When troubleshooting timeout problems or sluggishness, it can be beneficial to take a look at what kind of requests the SDK is trying to send, and what ports it is trying to access.  
You don't necessarily have to understand what the requests are about, it is often enough to 
see which request is failing to get some clue about the problem.

![Screenshot illustrating Couchbase requests captured with Fiddler.](/images/2016/01/couchbase-fiddler.png)

Keep in mind that you might have to explicitly configure your application to use the proxy provided by Fiddler, you can find the details [here](http://docs.telerik.com/fiddler/Configure-Fiddler/Tasks/ConfigureDotNETApp).  
Also, if you have your Couchbase server installation on the local machine, you have to use `ipv4.fiddler` instead of `localhost` in the url configuration.

# Networking issues

It is pretty easy to run into networking issues when using Couchbase, especially if the server and the client run in a different network or environment, for example in different clouds.

One of the reasons for these issues can often be a firewall between the two computers, because Couchbase uses many different ports, and not just port 80. You can find the list of these ports in the [official documentation](http://docs.couchbase.com/admin/admin/Install/install-networkPorts.html).

This can cause either the connection to not work at all, or can cause long response times of the SDK.  
Luckily these issues are usually easy to spot, because they produce an error in the logs, or you can see the failed requests with Fiddler, and opening the port in the firewall solves the problem.

There is still one problem I couldn't solve. If I hosted a Couchbase cluster in Amazon EC2, and tried to access it from a virtual machine in Azure, I got randomly slow response times. You can find the details in this [Stack Overflow question](http://stackoverflow.com/questions/34204339/use-couchbase-hosted-in-amazon-from-a-client-hosted-in-azure-what-can-cause-bad?noredirect=1#comment56154827_34204339). Luckily this was only a test setup, our production architecture is different, but it would be still interesting to find the root cause of this.

# Default `<bucket>` configuration

There is a surprising gotcha related to the bucket configurations of the SDK.  
There are two ways to open buckets: you can either statically preconfigure the bucket to use in the app.config:

```xml
<couchbaseClients>
  <couchbase useSsl="false" operationLifeSpan="1000">
    <servers>
      <add uri="http://192.168.56.101:8091/pools"></add>
    </servers>
    <buckets>
      <add name="my-bucket-name" useSsl="false" password="" operationLifespan="2000">
        <connectionPool name="custom" maxSize="10" minSize="5" sendTimeout="12000"></connectionPool>
      </add>
    </buckets>
  </couchbase>
</couchbaseClients>
```

In this case if you try to open the bucket `my-bucket-name`, its configuration will be picked up from the config file.

However, there can be situations in which the name of the buckets you want to use are only known dynamically during runtime, so you cannot preconfigure any buckets. In that case you `couchbaseClients` section will look like this:

```xml
<couchbaseClients>
  <couchbase useSsl="false" operationLifeSpan="1000">
    <servers>
      <add uri="http://192.168.56.101:8091/pools"></add>
    </servers>
  </couchbase>
</couchbaseClients>
```

The weird thing is that now if you try to open a bucket by using `cluster.OpenBucket(bucketName)`, the SDK does not pick up the server configuration from the `<servers>` section, but at first it tries to connect to `localhost`, and it only uses the proper server after that fails.  
This can have two consequences:

 - If we have no Couchbase server running at localhost:8091, opening the bucket can take seconds, because the client is trying to connect to localhost at first, and only after that fails does it connect to the configured server. This problem and a workaround is described in [this SO question](http://stackoverflow.com/questions/34183342/why-can-opening-a-couchbase-bucket-be-very-slow).
 - If we actually do have a server at localhost:8091, then that is getting used instead of the one configured in `<servers>`. I consider this clearly a bug.

The workaround is simple: you just have to add a dummy bucket to the configuration:

```xml
<couchbaseClients>
  <couchbase useSsl="false" operationLifeSpan="1000">
    <servers>
      <add uri="http://192.168.56.101:8091/pools"></add>
    </servers>
    <buckets>
      <add name="dummy-bucket" useSsl="false" operationLifespan="1000">
      </add>
    </buckets>
  </couchbase>
</couchbaseClients>
```

A bucket with the specified name doesn't even have to exist on the server. Solely the existence of that section will make the SDK pick up the server configuration from the `<servers>` section.

You can find some more details in [this SO question](http://stackoverflow.com/questions/34183342/why-can-opening-a-couchbase-bucket-be-very-slow), and my proposed fix in the [following pull request](https://github.com/couchbase/couchbase-net-client/pull/52).

# TCP connection count

If you are accessing Couchbase at a high volume, possibly on multiple threads, the client can easily run out of available TCP connections. The maximum number of TCP connections can be configured in the app.config. Its default value is 2, which is really low, and it can cause the operation to fail. In the logs and in the result object you can see an exception similar to this.

```plain
The operation has timed out.
Couchbase.IO.ConnectionUnavailableException: Failed to acquire a pooled client connection on 192.168.56.101:11210 after 5 tries.
    at Couchbase.IO.ConnectionPool`1.Acquire()
    at Couchbase.IO.ConnectionPool`1.Acquire()
    at Couchbase.IO.ConnectionPool`1.Acquire()
    at Couchbase.IO.ConnectionPool`1.Couchbase.IO.IConnectionPool.Acquire()
    at Couchbase.IO.Strategies.DefaultIOStrategy.Execute[T](IOperation`1 operation)
    at Couchbase.Core.Server.Send[T](IOperation`1 operation)
```

The solution is to increase the number of maximum TCP connections, which can be separately controlled on a default level, or for a specific bucket:

```xml
<couchbaseClients>
    <couchbase>
        <servers>
            <add uri="http://192.168.56.101:8091/pools"/>
        </servers>
        <connectionPool name="default" maxSize="35" minSize="5" sendTimeout="15000">
        </connectionPool>
        <buckets>
            <add name="default">
                <connectionPool maxSize="30" minSize="5" name="default"/>
            </add>
        </buckets>
    </couchbase>
</couchbaseClients>
```

For us a pool size of 30 seems to have solved the problem, you should fine tune the configuration until you find a proper value for your scenario.

I found this solution with an official answer in the [Couchbase Forums](https://forums.couchbase.com/t/failed-to-acquire-a-pooled-client-connection-after-5-tries/6062/6?u=markvincze)

#The importance of `ClusterHelper`

When we use the `OpenBucket` of the `ICluster` interface, a new TCP connection will be made to the Couchbase server. That bucket object should be used in a `using` block, and when the object is disposed, the connection will be closed. The performance of this approach is not ideal if we are accessing Couchbase at a high volume.

Luckily the SDK contains support for pooling TCP connection in the form of the `ClusterHelper` class. A couple of things to keep in mind:

- During the startup of your application (for example in the `Global.asax.cs` in case of a web application) you need to initialize the helper by calling `ClusterHelper.Initialize(...)`.
- When your application shuts down, you should call `ClusterHelper.Close()`.
- If you open a bucket with `ClusterHelper.GetBucket(...)`, you **should not** put it in a using block. The ClusterHelper will internally manage and dispose the bucket objects.

You can find more details about this in the [official documentation](http://developer.couchbase.com/documentation/server/4.0/sdks/dotnet-2.2/cluster-helper.html).

Couchbase is a very exciting technology, on which big companies are betting (Ebay, LinkedIn, Ryanair, etc.). It's great to be able to replace an outdated legacy caching system with something more modern, and far better scalable.  
However, the above problems can be quite annoying, and they can make the introduction of Couchbase in your architecture more challenging.  
I hope this post will help you avoid making the same mistakes, or at least spend less time looking for the solution.
