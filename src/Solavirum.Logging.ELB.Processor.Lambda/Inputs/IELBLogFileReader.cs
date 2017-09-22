using System.Collections.Generic;

namespace Solavirum.Logging.ELB.Processor.Lambda.Inputs
{
	public interface IELBLogFileReader
	{
		IEnumerable<string> Lines();
	}
}