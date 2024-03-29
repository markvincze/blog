+++
title = "Introducing Sabledocs, a documentation generator for Protobuf and gRPC"
slug = "introducing-sabledocs-documentation-generator-for-protobuf-grpc"
description = "Introducing a new open-source project called sabledocs, which is a static documentation generator for Protobuf and gRPC contracts."
date = "2023-04-16T20:00:00.0000000"
tags = ["documentation", "protobuf", "grpc", "python"]
+++

In this post I'd like to introduce a a new project called [**Sabledocs**](https://github.com/markvincze/sabledocs), a simple static documentation generator for Protobuf and gRPC contracts.

As I started using Protobuf and gRPC more and more for service-to-service communication, I started looking for a way to generate documentation for the Protobuf contracts.

I had the following requirements.

 - Be able to generate static HTML documentation with a CLI.
 - Include both gRPC service contracts, and ordinary Protobuf data models.
 - Generate one documentation site for multiple packages.
 - Customizable HTML template.
 - Free and preferably open source.

I have found some existing technologies and services, some of them are described in [this post](https://blog.gendocu.com/posts/documenting-grpc/), but each of them had something lacking. `protoc-gen-doc` only works for data contracts, and not for gRPC, `grpc-docs` seemed a bit convoluted to use, and needed React to serve the docs instead of generating static HTML. And GenDocu Cloud and Buf are commercial products offering hosted documentation as a service, and not static content generation.

Thus I decided to try to implement a new documentation generator which satisfies the requirements listed above.  
It has been an interesting process, I've learned a lot about the Protobuf format, the binary Proto descriptor generated by `protoc`, and the [Jinja2](https://jinja.palletsprojects.com/en/3.0.x/) Python templating engine, which I used for the HTML content generation.

The project has reached the point where it supports the basic Protobuf features, which can be enough to start using it for real applications.  
[Here you can see a demo](https://markvincze.github.io/sabledocs/demo) demonstrating the currently supported capabilities, with a documentation generated from some of the Proto contracts of the [Google Cloud SDK](https://github.com/googleapis/googleapis/tree/master/google/pubsub/v1).

[![Screenshot from the generated documentation.](/images/2023/04/sable-docs-example.png)](https://markvincze.github.io/sabledocs/demo)

# How to use

## Generate the proto descriptor

In order to build the documentation, you need to generate a binary descriptor from your Proto contracts using `protoc`. If you don't have it yet, the `protoc` CLI can be installed by downloading the release from the official [protobuf](https://github.com/protocolbuffers/protobuf/releases) repository.

For example, in the folder where your proto files are located, you can execute the following command.

```
protoc *.proto -o descriptor.pb --include_source_info
```

*(It's important to use the `--include_source_info` flag, otherwise the comments will not be included in the generated documentation.)*

The generated `descriptor.pb` file will be the input needed to build the documentation site.

## Build the documentation

Install the `sabledocs` package. It requires [Python](https://www.python.org/downloads/) (version 3.11 or higher) to be installed.

```
pip install sabledocs
```

In the same folder where the generated `descriptor.pb` file is located, execute the command.

```
sabledocs
```

The documentation will be generated into a folder `sabledocs_output`, its main page can be opened with `index.html`.

More information about further customization options can be found in the [README](https://github.com/markvincze/sabledocs).

# Summary and further features
 
There are some features not yet implemented that eventually I'd like to support, for example the following.

 - Certain Protobuf language features such as `oneof` and `option` annotations.
 - Streamlined support and documentation for creating a custom HTML template.
 - Dark mode and mobile support in the default template.

I hope this library will be useful for others too, particularly as gRPC seems to be becoming more and more popular as an alternative for REST and SOAP.

If you try it out, [any feedback or missing features](https://github.com/markvincze/sabledocs/issues) are welcome!

