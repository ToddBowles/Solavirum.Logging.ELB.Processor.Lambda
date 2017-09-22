using System.Collections.Generic;

namespace Solavirum.Logging.ELB.Processor.Lambda.Logging
{
	public class InMemoryLogger : ILogger
	{
		public List<string> Messages = new List<string>();

		public void Log(string message)
		{
			Messages.Add(message);
		}
	}
}