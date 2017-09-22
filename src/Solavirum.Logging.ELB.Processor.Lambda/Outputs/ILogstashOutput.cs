using Solavirum.Logging.ELB.Processor.Lambda.Processing;

namespace Solavirum.Logging.ELB.Processor.Lambda.Outputs
{
	public interface ILogstashOutput
	{
		bool Send(LogEvent e);
	}
}