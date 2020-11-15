+++
title = "A data model exercise in two languages, part 1: C#"
slug = "a-data-model-exercise-in-two-languages-part-1-c"
description = "A simple data model exercise illustrating some challenges we encounter when designing domain models in object oriented programming languages."
date = "2017-05-04T19:29:25.0000000"
tags = ["c#", "computer science", "f#"]
ghostCommentId = "ghost-37"
+++


# Introduction

When I'm learning a new programming language, I usually like to do some coding exercises to get familiar with the various language features, and to get used to the syntax.
Many of these exercises—or *katas*—are about implementing some kind of algorithm, which is a great way to learn about the control structures of the language, the conditions, loops and functions.
Other katas are more focused on designing a data model for a certain domain, where the goal is to utilize the various features of the type system to create a model as expressive and intuitive as possible.

Since I've been learning F#, I've been doing some data modeling exercises to learn what F# type system is capable of. And because I come from a C# background, I often compare my solutions to their C# counterpart, to be able to grasp the differences between the data models used in a functional and an object-oriented language.

In this and the next post I'll take a look at a very simple data modelling exercise: creating a data type representing a card from the [standard 52-card deck](https://en.wikipedia.org/wiki/Standard_52-card_deck). I found this kata simple enough to describe it in detail in a blog post, but it has enough quirks that we can get our teeth into it.  
In this first post I'll do it in C#, and in the next one I'm going to do the same in F#, where I'll try to contrast how the functional features of F# can solve problems that are cumbersome to express in OO languages.

# The task

The task I'd like to solve in this simple exercise is to design a data model to represent a card in the standard 52-card deck. For now I'm only interested in representing one single card, and not a full deck.

We can specify a card with the following points.

 - Every card has a suit (except the Joker), which can be clubs (♣), diamonds (<span style="color: red">♦</span>), hearts (<span style="color: red">♥</span>) and spades (♠).
 - A card can be either
  - a card with a number on it between 2 and 10, I'll call this a *value card*,
  - or it can be one of the *face cards*: Jack, Queen, King or Ace.  
  *(Note: the terminology is not 100% unambiguous, some sources don't call the Ace a face card, but I'll consider it as one for the sake of this exercise.)*
 - There is a special card, the Joker, which does not have a suit.

![Image illustrating the standard 52-card deck.](/images/2017/05/cards.png)

I would like to implement a data model, which potentially can be used by multiple different algorithms. More concretely, let's imagine that we deliver the data model in a self-contained package, and then we can implement the logic necessary to model various card games, which all depend on this single data model.  
What this means in practice is that I would not like to mix data and logic in our data types, but rather just focus on the data. This might be different than what encapsulation in OO would suggest, but it's necessary if we want to have a data model which then can be used in several different algorithms (which is a typical practice in functional programming).

# Implementing in C&#35;

When we start to implement this data model in C#, it seems intuitive that we'll probably need an enum for the suit of a card.

```csharp
enum Suit
{
    Clubs,
    Hearts,
    Diamonds,
    Spades
}
```

Similarly, I'll creat an enum type for the different kind of face types.  
(It's debatable whether Ace is considered a face card or not, in this model I'll assume that it is.)

```csharp
enum Face
{
    Jack,
    Queen,
    King,
    Ace
}
```

With these in place I can create the actual type representing a card in the deck. I'll add a `Suit`, a `Face` and a `Value` property, saying that a card is either a face card or a value card, so that only one of those properties will have a value at any given time.  
Since these are represented with value types, we have to make them nullable to be able to say they might not have a value. I also added a constructor.

```csharp
class Card
{
    public Suit Suit { get; set; }

    public Face? Face { get; set; }

    public int? Value { get; set; }

    public Card(Suit suit, Face? face, int? value)
    {
        Suit = suit;
        Face = face;
        Value = value;
    }
}
```

This type seems to be covering our requirements, since any card of the deck can be represented with an instance of it.

## Avoid invalid states (à la DDD)

We cannot be completely satisfied yet: this data model violates an important guideline of domain-driven design (and just generally an all-around good practice): **Design our data model in a way that illegal states are not representable**.  
This is beneficial for two main reasons.

 - It helps avoiding bugs we would bump into due to invalid data.
 - It makes implementing any sort of validation logic easier, since (at least some of) the validity of our data is immediately enforced by our data model.

Our current model doesn't satisfy this requirement, since we're able to do this:

```csharp
var card = new Card(Suit.Clubs, Face.Jack, 5);
```

Since this card instance will have both of its `Face` and `Value` property set, we will have no way deciding what it actually represent. We should not allow an instance like this to be created.

This can be nicely solved by a simple C# pattern I like to call the *Factory method pattern*. (Note: you might find other sources using the same term to denote a slightly more complicated pattern.)  
We can make our constructor private, and introduce designated public methods (the *factory methods*) for creating instances of various kinds. Since the constructor is not accessible from the outside, we just have to make sure that our factory methods initialize the instance in a way that it represents a valid value.

```csharp
class Card
{
    public Suit Suit { get; set; }

    public Face? Face { get; set; }

    public int? Value { get; set; }

    private Card(Suit suit, Face? face, int? value)
    {
        Suit = suit;
        Face = face;
        Value = value;
    }
    
    public static Card CreateFace(Suit suit, Face face)
    {
        return new Card(suit, face, null);
    }
    
    public static Card CreateValue(Suit suit, int value)
    {
        return new Card(suit, null, value);
    }
}
```

Better, now we cannot use the constructor from outside, we have to use one of the two factory methods, thereby enforcing us to create only valid instances.

```csharp
var card = Card.CreateFace(Suit.Clubs, Face.Jack);
```

I use this pattern all the time, not just to enforce some preconditions, but also to make code more self-documenting by introducing these expressive method names for object creation.

## Mutability

Of course we have a glaring problem: since our properties have public setters, there is nothing stopping us from creating a correct instance with the factory methods, but then mutate the instance afterwards to make it invalid.

```csharp
var invalid = Card.CreateFace(Suit.Clubs, Face.Jack);
invalid.Value = 5;
```

This is easy to mitigate, just remove the setters to make our type immutable (which is beneficial to strive for anyway).

```csharp
class Card
{
    public Suit Suit { get; }

    public Face? Face { get; }

    public int? Value { get; }

    ...
}
```

(This is something that I could've done immediately, but I wanted to illustrate the thought process that often happens during implementing a data model in C#, where—not to be condescending, just based on my experience—not necessarily every developer thinks about mutability consciously.)

## Finishing up

When I first started implementing this data model, I initially forgot about the fact that we also have to support the Joker cards (this is not just for the sake of the example, I did actually forgot :)), this is the last thing we have to cover.

We could say that if both `Face` and `Value` are `null`, we consier the card a Joker, but that feels a bit hacky, let's introduce a boolean instead.  
This is the final data model, covering all use cases.

```csharp
class Card
{
    public Suit Suit { get; }

    public Face? Face { get; }

    public int? Value { get; }

    public bool IsJoker { get; }

    private Card(Suit suit, Face? face, int? value, bool isJoker)
    {
        Suit = suit;
        Face = face;
        Value = value;
        IsJoker = isJoker;
    }

    public static Card CreateFace(Suit suit, Face face)
    {
        return new Card(suit, face, null, false);
    }

    public static Card CreateValue(Suit suit, int value)
    {
        return new Card(suit, null, value, false);
    }

    public static Card CreateJoker()
    {
        return new Card(default(Suit), null, null, true);
    }
}
```

I could've made the `Suit` property nullable too, but I didn't have to, since if `IsJoker` is true, we'll ignore the value of `Suit` anyway. However, this this is definitely debatable, it's one of those things where neither approach is obviously better than the other.

# Usage

Let's see how we would use this in an application. As an example, implement the [score calculation](https://en.wikipedia.org/wiki/Rummy#Scoring) of the card game Rummy.

```csharp
int CalculateValue(Card card)
{
    if(card.IsJoker)
        return 0;
        
    if(card.Face.HasValue) // It's a face card
    {
        if(card.Face.Value == Face.Ace)
            return 15;
        
        if(card.Face.Value == Face.Queen && card.Suit == Suit.Spades)
            return 40;
        
        return 10;
    }
    
    // Now it has to be a value card
    if(card.Value.Value == 10)
        return 10;
    
    return 5;
}
```

It works fine, although I'm not 100% happy with this syntax, it feels a bit awkward to do the `HasValue` check to find out what the object really represents.  
*It feels to me that the type system does not help to express our domain, we had to do it ourselves*, we'll see in the next post how this is different in F#.

# Possible improvements

## Check the *kind* of the card more conveniently

In order to make usage a bit more convenient, we can introduce a new property in the `Card` type explicitly specifying the *kind* of our card. We can introduce a new enum for this purpose.

```csharp
enum CardKind
{
    Value,
    Face,
    Joker
}
```

Then implement the property returning the appropriate value.

```csharp
class Card
{
    public CardKind Kind
    {
        get
        {
            if(IsJoker)
                return CardKind.Joker;
            if(Face.HasValue)
                return CardKind.Face;
            return CardKind.Value;
        }
    }
    ...
}
```

This way the actual usage of the type in any given algorithm can become a bit more expressive, we can phrase it like this.

```csharp
int CalculateValue(Card card)
{
    switch (card.Kind)
    {
        case CardKind.Joker:
            ...
        case CardKind.Face:
            ...
        case CardKind.Value:
            ...
    }
}
```

We can go one step further, and—since we are not using the `HasValue` property of our nullable types to determine the kind of the card—we can change our properties to return a non-nullable value.  
So instead of

```csharp
class Card
{
    public Face? Face { get; }
    ...
}
```

we can do something like

```csharp
class Card
{
    private Face? face;
    public Face Face
    {
         get
         {
             if(!face.HasValue)
                throw new InvalidOperationException($"You can only retrieve the Face property from a Face card. This is a {Kind} card.");
             return face.Value;
         }
    }
    ...
}
```

This way in our logic using this type we can simply write `card.Face` instead of `card.Face.Value`.

These changes improve the "developer experience" of working with this data model, but keep in mind that these all introduce more and more code we have to implement, thereby increasing the complexity of our data model, giving us more chance to make mistakes. So any improvement like these is always a tradeoff.

## What about OO?

If we have learnt OO from a textbook, or at a university, we might have seen an introduction through examples like Hawk -> Bird -> Animal, or Square -> Rectangle -> Shape (and then later in the industry we probably heard many arguments against the validity of such examples, but let's put that aside for a moment :)).  
Now if we look at our domain, it seems to fit the same pattern, so if OO dictates creating such inheritance trees, shouldn't we represent the various kinds of card as classes deriving from each other? We could do the following:

```csharp
abstract class Card { ... }

class FaceCard : Card { ... }

class ValueCard : Card { ... }

class Joker : Card { ... }
```

We could definitely do this. My problem with this approach is twofold.  
First, it is cumbersome to actually use this model in an algorithm. We could either do a switch-case on the type of our card.

```csharp
int CalculateValue(Card card)
{
    switch (card)
    {
        case Joker j:
            ...
        case FaceCard f:
            ...
        case ValueCard v:
            ...
    }
}
```

But normally this is considered an anti-pattern in object oriented programming. According to pure OO, if we have to switch case on the dynamic type of our object, we are doing something wrong. (Although this is not 100% clear, especially since the ability to do this conveniently has recently been introduced in C# in the form of pattern matching.)

The other way to do it would be the "proper OO way", to introduce the `CalculateValue` method on the base class, and override it with the actual implementation in the derived types.

```csharp
abstract class Card
{
    public abstract int CalculateValue();
    ...
}

class FaceCard : Card
{
    public override int CalculateValue()
    {
        // Implementation for a face card.
        ...
    }
    ...
}
...
```

This supposed to be the textbook OO solution, however, it has a problem: with this approach we cannot achieve the goal we set out to deliver, namely to implement the data model as a self-contained unit (a separate library), on which the implementations of the various algorithms can depend. Because as we would introduce the implementation of more and more different card games, all of their logic would go into these *Card classes, thereby growing and growing them in size.  
This is a manifestation of one of the general arguments against OO (or specifically inheritance), that as we introduce more and more features, due to encapsulation, our OO classes tend to grow, and become large and complicated.

Because of these reasons I think this OO approach is not really suitable to solve our problem. The puzzle pieces of OO seemingly fall in place nicely, but this approach actually causes more problems than what it solves.

# Conclusion

In this post I tried to illustrate the challenges and tough decisions we usually face when designing a data model in an object oriented language. If you have any suggestions on how to further improve this implementation, feel free to leave it as a comment!

In the next post I'll look at how to solve the same problem in F#, and how can its type system eliminate some problems that are difficult to express in an OO language.
