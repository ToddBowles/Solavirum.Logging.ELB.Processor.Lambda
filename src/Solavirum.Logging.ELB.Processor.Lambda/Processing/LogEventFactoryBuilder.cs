using Solavirum.Logging.ELB.Processor.Lambda.Processing;

namespace Solavirum.Logging.ELB.Processor.Lambda.Tests.Unit.Helpers
{
	public class LogEventFactoryBuilder
	{
		public string Environment = "environment";
		public string Application = "application";
		public string Component = "component";
		public string SourceModuleName = "source-module-name";
		public string Type = "logs";

		public LogEventFactory Build()
		{
			return new LogEventFactory(Environment, Application, Component, SourceModuleName, Type);
		}
	}
}