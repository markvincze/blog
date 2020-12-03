+++
title = "Playing with the composition of the Kleisli category in C#"
slug = "playing-with-the-composition-of-the-kleisli-category-in-c"
description = "Taking a look at how the composition of the Kleisli category can be implemented in C#, and what are the limitations we have to face in type inference."
date = "2017-04-19T21:27:16.0000000"
tags = ["c#", "f#", "category-theory"]
ghostCommentId = "ghost-36"
+++

# Introduction

Recently I learnt about an interesting concept in category theory called a *Kleisli category*.

Let's look at a concrete example I took from [this blog post](https://bartoszmilewski.com/2014/12/23/kleisli-categories/) (in his series about category theory) by Bartosz Milewski.
We would like to extend all of the functions in a library in a way that besides their normal result, they also return an extra string. We'll consider this extra string a sort of log message or "comment", which we'll collect as we call various methods.

For example we might have the following original method.

```csharp
int Increment(int x)
{
    return x + 1;
}
```

We can extend it the following way to also return a message.

```csharp
(int result, string log) Increment(int x)
{
    return (x + 1, "Incremented");
}
```

(I wanted to be fancy, so I'm using C# 7 tuple literals, but I could also have used a `Tuple<int, string>` as the return type.)
For the sake of the example I'll implement another method.

```csharp
(int result, string log) Double(int x)
{
    return (x * 2, "Doubled");
}
```

If we extend the return type of a function with something extra like this, we call it an *embellished* function. We could imagine many other useful ways to embellish functions. For example we could return what the execution time of the function was, or return a second value containing any errors happened during the call.

It turns out that if we define a way to compose such embellished functions (for example compose `Increment` and `Double` so that they are applied after each other), and if we can compose the embellished return values associatively (for example the extra log messages can be concatenated), then our input and output data types, and our functions will form a specific *category* of category theory called the *[Kleisli category](https://en.wikipedia.org/wiki/Kleisli_category)*. If you are interested in the details, I recommend the [above mentioned post](https://bartoszmilewski.com/2014/12/23/kleisli-categories/).

# Composition

In this post I'm going to focus on the **composition** part, more specifically how such composition can be implemented in C#.

We want to have a method—let's call it `Compose`—which takes two such embellished functions as input, and returns their composition, that is, a method that executes the two functions after each other, returns the second output, and concatenates the extra log messages.
*(Note: I'm using the C# terminology pretty loosely here. In C# functions are not first class citizens to the extent they are in some other languages, although we can have various constructs that we can use in a similar way, such as delegates, method groups, anonymous functions or lambda expressions.)*

It was pretty straightforward to implement a specific composition method for the above scenario. The only tricky part, that needed an extra mental step is that in this method we shouldn't actually *call* the functions passed as inputs, but we just have to return a function that will call them when executed.

```csharp
Func<int, (int, string)> Compose(Func<int, (int, string)> a, Func<int, (int, string)> b)
{
    return (int x) =>
    {
        var (aResult, aLog) = a(x);
        var (bResult, bLog) = b(aResult);
        return (bResult, aLog + bLog);
    };
}
```

We can try our composition method in a console application.

```csharp
var incrementAndDouble = Compose(Increment, Double);

var (result, log) = incrementAndDouble(2);

Console.WriteLine($"Result: {result}, Log: {log}");
```

And in the terminal we'll see that it works:

```
Result: 6, Log: IncrementedDoubled
```

## Generic composition

The second thing I wanted to achieve is to improve the `Compose` method by making it generic, so that it can work for all input and output types, not just for integers. This didn't seem to be difficult to achieve, I replaced the concrete types with generic type parameters (except the `string`, with which the return type is embellished).

```csharp
Func<A, (C, string)> Compose<A, B, C>(Func<A, (B, string)> a, Func<B, (C, string)> b)
{
    return (A x) =>
    {
        var (aResult, aLog) = a(x);
        var (bResult, bLog) = b(aResult);
        return (bResult, aLog + bLog);
    };
}
```

The configuration of the type parameters nicely correspond to function composition in a mathematical sense, since if we have a function `f :: a -> b` and `g :: b -> c`, then the type of their composition will be `g ∘ f :: a -> c`. Notice that although we use integers both as our input and output, in the generic `Compose` we still have different type arguments for the parameters and the return values, so it also supports functions that have different input and output types.

I was really happy with this implementation, the building blocks of C# seemed to fall nicely in place. Unfortunately when I tried to use this generic version of `Compose` with the same call:

```csharp
var incrementAndDouble = Compose(Increment, Double);
```

I received the following build error.

>`Error CS0411: The type arguments for method 'Program.Compose<A, B, C>(Func<A, (B, string)>, Func<B, (C, string)>)' cannot be inferred from the usage. Try specifying the type arguments explicitly.`

I was surprised by this error message, and couldn't immediately figure out its reason. Since in the two methods `Increment` and `Double` the parameter and return types are explicitly specified, I thought the compiler would be able to *infer* the proper values for the type arguments.

I found the reason in the answer to [this SO question](http://stackoverflow.com/questions/7400550/c-sharp-infer-generic-type-based-on-passing-a-delegate): The C# spec states that type inference based on the output type only works if the types are explicitly specified, *or* if we pass in an anonymous function. The C# constructs we're trying to pass in to `Compose` are *method groups*, and the spec does not require the type inference to work for them. (This would not be impossible to do, but it would probably not worth the effort by the compiler, and it could cause more problems, as stated by Eric Lippert in [this comment](http://stackoverflow.com/questions/6229131/why-cant-c-sharp-infer-type-from-this-seemingly-simple-obvious-case#comment7312385_6231921). One of the reasons why this is problematic, is that a method group might have more than one corresponding method underneath because of method overloading, in which case the type inference wouldn't necessarily be unambiguous.)

The way to work around this is to help the compiler, and somehow tell it the actual types of our methods.
We can either explicitly specify the type arguments:

```csharp
var incrementAndDouble = Compose<int, int, int>(Increment, Double);
```

Or—as the spec suggests—pass in the methods as anonymous functions instead of method groups:

```csharp
var incrementAndDouble = Compose((int x) => Increment(x), (int x) => Double(x));
```

I'm not particularly happy about these workarounds, but so far I couldn't find an easier way to do this in C#.

I'm not sure if I'll ever use this approach in a real project, but I found this example interesting enough to share, especially regarding the limitations of the C# type inference algorithm.

# Composition in F&#35;

Just to see what the same thing would look like in a language where functions are first-class citizens (and where we don't have function overloading), here is the implementation of the same two functions and the generic composition in F#.

```fsharp
let increment x = (x + 1, "Incremented")

let double x = (x * 2, "Doubled")

let compose a b =
    fun x ->
        let (ares, alog) = a x
        let (bres, blog) = b ares
        (bres, alog + blog)

let incrementAndDouble = compose increment double

let (result, log) = incrementAndDouble 2

printfn "Result: %i, Log: %s" result log
```

I really like the clarity of the of this code, and especially that through the powerful type inference capabilities of the F# compiler we get both strict strong typing and genericity without explicitly specifying any type signature.

The automatically inferred type signature of the `compose` function is the following (where `a * b` means a tuple of `a` and `b`):

```fsharp
val compose : a:('a -> 'b * string) -> b:('b -> 'c * string) -> x:'a -> 'c * string
```

Which nicely resonates with the generic type signature we had to specify in the C# implementation.

I hope you found this post interesting, and—especially since I'm still in the very beginning of learning about category theory—any feedback and suggestion is welcome.
I'll try to write some more posts like this as I continue experimenting with concepts of category theory in C# and F#.
