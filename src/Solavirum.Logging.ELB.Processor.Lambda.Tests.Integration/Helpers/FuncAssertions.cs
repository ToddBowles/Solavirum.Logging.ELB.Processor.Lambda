using System;
using System.Collections.Generic;
using System.Threading;

namespace Solavirum.Logging.ELB.Processor.Lambda.Tests.Integration.Helpers
{
    public static class FuncAssertions
    {
        public static void ResultShouldEventuallyBe<TResult>(this Func<TResult> func, Action<TResult> assertion, int maxAttempts = 5, TimeSpan? wait = null)
        {
            wait = wait ?? TimeSpan.FromMilliseconds(500);
            var attempts = 0;
            List<Exception> failures = new List<Exception>();
            try
            {
                attempts++;

                if (attempts >= maxAttempts)
                {
                    throw new AggregateException($"The result of the function [{func}] never successfully passed its assertion", failures);
                }

                var result = func();
                assertion(result);
            }
            catch (Exception ex)
            {
                failures.Add(ex);
                Thread.Sleep(wait.Value);
            }
        }
    }
}