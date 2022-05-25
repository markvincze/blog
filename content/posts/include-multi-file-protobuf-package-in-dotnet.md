+++
title = "Include a multi-file protobuf package in a .NET Core project"
slug = "include-multi-file-protobuf-package-in-dotnet"
description = "How to include protobuf contracts consisting of multiple files in .NET Core projects."
date = "2022-05-25T21:00:00.0000000"
tags = [".net-core", "protobuf", "grpc"]
+++

We can get the .NET types for a Protobuf contract automatically generated in a .NET Core project by adding a reference to a proto file.  
A basic example from the [official docs](https://docs.microsoft.com/en-us/aspnet/core/grpc/?view=aspnetcore-6.0#c-tooling-support-for-proto-files) is having the following proto file in our project.

```proto
syntax = "proto3";

service Greeter {
  rpc SayHello (HelloRequest) returns (HelloReply);
}

message HelloRequest {
  string name = 1;
}

message HelloReply {
  string message = 1;
}
```

If we have this file inside our project folder in a subfolder called `Protos`, we can reference it in our project the following way.

```xml
<ItemGroup>
  <Protobuf Include="Protos\greet.proto" />
</ItemGroup>
```

The contract in the above example consists of one single `proto` file.

In real-life applications with more complicated contracts, it is typical to structure our proto contract into multiple files and multiple "packages", where files can reference each other with the `import` statement.  
When we want to reference such multi-file proto contracts, we might encounter errors related to the proto file imports paths.

The way imports are processed by the code generation depends on whether the proto files are physically under folder of the .NET Core project or not.

## Proto files physically under the project folder

Let's say we have two proto files physically in our project folder, under a `Protos` subfolder.
The first file, `bar.proto`:

```proto
syntax = "proto3";

message Bar {
  string prop1 = 1;
}
```

And the second file, `foo.proto`, which is referencing the first one:

```proto
syntax = "proto3";

import "Protos/bar.proto";

message Foo {
  string prop1 = 1;
  Bar prop2 = 2;
}
```

Notice that even though the proto files are in the same folder, the import statement uses the path `Protos/bar.proto`, and not just `bar.proto`. The reason for this is that by default, the .NET tooling interprets the import paths as being relative to the root of the project.

Then we can include the two proto files in our project, and the build will successfully generate the corresponding types.

```xml
  <ItemGroup>
    <Protobuf Include="Protos\bar.proto" />
    <Protobuf Include="Protos\foo.proto" />
  </ItemGroup>
```

So this approach works fine if our proto files are physically under the project folder, and they are using import paths which are all relative to the root of the project.

## Proto files physically outside of the project folder

There can be scenarios when we don't want to put the proto files physically under our project folder.  
The typical example is if we are maintaining our Protobuf contracts in a separate Git repository to share it across multiple consumers. In this case, the repository containing the contracts is often included in the consumer repos as a Git submodule, which we typically want to include in their own folder at the root of our repository.

In this case, the proto files will not be present physically under the project folder, and thus the build process won't find the imported proto files.

In this case we typically also want to specify a `package` for our Protobuf contracts, and structure the folder structure in the contracts repository according to the package name.  
Let's say we have the same contract as above, and we want to name this package `acme.demo.v1`. (The `.v1` suffix is a [common practice](https://docs.buf.build/lint/rules#package_version_suffix) to make it easier to eventually introduce breaking changes.)  
In this case we want to have these two proto files under the following folder structure.

```
. // This is the root of our contracts repository, which we might include as a submodule in the consumer repos.
└── acme
    └── demo
        └── v1
            ├── bar.proto
            └── foo.proto
```

And the content of the two files are slightly different than before, they specify the `package`, and the import paths are all relative _to the root of the package_. (More details about how Protobuf packages should typically be structured can be found [here](https://docs.buf.build/tour/use-a-workspace).)  

`bar.proto`:

```proto
syntax = "proto3";

package acme.demo.v1;

message Bar {
  string prop1 = 1;
}
```

`foo.proto`:

```proto
syntax = "proto3";

package acme.demo.v1;

import "acme/demo/v1/bar.proto";

message Foo {
  string prop1 = 1;
  Bar prop2 = 2;
}
```

Let's say that the contracts repo is included in our consumer repository as a submodule in a folder called `contracts` at the root of our repo, so our repository with the .NET Core solution has the following structure.

```
.
├── contracts // This is the submodule for the contracts repo
|   └── acme
|       └── demo
|           └── v1
|               ├── bar.proto
|               └── foo.proto
├── src
|   └── Acme.Consumer.Service
|       ├── Acme.Consumer.Service.csproj
|       └── SomeCodeFile.cs
└── Acme.Consumer.sln
```

In this case we can add the `<Protobuf />` references to our `csproj` file by using relative paths.

```xml
  <ItemGroup>
    <Protobuf Include="..\..\contracts\acme\demo\v1\bar.proto" />
    <Protobuf Include="..\..\contracts\acme\demo\v1\foo.proto" />
  </ItemGroup>
```

The problem with this is that because the `import` paths in our proto files are interpreted as being relative to the _root of our project folder_, the `import` statement in `foo.bar` won't work, we'll get the following build error.

```
acme/demo/v1/bar.proto : error : File not found. [...\src\Acme.Consumer.Service\Acme.Consumer.Service.csproj]
../../contracts/acme/demo/v1/foo.proto(5,1): error : Import "acme/demo/v1/bar.proto" was not found or had errors.
```

Luckily, there is a simple solution, we can add the `AdditionalImportDirs` attribute to the `<Protobuf \>` element to specify the root of our contracts folder to be considered as an extra possible root for the `import` statements.

```
  <ItemGroup>
    <Protobuf Include="..\..\contracts\acme\demo\v1\bar.proto" AdditionalImportDirs="..\..\contracts" />
    <Protobuf Include="..\..\contracts\acme\demo\v1\foo.proto" AdditionalImportDirs="..\..\contracts" />
  </ItemGroup>
```

Once we do this, the build will work correctly. This issue took me a while to figure out, I couldn't find much information about the `AdditionalImportDirs` attribute in the documentation. (The first search result I can find is an [open issue](https://github.com/grpc/grpc/issues/22878) to add it to the docs.)  
I hope this post will save you some time when encountering this problem.

I have uploaded a demo solution containing an example for these two approaches [here](https://github.com/markvincze/ProtobufImportDemo).
