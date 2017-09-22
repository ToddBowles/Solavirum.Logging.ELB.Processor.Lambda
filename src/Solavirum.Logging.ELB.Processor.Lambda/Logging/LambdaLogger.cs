namespace Solavirum.Logging.ELB.Processor.Lambda.Logging
{
	public class LambdaLogger : ILogger
	{
		public void Log(string message)
		{
			Amazon.Lambda.Core.LambdaLogger.Log(message);
		}
	}
}