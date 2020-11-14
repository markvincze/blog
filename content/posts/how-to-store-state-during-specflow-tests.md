+++
title = "How to store state during SpecFlow tests?"
slug = "how-to-store-state-during-specflow-tests"
description = "There are different ways to store state during SpecFlow tests, and all of them have benefits and drawbacks."
date = "2015-06-06T19:19:58.0000000"
tags = ["visual studio", "specflow", "c#", ".net"]
+++

#Introduction
[SpecFlow](http://www.specflow.org/) is an implementation of the [Gherkin](https://github.com/cucumber/cucumber/wiki/Gherkin) language for the .NET Framework. SpecFlow is to .NET what [Cucumber](https://cucumber.io/) is for the JavaScript ecosystem.
It is a way to write tests in a DSL that is easily readable (and maybe writable) by not just developers, but also the business. A simple example from the Cucumber web site (which is also generated when a new SpecFlow feature is added in Visual Studio) is the following:

```csharp
Feature: Addition

Scenario Outline: Add two numbers
    Given I have entered 50 into the calculator
    And I have entered 70 into the calculator
    When I press add
    Then the result should be 120 on the screen
```

What SpecFlow does is that it generates some C# code based on the Gherkin test descriptions, therefore implementing unit tests which will try to execute the steps in the feature description.
All the steps must have a corresponding method implementing the step in a binding class.
The binding class implementing the above steps could look like this:

```csharp
[Binding]
public class CalculatorTestSteps
{
    private readonly Calculator calculator = new Calculator();

    [Given(@"I have entered (\d+) into the calculator")]

    public void GivenIHaveEnteredIntoTheCalculator(int number)
    {
        this.calculator.Push(number);
    }

    [When(@"I press add")]
    public void GivenIPressAdd()
    {
        this.calculator.Add();
    }

    [Then(@"the result should be (\d+) on the screen")]
    public void ThenTheResultShouldBeOnTheScreen(int result)
    {
        Assert.AreEqual(result, this.calculator.result);
    }
}
```

SpecFlow generates a unit test based on the feature definition, which basically instantiates the above class, and executes the instance methods corresponding to the feature steps.
The unit tests themselves can be run with the test runner of our choice (for instance the built-in VS test runner or ReSharper), and assertions can be implemented with the usual Assert mechanism of the test framework (which can be either MSTest or NUnit).

#Maintaining state during a test

Most of the time we need to store and maintain some kind of state during a test. For instance in the Given step we initialize some input data, in the When step we use that input data to send a request to a service and then save the result, and in the When step we execute assertions on the result.
There are different ways to store data in SpecFlow steps. In the rest of the post I will introduce three different ways to achieve this.

## Using a private field

The simplest solution is what I used in the Calculator example. Simply create a field in the binding class, and store data in that field, which can be used in all of the steps. A pseudocode of a test sending a GET HTTP request and verifying the returned status code using this technique looks like this:

```csharp
[Binding]
public class ServiceTestSteps
{
    private IRestResponse response;

    [When(@"I send the request")]
    public void WhenISendTheRequest()
    {
        this.response = new RestClient().Execute(new RestRequest("http://my-service.com", Method.GET));
    }

    [Then(@"the status code should be OK")]
    public void ThenTheStatusCodeShouldBeOK()
    {
        Assert.AreEqual(HttpStatusCode.OK, this.response.StatusCode);
    }
}
```

The above solution is very simple and it requires the least amount of code, but it has one significant drawback: if we implement a feature, which has steps implemented in different binding classes, the state won't be shared among those classes, since the binding class instances won't see the each other during the feature execution.

## Using the ScenarioContext
`ScenarioContext` is a static class that has a shared state during the execution of a scenario. It can be freely used as a dictionary, either storing an object of a specific type without a key, or explicitly specifying a string key. The `ScenarioContext` can be accessed by all the binding classes involved, so they can share the state.  
The implementation of the same test using this approach is the following.

```csharp
[Binding]
public class ServiceTestSteps
{
    [When(@"I send the request")]
    public void WhenISendTheRequest()
    {
        ScenarioContext.Current.Set<IRestResponse>(new RestClient().Execute(new RestRequest("http://my-service.com", Method.GET)));
    }

    [Then(@"the status code should be OK")]
    public void ThenTheStatusCodeShouldBeOK(int result)
    {
        Assert.AreEqual(HttpStatusCode.OK, ScenarioContext.Current.Get<IRestResponse>().StatusCode);
    }
}
```

The drawback of using the `ScenarioContext` is that the contract between the different steps will not be explicit. If we change the data stored in one step we have to update all of the other steps which depend on it, and we won't get any compilation errors if we don't do so.
The situation is even worse if we store multiple instances of the same type and have to use and maintain hard-coded string keys.
The last solution solves this problem, but ??? as usual ??? it requires writing the most amount of code.

## Injecting a context instance

The SpecFlow engine supports injecting objects into the instantiated binding classes through their constructor. We just simply have to add constructor parameters to the binding classes, the rest will be taken care of by SpecFlow.  
It also makes sure that even if multiple binding classes have a constructor parameter of the same type, only a single instance of the said type will be created during the execution of a feature, so this feature is ideal for sharing state.

```csharp
public class ServiceTestContext
{
    public IRestResponse Response { get; set; }
}

[Binding]
public class ServiceTestSteps
{
    private readonly ServiceTestContext context;

    ServiceTestSteps(ServiceTestContext context)
    {
        this.context = context;
    }

    [When(@"I send the request")]
    public void WhenISendTheRequest()
    {
        context.Response = new RestClient().Execute(new RestRequest("http://my-service.com", Method.GET));
    }

    [Then(@"the status code should be OK")]
    public void ThenTheStatusCodeShouldBeOK()
    {
        Assert.AreEqual(HttpStatusCode.OK, context.Response.StatusCode);
    }
}
```

This context instance can be shared simply by adding it to another class as a constructor parameter.

```csharp
[Binding]
public class FruitTestSteps
{
    private readonly ServiceTestContext context;

    ServiceTestSteps(ServiceTestContext context)
    {
        this.context = context;
    }

    [Then(@"the response should contain ""(.*)""")]
    public void ThenTheResponseShouldContain(string fruit)
    {
        Assert.IsTrue(this.context.Response.Content.Contains(fruit))
    }
}
```

Then we are able to write a feature which uses steps from both of the binding classes:

```csharp
Scenario: Service response should contain pear
	When I send the request
	Then the status code should be OK
	And the response should contain "pear"
```

##Conclusion

There are multiple ways of storing state in a Specflow feature, all of which have different benefits and drawbacks.
If we only need the state in a single binding class, we can simply store it as a field of that class.
On the other hand if we need to share the state between multiple binding classes, we have two choices: if we're looking for a quick and dirty solution, the current instance of the ScenarioContext can be used as a dictionary, however, if we are willing to invest writing a bit more code to improve maintainability, we can extract the state to be stored to an external context class, which can be injected into all of the binding classes which need to access the shared data.
