+++
title = "How to fix the empty SpecFlow HTML report problem with vstest.console.exe"
description = "The slightly changed TRX generation in vstest.console.exe causes SpecFlow to generate empty HTML reports. This can be fixed with a custom Logger."
date = "2016-04-23T15:57:05.0000000"
tags = ["specflow"]
+++

## Introduction

There are multiple ways to run an MsTest test suite from the command line. The older, now deprecated tool is `mstest.exe`. It executes the test suite and produces an output in an XML-based format called TRX.  
Other tools, including the SpecFlow HTML report generation build upon that TRX format.

The newer, current way to execute the unit tests in a project is `vstest.console.exe`. This new tool has a pluggable logging system, it supports specifying different "loggers", which can produce different outputs.  
One of the built-in loggers is called `trx`, which is supposed to produce the output in the same format as mstest.exe did.

The problem with this TRX logger is that it produces a slightly different output than mstest.exe, which beaks the SpecFlow report generation. If you try to generate an HTML report from the new TRX file, the report will be empty, all the test names and descriptions will be missing.

![Empty SpecFlow HTML report.](/images/2016/04/empty-specflow-report.png)

## The problem

The issue was discussed in the a [GitHub issue](https://github.com/techtalk/SpecFlow/issues/278) in the SpecFlow repository. Paul Rohorzka identified the differences between the two TRX outputs causing the problems with the report:

>1. `//TestRun/TestDefinitions/UnitTest/TestMethod/@className` renders not the fully qualified name, but just the namespace.  
Effect for report generation: **No relevant textual output at all**

>2. The `TestDescriptionAttribute` is not rendered, but should be in `//TestRun/TestDefinitions/UnitTest/Description`.  
Effect for report generation: **No scenario titles**

>3. `TestPropertyAttributes` are not rendered, but should be in `//TestRun/TestDefinitions/UnitTest/Properties`.  
Effect for report generation: **No feature titles**

## The solution

Luckily thanks to the pluggable nature of the `vstest.console.exe` logging, it's possible to hook in a custom Logger implementation when executing the test suite.

In order to do this we need to implement the interface `Microsoft.VisualStudio.TestPlatform.ObjectModel.Client.ITestLogger`, where we can implement our fully custom code generating the output (instructions to get started can be found [here](https://blogs.msdn.microsoft.com/vikramagrawal/2012/07/26/writing-loggers-for-command-line-test-runner-vstest-console-exe/)).

Then the compiled assembly should be copied into `C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\CommonExtensions\Microsoft\TestWindow\Extensions` so that `vstest.console.exe` can pick it up.  
The last thing to do is to specify that we want to use that particular logger. That can be done with the `Logger` parameter of the test runner. Example:

```bash
vstest.console.exe ... /Logger:MyCustomLogger
```

The name of the logger has to be equal to the value specified in the `FriendlyName` attribute on our implementation class.

I implemented a custom logger called `MsTestTrxLogger` in which I replicated to format of the old `mstest.exe`. I tried to make it generate an output as close to the original as possible, but I had to make some assumptions. A [post](https://blogs.msdn.microsoft.com/dhopton/2008/06/13/helpful-internals-of-trx-and-vsmdi-files/) by Dominic Hopton about TRX internals helped in filling in some of the details.

I uploaded the solution with instructions about how to use it to this [GitHub repository](https://github.com/markvincze/MsTestTrxLogger).

It was an interesting experience to to reverse engineer the `mstest.exe` output and try to replicate that using the data model provided by `Microsoft.VisualStudio.TestPlatform.ObjectModel`, and it's nice to see that with some tinkering we can fully customize the output of `vstest.console.exe`.

So far it's working perfectly with the SpecFlow report of a test suite containing ~300 tests. However, due to the assumptions I had to make, it might now work perfectly in every situation. So issue reports (or pull requests :)) are welcome if you find any problems.
