+++
title = "Automated, portable code style checking in .NET Core projects"
slug = "automated-portable-code-style-checking-in-net-core-projects"
description = "A quick introduction to setting up automated code style checking for .NET Core projects with StyleCopAnalyzers and editorconfig."
date = "2018-07-08T15:48:55.0000000"
tags = ["c#", ".net-core", "linting"]
ghostCommentId = "ghost-5b422ffe19ac3b1e3f6dd2b1"
+++

I haven't been using automated code style checking in .NET before. I sporadically experimented with StyleCop, FxCop, or the code style rules of ReSharper, but never ended up using them extensively, or introducing and distributing a maintained configuration in the organization I was working in.

Recently having worked on JavaScript and TypeScript projects, I really started to appreciate how straightforward and established the process of linting is in those communities: it seems to be almost universal that every project in the JS and TS ecosystem is using `eslint` and `tslint` respectively, and the way to specify the linting rules is very straightforward.

So I decided to take a look at the options available today to do linting for .NET Core (mainly C#) projects. My preferences were the following.

 - Be able to customize the linting rules, and distribute that configuration to be used in every project in our organization.
 - Preferably have integration for both Visual Studio and Visual Studio Code.
 - Besides IDE integration, be able to also execute it in our CI-builds, and make the build fail if there are linting errors.
 - Related to the above, be able to run it in the terminal not just on Windows, but also on Linux and Mac.

ReSharper provides the linting capability and the distributable configuration, but the IDE-integration is only there if you're using the ReSharper extension in Visual Studio, and it doesn't work in VSCode. Because of this I ruled ReSharper out. It can still be a viable option if everyone on your project is using VS with ReSharper, but I wanted to choose method that I can use both at work and in my open source projects.

Other than ReSharper, the two tools I found were [StyleCopAnalyzers](https://github.com/DotNetAnalyzers/StyleCopAnalyzers), and [editorconfig](https://docs.microsoft.com/en-us/visualstudio/ide/create-portable-custom-editor-options).

I could not manage to set up editorconfig in a way that it was reliably working, on the other hand, StyleCopAnalyzers was working fairly well, although not yet delivering all the above points.  
The rest of the post will be about setting up and configuring StyleCopAnalyzers for your project, and in the end I'll include some details about my experience with editorconfig too.

To be able to test these tools, I created a sample project where I intentionally made some code style violations that I would want the linters to warn about. I uploaded the code [here](https://github.com/markvincze/CodeStyleCheckSample), where I created two branches, [`stylecopanalyzers`](https://github.com/markvincze/CodeStyleCheckSample/tree/stylecopanalyzers) and [`editorconfig`](https://github.com/markvincze/CodeStyleCheckSample/tree/editorconfig) for the setup of the two tools.

# Adding StyleCopAnalyzers to your project

Including StyleCopAnalyzers in your project is very simple, it's basically just adding the reference to its Nuget package. You can do this from the terminal with `dotnet`.

```plain
dotnet add package StyleCop.Analyzers
```

After this, if you try to build your project, you'll immediately receive the violations in the form of compiler warnings.

```plain
$ dotnet build
Microsoft (R) Build Engine version 15.7.179.6572 for .NET Core
Copyright (C) Microsoft Corporation. All rights reserved.

  Restore completed in 33.08 ms for C:\Workspaces\Github\CodeStyleCheckSample\src\CodeStyleCheckSample\CodeStyleCheckSample.csproj.
MyClass.cs(20,13): warning SA1000: The keyword 'if' must be followed by a space. [C:\Workspaces\Github\CodeStyleCheckSample\src\CodeStyleCheckSample\CodeStyleCheckSample.csproj]
MyClass.cs(8,23): warning SA1401: Field must be private [C:\Workspaces\Github\CodeStyleCheckSample\src\CodeStyleCheckSample\CodeStyleCheckSample.csproj]
...
```

Or, if we add the `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` flag to our project file, these will be actual errors instead of just warnings. This is what I would generally suggest to do from the start, otherwise it's very easy to pile up hundreds or thousands of warnings in a large code base, which is daunting to clean up later. (This can typically be the situation when we want to introduce linting to an existing legacy project.)

The linting producing errors by the `dotnet build` command makes it very easy to wire this into our CI-build, since the build errors will make our CI-build fail too, so we don't need to do anything else.

The errors also nicely show up in Visual Studio, where we can even quickly fix them with Roslyn quick fixes.

![Linting errors showing up in Visual Studio](/images/2018/07/error-in-vs.png)

Unfortunately, at this moment, Visual Studio Code does not support displaying the errors coming from Roslyn analyzers, as mentioned in [this comment](https://github.com/DotNetAnalyzers/StyleCopAnalyzers/issues/2739#issuecomment-403258345). Thus StyleCopAnalyzers today is the most ideal if we are using Visual Studio. If we're using VSCode, we'll have to rely on the build errors produced by `dotnet build` instead of the IDE-integration.

# Customizing the linting rules

When using `eslint` and `tslint`, we can customize the linting rules by creating an `.eslintrc` or `tslint.json` file, respectively, where we can change both the violation severity, and also customize how some of the rules work (for example whether to enforce single quotes, double quotes, or accept both for string literals).

We can do similar customization with StyleCopAnalyzers, but the situation is a bit more complicated. There are two different configuration files we can use for different purposes.

## Turn rules on and off

In order to select which rules we even want to validate in the first place, we have to use a **Code analysis rule set file**, which has a format utilized by other analyzers, for example the built-in analyer in VS.  
We can turn off some of the rules we don't need by adding the following XML file (we can choose its name) to the project.

```xml
<?xml version="1.0" encoding="utf-8"?>
<RuleSet Name="Sample rule set" Description="Sample rule set illustrating customizing StyleCopAnalyzer rule severity" ToolsVersion="14.0">
  <Rules AnalyzerId="StyleCop.Analyzers" RuleNamespace="StyleCop.Analyzers">
    <Rule Id="SA1200" Action="None" />
    <Rule Id="SA1633" Action="None" />
  </Rules>
</RuleSet>
```

In the `<Rule>` element we have to specify the ID of the specific linting rule, and set the `Action` property to either `None`, `Info`, `Warning` or `Error`. To figure out the codes of the individual rules, we can find them in the output we get from the `dotnet` CLI.  
And we have to specify the name of our file in the `CodeAnalysisRuleSet` property in the project file.

```xml
    <CodeAnalysisRuleSet>SampleRuleSet.ruleset</CodeAnalysisRuleSet>
```


(One strange thing about the ruleset file is that if I try to open it in VS, instead of opening the XML in the text editor, it opens the built-in GUI for editing `ruleset` files, which simply doesn't work for me at all, it doesn't display any of the rules. However, I prefer editing the XML content by hand anyway, so I didn't investigate further about this problem.)

## Further customize certain rules

In order to fine-tune the behavior of certain rules, we can add a `stylecop.json` file to our project, and [add the following item](https://github.com/DotNetAnalyzers/StyleCopAnalyzers/blob/master/documentation/EnableConfiguration.md) to the project file:

```xml
  <ItemGroup>
    <AdditionalFiles Include="stylecop.json" />
  </ItemGroup>
```

This is a small example, in which I'm forbidding having a new line at the end of our source files.

```json
{
  "$schema": "https://raw.githubusercontent.com/DotNetAnalyzers/StyleCopAnalyzers/master/StyleCop.Analyzers/StyleCop.Analyzers/Settings/stylecop.schema.json",
  "settings": {
    "layoutRules": {
      "newlineAtEndOfFile": "omit"
    }
  }
}
```

![Rule customized with stylecop.json showing up in Visual Studio](/images/2018/07/stylecop-error-in-vs.png)

You can read about all the possible customization on [this page](https://github.com/DotNetAnalyzers/StyleCopAnalyzers/blob/master/documentation/Configuration.md). The set of rules supported today feels a bit ad-hoc and limited, but since the project is being actively developed, I expect this to improve in the future.

## Distributing our custom configuration

If we're working on multiple projects in an organization, it's important to be able to distribute our custom rules to all of the projects we're working on, to keep the linting rules consistent. The naive way to do this would be to maintain our `.ruleset` and `stylecop.json` files in a central place, for example a git repository, and then from time to time, copy the two files from this repo to our actual projects. Although this approach is doable, it's not ideal. Copy pasting the files can be a bit tedious, and the versioning of our configuration will be unclear.

A better way is to create a custom Nuget package, which references `StyleCop.Analyzers`, and also makes the projects depending on it including our custom configuration files in the correct way. This way we can use proper versioning for our linting configuration, and distribute it to the dependant projects as a Nuget dependency.

In order to do this properly, we need to set up a `.nuspec` and a `.props` file in our package, as it is described [in the documentation](https://github.com/DotNetAnalyzers/StyleCopAnalyzers/blob/master/documentation/Configuration.md#sharing-configuration-among-solutions).

You can find a working example of this setup in [this repo](https://github.com/markvincze/MyCustomStyleCopAnalyzerPackage).

# What about editorconfig?

Watching the [.NET Roadmap talk](https://channel9.msdn.com/Events/Build/2018/BRK2100) from the Build conference I learned that—contrary to what I thought before—`editorconfig` is not only capable of controlling basic, language-agnostic properties of our source files, such as indentation, newline at the end of a file, trimming trailing whitespace, etc., but with Visual Studio, it also supports enforcing actual C#-specific linting rules, such as qualifying fields with `this.`, sorting the user directives, etc.

Looking at some of the projects in the JS ecosystem ([react](https://github.com/facebook/react), [vue](https://github.com/vuejs/vue), [yarn](https://github.com/yarnpkg/yarn), just to name a few) it seems pretty universal that the JS-specific linting is done through `eslint`, and editorconfig is used only to control a handful of low-level properties of the source files. So `eslint` and `editorconfig` are complementary.

On the other hand, now in the .NET ecosystem it seems that `StyleCopAnalyzers` and the C#-specific `editorconfig` integration in Visual Studio aren't really complementary, but they are rather competing alternatives, which seems to be a strange situation to me, since both have some shortcomings at the moment. Although I haven't heard any "official" information about how this will play out, so I might be misunderstanding the situation.

Nevertheless, I gave `editorconfig` a try too (you can see it in the [`editorconfig`](https://github.com/markvincze/CodeStyleCheckSample/tree/editorconfig) branch of the sample repo), but couldn't get it to work reliably. It doesn't seem to integrate into VSCode at all, and also in Visual Studio for me only some of the rules were working, some others were simply not triggered.  
And my biggest issue was that although VS picks up the `editorconfig` rules, and—depending on the configuration—it might show them as Errors, but it doesn't make the actual build fail, so I couldn't find a way to also integrate into the CI-worklow.

# Conclusion

Based on the above I'd say that right now the preferable way to implement portable, automated code style checking for a .NET Core project is to use `StyleCopAnalyzers`, even if it doesn't directly support VSCode.

I'm really curious how this area is going to improve in the future, and especially the role that `StyleCopAnalyzers` and `editorconfig` are going to play in linting .NET Core projects.  
For me the sweet spot would be if we had one unified way of doing linting for .NET Core, with a single configuration file, VSCode support, and maybe with even core integration into the `dotnet` CLI as a separate `lint` command, so that we could run it separately from our build.
