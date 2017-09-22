using System;

namespace Solavirum.Logging.ELB.Processor.Lambda
{
	public class FailureStatistics
	{
		public int Total { get; set; }
		public Exception[] LastFew { get; set; }
	}
}