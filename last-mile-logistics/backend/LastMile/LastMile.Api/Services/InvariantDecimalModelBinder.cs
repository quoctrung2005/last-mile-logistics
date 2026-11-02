using System.Globalization;
using Microsoft.AspNetCore.Mvc.ModelBinding;

namespace LastMile.Api.Services;

// Mobile multipart uses JSON-style decimal points even under vi-VN hosting.
public sealed class InvariantDecimalModelBinder : IModelBinder
{
    public Task BindModelAsync(ModelBindingContext context)
    {
        var value=context.ValueProvider.GetValue(context.ModelName);
        if(value==ValueProviderResult.None)return Task.CompletedTask;
        context.ModelState.SetModelValue(context.ModelName,value);
        if(string.IsNullOrWhiteSpace(value.FirstValue)){
            context.Result=ModelBindingResult.Success(null);return Task.CompletedTask;
        }
        if(decimal.TryParse(value.FirstValue,NumberStyles.AllowLeadingSign|NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out var number))
            context.Result=ModelBindingResult.Success(number);
        else context.ModelState.TryAddModelError(context.ModelName,"Dùng số không phân cách nghìn và dấu chấm cho phần thập phân.");
        return Task.CompletedTask;
    }
}
