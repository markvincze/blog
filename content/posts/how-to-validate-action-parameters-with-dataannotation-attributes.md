+++
title = "How to validate action parameters with DataAnnotation attributes?"
description = "A simple approach to evaluate DataAnnotation validation attributes not only on model properties, but on the action method parameters as well."
date = "2016-02-28T14:23:00.0000000"
tags = ["asp.net", "c#", ".net-core", "asp.net-core"]
+++

## Model validation in MVC

In both MVC and Web Api we can use the attributes provided in the `System.ComponentModel.DataAnnotations` namespace to specify validation rules for our models.

Let's say we have a controller action with the following signature, accepting a single parameter populated from the request body.

```csharp
public IActionResult Post([FromBody]Product product);
```

And we decorated our `Product` type with the following validation attributes (example taken from the [official ASP.NET documentation](http://www.asp.net/web-api/overview/formats-and-model-binding/model-validation-in-aspnet-web-api)).

```csharp
public class Product
{
    public int Id { get; set; }
    [Required]
    public string Name { get; set; }
    public decimal Price { get; set; }
    [Range(0, 999)]
    public double Weight { get; set; }
}
```

When we call our endpoint by posting a product object in the body of our request, the framework is going to evaluate our validation attributes during the model binding process, and save its result (with possibly errors) in the `ModelState` property of our controller.  
So in the implementation of our action we can simply use the `ModelState` property to check whether the input is valid or not, and we can return its value as our response in case of an error.

```csharp
public IActionResult Post(Product product)
{
    if (!ModelState.IsValid)
    {
        return HttpBadRequest(ModelState);
    }

    // Process the product...

    return Ok();
}
```

If we post the following Json to our endpoint (note that the required `Name` property is missing)

```json
{ "Id":4, "Price":2.99, "Weight":5 }
```

we get back an error response containing all the validation errors produced during the model binding.

```json
{
  "name": [
    "The Name field is required."
  ]
}
```

## Validation attributes on action parameters

There is nothing preventing us from putting validation attributes not on a model property, but on the method parameters of an action. We might want to enforce our callers to post a product object to this endpoint, so it seems logical to add the `Required` attribute on the method parameter itself.

```csharp
public IActionResult Post([FromBody][Required]Product product)
```

The problem with this approach - which surprised me - is that it simply doesn't work. The framework does not seem to evaluate these attributes at all.

If we call the endpoint with an empty request body, the value of the `product` argument will be `null`, but `ModelState.IsValid` will return true.

### Solution

Luckily, it is not difficult to hook into the MVC pipeline with a custom filter attribute. With the following custom filter attribute we can iterate over all of the action parameters and evaluate all the validation attributes specified for them.

```csharp
public class ValidateActionParametersAttribute : ActionFilterAttribute
{
    public override void OnActionExecuting(ActionExecutingContext context)
    {
        var descriptor = context.ActionDescriptor as ControllerActionDescriptor;

        if (descriptor != null)
        {
            var parameters = descriptor.MethodInfo.GetParameters();

            foreach (var parameter in parameters)
            {
                var argument = context.ActionArguments[parameter.Name];

                EvaluateValidationAttributes(parameter, argument, context.ModelState);
            }
        }

        base.OnActionExecuting(context);
    }

    private void EvaluateValidationAttributes(ParameterInfo parameter, object argument, ModelStateDictionary modelState)
    {
        var validationAttributes = parameter.CustomAttributes;

        foreach (var attributeData in validationAttributes)
        {
            var attributeInstance = CustomAttributeExtensions.GetCustomAttribute(parameter, attributeData.AttributeType);

            var validationAttribute = attributeInstance as ValidationAttribute;

            if (validationAttribute != null)
            {
                var isValid = validationAttribute.IsValid(argument);
                if (!isValid)
                {
                    modelState.AddModelError(parameter.Name, validationAttribute.FormatErrorMessage(parameter.Name));
                }
            }
        }
    }
}
```

(Note: this has been implemented using ASP.NET Core 1.0. In ASP.NET 4 the Api might be slightly different, but the same approach should work there as well.)

If we apply this filter to our action

```csharp
[ValidateActionParameters]
public IActionResult Post([FromBody][Required]Product product)
```

and we send a POST request with an empty body, we'll get back the expected error response.

```json
{"product":["The product field is required."]}
```

This approach will work nicely even if we have more than one action parameters with multiple different attributes, and also works with custom validation attributes implemented by us. The action I wanted to use this with looked like this, where one of the parameters come from the query string, and the other from the body.

```csharp
[HttpPost("{categoryId}/products")]
IActionResult Post([CustomNotEmptyGuid]Guid categoryId, [FromBody][Required]Product product)
```

Since the above code iterates over all the parameters and attributes, we'll get a list of all the errors in the response.

I uploaded the source code to this [Github respository](https://github.com/markvincze/rest-api-helpers/tree/master), and pushed the [package](https://www.nuget.org/packages/RestApiHelpers/) to NuGet. I plan to extend it with implementation of other cross-cutting concerns useful in a Rest Api in the future.
