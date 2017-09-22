using System.Collections.Generic;
using Solavirum.Logging.ELB.Processor.Lambda.Processing;

namespace Solavirum.Logging.ELB.Processor.Lambda.Outputs
{
	public class InMemoryLogstashOutput : ILogstashOutput
	{
		public List<LogEvent> Events = new List<LogEvent>();

		public bool Send(LogEvent e)
		{
			lock (Events)
			{
				Events.Add(e);
			}
			return true;
		}
	}
}