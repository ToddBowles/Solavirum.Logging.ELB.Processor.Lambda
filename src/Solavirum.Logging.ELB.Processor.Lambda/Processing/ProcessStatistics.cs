namespace Solavirum.Logging.ELB.Processor.Lambda.Processing
{
	public class ProcessStatistics
	{
		public LinesStatistics Lines { get; set; }
		public FailureStatisticsCollection Failures { get; set; }
	}
}